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
cp "$ROOT/cursor/scripts/clover-hook" "$PLUGIN_ROOT/cursor/scripts/"
cp "$ROOT/cursor/scripts/clover-hook.cmd" "$PLUGIN_ROOT/cursor/scripts/"
chmod +x "$PLUGIN_ROOT/cursor/scripts/clover-hook"

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
# Cursor, unlike Claude Code, has no `shell` field and no per-OS command variant,
# and it runs hook commands through PowerShell on Windows. Naming bash (or any
# .sh) in a Cursor hook command therefore makes Windows spawn Git Bash: a visible
# console window, plus no `jq` for the script to use. The commands must instead
# reach the extensionless launcher, which each platform's shell resolves to its
# own half.
if [ "$(jq '[.. | objects | .command? // empty] | map(select(length > 0)) | any(test("(^|[/\\\\ ])bash([ \"]|$)"))' "$ROOT/cursor/hooks/hooks.json")" != "false" ]; then
  echo "ERROR: a Cursor hook command still invokes bash, which spawns Git Bash on Windows" >&2
  exit 1
fi
if [ "$(jq '[.. | objects | .command? // empty] | map(select(length > 0)) | all(contains("/cursor/scripts/clover-hook\""))' "$ROOT/cursor/hooks/hooks.json")" != "true" ]; then
  echo "ERROR: Cursor hooks do not all dispatch through the clover-hook launcher" >&2
  exit 1
fi
if [ "$(jq '[.. | objects | .command? // empty] | map(select(test("\\.sh"))) | length' "$ROOT/cursor/hooks/hooks.json")" != "0" ]; then
  echo "ERROR: a Cursor hook command names a .sh file, which Windows cannot execute natively" >&2
  exit 1
fi

# Every hook must ask the binary for a cursor-* subcommand: the Claude-shaped
# subcommands speak a different stdout contract and would be misread by Cursor.
if [ "$(jq '[.. | objects | .command? // empty] | map(select(length > 0)) | all(test("\" cursor-[a-z-]+$"))' "$ROOT/cursor/hooks/hooks.json")" != "true" ]; then
  echo "ERROR: Cursor hooks do not all invoke a cursor-* subcommand" >&2
  exit 1
fi

# Both halves of the launcher have to ship, and the unix half needs its exec bit.
for launcher in cursor/scripts/clover-hook cursor/scripts/clover-hook.cmd; do
  if [ ! -f "$ROOT/$launcher" ]; then
    echo "ERROR: missing launcher $launcher" >&2
    exit 1
  fi
done
if [ ! -x "$ROOT/cursor/scripts/clover-hook" ]; then
  echo "ERROR: cursor/scripts/clover-hook is not executable" >&2
  exit 1
fi

# Line endings are load-bearing for both launchers: a CRLF shebang breaks the
# POSIX half, and cmd.exe misparses LF-only batch files.
if ! git -C "$ROOT" check-attr eol -- cursor/scripts/clover-hook | grep -q 'eol: lf'; then
  echo "ERROR: the POSIX launcher is not pinned to LF line endings" >&2
  exit 1
fi
if ! git -C "$ROOT" check-attr eol -- cursor/scripts/clover-hook.cmd | grep -q 'eol: crlf'; then
  echo "ERROR: the Windows launcher is not pinned to CRLF line endings" >&2
  exit 1
fi

# The Windows launcher cannot be executed in CI (no Windows runner), so assert
# statically that it can reach both Windows builds and never reaches for bash.
# The arch is composed at runtime from %ARCH%, so check the pieces: the shared
# binary prefix, an ARM64 detection branch, and the amd64 fallback that covers
# ARM machines running the x64 build under emulation.
if ! grep -q 'clover-hook-windows-%ARCH%\.exe' "$ROOT/cursor/scripts/clover-hook.cmd"; then
  echo "ERROR: the Windows launcher does not select a per-arch Windows build" >&2
  exit 1
fi
if ! grep -qi 'ARM64' "$ROOT/cursor/scripts/clover-hook.cmd"; then
  echo "ERROR: the Windows launcher has no ARM64 detection" >&2
  exit 1
