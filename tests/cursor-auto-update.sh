#!/usr/bin/env bash
# Cursor binary refresh wiring.
#
# The refresh itself lives in the binary (cursor-check-update) and is covered by
# the Go suite. What is untested there — and what silently broke Cursor updates —
# is the wiring: hooks.json's sessionStart runs clover-hook.cmd, whose POSIX
# branch routes to cursor/scripts/setup.sh rather than to the binary's
# cursor-setup, where the refresh call sits. On macOS and Linux the refresh
# therefore never ran, and on Windows (where cursor-setup IS reached) the binary
# skips the swap by platform — so it was dead code everywhere.
#
# These checks pin the wiring: setup.sh invokes the refresh, hands it the env it
# needs, stays fail-open when it errors, and never lets it corrupt the env
# contract Cursor parses from stdout.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEST_DIR="$(mktemp -d)"
trap 'rm -rf "$TEST_DIR"' EXIT

command -v jq >/dev/null || { echo "cursor-auto-update.sh: jq is required" >&2; exit 2; }

MOCK_BIN="$TEST_DIR/mock-bin"
PLUGIN_ROOT="$TEST_DIR/plugin"
TEST_HOME="$TEST_DIR/home"
CALLS="$TEST_DIR/calls"
DATA="$TEST_HOME/.cursor/clover"

mkdir -p "$MOCK_BIN" "$PLUGIN_ROOT/.cursor-plugin" "$PLUGIN_ROOT/bin" "$PLUGIN_ROOT/cursor/scripts" "$TEST_HOME"

cat > "$MOCK_BIN/uname" <<'EOF'
#!/usr/bin/env bash
case "${1:-}" in
  -s) printf 'Darwin\n' ;;
  -m) printf 'arm64\n' ;;
  *) exit 2 ;;
esac
EOF
chmod +x "$MOCK_BIN/uname"

cp "$ROOT/cursor/scripts/setup.sh" "$PLUGIN_ROOT/cursor/scripts/"
printf '{\n  "name": "clover",\n  "version": "0.1.90",\n  "hooks": "./cursor/hooks/hooks.json"\n}\n' \
  > "$PLUGIN_ROOT/.cursor-plugin/plugin.json"

# Stand-in for the hook binary: records each subcommand and the env the refresh
# depends on, and can be told to fail or to write junk to stdout.
cat > "$PLUGIN_ROOT/bin/clover-hook-darwin-arm64" <<'EOF'
#!/usr/bin/env bash
printf '%s|CURSOR_PLUGIN_ROOT=%s|CLAUDE_PLUGIN_ROOT=%s|CLAUDE_PLUGIN_DATA=%s\n' \
  "$1" "${CURSOR_PLUGIN_ROOT:-}" "${CLAUDE_PLUGIN_ROOT:-}" "${CLAUDE_PLUGIN_DATA:-}" >> "$MOCK_CALLS"
[ -n "${MOCK_BIN_NOISY:-}" ] && printf 'not json at all\n'
[ -n "${MOCK_BIN_FAILS:-}" ] && exit 3
exit 0
EOF
chmod +x "$PLUGIN_ROOT/bin/clover-hook-darwin-arm64"

run_setup() {
  printf '{}\n' | \
    env \
      PATH="$MOCK_BIN:$PATH" \
      HOME="$TEST_HOME" \
      CURSOR_PLUGIN_ROOT="$PLUGIN_ROOT" \
      MOCK_CALLS="$CALLS" \
      "$@" \
      bash "$PLUGIN_ROOT/cursor/scripts/setup.sh"
}

# Same, with CURSOR_PLUGIN_ROOT unset, so setup.sh has to derive the tree root
# from its own location and forward that.
run_setup_without_plugin_root() {
  printf '{}\n' | \
    env -u CURSOR_PLUGIN_ROOT \
      PATH="$MOCK_BIN:$PATH" \
      HOME="$TEST_HOME" \
      MOCK_CALLS="$CALLS" \
      bash "$PLUGIN_ROOT/cursor/scripts/setup.sh"
}

