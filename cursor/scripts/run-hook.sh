#!/usr/bin/env bash
#
# Clover Cursor plugin — hook dispatcher / Claude-compat shim.
#
# The bundled clover-hook binary was built for Claude Code and speaks Claude's
# hook dialect. Cursor's hooks use different field names and a different output
# schema, so this script translates in both directions.
#
# Like the Claude plugin, the bash layer does no logging of its own — all
# diagnostics live in the binary's log (/tmp/clover-hook.log); shim errors
# surface on stderr, which Cursor captures in its cursor.hooks output log.
#
# Subcommands (set in hooks.json):
#   log-prompt        beforeSubmitPrompt -> audit prompt + drop generation marker
#   review-plan-stop  stop          -> review plan files this chat wrote this generation
#   track-plan-write  afterFileEdit + subagentStart/subagentStop -> record which
#                     chat wrote which plan (binary-only; prints nothing)
#   review-plan       preToolUse (tool_name=="CreatePlan"; Cursor never emits it
#                     for CreatePlan — kept for if/when that changes)
#
# Fail-open, matching the Claude binary: any shim error lets the action proceed.
# A preToolUse path that does not block prints nothing — never
# {"permission":"allow"}, which is a grant, not "no opinion" — so the call stays
# with the user's own approval flow (marketplace/tests/cursor-pretool-no-allow.sh).
set -uo pipefail

SUB="${1:-}"

# Agent identity forwarded to the binary on every invocation. agentName is
# free-text for audit rows; codingAgent must match the server's
# CodingAgentType enum (Infrastructure/Entities/Enums/CodingAgentType.cs).
AGENT_NAME="cursor"
CODING_AGENT="Cursor"

# Prefix of the followup message review-plan-stop injects after a deny.
# log-prompt uses it to recognize Clover's own followup when Cursor re-submits
# it as a prompt: the generation marker is still dropped (the revision's stop
# review needs it) but the prompt is NOT audited to the server — it is not
# user input, just our own deny reason echoing back.
CLOVER_FOLLOWUP_PREFIX="Clover security review rejected the plan."

IN="$(cat 2>/dev/null || true)"

deny_pretool()  { jq -nc --arg r "$1" '{permission:"deny", user_message:$r, agent_message:$r}'; }
continue_ok()   { printf '{"continue":true}\n'; }
safe_default()  { case "$SUB" in log-prompt) continue_ok ;; *) : ;; esac; }

# Locate the binary in this launcher's own tree. The CLOVER_HOOK_BIN that
# sessionStart injects is only a fallback, for a tree that ships no binary (a
# source checkout): Cursor merges the sessionStart env of every installed
# plugin, so with two Clover installs (Cursor's and the Claude Code plugin
# Cursor also loads) it names whichever install's setup ran last, and an older
# binary lacks this launcher's subcommands (marketplace/tests/cursor-two-installs.sh).
# <tree>/cursor/scripts -> <tree>: bin/ hangs off the tree root, not off
# cursor/ (see the same climb in setup.sh).
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OS="$(uname -s | tr '[:upper:]' '[:lower:]')"; ARCH="$(uname -m)"
EXE_SUFFIX=""
case "$OS" in
  darwin*) OS=darwin ;;
  linux*) OS=linux ;;
  mingw*|msys*|cygwin*|windows_nt*) OS=windows; EXE_SUFFIX=.exe ;;
esac
case "$ARCH" in x86_64) ARCH=amd64 ;; aarch64|arm64) ARCH=arm64 ;; esac
BIN="${ROOT}/bin/clover-hook-${OS}-${ARCH}${EXE_SUFFIX}"
if [ ! -x "$BIN" ] && [ -n "${CLOVER_HOOK_BIN:-}" ]; then
  BIN="$CLOVER_HOOK_BIN"
fi

# track-plan-write fires on every file write, so it goes straight to the binary
# ahead of the jq check and credential scan below: recording a path needs
# neither, and a file-write hook must print nothing.
if [ "$SUB" = "track-plan-write" ]; then
  [ -x "$BIN" ] && printf '%s' "$IN" | "$BIN" cursor-track-plan-write >/dev/null 2>&1
  exit 0
fi

