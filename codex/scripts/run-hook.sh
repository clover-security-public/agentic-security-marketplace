#!/usr/bin/env bash
# Thin dispatcher from Codex hooks to the shared binary.
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
