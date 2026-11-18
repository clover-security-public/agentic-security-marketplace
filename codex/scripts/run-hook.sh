#!/usr/bin/env bash
# Thin dispatcher from Codex hooks to the shared binary.
# When this launcher started, so the binary's hook_duration log line can report
# the time spent here before it ran (since_launch_ms). Only bash 5 has the clock
# for it ($EPOCHREALTIME); macOS's bash 3.2 reports nothing rather than fork date
# on every hook for a value up to a second high.
if [ -n "${EPOCHREALTIME:-}" ]; then export CLOVER_HOOK_LAUNCHED_AT="$EPOCHREALTIME"; else unset CLOVER_HOOK_LAUNCHED_AT; fi
if [ -z "${CLAUDE_PLUGIN_DATA}" ]; then
    echo "clover: fail-open (plugin data directory missing)" >&2
    exit 0
fi

# Bootstrap when the plugin was enabled or updated after SessionStart.
EXE_SUFFIX=""
case "$(uname -s | tr '[:upper:]' '[:lower:]')" in
    mingw*|msys*|cygwin*|windows_nt*) EXE_SUFFIX=".exe" ;;
esac
BINARY="${CLAUDE_PLUGIN_DATA}/bin/clover-hook${EXE_SUFFIX}"
SOURCE_VERSION_FILE="${CLAUDE_PLUGIN_DATA}/bin/.codex-source-version"
PLUGIN_VERSION=$(grep -o '"version"[[:space:]]*:[[:space:]]*"[^"]*"' "${CLAUDE_PLUGIN_ROOT}/.codex-plugin/plugin.json" 2>/dev/null | head -1 | sed 's/.*"\([^"]*\)"$/\1/')
if [ ! -x "$BINARY" ] || [ "$(cat "$SOURCE_VERSION_FILE" 2>/dev/null)" != "$PLUGIN_VERSION" ]; then
    bash "${CLAUDE_PLUGIN_ROOT}/codex/scripts/setup.sh"
fi

if [ ! -x "$BINARY" ]; then
    echo "clover: fail-open (binary missing) bin=$BINARY" >&2
    exit 0
fi

# Generated per-install credentials file.
# shellcheck disable=SC1091
. "${CLAUDE_PLUGIN_DATA}/env.sh" 2>/dev/null
exec "$BINARY" "$@"
