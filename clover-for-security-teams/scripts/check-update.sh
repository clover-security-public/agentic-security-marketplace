#!/usr/bin/env bash
# SessionStart hook (async): auto-update this plugin when the marketplace
# publishes a newer version. Best-effort — every failure path exits 0 so a
# broken network, missing CLI, or unreadable manifest never affects the
# session. An applied update takes effect on the next session.

MARKETPLACE_NAME="clover-security"
PLUGIN_NAME="clover-for-security-teams"
MANIFEST_URL="https://raw.githubusercontent.com/clover-security-public/agentic-security-marketplace/main/.claude-plugin/marketplace.json"
CHECK_INTERVAL_SECS=$((24 * 60 * 60))

# Channel gate — the version suffix encodes the channel (X.Y.Z-beta.N = org
# ring, -local = developer build). Only the public channel self-updates;
# beta/local installs rely on Claude Code's marketplace autoUpdate. A plain or
# unreadable version is public, the default behavior.
FULL_VERSION=$(grep -o '"version"[[:space:]]*:[[:space:]]*"[^"]*"' "${CLAUDE_PLUGIN_ROOT}/.claude-plugin/plugin.json" 2>/dev/null | head -1 | sed 's/.*"\([^"]*\)"$/\1/')
case "$FULL_VERSION" in
  *-beta*|*-local*) exit 0 ;;
esac

# Throttle to one remote check per day. The stamp lives in the plugin data
# dir so it survives plugin updates; fall back to the standard data path
# when CLAUDE_PLUGIN_DATA is not injected.
DATA_DIR="${CLAUDE_PLUGIN_DATA:-${HOME}/.claude/plugins/data/${PLUGIN_NAME}@${MARKETPLACE_NAME}}"
mkdir -p "$DATA_DIR" 2>/dev/null || exit 0
STAMP_FILE="${DATA_DIR}/.last-update-check"

NOW=$(date +%s)
LAST=$(cat "$STAMP_FILE" 2>/dev/null)
case "$LAST" in ''|*[!0-9]*) LAST=0 ;; esac
[ $((NOW - LAST)) -lt "$CHECK_INTERVAL_SECS" ] && exit 0
echo "$NOW" > "$STAMP_FILE"

# The update is applied through the claude CLI; without it there is nothing
# we can safely do.
command -v claude >/dev/null 2>&1 || exit 0

INSTALLED=$(grep -o '"version"[[:space:]]*:[[:space:]]*"[^"]*"' "${CLAUDE_PLUGIN_ROOT}/.claude-plugin/plugin.json" 2>/dev/null | grep -o '[0-9][0-9.]*')
[ -n "$INSTALLED" ] || exit 0

MANIFEST=$(curl -fsSL --max-time 10 "$MANIFEST_URL" 2>/dev/null)
[ -n "$MANIFEST" ] || exit 0

if command -v python3 >/dev/null 2>&1; then
  LATEST=$(printf '%s' "$MANIFEST" | python3 -c '
import json, sys
try:
    data = json.load(sys.stdin)
    for p in data.get("plugins", []):
        if p.get("name") == "'"$PLUGIN_NAME"'":
            print(p.get("version", ""))
            break
except Exception:
    pass
' 2>/dev/null)
else
  # Fallback without python3: the version field follows the name field in
  # the jq-formatted manifest the release workflow writes.
  LATEST=$(printf '%s' "$MANIFEST" | grep -A4 "\"name\": \"${PLUGIN_NAME}\"" | grep -o '"version"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | grep -o '[0-9][0-9.]*')
fi
[ -n "$LATEST" ] || exit 0
[ "$INSTALLED" = "$LATEST" ] && exit 0

# Refresh the marketplace clone first so the plugin update can see the new
# version, then update the plugin itself. Both are no-ops when current.
claude plugin marketplace update "$MARKETPLACE_NAME" >/dev/null 2>&1 || true
claude plugin update "${PLUGIN_NAME}@${MARKETPLACE_NAME}" >/dev/null 2>&1 || exit 0

echo "${PLUGIN_NAME}: updated ${INSTALLED} -> ${LATEST} (takes effect next session)" >&2
exit 0
