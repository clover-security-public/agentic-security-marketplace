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
#   review-plan-stop  stop          -> review plan files written this generation
#   review-plan       preToolUse (tool_name=="CreatePlan"; Cursor never emits it
#                     for CreatePlan — kept for if/when that changes)
#
# Fail-open, matching the Claude binary: any shim error allows the action.
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

allow_pretool() { printf '{"permission":"allow"}\n'; }
deny_pretool()  { jq -nc --arg r "$1" '{permission:"deny", user_message:$r, agent_message:$r}'; }
continue_ok()   { printf '{"continue":true}\n'; }
safe_default()  { case "$SUB" in log-prompt) continue_ok ;; review-plan-stop) : ;; *) allow_pretool ;; esac; }

# Locate the binary. sessionStart injects CLOVER_HOOK_BIN; otherwise derive it.
BIN="${CLOVER_HOOK_BIN:-}"
if [ -z "$BIN" ] || [ ! -x "$BIN" ]; then
  # <tree>/cursor/scripts -> <tree>: bin/ hangs off the tree root, not off
  # cursor/ (see the same climb in setup.sh).
  ROOT="${CURSOR_PLUGIN_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"
  OS="$(uname -s | tr '[:upper:]' '[:lower:]')"; ARCH="$(uname -m)"
  EXE_SUFFIX=""
  case "$OS" in
    darwin*) OS=darwin ;;
    linux*) OS=linux ;;
    mingw*|msys*|cygwin*|windows_nt*) OS=windows; EXE_SUFFIX=.exe ;;
  esac
  case "$ARCH" in x86_64) ARCH=amd64 ;; aarch64|arm64) ARCH=arm64 ;; esac
  BIN="${ROOT}/bin/clover-hook-${OS}-${ARCH}${EXE_SUFFIX}"
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

# Context overrides forwarded to the binary (empty values are ignored there):
# this plugin's manifest version, plus git context for the workspace root.
# Computed here because the binary's own derivations are Claude-shaped
# (.claude-plugin manifest path) or need a cwd that is a git repo.
PLUG_DIR="${CURSOR_PLUGIN_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"
AGENT_VERSION="$(jq -r '.version // empty' "$PLUG_DIR/.cursor-plugin/plugin.json" 2>/dev/null)"
GIT_BRANCH=""; GIT_REPO=""; GIT_URL=""
if [ -n "$cwd" ] && [ -d "$cwd" ]; then
  GIT_BRANCH="$(git -C "$cwd" branch --show-current 2>/dev/null)"
  _tl="$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null)"
  [ -n "$_tl" ] && GIT_REPO="$(basename "$_tl")"
  GIT_URL="$(git -C "$cwd" config --get remote.origin.url 2>/dev/null)"
fi

