#!/usr/bin/env bash
# Cursor's run-hook.sh recovers the "Clover MCP" credentials from an mcp.json on
# every prompt and every stop, and the prompt waits for it. The lookup used to
# walk all of ~/.cursor, which holds a full checkout of every repo under
# ~/.cursor/worktrees: 35s a call on a customer laptop, twice per turn. It must
# read only ~/.cursor/mcp.json and Cursor's plugin tree, and once it has found
# the plugin config it reads that one file instead of searching again.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEST_DIR="$(mktemp -d)"
trap 'rm -rf "$TEST_DIR"' EXIT
CURSOR_DIR="$TEST_DIR/home/.cursor"
STATE_DIR="$TEST_DIR/state"
CACHE="$STATE_DIR/mcp-config-path"

# A stand-in binary that records the credentials the launcher handed it.
cat > "$TEST_DIR/clover-hook" <<EOF
#!/usr/bin/env bash
cat >/dev/null
printf '%s/%s' "\${CLOVER_SECURITY_KURA_PLUGIN_CLIENT_ID:-}" "\${CLOVER_SECURITY_KURA_PLUGIN_CLIENT_SECRET:-}" \
  > "$TEST_DIR/creds"
EOF
chmod +x "$TEST_DIR/clover-hook"

# A find that counts its searches of the plugin tree (the launcher also runs
# find to expire its followup files), so a test can tell whether it searched.
mkdir -p "$TEST_DIR/fakebin"
REAL_FIND="$(command -v find)"
cat > "$TEST_DIR/fakebin/find" <<EOF
#!/usr/bin/env bash
case "\$*" in *"/.cursor/plugins "*) echo run >> "$TEST_DIR/find-runs" ;; esac
exec "$REAL_FIND" "\$@"
EOF
chmod +x "$TEST_DIR/fakebin/find"

# mcp <path> <client id> [secret] writes a "Clover MCP" config.
mcp() {
  mkdir -p "$(dirname "$1")"
  printf '{"mcpServers":{"Clover MCP":{"url":"https://mcp.example.test/mcp","auth":{"CLIENT_ID":"%s","CLIENT_SECRET":"%s"}}}}\n' \
    "$2" "${3:-secret-$2}" > "$1"
}

# creds_seen prints the id/secret the binary received on a prompt; searches
# counts the plugin-tree searches that prompt ran.
creds_seen() {
  rm -f "$TEST_DIR/creds" "$TEST_DIR/find-runs"
  printf '{"conversation_id":"c1","prompt":"hi"}' |
    env -u CLOVER_SECURITY_KURA_PLUGIN_CLIENT_ID -u CAS_CLOVER_PLUGIN_CLIENT_ID -u CURSOR_PLUGIN_ROOT \
      PATH="$TEST_DIR/fakebin:$PATH" HOME="$TEST_DIR/home" CLOVER_HOOK_BIN="$TEST_DIR/clover-hook" \
      CLOVER_STATE_DIR="$STATE_DIR" bash "$ROOT/cursor/scripts/run-hook.sh" log-prompt >/dev/null
  cat "$TEST_DIR/creds"
}
searches() { [ -f "$TEST_DIR/find-runs" ] && grep -c '' "$TEST_DIR/find-runs" || echo 0; }

expect() {
  if [ "$2" != "$3" ]; then
    echo "ERROR: $1: got '$2', want '$3'" >&2
    exit 1
  fi
}

# fresh starts a case from an empty ~/.cursor and no remembered config.
fresh() { rm -rf "$CURSOR_DIR" "$STATE_DIR"; mkdir -p "$CURSOR_DIR"; }

PLUGIN_CACHE="$CURSOR_DIR/plugins/cache/org/clover-mcp/sha1/.mcp.json"
MARKETPLACE="$CURSOR_DIR/plugins/marketplaces/github.com/org/repo/sha/clover-for-developers/.mcp.json"

# --- Where the lookup may look --------------------------------------------------

# Configs outside the plugin tree are never read: reaching them means the
# lookup walked the worktrees and everything else under ~/.cursor.
fresh
mcp "$CURSOR_DIR/worktrees/api/feature-x/.cursor/mcp.json" worktree
mcp "$CURSOR_DIR/extensions/some.extension-1.0.0/mcp.json" extension
mcp "$CURSOR_DIR/plugins/local/big-plugin/node_modules/pkg/.mcp.json" node-modules
expect "only configs outside the plugin tree" "$(creds_seen)" "/"
expect "nothing found, nothing remembered" "$([ -e "$CACHE" ] && echo yes || echo no)" no

