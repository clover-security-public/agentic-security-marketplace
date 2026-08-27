#!/usr/bin/env bash
#
# Clover Devin plugin — hook dispatcher / Claude-compat shim.
#
# The bundled clover-hook binary speaks Claude Code's hook dialect. Devin CLI's
# hooks are "Claude Code compatible" but not identical: Devin's tool names are
# lowercase (write/edit/exec), and a blocking decision is {"decision":"block"}
# rather than Claude's hookSpecificOutput.permissionDecision. This script
# translates in both directions and self-locates everything, because Devin's
# SessionStart cannot inject env into later hooks and exposes only
# DEVIN_PROJECT_DIR.
#
# Fail-open, matching the Claude/Cursor shims: any shim error allows the action.
#
# Subcommands (wired in hooks.json / hooks.v1.json):
#   log-prompt    UserPromptSubmit          -> audit the prompt to the server
#   review-write  PreToolUse(write|edit)    -> plan gate on .md writes
#   discover <ev> any (debug)               -> log full stdin payload, allow
#
# ── Why the plan gate hangs off .md writes ──────────────────────────────────
# Clover reviews plan text. Claude Code hands it over through the ExitPlanMode
# tool input; Devin has no ExitPlanMode tool and its /plan approval is a UI
# action, not a hook event. What Devin does expose is PreToolUse with a regex
# matcher over tool_name, and write/edit carry file_path + content. That is the
# same seam Claude Code's auto-mode uses: intercept the .md write and let the
# server classify whether the file is a plan (should-review-plan). A plan the
# agent is about to commit to disk is reviewed before it lands.
set -uo pipefail

SUB="${1:-}"

# Agent identity forwarded to the binary. agentName is free-text for audit rows;
# codingAgent must match the server's CodingAgentType enum, which already has a
# Devin member (Infrastructure/Entities/Enums/CodingAgentType.cs).
AGENT_NAME="devin"
CODING_AGENT="Devin"

IN="$(cat 2>/dev/null || true)"

# ── locate root, data dir, binary (idempotent; independent of SessionStart) ──
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DATA="${CLOVER_DEVIN_DATA:-${HOME}/.devin/clover}"
export CLAUDE_PLUGIN_ROOT="$DATA" CLAUDE_PLUGIN_DATA="$DATA"

OS="$(uname -s | tr '[:upper:]' '[:lower:]')"; ARCH="$(uname -m)"
case "$ARCH" in x86_64) ARCH=amd64 ;; aarch64|arm64) ARCH=arm64 ;; esac
BIN="${CLOVER_HOOK_BIN:-${DATA}/bin/clover-hook}"

# Self-bootstrap: if the plugin was enabled mid-session, SessionStart never ran
# and the binary was never deployed, so every hook would silently no-op. setup.sh
# deploys from the bundled tree, so this stays off the network.
if [ ! -x "$BIN" ] && [ -z "${CLOVER_HOOK_BIN:-}" ]; then
  bash "${ROOT}/scripts/setup.sh" >/dev/null 2>&1 || true
fi

LOG="${CLOVER_LOG:-/tmp/clover-devin-hook.log}"
dbg() { [ -n "${CLOVER_DEBUG:-}" ] && echo "clover(devin): $*" >&2 || true; }

# Emit a block in every dialect Devin might read. Devin documents
# {"decision":"block"}; the hookSpecificOutput form is Claude's. Emitting both
# in one object costs nothing and means a dialect change cannot silently turn
# the gate into a no-op.
emit_block() {
  jq -nc --arg r "$1" '{
    decision: "block",
    reason: $r,
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: $r
    }
  }'
}

# ── discovery: log the raw payload and always allow ─────────────────────────
if [ "$SUB" = "discover" ]; then
  { printf '=== %s event=%s ===\n' "$(date '+%Y-%m-%dT%H:%M:%S' 2>/dev/null)" "${2:-?}"
    printf 'DEVIN_PROJECT_DIR=%s\n' "${DEVIN_PROJECT_DIR:-}"
    printf '%s\n' "$IN"
  } >> "$LOG" 2>/dev/null || true
  exit 0
fi

