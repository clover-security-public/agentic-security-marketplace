#!/usr/bin/env bash
# Deploy a new plugin-cache version without overwriting a newer self-update.
PLUGIN_VERSION=$(grep -o '"version"[[:space:]]*:[[:space:]]*"[^"]*"' "${CLAUDE_PLUGIN_ROOT}/.codex-plugin/plugin.json" 2>/dev/null | head -1 | sed 's/.*"\([^"]*\)"$/\1/')
EXE_SUFFIX=""
case "$(uname -s | tr '[:upper:]' '[:lower:]')" in
    mingw*|msys*|cygwin*|windows_nt*) EXE_SUFFIX=".exe" ;;
esac
BINARY="${CLAUDE_PLUGIN_DATA}/bin/clover-hook${EXE_SUFFIX}"
SOURCE_VERSION_FILE="${CLAUDE_PLUGIN_DATA}/bin/.codex-source-version"

if [ -x "$BINARY" ] && [ -n "$PLUGIN_VERSION" ] \
    && [ "$(cat "$SOURCE_VERSION_FILE" 2>/dev/null)" = "$PLUGIN_VERSION" ]; then
    exit 0
fi

CLOVER_SKIP_CLAUDE_REGISTRY=1 bash "${CLAUDE_PLUGIN_ROOT}/claude/scripts/setup.sh" "$@"
STATUS=$?
if [ "$STATUS" -eq 0 ] && [ -x "$BINARY" ] && [ -n "$PLUGIN_VERSION" ]; then
    printf '%s\n' "$PLUGIN_VERSION" > "$SOURCE_VERSION_FILE"
fi
exit "$STATUS"