fi
if ! grep -q 'clover-hook-windows-amd64\.exe' "$ROOT/cursor/scripts/clover-hook.cmd"; then
  echo "ERROR: the Windows launcher has no amd64 fallback" >&2
  exit 1
fi
if grep -qi "bash" "$ROOT/cursor/scripts/clover-hook.cmd"; then
  if grep -i "bash" "$ROOT/cursor/scripts/clover-hook.cmd" | grep -vq "^rem"; then
    echo "ERROR: the Windows launcher invokes bash" >&2
    exit 1
  fi
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

# The POSIX launcher must resolve the platform binary and forward the subcommand
# verbatim. Only the unix half is executable here; the .cmd is covered by the
# static assertions above because CI has no Windows runner.
cursor_result="$(
  printf '{"tool_name":"NotCreatePlan"}\n' | \
    PATH="$MOCK_BIN:$PATH" \
    HOME="$TEST_HOME" \
    CURSOR_PLUGIN_ROOT="$PLUGIN_ROOT" \
    TEST_UNAME_S="Darwin" \
    TEST_UNAME_M="arm64" \
      "$PLUGIN_ROOT/cursor/scripts/clover-hook" cursor-review-plan
)"
if [ "$cursor_result" != "fake-hook:cursor-review-plan" ]; then
  echo "ERROR: Cursor launcher did not exec the platform binary: $cursor_result" >&2
  exit 1
fi

# x86_64 must normalise to amd64, or the launcher looks for a binary we never ship.
if [ ! -f "$PLUGIN_ROOT/bin/clover-hook-darwin-amd64" ]; then
  cat > "$PLUGIN_ROOT/bin/clover-hook-darwin-amd64" <<'EOF'
#!/usr/bin/env bash
printf 'fake-hook:%s\n' "$*"
EOF
  chmod +x "$PLUGIN_ROOT/bin/clover-hook-darwin-amd64"
fi
amd64_result="$(
  printf '{}\n' | \
    PATH="$MOCK_BIN:$PATH" \
    HOME="$TEST_HOME" \
    CURSOR_PLUGIN_ROOT="$PLUGIN_ROOT" \
    TEST_UNAME_S="Darwin" \
    TEST_UNAME_M="x86_64" \
      "$PLUGIN_ROOT/cursor/scripts/clover-hook" cursor-log-prompt
)"
if [ "$amd64_result" != "fake-hook:cursor-log-prompt" ]; then
  echo "ERROR: Cursor launcher did not normalise x86_64 to amd64: $amd64_result" >&2
  exit 1
fi

# A missing binary must fail open with each hook's safe default and exit 0 --
# never a non-zero exit, which Cursor would treat as a hook failure.
EMPTY_ROOT="$TEST_DIR/empty-root"
mkdir -p "$EMPTY_ROOT/bin"

set +e
missing_prompt="$(
  printf '{}\n' | \
    PATH="$MOCK_BIN:$PATH" \
    CURSOR_PLUGIN_ROOT="$EMPTY_ROOT" \
    TEST_UNAME_S="Darwin" \
    TEST_UNAME_M="arm64" \
      "$PLUGIN_ROOT/cursor/scripts/clover-hook" cursor-log-prompt 2>/dev/null
)"
missing_prompt_status=$?
missing_stop="$(
  printf '{}\n' | \
    PATH="$MOCK_BIN:$PATH" \
    CURSOR_PLUGIN_ROOT="$EMPTY_ROOT" \
    TEST_UNAME_S="Darwin" \
    TEST_UNAME_M="arm64" \
      "$PLUGIN_ROOT/cursor/scripts/clover-hook" cursor-review-plan-stop 2>/dev/null
)"
missing_stop_status=$?
set -e

if [ "$missing_prompt_status" != "0" ] || [ "$missing_stop_status" != "0" ]; then
  echo "ERROR: Cursor launcher exited non-zero when the binary was missing" >&2
  exit 1
fi
if [ "$missing_prompt" != '{"continue":true}' ]; then
  echo "ERROR: Cursor launcher fail-open for log-prompt was $missing_prompt" >&2
  exit 1
fi
if [ -n "$missing_stop" ]; then
  echo "ERROR: Cursor launcher printed a verdict for the stop hook: $missing_stop" >&2
  exit 1
fi

echo "Windows marketplace support checks passed."
