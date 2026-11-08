#!/usr/bin/env bash
# Claude Code parses a PreToolUse hook's stdout as one JSON value. When the
# launcher redeploys a stale binary it runs setup.sh first, and anything setup
# prints there lands ahead of the binary's deny: the decision no longer parses,
# Claude Code ignores it, and an unreviewed plan goes through. Whatever setup
# says must reach stderr, never the decision channel.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LAUNCHER="$ROOT/claude/scripts/run-hook.sh"
TEST_DIR="$(mktemp -d)"
trap 'rm -rf "$TEST_DIR"' EXIT

command -v jq >/dev/null || { echo "claude-launcher.sh: jq is required" >&2; exit 2; }

DENY='{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"plan stores secrets in plaintext"}}'

FAILED=0
fail() { echo "FAIL: $*" >&2; FAILED=1; }

# new_case <name> <plugin version> — a plugin tree newer than the deployed
# binary, so the launcher takes its redeploy path, and a deployed binary that
# denies.
new_case() {
  CASE="$TEST_DIR/$1"
  PLUGIN_ROOT="$CASE/plugin"
  DATA="$CASE/data"
  TEST_HOME="$CASE/home"
  mkdir -p "$PLUGIN_ROOT/.claude-plugin" "$PLUGIN_ROOT/claude/scripts" "$DATA/bin" "$TEST_HOME/.claude/plugins"
  printf '{"name":"clover","version":"%s"}\n' "$2" > "$PLUGIN_ROOT/.claude-plugin/plugin.json"
  printf '#!/bin/sh\ncat >/dev/null\nprintf '"'"'%%s\\n'"'"' '"'"'%s'"'"'\n' "$DENY" > "$DATA/bin/clover-hook"
  chmod +x "$DATA/bin/clover-hook"
  echo "0.0.1" > "$DATA/bin/.version"
}

run_launcher() {
  set +e
  OUT="$(printf '{"tool_name":"ExitPlanMode"}' | \
    env HOME="$TEST_HOME" CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" CLAUDE_PLUGIN_DATA="$DATA" \
      bash "$LAUNCHER" review-plan 2>/dev/null)"
  RC=$?
  set -e
}

assert_deny_is_the_only_output() {
  local label="$1"
  [ "$RC" = "0" ] || fail "$label — exit $RC, want 0"
  if ! printf '%s' "$OUT" | jq -e '.hookSpecificOutput.permissionDecision == "deny"' >/dev/null 2>&1; then
    fail "$label — stdout is not the binary's deny alone, Claude Code would drop the decision: '$OUT'"
  fi
}

# A setup.sh that talks on stdout: the launcher's contract, whatever setup says.
new_case chatty-setup "9.9.9-local"
printf '#!/bin/sh\necho "setup: redeploying the hook binary"\n' > "$PLUGIN_ROOT/claude/scripts/setup.sh"
run_launcher
assert_deny_is_the_only_output "redeploy with a setup.sh that prints to stdout"

# The real setup.sh with a corrupt plugin registry: its self-heal reports on
# stdout. A -local tree never downloads, so the deny comes from the old binary.
if command -v python3 >/dev/null; then
  new_case registry-self-heal "9.9.9-local"
  cp "$ROOT/claude/scripts/setup.sh" "$PLUGIN_ROOT/claude/scripts/setup.sh"
  echo "not json" > "$TEST_HOME/.claude/plugins/installed_plugins.json"
  run_launcher
  assert_deny_is_the_only_output "redeploy whose registry self-heal reports a corrupt registry"
fi

if [ "$FAILED" != 0 ]; then
  exit 1
fi
echo "claude-launcher.sh: ok"