# Convert a raw .plan.md serialization into the plan as the user reads it:
# strip Cursor's YAML frontmatter (todo machine-state), lift name + overview,
# keep the markdown body. Result in $PLAN_TEXT. No frontmatter -> verbatim.
plan_text_from_raw() {
  local raw="$1"
  if printf '%s\n' "$raw" | head -1 | grep -q '^---[[:space:]]*$'; then
    local fm body pname pover part
    fm="$(printf '%s\n' "$raw" | awk 'NR==1{next} /^---[ \t]*$/{exit} {print}')"
    body="$(printf '%s\n' "$raw" | awk '/^---[ \t]*$/{c++; if(c==2){f=1; next}} f')"
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
      allow_pretool; exit 0
    fi
    # CreatePlan tool_input = { name, overview, plan(markdown body), todos[] }.
    # Flatten name + overview + body into the single plan string the binary wants.
    plan="$(printf '%s' "$IN" | jq -r '
      [ .tool_input.name, .tool_input.overview, (.tool_input.plan // .tool_input.body // "") ]
      | map(select(. != null and . != "")) | join("\n\n")' 2>/dev/null)"
    claude_in="$(jq -nc --arg s "$session" --arg c "$cwd" --arg p "$plan" \
      --arg an "$AGENT_NAME" --arg ca "$CODING_AGENT" --arg av "$AGENT_VERSION" --arg br "$GIT_BRANCH" --arg re "$GIT_REPO" --arg ru "$GIT_URL" \
      '{session_id:$s, cwd:$c, agentName:$an, codingAgent:$ca, agentVersion:$av, branch:$br, repository:$re, repositoryUrl:$ru, tool_input:{plan:$p, planFilePath:""}}')"
    out="$(printf '%s' "$claude_in" | "$BIN" review-plan)"
    decision="$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecision // "allow"' 2>/dev/null)"
    reason="$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecisionReason // empty' 2>/dev/null)"
    if [ "$decision" = "deny" ] && [ -n "$reason" ]; then deny_pretool "$reason"; else allow_pretool; fi
    ;;


  review-plan-stop)
    # stop: plan-mode plans are written by the IDE straight to ~/.cursor/plans
    # with no hookable tool event (CreatePlan never reaches the hook service),
    # but the .plan.md is fully on disk by the time stop fires. Review it here;
    # a deny comes back as followup_message so the agent revises the plan.
    # Note: stop has no composer_mode field — "new plan file since the marker"
    # is the plan-mode signal.
    gen="$(printf '%s' "$IN" | jq -r '.generation_id // empty' 2>/dev/null)"
    loops="$(printf '%s' "$IN" | jq -r '.loop_count // 0' 2>/dev/null)"
    MARKS="${CLOVER_STATE_DIR:-$HOME/.cursor/clover}/generation-marks"
    PLANS="${CLOVER_PLANS_DIR:-$HOME/.cursor/plans}"
    marker="$MARKS/${gen:-none}"
    if [ -n "$gen" ] && [ -f "$marker" ]; then
      new_plans="$(find "$PLANS" -maxdepth 1 -name '*.plan.md' -newer "$marker" 2>/dev/null)"
    elif [ "${loops:-0}" -gt 0 ] 2>/dev/null; then
      # Followup-loop pass: no beforeSubmitPrompt fired, so no marker. Review
      # recently-touched plans (the agent's revision) within a tight window.
      new_plans="$(find "$PLANS" -maxdepth 1 -name '*.plan.md' -mmin -5 2>/dev/null)"
    else
      # No marker and not a followup loop: nothing attributable to review.
      new_plans=""
    fi
    rm -f "$marker" 2>/dev/null || true
    [ -z "$new_plans" ] && exit 0
    if [ "${loops:-0}" -ge 3 ] 2>/dev/null; then
      # Loop guard: stop re-reviewing after repeated denies (belt and braces
      # with hooks.json loop_limit).
      exit 0
    fi
    deny_reasons=""
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
        --arg an "$AGENT_NAME" --arg ca "$CODING_AGENT" --arg av "$AGENT_VERSION" --arg br "$GIT_BRANCH" --arg re "$GIT_REPO" --arg ru "$GIT_URL" \
        '{session_id:$s, cwd:$c, agentName:$an, codingAgent:$ca, agentVersion:$av, branch:$br, repository:$re, repositoryUrl:$ru, tool_input:{plan:$p, planFilePath:$f}}')"
      out="$(printf '%s' "$claude_in" | "$BIN" review-plan)"
      decision="$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecision // "allow"' 2>/dev/null)"
      reason="$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecisionReason // empty' 2>/dev/null)"
      if [ "$decision" = "deny" ] && [ -n "$reason" ]; then
        deny_reasons="${deny_reasons}${deny_reasons:+
}[$(basename "$f")] $reason"
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
    fi
    ;;

  log-prompt)
    # Drop a per-generation timestamp marker so review-plan-stop can identify
    # plan files written during this generation.
    gen="$(printf '%s' "$IN" | jq -r '.generation_id // .session_id // empty' 2>/dev/null)"
    MARKS="${CLOVER_STATE_DIR:-$HOME/.cursor/clover}/generation-marks"
    mkdir -p "$MARKS" 2>/dev/null || true
    if [ -n "$gen" ]; then : > "$MARKS/$gen" 2>/dev/null || true; fi
    find "$MARKS" -type f -mmin +240 -delete 2>/dev/null || true
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
      --arg an "$AGENT_NAME" --arg ca "$CODING_AGENT" --arg av "$AGENT_VERSION" --arg br "$GIT_BRANCH" --arg re "$GIT_REPO" --arg ru "$GIT_URL" \
      '{session_id:$s, cwd:$c, agentName:$an, codingAgent:$ca, agentVersion:$av, branch:$br, repository:$re, repositoryUrl:$ru, prompt:$p}')"
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
