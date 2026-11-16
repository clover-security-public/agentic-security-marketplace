#!/usr/bin/env bash
# Cursor merges the sessionStart env of every installed plugin into the chat, so
# with two Clover installs (Cursor's own and the Claude Code plugin Cursor also
# loads) CLOVER_HOOK_BIN names whichever install's setup ran last. A launcher
# must still run the binary from its own tree: an older binary lacks the newer
# launcher's subcommands, whose errors the launcher discards, so plan tracking
# and the stop review silently stopped on a machine that had both.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEST_DIR="$(mktemp -d)"
trap 'rm -rf "$TEST_DIR"' EXIT

OS="$(uname -s | tr '[:upper:]' '[:lower:]')"; ARCH="$(uname -m)"
case "$OS" in darwin*) OS=darwin ;; linux*) OS=linux ;; esac
case "$ARCH" in x86_64) ARCH=amd64 ;; aarch64|arm64) ARCH=arm64 ;; esac

# install <name> lays out an installed plugin tree whose binary records which
# install ran it.
install() {
  local tree="$TEST_DIR/$1"
  mkdir -p "$tree/cursor" "$tree/bin" "$tree/.cursor-plugin"
  cp -R "$ROOT/cursor/scripts" "$tree/cursor/scripts"
  printf '{"version":"0.1.0-%s"}\n' "$1" > "$tree/.cursor-plugin/plugin.json"
  cat > "$tree/bin/clover-hook-$OS-$ARCH" <<EOF
#!/usr/bin/env bash
cat >/dev/null
echo "$1 \$*" >> "$TEST_DIR/ran"
EOF
  chmod +x "$tree/bin/clover-hook-$OS-$ARCH"
}
install new
install old

# ran_by <tree> <sub> [env...] runs <tree>'s launcher and prints which install's
# binary it ran.
ran_by() {
  local tree="$1" sub="$2"; shift 2
  rm -f "$TEST_DIR/ran"
  printf '{"conversation_id":"c1","prompt":"hi","workspace_roots":["%s"]}' "$TEST_DIR" |
    env -u CURSOR_PLUGIN_ROOT HOME="$TEST_DIR/home" CLOVER_SECURITY_KURA_PLUGIN_CLIENT_ID=id \
      CLOVER_SECURITY_KURA_PLUGIN_CLIENT_SECRET=secret "$@" \
      bash "$tree/cursor/scripts/clover-hook.cmd" "$sub" >/dev/null 2>&1 || true
  cut -d' ' -f1 "$TEST_DIR/ran" 2>/dev/null | sort -u | tr '\n' ' ' | sed 's/ $//'
}

expect() {
  if [ "$2" != "$3" ]; then
    echo "ERROR: $1: ran the binary of '$2', want '$3'" >&2
    exit 1
  fi
}

OLD_BIN="$TEST_DIR/old/bin/clover-hook-$OS-$ARCH"
expect "track-plan-write, other install's CLOVER_HOOK_BIN" \
  "$(ran_by "$TEST_DIR/new" track-plan-write CLOVER_HOOK_BIN="$OLD_BIN")" new
expect "log-prompt, other install's CLOVER_HOOK_BIN" \
  "$(ran_by "$TEST_DIR/new" log-prompt CLOVER_HOOK_BIN="$OLD_BIN")" new
expect "log-prompt, Cursor's CURSOR_PLUGIN_ROOT for this install" \
  "$(ran_by "$TEST_DIR/new" log-prompt CLOVER_HOOK_BIN="$OLD_BIN" CURSOR_PLUGIN_ROOT="$TEST_DIR/new")" new
expect "log-prompt, no CLOVER_HOOK_BIN" \
  "$(ran_by "$TEST_DIR/new" log-prompt)" new

# A tree that ships no binary (a source checkout, as the tests run it) still
# takes the one CLOVER_HOOK_BIN names.
mkdir -p "$TEST_DIR/source/cursor" "$TEST_DIR/source/.cursor-plugin"
cp -R "$ROOT/cursor/scripts" "$TEST_DIR/source/cursor/scripts"
expect "tree without a binary" \
  "$(ran_by "$TEST_DIR/source" log-prompt CLOVER_HOOK_BIN="$OLD_BIN")" old

echo "cursor two installs: ok"