if ! command -v jq >/dev/null 2>&1 || [ ! -x "$BIN" ]; then
  echo "clover: fail-open (missing jq or binary) bin=$BIN" >&2
  safe_default; exit 0
fi

if [ -z "${CLOVER_SECURITY_KURA_PLUGIN_CLIENT_ID:-}" ] && [ -z "${CAS_CLOVER_PLUGIN_CLIENT_ID:-}" ]; then
  # Creds come from the "Clover MCP" server entry, which may live in the user's
  # own ~/.cursor/mcp.json or in any plugin's bundled .mcp.json (how the
  # team-pushed clover-mcp plugin ships them). Scan every mcp.json / .mcp.json
  # under ~/.cursor and take the first "Clover MCP" entry with a non-empty client
  # id AND secret; entries with missing/blank creds are skipped so the search
  # keeps going. CLIENT_ID/CLIENT_SECRET/AUTH_URL live under "auth" (snake/camel/
  # bare fallbacks); "url" is the server origin; no auth url -> auth.cloversec.io.
  _pick='
    def pick($o; $ks): reduce $ks[] as $k (null; if . == null then $o[$k] else . end);
    ((.mcpServers // {})["Clover MCP"] // empty) | . as $v | ($v.auth // {}) as $a | {
        id:     (pick($a;["CLIENT_ID","client_id","clientId"]) // pick($v;["CLIENT_ID","client_id","clientId"])),
        secret: (pick($a;["CLIENT_SECRET","client_secret","clientSecret"]) // pick($v;["CLIENT_SECRET","client_secret","clientSecret"])),
        auth:   (pick($a;["AUTH_URL","auth_url","authUrl"]) // pick($v;["AUTH_URL","auth_url","authUrl"]) // ""),
        url:    ($v.url // "")
      } | select((.id // "") != "" and (.secret // "") != "") | [ .id, .secret, .auth, .url ] | @tsv'
  _row=""
  while IFS= read -r _mcp; do
    # jq can't parse Cursor's JSONC; retry once with // line-comments stripped.
    _row="$(jq -r "$_pick" "$_mcp" 2>/dev/null)"
    [ -n "$_row" ] || _row="$(sed -E 's@^[[:space:]]*//.*$@@; s@[[:space:]]//.*$@@' "$_mcp" | jq -r "$_pick" 2>/dev/null)"
    [ -n "$_row" ] && break
  done < <(find "$HOME/.cursor" -type f \( -name 'mcp.json' -o -name '.mcp.json' \) 2>/dev/null | sort)
  if [ -n "$_row" ]; then
    CLOVER_SECURITY_KURA_PLUGIN_CLIENT_ID="$(printf '%s' "$_row" | cut -f1)"
    CLOVER_SECURITY_KURA_PLUGIN_CLIENT_SECRET="$(printf '%s' "$_row" | cut -f2)"
    CLOVER_SECURITY_KURA_PLUGIN_AUTH_URL="$(printf '%s' "$_row" | cut -f3)"
    _url="$(printf '%s' "$_row" | cut -f4)"
    CLOVER_SECURITY_KURA_PLUGIN_SERVER_URL="$(printf '%s' "$_url" | sed -E 's#^([a-zA-Z][a-zA-Z0-9+.-]*://[^/]+).*#\1#')"
    [ -n "$CLOVER_SECURITY_KURA_PLUGIN_AUTH_URL" ] || CLOVER_SECURITY_KURA_PLUGIN_AUTH_URL="https://auth.cloversec.io"
    export CLOVER_SECURITY_KURA_PLUGIN_CLIENT_ID CLOVER_SECURITY_KURA_PLUGIN_CLIENT_SECRET CLOVER_SECURITY_KURA_PLUGIN_SERVER_URL CLOVER_SECURITY_KURA_PLUGIN_AUTH_URL
  fi
fi

session="$(printf '%s' "$IN" | jq -r '.conversation_id // .generation_id // empty' 2>/dev/null)"
cwd="$(printf '%s' "$IN" | jq -r '(.workspace_roots[0]) // .cwd // empty' 2>/dev/null)"

# Context override forwarded to the binary (an empty value is ignored there):
# this plugin's manifest version, computed here because the binary's own lookup
# is Claude-shaped (.claude-plugin manifest path). Branch, repository name and
# URL are left to the binary, which reads them from the forwarded cwd and still
# finds a URL when the remote isn't named origin.
PLUG_DIR="${CURSOR_PLUGIN_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"
AGENT_VERSION="$(jq -r '.version // empty' "$PLUG_DIR/.cursor-plugin/plugin.json" 2>/dev/null)"

# What Cursor reports about itself, forwarded under the binary's shim field
# names: its version, the model, the signed-in account (which outranks the
# locally read emails) and every workspace root (tried for git metadata when the
# first is not a repository). Absent fields are dropped, never sent empty, and
# so is a value of an unexpected type: these fields are informational, and one
# the binary cannot read must not cost the request anything else.
REPORT="$(printf '%s' "$IN" | jq -c --arg remote "${CURSOR_CODE_REMOTE:-}" '
  def text: if type == "string" then . else null end;
  {
    codingAgentVersion: ((.cursor_version | text) // env.CURSOR_VERSION // null),
    model: (.model | text),
    userEmail: (.user_email | text),
    workspaceRoots: (.workspace_roots | if type == "array" then map(strings) else null end),
    remote: ($remote != "" and $remote != "false" and $remote != "0")
  } | with_entries(select(.value != null and .value != "" and .value != false))' 2>/dev/null)"
[ -n "$REPORT" ] || REPORT='{}'

# Convert a raw .plan.md serialization into the plan as the user reads it:
# strip Cursor's YAML frontmatter (todo machine-state), lift name + overview,
# keep the markdown body. Result in $PLAN_TEXT. No frontmatter -> verbatim.
plan_text_from_raw() {
  local raw="$1"
  if printf '%s\n' "$raw" | head -1 | grep -q '^---[[:space:]]*$'; then
    local fm body pname pover part
    fm="$(printf '%s\n' "$raw" | awk 'NR==1{next} /^---[ \t]*$/{exit} {print}')"
    # Leading blank lines dropped (Cursor writes one after the frontmatter) and
    # trailing ones by $(), as cursorPlanTextFromRaw trims them: the binary
    # matches a delivered denial by this text's hash.
    body="$(printf '%s\n' "$raw" | awk '/^---[ \t]*$/{c++; if(c==2){f=1; next}} f && (s || length($0)) {s=1; print}')"
    pname="$(printf '%s\n' "$fm" | sed -n 's/^name:[[:space:]]*//p' | head -1)"
    pover="$(printf '%s\n' "$fm" | sed -n 's/^overview:[[:space:]]*//p' | head -1)"
    PLAN_TEXT=""
    for part in "$pname" "$pover"; do
      [ -n "$part" ] && PLAN_TEXT="${PLAN_TEXT}${PLAN_TEXT:+

}${part}"
    done
    [ -n "$body" ] && PLAN_TEXT="${PLAN_TEXT}${PLAN_TEXT:+

}${body}"
    [ -z "$PLAN_TEXT" ] && PLAN_TEXT="$raw"
  else
    PLAN_TEXT="$raw"
  fi
}

case "$SUB" in
  review-plan)
    tool="$(printf '%s' "$IN" | jq -r '.tool_name // empty' 2>/dev/null)"
    if [ "$tool" != "CreatePlan" ]; then
      exit 0
    fi
    # CreatePlan tool_input = { name, overview, plan(markdown body), todos[] }.
    # Flatten name + overview + body into the single plan string the binary wants.
    # The plan is not on disk yet, so planFilePath is empty; the binary reviews
    # it without a file rather than matching it to a plan in ~/.claude/plans.
    plan="$(printf '%s' "$IN" | jq -r '
      [ .tool_input.name, .tool_input.overview, (.tool_input.plan // .tool_input.body // "") ]
      | map(select(. != null and . != "")) | join("\n\n")' 2>/dev/null)"
    claude_in="$(jq -nc --arg s "$session" --arg c "$cwd" --arg p "$plan" \
      --arg an "$AGENT_NAME" --arg ca "$CODING_AGENT" --arg av "$AGENT_VERSION" --argjson rp "$REPORT" \
      '{session_id:$s, cwd:$c, agentName:$an, codingAgent:$ca, agentVersion:$av, tool_input:{plan:$p, planFilePath:""}} + $rp')"
    out="$(printf '%s' "$claude_in" | "$BIN" review-plan)"
    decision="$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecision // "allow"' 2>/dev/null)"
    reason="$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecisionReason // empty' 2>/dev/null)"
    if [ "$decision" = "deny" ] && [ -n "$reason" ]; then deny_pretool "$reason"; fi
    ;;


  review-plan-stop)
    # stop: plan-mode plans are written by the IDE straight to ~/.cursor/plans
    # with no hookable tool event (CreatePlan never reaches the hook service),
    # but the .plan.md is fully on disk by the time stop fires. Review it here;
    # a deny comes back as followup_message so the agent revises the plan.
    # Note: stop has no composer_mode field — "new plan file since the marker"
    # is the plan-mode signal.
    #
    # Which plans this stop owns is decided by the binary, the same code the
    # Windows path runs: the plans this chat (or its subagents) wrote since
    # this turn's generation marker — workspace *.plan.md included — plus
    # ~/.cursor/plans files no other chat wrote or owns (CreatePlan has no
    # hookable event). It pins each to this chat, so review-plan keys the
    # review by this chat, consumes the marker, and prints one absolute path
    # per line.
    #
    # Each plan below is its own binary process, which would start its own
    # 270s budget (hookBudget in net.go) and let two slow plans outlive the
    # stop's 300s timeout. They all inherit this stop's one deadline instead.
    CLOVER_HOOK_DEADLINE="$(( $(date +%s) + 270 ))"
    export CLOVER_HOOK_DEADLINE
    loops="$(printf '%s' "$IN" | jq -r '.loop_count // 0' 2>/dev/null)"
    new_plans="$(printf '%s' "$IN" | "$BIN" cursor-stop-plans 2>/dev/null)"
    [ -z "$new_plans" ] && exit 0
    if [ "${loops:-0}" -ge 3 ] 2>/dev/null; then
      # Loop guard: stop re-reviewing after repeated denies (belt and braces
      # with hooks.json loop_limit).
      exit 0
    fi
    deny_reasons=""
    denied_plans=""
    while IFS= read -r f; do
      [ -f "$f" ] || continue
      # .plan.md = YAML frontmatter (name/overview + todo machine-state) above
      # the markdown body. The server wants the plan as the user reads it —
      # name + overview + body — not todo ids/statuses/isProject. Mirrors the
      # old CreatePlan flatten (name, overview, plan body joined by blank lines).
      raw="$(cat "$f" 2>/dev/null)"
      plan_text_from_raw "$raw"
      plan="$PLAN_TEXT"
      # Cursor skip channel: the server's deny text tells Cursor agents to add
      # [SKIP:N — reason] lines under a "## Security skips" section of the plan
      # (Cursor has no agent-writable sidecar during the plan flow). The binary
      # only reads skips from the {plan-stem}.clover-skips.md sidecar, so
      # extract the markers here and write that file before invoking it. The
      # binary dedups ids and deletes the file once the server has consumed it.
      skips="$(printf '%s\n' "$plan" | grep -E '\[SKIP:[[:space:]]*[0-9]+' 2>/dev/null || true)"
      if [ -n "$skips" ]; then
        stem="${f%.*}"  # x.plan.md -> x.plan, matching the binary's sidecarPath
        printf '%s\n' "$skips" > "${stem}.clover-skips.md" 2>/dev/null || true
        chmod 600 "${stem}.clover-skips.md" 2>/dev/null || true
        # Now that the skips live in the sidecar, drop the markers and their
        # "## Security skips" heading from the plan we forward, so the plan the
        # server stores and shows stays clean — same as the Claude flow, where
        # skips only ever live in the sidecar and never in the plan text.
        plan="$(printf '%s\n' "$plan" \
          | grep -vE '\[SKIP:[[:space:]]*[0-9]+' \
          | grep -ivE '^[[:space:]]*#{2,}[[:space:]]+security[[:space:]]+skips[[:space:]]*$' \
          2>/dev/null || true)"
      fi
      claude_in="$(jq -nc --arg s "$session" --arg c "$cwd" --arg p "$plan" --arg f "$f" \
        --arg an "$AGENT_NAME" --arg ca "$CODING_AGENT" --arg av "$AGENT_VERSION" --argjson rp "$REPORT" \
        '{session_id:$s, cwd:$c, agentName:$an, codingAgent:$ca, agentVersion:$av, tool_input:{plan:$p, planFilePath:$f}} + $rp')"
      out="$(printf '%s' "$claude_in" | "$BIN" review-plan)"
      decision="$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecision // "allow"' 2>/dev/null)"
      reason="$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecisionReason // empty' 2>/dev/null)"
      if [ "$decision" = "deny" ] && [ -n "$reason" ]; then
        deny_reasons="${deny_reasons}${deny_reasons:+
}[$(basename "$f")] $reason"
        denied_plans="${denied_plans}${denied_plans:+
}$f"
      fi
    done <<< "$new_plans"
    if [ -n "$deny_reasons" ]; then
      msg="$CLOVER_FOLLOWUP_PREFIX Revise the plan to address the following, then update it:
$deny_reasons"
      # Persist the exact emitted text: beforeSubmitPrompt has no origin field,
      # so log-prompt recognizes the followup by matching the incoming prompt
      # against this stored copy (survives wording changes and Cursor wrapping;
      # the prefix check there is only a fallback).
      FUPS="${CLOVER_STATE_DIR:-$HOME/.cursor/clover}/pending-followups"
      mkdir -p "$FUPS" 2>/dev/null || true
      printf '%s' "$msg" > "$FUPS/${session:-unknown}" 2>/dev/null || true
      jq -nc --arg m "$msg" '{followup_message:$m}'
      # Record that these denials reached the developer, so a later stop does
      # not re-send them while the plan's reviewed text is unchanged (Cursor
      # rewrites the todo frontmatter as the chat implements the plan).
      jq -nc --arg c "$session" --arg p "$denied_plans" \
        '{conversation_id:$c, clover_followup_plans:($p | split("\n") | map(select(. != "")))}' \
        | "$BIN" cursor-followup-sent >/dev/null 2>&1 || true
    fi
    ;;

  log-prompt)
    # Drop a per-generation timestamp marker so review-plan-stop can identify
    # plan files written during this generation, and note this conversation
    # as a chat. The binary writes both, so the state has the layout its
    # cursor-stop-plans (and the Windows path) reads.
    printf '%s' "$IN" | "$BIN" cursor-start-turn >/dev/null 2>&1 || true
    prompt="$(printf '%s' "$IN" | jq -r '.prompt // empty' 2>/dev/null)"
    # Clover's own followup re-entering as a prompt: skip the server audit
    # (it is our deny reason, not user input). Primary check — the prompt
    # embeds the exact text persisted when the followup was emitted; fallback —
    # the well-known prefix (state file lost). The generation marker above is
    # dropped either way; the revision's stop review depends on it.
    FUPS="${CLOVER_STATE_DIR:-$HOME/.cursor/clover}/pending-followups"
    fup="$FUPS/${session:-unknown}"
    if [ -f "$fup" ]; then
      stored="$(cat "$fup" 2>/dev/null)"
      if [ -n "$stored" ]; then
        case "$prompt" in
          *"$stored"*) rm -f "$fup" 2>/dev/null; continue_ok; exit 0 ;;
        esac
      fi
    fi
    find "$FUPS" -type f -mmin +240 -delete 2>/dev/null || true
    case "$prompt" in
      "$CLOVER_FOLLOWUP_PREFIX"*) continue_ok; exit 0 ;;
    esac
    claude_in="$(jq -nc --arg s "$session" --arg c "$cwd" --arg p "$prompt" \
      --arg an "$AGENT_NAME" --arg ca "$CODING_AGENT" --arg av "$AGENT_VERSION" --argjson rp "$REPORT" \
      '{session_id:$s, cwd:$c, agentName:$an, codingAgent:$ca, agentVersion:$av, prompt:$p} + $rp')"
    # Fire-and-forget audit; binary stdout suppressed so our protocol JSON
    # below is the only thing Cursor parses. stderr passes through to Cursor.
    printf '%s' "$claude_in" | "$BIN" log-prompt >/dev/null || true
    continue_ok
    ;;

  *)
    safe_default
    ;;
esac
exit 0