# The deepest plugin layout Cursor uses: a marketplace checkout.
fresh
mcp "$MARKETPLACE" marketplace
expect "marketplace checkout" "$(creds_seen)" "marketplace/secret-marketplace"

# Plugin configs are taken in sorted order: the plugin cache sorts first.
fresh
mcp "$MARKETPLACE" marketplace
mcp "$PLUGIN_CACHE" cache
expect "plugin cache" "$(creds_seen)" "cache/secret-cache"

# Cursor keeps team-managed content in ~/.cursor/managed/team_<id>/ (today only
# hooks); a team-managed MCP config there is found, ahead of plugin configs.
fresh
mcp "$CURSOR_DIR/managed/team_123/mcp.json" managed
expect "team-managed config" "$(creds_seen)" "managed/secret-managed"
expect "remembers the team-managed path" "$(cat "$CACHE")" "$CURSOR_DIR/managed/team_123/mcp.json"
expect "team-managed config, second prompt" "$(creds_seen)" "managed/secret-managed"
expect "team-managed config, second prompt needs no search" "$(searches)" 0
fresh
mcp "$PLUGIN_CACHE" cache
mcp "$CURSOR_DIR/managed/team_123/mcp.json" managed
expect "team-managed config sorts ahead of plugins" "$(creds_seen)" "managed/secret-managed"

# The user's own config wins over any plugin's.
fresh
mcp "$PLUGIN_CACHE" cache
mcp "$CURSOR_DIR/mcp.json" user
expect "user mcp.json" "$(creds_seen)" "user/secret-user"
expect "user mcp.json needs no search" "$(searches)" 0

# --- Remembering where the config is -------------------------------------------

fresh
mcp "$PLUGIN_CACHE" cache
expect "first prompt" "$(creds_seen)" "cache/secret-cache"
expect "first prompt searches" "$(searches)" 1
expect "remembered path" "$(cat "$CACHE")" "$PLUGIN_CACHE"
if grep -q secret "$CACHE"; then
  echo "ERROR: the remembered file holds the client secret" >&2; exit 1
fi

expect "second prompt" "$(creds_seen)" "cache/secret-cache"
expect "second prompt reads the remembered file, no search" "$(searches)" 0

# A rotated secret is read from the remembered file, never served stale.
mcp "$PLUGIN_CACHE" cache rotated
expect "rotated secret" "$(creds_seen)" "cache/rotated"
expect "rotated secret needs no search" "$(searches)" 0

# The user adding their own config later still takes precedence.
mcp "$CURSOR_DIR/mcp.json" user
expect "user config added later" "$(creds_seen)" "user/secret-user"
rm -f "$CURSOR_DIR/mcp.json"

# A plugin update moves the config: the old path is gone, so search again and
# remember the new one.
rm -rf "$(dirname "$PLUGIN_CACHE")"
mcp "$CURSOR_DIR/plugins/cache/org/clover-mcp/sha2/.mcp.json" updated
expect "after plugin update" "$(creds_seen)" "updated/secret-updated"
expect "after plugin update searches once" "$(searches)" 1
expect "remembers the new path" "$(cat "$CACHE")" "$CURSOR_DIR/plugins/cache/org/clover-mcp/sha2/.mcp.json"

# A remembered file that no longer carries credentials is searched past.
mcp "$CURSOR_DIR/plugins/cache/org/clover-mcp/sha2/.mcp.json" "" ""
mcp "$MARKETPLACE" marketplace
expect "remembered file lost its credentials" "$(creds_seen)" "marketplace/secret-marketplace"
expect "remembers the replacement" "$(cat "$CACHE")" "$MARKETPLACE"

# A remembered path outside the plugin tree is not trusted.
fresh
mcp "$CURSOR_DIR/worktrees/api/.cursor/mcp.json" worktree
mcp "$PLUGIN_CACHE" cache
mkdir -p "$STATE_DIR"
printf '%s\n' "$CURSOR_DIR/worktrees/api/.cursor/mcp.json" > "$CACHE"
expect "remembered path outside plugins/" "$(creds_seen)" "cache/secret-cache"
printf '%s\n' "$CURSOR_DIR/plugins/../worktrees/api/.cursor/mcp.json" > "$CACHE"
expect "remembered path climbing out of plugins/" "$(creds_seen)" "cache/secret-cache"

echo "cursor mcp lookup: ok"