# Self-heal the staged manifest through setup.sh rather than copying it here:
# setup.sh stages the tree's channel-stamped .claude-plugin/plugin.json, and
# devin's own .devin-plugin/plugin.json is an unstamped snapshot that would make
# the binary report the wrong version on every audit row.
if [ ! -f "$DATA/.claude-plugin/plugin.json" ]; then
  bash "${ROOT}/scripts/setup.sh" >/dev/null 2>&1 || true
fi
chmod +x "$BIN" 2>/dev/null || true

# Fail open if the essentials are missing.
if ! command -v jq >/dev/null 2>&1 || [ ! -x "$BIN" ]; then
  dbg "fail-open (missing jq or binary) bin=$BIN"
  exit 0
fi

# Credentials. Devin has no plugin-option prompt, so creds come from the
# launcher's process environment as CLOVER_SECURITY_KURA_PLUGIN_* (verified:
# hooks inherit it; config-file `env` blocks and hook-entry `env` maps are NOT
# injected), or from ${DATA}/env.sh — written by configure.sh or dropped by
# fleet tooling. The binary still accepts the legacy CAS_CLOVER_PLUGIN_* names,
# so the guards here check both.
clover_creds_present() {
  { [ -n "${CLOVER_SECURITY_KURA_PLUGIN_CLIENT_ID:-}" ] || [ -n "${CAS_CLOVER_PLUGIN_CLIENT_ID:-}" ]; } \
    && { [ -n "${CLOVER_SECURITY_KURA_PLUGIN_CLIENT_SECRET:-}" ] || [ -n "${CAS_CLOVER_PLUGIN_CLIENT_SECRET:-}" ]; }
}
if ! clover_creds_present && [ -f "$DATA/env.sh" ]; then
  # shellcheck disable=SC1091
  . "$DATA/env.sh" 2>/dev/null || true
fi

# ── shared context forwarded to the binary ─────────────────────────────────
cwd="${DEVIN_PROJECT_DIR:-$(printf '%s' "$IN" | jq -r '.cwd // empty' 2>/dev/null)}"
session="$(printf '%s' "$IN" | jq -r '.session_id // .conversation_id // empty' 2>/dev/null)"
# Prefer the channel-stamped manifest setup.sh stages in the data dir, then the
# tree's own — both carry the version the running channel actually shipped.
AGENT_VERSION="$(jq -r '.version // empty' "$DATA/.claude-plugin/plugin.json" 2>/dev/null)"
[ -n "$AGENT_VERSION" ] || AGENT_VERSION="$(jq -r '.version // empty' "$ROOT/../.claude-plugin/plugin.json" 2>/dev/null)"

GIT_BRANCH=""; GIT_REPO=""; GIT_URL=""
if [ -n "$cwd" ] && [ -d "$cwd" ]; then
  GIT_BRANCH="$(git -C "$cwd" branch --show-current 2>/dev/null)"
  _tl="$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null)"
  [ -n "$_tl" ] && GIT_REPO="$(basename "$_tl")"
  GIT_URL="$(git -C "$cwd" config --get remote.origin.url 2>/dev/null)"
fi

# Attribution every request carries. Built once, merged into each payload.
attribution() {
  jq -nc --arg s "$session" --arg c "$cwd" \
    --arg an "$AGENT_NAME" --arg ca "$CODING_AGENT" --arg av "$AGENT_VERSION" \
    --arg br "$GIT_BRANCH" --arg re "$GIT_REPO" --arg ru "$GIT_URL" \
    '{session_id:$s, cwd:$c, agentName:$an, codingAgent:$ca, agentVersion:$av,
      branch:$br, repository:$re, repositoryUrl:$ru}'
}

