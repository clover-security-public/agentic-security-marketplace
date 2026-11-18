#!/usr/bin/env bash
#
# Clover Devin plugin — hook launcher for macOS and Linux.
#
# The bundled clover-hook binary speaks Devin's hook protocol natively through
# its devin-* subcommands: it parses the payload, reconstructs the Markdown a
# write/edit/apply_patch/write_plan call produces, and prints a block in both
# Devin's and Claude's dialect. Windows already calls it directly from
# clover-hook.cmd; this script does the same, so every platform runs one code
# path and needs nothing but bash and the binary. jq is deliberately not used:
# a machine without it (a Devin cloud VM is not documented to ship it) would
# otherwise allow every write unreviewed.
#
# What stays here is what only a shell can do before the binary runs: locate the
# data dir, deploy the binary when SessionStart never ran, and source the
# credentials file fleet tooling or configure.sh drops.
#
# Fail-open, matching the Claude/Cursor shims: any launcher error allows the
# action, and only the binary ever prints a decision.
#
# Subcommands (wired in hooks.json / hooks.v1.json):
#   log-prompt    UserPromptSubmit -> devin-log-prompt   (audit, setup notice)
#   check-update  SessionStart     -> devin-check-update (self-update)
#   review-write  PreToolUse       -> devin-review-write (plan gate)
#   review-exec   PostToolUse(exec) -> devin-review-exec (exec plan gate)
#   session-baseline           SessionStart -> devin-session-baseline (implementation review)
#   snapshot-working-tree      PreToolUse   -> devin-snapshot-working-tree
#   mark-session-edit          PostToolUse  -> devin-mark-session-edit
#   stop-implementation-review Stop         -> devin-stop-implementation-review
#   discover <ev> any (debug)      -> log full stdin payload, allow
set -uo pipefail

SUB="${1:-}"

# When this launcher started, so the binary's hook_duration log line can report
# the time spent here before it ran (since_launch_ms). Only bash 5 has the clock
# for it ($EPOCHREALTIME); macOS's bash 3.2 reports nothing rather than fork date
# on every hook for a value up to a second high.
if [ -n "${EPOCHREALTIME:-}" ]; then export CLOVER_HOOK_LAUNCHED_AT="$EPOCHREALTIME"; else unset CLOVER_HOOK_LAUNCHED_AT; fi

IN="$(cat 2>/dev/null || true)"

# ── locate root, data dir, binary (idempotent; independent of SessionStart) ──
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DATA="${CLOVER_DEVIN_DATA:-${HOME}/.devin/clover}"
export CLAUDE_PLUGIN_ROOT="$DATA" CLAUDE_PLUGIN_DATA="$DATA"

BIN="${CLOVER_HOOK_BIN:-${DATA}/bin/clover-hook}"

LOG="${CLOVER_LOG:-/tmp/clover-devin-hook.log}"
dbg() { [ -n "${CLOVER_DEBUG:-}" ] && echo "clover(devin): $*" >&2 || true; }

# ── discovery: log the raw payload and always allow ─────────────────────────
if [ "$SUB" = "discover" ]; then
  { printf '=== %s event=%s ===\n' "$(date '+%Y-%m-%dT%H:%M:%S' 2>/dev/null)" "${2:-?}"
    printf 'DEVIN_PROJECT_DIR=%s\n' "${DEVIN_PROJECT_DIR:-}"
    printf '%s\n' "$IN"
  } >> "$LOG" 2>/dev/null || true
  exit 0
fi

# Self-bootstrap: if the plugin was enabled mid-session, SessionStart never ran
# and the binary was never deployed, so every hook would silently no-op. The
# staged manifest is healed the same way: setup.sh stages the tree's
# channel-stamped .claude-plugin/plugin.json, which the binary reports as its
# version for a manual install. setup.sh deploys from the bundled tree, so this
# stays off the network.
if { [ ! -x "$BIN" ] && [ -z "${CLOVER_HOOK_BIN:-}" ]; } || [ ! -f "$DATA/.claude-plugin/plugin.json" ]; then
  bash "${ROOT}/scripts/setup.sh" >/dev/null 2>&1 || true
fi
chmod +x "$BIN" 2>/dev/null || true

if [ ! -x "$BIN" ]; then
  dbg "fail-open (missing binary) bin=$BIN"
  exit 0
fi

# Credentials. Devin has no plugin-option prompt, so creds come from the
# launcher's process environment as CLOVER_SECURITY_KURA_PLUGIN_* (hooks inherit
# it; in cloud sessions a managed manifest entry's `env` block sets it), or from
# ${DATA}/env.sh — written by configure.sh or dropped by fleet tooling. The
# environment wins; the file is read only when the environment carries none.
# The binary still accepts the legacy CAS_CLOVER_PLUGIN_* names, so the guard
# checks both. The local Devin CLI applies the manifest `env` block without
# resolving secrets, so a value still reading `secret:...` counts as absent and
# env.sh is read on a developer's machine that shares the cloud manifest.
clover_value_set() {
  case "$1" in "" | secret:*) return 1 ;; esac
}
clover_creds_present() {
  { clover_value_set "${CLOVER_SECURITY_KURA_PLUGIN_CLIENT_ID:-}" || clover_value_set "${CAS_CLOVER_PLUGIN_CLIENT_ID:-}"; } \
    && { clover_value_set "${CLOVER_SECURITY_KURA_PLUGIN_CLIENT_SECRET:-}" || clover_value_set "${CAS_CLOVER_PLUGIN_CLIENT_SECRET:-}"; }
}
if ! clover_creds_present && [ -f "$DATA/env.sh" ]; then
  set -a
  # shellcheck disable=SC1091
  . "$DATA/env.sh" 2>/dev/null || true
  set +a
fi

case "$SUB" in
  log-prompt)   printf '%s' "$IN" | "$BIN" devin-log-prompt 2>/dev/null ;;
  review-write) printf '%s' "$IN" | "$BIN" devin-review-write 2>/dev/null ;;
  review-exec)  printf '%s' "$IN" | "$BIN" devin-review-exec 2>/dev/null ;;
  session-baseline | snapshot-working-tree | mark-session-edit | stop-implementation-review)
                printf '%s' "$IN" | "$BIN" "devin-$SUB" 2>/dev/null ;;
  # Self-update; the binary owns the TTL and the channel decision. Stdout is
  # suppressed so Devin never parses update chatter as a hook decision.
  check-update) printf '%s' "$IN" | "$BIN" devin-check-update >/dev/null 2>&1 ;;
  *)            dbg "unknown subcommand: $SUB" ;;
esac
exit 0
