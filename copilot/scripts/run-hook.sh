#!/usr/bin/env bash
# Clover Copilot plugin — dispatcher from copilot/hooks/hooks.json to the
# binary's Copilot-native copilot-* subcommands (cmd/clover-hook/agent_copilot.go).
#
# Copilot's preToolUse fails CLOSED: a non-zero exit denies the tool call. So
# this script never execs the binary and always ends in exit 0 — a crashed
# binary must leave the developer's tool alone, not block it. The only stdout is
# the binary's own; setup chatter goes to stderr, because sessionStart stdout is
# parsed as hook output.
#
# Copilot sets COPILOT_PLUGIN_ROOT/DATA (and CLAUDE_* aliases) for plugin hooks.
# The shared setup.sh and binary read the CLAUDE_* names, so they are mapped
# here rather than assumed.

SUB="${1:-}"
case "$SUB" in
  setup|check-update|log-prompt|review-plan|should-review-plan) ;;
  *) echo "clover(copilot): unknown subcommand '${SUB}', fail-open" >&2; exit 0 ;;
esac

ROOT="${COPILOT_PLUGIN_ROOT:-${CLAUDE_PLUGIN_ROOT:-$(cd -P "$(dirname "$0")/../.." && pwd -P)}}"
DATA="${COPILOT_PLUGIN_DATA:-${CLAUDE_PLUGIN_DATA:-}}"
if [ -z "$DATA" ]; then
  echo "clover(copilot): fail-open (plugin data directory missing)" >&2
  exit 0
fi
export CLAUDE_PLUGIN_ROOT="$ROOT" CLAUDE_PLUGIN_DATA="$DATA"

# Deploy the verified bundled binary when it is missing or the tree is newer —
# on the first hook of a session (sessionStart and userPromptSubmitted run
# concurrently, so either may get here first) and after `copilot plugin update`
# replaced the tree. Running a copy from the data dir means an update never
# swaps the executable under a hook that is mid-review.
EXE_SUFFIX=""
case "$(uname -s | tr '[:upper:]' '[:lower:]')" in
  mingw*|msys*|cygwin*|windows_nt*) EXE_SUFFIX=".exe" ;;
esac
BINARY="${DATA}/bin/clover-hook${EXE_SUFFIX}"
PLUGIN_VERSION=$(grep -o '"version"[[:space:]]*:[[:space:]]*"[^"]*"' "${ROOT}/.claude-plugin/plugin.json" 2>/dev/null | head -1 | sed 's/.*"\([^"]*\)"$/\1/')
plugin_is_newer() {
  [ "$1" != "$2" ] && [ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | tail -n 1)" = "$1" ]
}
if [ ! -x "$BINARY" ] || plugin_is_newer "$PLUGIN_VERSION" "$(cat "${DATA}/bin/.version" 2>/dev/null)"; then
  CLOVER_SKIP_CLAUDE_REGISTRY=1 bash "${ROOT}/claude/scripts/setup.sh" >&2
fi
if [ ! -x "$BINARY" ]; then
  echo "clover(copilot): fail-open (binary missing) bin=${BINARY}" >&2
  exit 0
fi

# Credentials: the environment Copilot was started with, else what
# configure.sh wrote. Sourced only when absent, so an env.sh can never shadow a
# fleet-managed value.
if [ -z "${CLOVER_SECURITY_KURA_PLUGIN_CLIENT_ID:-${CAS_CLOVER_PLUGIN_CLIENT_ID:-}}" ]; then
  # shellcheck disable=SC1091
  . "${DATA}/env.sh" 2>/dev/null
fi

"$BINARY" "copilot-${SUB}"
exit 0