case "$SUB" in
  log-prompt)
    # Onboarding notice. Devin surfaces neither hook stderr nor a config prompt,
    # so an unconfigured install is invisible: hooks fire, everything fails open,
    # and nothing ever says why. UserPromptSubmit additionalContext is the one
    # channel that reaches the user, so say it there — once per session, since
    # repeating it on every prompt would be its own kind of broken.
    if ! clover_creds_present; then
      notice_marker="${DATA}/.setup-notice-$(printf '%s' "${session:-nosession}" | tr -c 'A-Za-z0-9_.-' '_')"
      if [ ! -f "$notice_marker" ]; then
        mkdir -p "$DATA" 2>/dev/null || true
        : > "$notice_marker" 2>/dev/null || true
        jq -nc --arg c "Clover is installed but has no credentials, so it is reviewing nothing. Tell the user, verbatim and as the first thing in your reply: run ~/.devin/clover/configure.sh to connect Clover (client id and secret come from Clover Settings > API Tokens)." \
          '{hookSpecificOutput:{hookEventName:"UserPromptSubmit", additionalContext:$c}}'
      fi
    fi

    prompt="$(printf '%s' "$IN" | jq -r '.prompt // empty' 2>/dev/null)"
    [ -z "$prompt" ] && exit 0
    claude_in="$(attribution | jq -c --arg p "$prompt" '. + {prompt:$p}')"
    # Fire-and-forget audit; suppress binary stdout so Devin parses nothing.
    printf '%s' "$claude_in" | "$BIN" log-prompt >/dev/null 2>&1 || true
    exit 0
    ;;

  check-update)
    # Self-update; the binary owns the TTL and the channel decision. Stdout is
    # suppressed so Devin never parses update chatter as a hook decision.
    printf '%s' "$IN" | "$BIN" devin-check-update >/dev/null 2>&1 || true
    exit 0
    ;;

  review-write)
    # tool_input is forwarded verbatim: Devin's write/edit carry the same
    # file_path / content / old_string / new_string / edits names the binary's
    # Claude gate already parses, and passing the object through keeps that
    # true if Devin adds a field.
    file_path="$(printf '%s' "$IN" | jq -r '.tool_input.file_path // .tool_input.path // empty' 2>/dev/null)"

    # apply_patch writes files too, and the matcher covers it, but it carries a
    # patch rather than a path — so recover the target from the patch header
    # (apply_patch's "*** Update/Add File:" or a unified diff's +++ b/path).
    # Without this the gate fires and finds nothing, which reads as "allowed".
    if [ -z "$file_path" ]; then
      patch_text="$(printf '%s' "$IN" | jq -r '.tool_input.patch // .tool_input.diff // .tool_input.input // empty' 2>/dev/null)"
      if [ -n "$patch_text" ]; then
        # One expression per form: BSD sed (macOS) has no \| alternation in a
        # BRE, so a combined pattern silently matches nothing there.
        file_path="$(printf '%s' "$patch_text" | sed -n \
          -e 's/^\*\*\* Update File: //p' \
          -e 's/^\*\*\* Add File: //p' \
          -e 's/^+++ b\///p' | head -1)"
        dbg "review-write: recovered path from patch: ${file_path:-<none>}"
      fi
    fi

    case "$(printf '%s' "$file_path" | tr '[:upper:]' '[:lower:]')" in
      *.md) ;;
      "")
        # No path anywhere in the payload: allow, but say so — a silently
        # ungated write tool is exactly the failure this shim must not hide.
        dbg "review-write: no file path in tool_input (tool=$(printf '%s' "$IN" | jq -r '.tool_name // "?"' 2>/dev/null)), allow"
        exit 0
        ;;
      *) dbg "review-write: not a .md path=$file_path, allow"; exit 0 ;;
    esac

    tool_input="$(printf '%s' "$IN" | jq -c '.tool_input // {}' 2>/dev/null)"
    [ -z "$tool_input" ] && exit 0
    # Normalise the path onto file_path so the binary always finds it.
    tool_input="$(printf '%s' "$tool_input" | jq -c --arg fp "$file_path" '. + {file_path:$fp}')"

    claude_in="$(attribution | jq -c --argjson ti "$tool_input" '. + {tool_input:$ti}')"
    out="$(printf '%s' "$claude_in" | "$BIN" should-review-plan 2>/dev/null)"

    reason="$(printf '%s' "$out" | jq -r '
      .hookSpecificOutput.permissionDecisionReason // .reason // empty' 2>/dev/null)"
    decision="$(printf '%s' "$out" | jq -r '
      .hookSpecificOutput.permissionDecision // .decision // "allow"' 2>/dev/null)"

    if { [ "$decision" = "deny" ] || [ "$decision" = "block" ]; } && [ -n "$reason" ]; then
      dbg "review-write: blocking path=$file_path"
      emit_block "$reason"
    fi
    exit 0
    ;;

  *)
    dbg "unknown subcommand: $SUB"
    exit 0
    ;;
esac
