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
cp "$ROOT/cursor/scripts/clover-hook.cmd" "$PLUGIN_ROOT/cursor/scripts/"
chmod +x "$PLUGIN_ROOT/cursor/scripts/clover-hook.cmd"

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
# Cursor runs Windows hook commands through PowerShell, so a command that
# names bash or a .sh spawns a visible Git Bash console there. Every hook must
# instead dispatch through the clover-hook.cmd polyglot, whose first line hands
# POSIX straight to the existing shell scripts (unchanged for macOS/Linux).
if [ "$(jq '[.. | objects | .command? // empty] | map(select(length > 0)) | all(contains("/cursor/scripts/clover-hook.cmd\""))' "$ROOT/cursor/hooks/hooks.json")" != "true" ]; then
  echo "ERROR: Cursor hooks do not all dispatch through clover-hook.cmd" >&2
  exit 1
fi
if [ "$(jq '[.. | objects | .command? // empty] | map(select(test("bash|\\.sh"))) | length' "$ROOT/cursor/hooks/hooks.json")" != "0" ]; then
  echo "ERROR: a Cursor hook command names bash or a .sh, which spawns Git Bash on Windows" >&2
  exit 1
fi

# The polyglot's first line must route POSIX to the existing scripts, and the
# batch half must reach the per-arch Windows executable, never bash.
first_line="$(head -1 "$ROOT/cursor/scripts/clover-hook.cmd" | tr -d '\r')"
case "$first_line" in
  :*setup.sh*run-hook.sh*\#) ;;
  *)
    echo "ERROR: clover-hook.cmd line 1 is not the POSIX dispatch polyglot: $first_line" >&2
    exit 1
    ;;
esac
if [ "$(sed -n '2p' "$ROOT/cursor/scripts/clover-hook.cmd" | tr -d '\r')" != "@echo off" ]; then
  echo "ERROR: clover-hook.cmd does not silence echo on line 2" >&2
  exit 1
fi
if ! grep -q 'clover-hook-windows-%ARCH%\.exe' "$ROOT/cursor/scripts/clover-hook.cmd"; then
  echo "ERROR: clover-hook.cmd does not select a per-arch Windows build" >&2
  exit 1
fi
# Line 1 must keep invoking the scripts through bash: they use pipefail, a
# bashism a dash /bin/sh rejects, and the old hooks.json always ran them via
# bash. cmd.exe never executes line 1, so this cannot reach Windows.
case "$first_line" in
  *"exec bash"*) ;;
  *)
    echo "ERROR: the POSIX branch no longer runs the scripts through bash" >&2
    exit 1
    ;;
esac
# The batch half (everything after line 1) must never reach for bash.
if tail -n +2 "$ROOT/cursor/scripts/clover-hook.cmd" | grep -i "bash" | grep -vq "rem"; then
  echo "ERROR: the Windows batch half of clover-hook.cmd invokes bash" >&2
  exit 1
fi
for sub in cursor-setup cursor-log-prompt cursor-review-plan-stop; do
  if ! grep -q "$sub" "$ROOT/cursor/scripts/clover-hook.cmd"; then
    echo "ERROR: clover-hook.cmd does not map to $sub" >&2
    exit 1
  fi
done
if ! git -C "$ROOT" check-attr eol -- cursor/scripts/clover-hook.cmd | grep -q 'eol: crlf'; then
  echo "ERROR: clover-hook.cmd is not pinned to CRLF line endings" >&2
  exit 1
fi
if [ ! -x "$ROOT/cursor/scripts/clover-hook.cmd" ]; then
  echo "ERROR: clover-hook.cmd is not executable (POSIX runs it directly)" >&2
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

# The polyglot's POSIX branch must hand off to the existing scripts unchanged:
# `setup` routes to setup.sh, anything else to run-hook.sh.
cmd_setup="$(
  printf '{}\n' | \
    PATH="$MOCK_BIN:$PATH" \
    HOME="$TEST_HOME" \
    CURSOR_PLUGIN_ROOT="$PLUGIN_ROOT" \
    TEST_UNAME_S="Darwin" \
    TEST_UNAME_M="arm64" \
      "$PLUGIN_ROOT/cursor/scripts/clover-hook.cmd" setup
)"
case "$cmd_setup" in
  *"clover-hook-darwin-arm64"*) ;;
  *)
    echo "ERROR: clover-hook.cmd setup did not reach setup.sh: $cmd_setup" >&2
    exit 1
    ;;
esac

cmd_prompt="$(
  printf '{"prompt":"hi"}\n' | \
    PATH="$MOCK_BIN:$PATH" \
    HOME="$TEST_HOME" \
    CURSOR_PLUGIN_ROOT="$PLUGIN_ROOT" \
    TEST_UNAME_S="Darwin" \
    TEST_UNAME_M="arm64" \
      "$PLUGIN_ROOT/cursor/scripts/clover-hook.cmd" log-prompt
)"
if [ "$cmd_prompt" != '{"continue":true}' ]; then
  echo "ERROR: clover-hook.cmd log-prompt did not reach run-hook.sh: $cmd_prompt" >&2
  exit 1
fi

echo "Windows marketplace support checks passed."
