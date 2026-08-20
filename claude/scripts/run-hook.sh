#!/usr/bin/env bash
# Wrapper invoked by every Claude Code hook event. Plugin-level hooks
# (UserPromptSubmit, PreToolUse) get CLAUDE_PLUGIN_DATA injected by Claude Code;
# skill-scoped hooks (Stop, PostToolUse defined inside SKILL.md frontmatter) do
# not. When CLAUDE_PLUGIN_DATA is missing, fall back to the standard plugin
# data directory under ~/.claude/plugins/data/.
if [ -z "${CLAUDE_PLUGIN_DATA}" ]; then
    for candidate in "${HOME}/.claude/plugins/data"/*clover*; do
        if [ -d "${candidate}" ]; then
            export CLAUDE_PLUGIN_DATA="${candidate}"
            break
        fi
    done
fi

# Self-bootstrap. If the plugin was enabled (or auto-updated) mid-session,
# SessionStart never fired with the plugin loaded, so setup.sh never ran
# and the binary was never deployed — making every hook event silently
# no-op. Run setup.sh on demand whenever the binary is missing or stale.
EXE_SUFFIX=""
case "$(uname -s | tr '[:upper:]' '[:lower:]')" in
    mingw*|msys*|cygwin*|windows_nt*) EXE_SUFFIX=".exe" ;;
esac
BINARY="${CLAUDE_PLUGIN_DATA}/bin/clover-hook${EXE_SUFFIX}"
VERSION_FILE="${CLAUDE_PLUGIN_DATA}/bin/.version"
PLUGIN_VERSION=$(grep -o '"version"[[:space:]]*:[[:space:]]*"[^"]*"' "${CLAUDE_PLUGIN_ROOT}/.claude-plugin/plugin.json" 2>/dev/null | head -1 | sed 's/.*"\([^"]*\)"$/\1/')
if [ ! -x "$BINARY" ] || [ "$(cat "$VERSION_FILE" 2>/dev/null)" != "$PLUGIN_VERSION" ]; then
    bash "${CLAUDE_PLUGIN_ROOT}/claude/scripts/setup.sh"
fi

# Registry self-heal trigger. For users stuck in split-brain state
# (installed_plugins.json missing the clover entry), the SessionStart
# hook never fires for the plugin, so setup.sh never runs, so the
# self-heal block inside setup.sh — which would write the missing
# entry — is unreachable. This is the only execution path that DOES
# fire in that state, because Claude Code's hook dispatch keeps
# routing through the deployed binary path. setup.sh is fully
# idempotent — its self-heal block is a no-op on machines where the
# registry entry already exists and is valid. See the matching block
# in setup.sh and its TODO(clover-coding-plugin) for removal criteria.
REGISTRY="${HOME}/.claude/plugins/installed_plugins.json"
HOOK_PLUGIN_NAME=$(grep -o '"name"[[:space:]]*:[[:space:]]*"[^"]*"' "${CLAUDE_PLUGIN_ROOT}/.claude-plugin/plugin.json" 2>/dev/null | head -1 | sed 's/.*"\([^"]*\)"$/\1/')
[ -n "$HOOK_PLUGIN_NAME" ] || HOOK_PLUGIN_NAME="clover"
# Marketplace name follows the channel, which the version suffix encodes
# (public is the default for anything unrecognized).
case "$PLUGIN_VERSION" in
  *-beta*)  HOOK_MARKETPLACE_NAME="clover-security-beta" ;;
  *-local*) HOOK_MARKETPLACE_NAME="clover-security-local" ;;
  *)        HOOK_MARKETPLACE_NAME="clover-security" ;;
esac
if [ ! -f "$REGISTRY" ] || ! grep -q "\"${HOOK_PLUGIN_NAME}@${HOOK_MARKETPLACE_NAME}\"" "$REGISTRY" 2>/dev/null; then
    bash "${CLAUDE_PLUGIN_ROOT}/claude/scripts/setup.sh" >/dev/null 2>&1 || true
fi

. "${CLAUDE_PLUGIN_DATA}/env.sh" 2>/dev/null
exec "$BINARY" "$@"
