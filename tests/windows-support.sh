#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEST_DIR="$(mktemp -d)"
trap 'rm -rf "$TEST_DIR"' EXIT

if ! git -C "$ROOT" check-attr eol -- claude/scripts/setup.sh | grep -q 'eol: lf'; then
  echo "ERROR: shell scripts are not pinned to LF line endings for Git Bash" >&2
  exit 1
fi

MOCK_BIN="$TEST_DIR/mock-bin"
PLUGIN_ROOT="$TEST_DIR/plugin"
CLAUDE_DATA="$TEST_DIR/claude-data"
TEST_HOME="$TEST_DIR/home"

mkdir -p \
  "$MOCK_BIN" \
  "$PLUGIN_ROOT/.claude-plugin" \
  "$PLUGIN_ROOT/.cursor-plugin" \
  "$PLUGIN_ROOT/bin" \
  "$PLUGIN_ROOT/claude/scripts" \
  "$PLUGIN_ROOT/cursor/scripts" \
  "$TEST_HOME"

cat > "$MOCK_BIN/uname" <<'EOF'
#!/usr/bin/env bash
case "${1:-}" in
  -s) printf '%s\n' "${TEST_UNAME_S:-MINGW64_NT-10.0-22631}" ;;
  -m) printf '%s\n' "${TEST_UNAME_M:-x86_64}" ;;
  *) exit 2 ;;
esac
EOF
chmod +x "$MOCK_BIN/uname"

cp "$ROOT/.claude-plugin/plugin.json" "$PLUGIN_ROOT/.claude-plugin/"
cp "$ROOT/.cursor-plugin/plugin.json" "$PLUGIN_ROOT/.cursor-plugin/"
cp "$ROOT/claude/scripts/setup.sh" "$PLUGIN_ROOT/claude/scripts/"
cp "$ROOT/claude/scripts/run-hook.sh" "$PLUGIN_ROOT/claude/scripts/"
cp "$ROOT/cursor/scripts/setup.sh" "$PLUGIN_ROOT/cursor/scripts/"
cp "$ROOT/cursor/scripts/run-hook.sh" "$PLUGIN_ROOT/cursor/scripts/"

cat > "$PLUGIN_ROOT/bin/clover-hook-windows-amd64.exe" <<'EOF'
#!/usr/bin/env bash
printf 'fake-hook:%s\n' "$*"
EOF
cat > "$PLUGIN_ROOT/bin/clover-hook-windows-arm64.exe" <<'EOF'
#!/usr/bin/env bash
printf 'fake-hook:%s\n' "$*"
EOF
cat > "$PLUGIN_ROOT/bin/clover-hook-darwin-arm64" <<'EOF'
#!/usr/bin/env bash
printf 'fake-hook:%s\n' "$*"
EOF
chmod +x "$PLUGIN_ROOT"/bin/*

for target in clover-hook-windows-amd64.exe clover-hook-windows-arm64.exe; do
  if ! grep -q "$target" "$ROOT/.github/workflows/release.yml"; then
    echo "ERROR: release workflow does not require $target" >&2
    exit 1
  fi
  if ! grep -q "${target#clover-hook-}" "$ROOT/claude/scripts/build-org-zip.sh"; then
    echo "ERROR: offline bundle does not include $target" >&2
    exit 1
  fi
done

if [ "$(jq '[.. | objects | select(.type? == "command") | .shell? // empty] | all(. == "bash")' "$ROOT/claude/hooks/hooks.json")" != "true" ]; then
  echo "ERROR: Claude hooks do not force the Git Bash execution path" >&2
  exit 1
fi
if [ "$(jq '[.. | objects | .command? // empty] | map(select(length > 0)) | all(startswith("bash "))' "$ROOT/cursor/hooks/hooks.json")" != "true" ]; then
  echo "ERROR: Cursor hooks do not invoke shell scripts through bash" >&2
  exit 1
fi

PATH="$MOCK_BIN:$PATH" \
HOME="$TEST_HOME" \
CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" \
CLAUDE_PLUGIN_DATA="$CLAUDE_DATA" \
TEST_UNAME_S="MINGW64_NT-10.0-22631" \
TEST_UNAME_M="x86_64" \
  bash "$PLUGIN_ROOT/claude/scripts/setup.sh"

if [ ! -x "$CLAUDE_DATA/bin/clover-hook.exe" ]; then
  echo "ERROR: Claude setup did not deploy clover-hook.exe on Windows" >&2
  exit 1
fi

claude_output="$(
  PATH="$MOCK_BIN:$PATH" \
  HOME="$TEST_HOME" \
  CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" \
  CLAUDE_PLUGIN_DATA="$CLAUDE_DATA" \
  TEST_UNAME_S="MINGW64_NT-10.0-22631" \
  TEST_UNAME_M="x86_64" \
    bash "$PLUGIN_ROOT/claude/scripts/run-hook.sh" review-plan
)"
if [ "$claude_output" != "fake-hook:review-plan" ]; then
  echo "ERROR: Claude dispatcher did not execute clover-hook.exe: $claude_output" >&2
  exit 1
fi

UNIX_DATA="$TEST_DIR/unix-data"
PATH="$MOCK_BIN:$PATH" \
HOME="$TEST_HOME" \
CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" \
CLAUDE_PLUGIN_DATA="$UNIX_DATA" \
TEST_UNAME_S="Darwin" \
TEST_UNAME_M="arm64" \
  bash "$PLUGIN_ROOT/claude/scripts/setup.sh"
if [ ! -x "$UNIX_DATA/bin/clover-hook" ]; then
  echo "ERROR: Claude setup regressed the extensionless macOS binary path" >&2
  exit 1
fi

cursor_output="$(
  printf '{}\n' | \
    PATH="$MOCK_BIN:$PATH" \
    HOME="$TEST_HOME" \
    CURSOR_PLUGIN_ROOT="$PLUGIN_ROOT" \
    TEST_UNAME_S="MSYS_NT-10.0-22631" \
    TEST_UNAME_M="aarch64" \
      bash "$PLUGIN_ROOT/cursor/scripts/setup.sh"
)"
case "$cursor_output" in
  *"clover-hook-windows-arm64.exe"*) ;;
  *)
    echo "ERROR: Cursor setup did not select the Windows ARM64 executable: $cursor_output" >&2
    exit 1
    ;;
esac

cursor_error="$TEST_DIR/cursor.err"
cursor_result="$(
  printf '{"tool_name":"NotCreatePlan"}\n' | \
    PATH="$MOCK_BIN:$PATH" \
    HOME="$TEST_HOME" \
    CURSOR_PLUGIN_ROOT="$PLUGIN_ROOT" \
    TEST_UNAME_S="MINGW64_NT-10.0-22631" \
    TEST_UNAME_M="x86_64" \
      bash "$PLUGIN_ROOT/cursor/scripts/run-hook.sh" review-plan 2>"$cursor_error"
)"
if [ "$cursor_result" != '{"permission":"allow"}' ]; then
  echo "ERROR: Cursor dispatcher returned an unexpected result: $cursor_result" >&2
  exit 1
fi
if grep -q "missing jq or binary" "$cursor_error"; then
  echo "ERROR: Cursor dispatcher could not locate the Windows executable" >&2
  exit 1
fi

echo "Windows marketplace support checks passed."