assert_env_contract() {
  local label="$1" out="$2"
  if ! printf '%s' "$out" | jq -e . >/dev/null 2>&1; then
    echo "ERROR: $label — stdout is not valid JSON: $out" >&2
    exit 1
  fi
  if [ "$(printf '%s' "$out" | jq -r '.env.CLOVER_HOOK_BIN')" != "$PLUGIN_ROOT/bin/clover-hook-darwin-arm64" ]; then
    echo "ERROR: $label — env contract lost CLOVER_HOOK_BIN: $out" >&2
    exit 1
  fi
  if [ "$(printf '%s' "$out" | jq -r '.env.CLAUDE_PLUGIN_DATA')" != "$DATA" ]; then
    echo "ERROR: $label — env contract lost CLAUDE_PLUGIN_DATA: $out" >&2
    exit 1
  fi
}

# --- 1. sessionStart invokes the refresh with the env it needs ---------------
: > "$CALLS"
out="$(run_setup)"
assert_env_contract "happy path" "$out"
if [ "$(grep -c '^cursor-check-update|' "$CALLS")" != "1" ]; then
  echo "ERROR: setup.sh did not invoke cursor-check-update exactly once: $(cat "$CALLS")" >&2
  exit 1
fi
# CURSOR_PLUGIN_ROOT resolves the version and so the channel (a -beta/-local
# tree must not take the public build); the data dir is where the binary keeps
# the manifest copy it reads back.
if ! grep -q "^cursor-check-update|CURSOR_PLUGIN_ROOT=$PLUGIN_ROOT|CLAUDE_PLUGIN_ROOT=$DATA|CLAUDE_PLUGIN_DATA=$DATA$" "$CALLS"; then
  echo "ERROR: the refresh was not handed the plugin root and data dir: $(cat "$CALLS")" >&2
  exit 1
fi

# --- 2. A failing refresh must not break session start -----------------------
: > "$CALLS"
out="$(run_setup MOCK_BIN_FAILS=1)"
assert_env_contract "refresh exits non-zero" "$out"

# --- 3. Refresh output must never reach Cursor's stdout ----------------------
# setup.sh's stdout IS the hook protocol; anything the binary prints there would
# make Cursor discard the whole env contract.
: > "$CALLS"
out="$(run_setup MOCK_BIN_NOISY=1)"
assert_env_contract "refresh writes to stdout" "$out"
case "$out" in
  *"not json at all"*)
    echo "ERROR: refresh stdout leaked into the hook protocol: $out" >&2
    exit 1 ;;
esac

# --- 4. A missing binary is still a working session --------------------------
: > "$CALLS"
mv "$PLUGIN_ROOT/bin/clover-hook-darwin-arm64" "$TEST_DIR/held"
out="$(run_setup)"
assert_env_contract "binary absent" "$out"
if [ -s "$CALLS" ]; then
  echo "ERROR: setup.sh invoked a binary that is not installed: $(cat "$CALLS")" >&2
  exit 1
fi
mv "$TEST_DIR/held" "$PLUGIN_ROOT/bin/clover-hook-darwin-arm64"

# --- 5. The derived tree root is forwarded when Cursor does not set it -------
# Without it the binary falls back to locating the tree from its own path, so
# the version — and with it the channel — is resolved off a different root than
# the one this script was invoked for.
: > "$CALLS"
out="$(run_setup_without_plugin_root)"
assert_env_contract "plugin root unset" "$out"
if ! grep -q "^cursor-check-update|CURSOR_PLUGIN_ROOT=$PLUGIN_ROOT|" "$CALLS"; then
  echo "ERROR: setup.sh did not forward the tree root it derived: $(cat "$CALLS")" >&2
  exit 1
fi

# --- 6. The local channel must be stamped, or a dev build self-updates -------
# channelForVersion reads .cursor-plugin/plugin.json. An unstamped local tree
# reads as public, and the refresh would replace a developer's own build with
# the published one.
BIN_FIXTURE="$TEST_DIR/assemble-bin"
mkdir -p "$BIN_FIXTURE"
printf 'x' > "$BIN_FIXTURE/clover-hook-darwin-arm64"
bash "$ROOT/../scripts/assemble-plugin-tree.sh" \
  --channel local --bin "$BIN_FIXTURE" --output "$TEST_DIR/assembled" >/dev/null
LOCAL_VERSION="$(jq -r '.version' "$TEST_DIR/assembled/.cursor-plugin/plugin.json")"
case "$LOCAL_VERSION" in
  *-local) ;;
  *)
    echo "ERROR: a local tree's .cursor-plugin manifest is not stamped -local (got $LOCAL_VERSION) — it would self-update to the public build" >&2
    exit 1 ;;
esac

echo "cursor-auto-update.sh: all checks passed"
