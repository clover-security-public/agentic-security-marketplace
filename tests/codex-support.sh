#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_DIR="$(mktemp -d)"
trap 'rm -rf "$TEST_DIR"' EXIT

bash -n "$ROOT/codex/scripts/install.sh" "$ROOT/codex/scripts/run-hook.sh" "$ROOT/codex/managed/run-hook.sh"
python3 - "$ROOT/codex/hooks/hooks.json" <<'PY'
import json, pathlib, sys
hooks = json.loads(pathlib.Path(sys.argv[1]).read_text())["hooks"]
session_start = hooks["SessionStart"][0]["hooks"]
assert len(session_start) == 1, session_start
assert session_start[0]["command"].endswith("codex-check-update"), session_start
PY

FAKE_MARKETPLACE="$TEST_DIR/marketplace"
mkdir -p "$FAKE_MARKETPLACE/.codex-plugin" "$FAKE_MARKETPLACE/.claude-plugin" \
  "$FAKE_MARKETPLACE/bin" "$FAKE_MARKETPLACE/codex/managed"
cp "$ROOT/.codex-plugin/plugin.json" "$FAKE_MARKETPLACE/.codex-plugin/plugin.json"
cp "$ROOT/.claude-plugin/plugin.json" "$FAKE_MARKETPLACE/.claude-plugin/plugin.json"
cp "$ROOT/codex/managed/run-hook.sh" "$FAKE_MARKETPLACE/codex/managed/run-hook.sh"
cp "$ROOT/codex/managed/requirements.toml.template" "$FAKE_MARKETPLACE/codex/managed/requirements.toml.template"

OS="$(uname -s | tr '[:upper:]' '[:lower:]')"
case "$OS" in darwin*) OS=darwin ;; linux*) OS=linux ;; esac
ARCH="$(uname -m)"
case "$ARCH" in x86_64) ARCH=amd64 ;; aarch64|arm64) ARCH=arm64 ;; esac
BINARY_NAME="clover-hook-${OS}-${ARCH}"
cat > "$FAKE_MARKETPLACE/bin/$BINARY_NAME" <<'EOF'
#!/usr/bin/env bash
if [ "${1:-}" = codex-doctor ]; then
  sed -n '1p' >/dev/null
  printf '%s\n' '{"ok":true,"stage":"complete"}'
  exit 0
fi
printf 'fake clover hook: %s\n' "$*" >&2
EOF
chmod +x "$FAKE_MARKETPLACE/bin/$BINARY_NAME"
(
  cd "$FAKE_MARKETPLACE/bin"
  if command -v sha256sum >/dev/null; then
    sha256sum "$BINARY_NAME" > checksums.sha256
  else
    shasum -a 256 "$BINARY_NAME" > checksums.sha256
  fi
)

MOCK_BIN="$TEST_DIR/mock-bin"
mkdir -p "$MOCK_BIN"
cat > "$MOCK_BIN/codex" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$CODEX_COMMAND_LOG"
EOF
chmod +x "$MOCK_BIN/codex"

cp "$ROOT/codex/scripts/install.sh" "$TEST_DIR/install.sh"
chmod +x "$TEST_DIR/install.sh"

COMMON_ENV=(
  "PATH=$MOCK_BIN:$PATH"
  "HOME=$TEST_DIR/home"
  "CLOVER_MARKETPLACE_URL=file://$FAKE_MARKETPLACE"
  "CLOVER_MARKETPLACE_GIT_URL=https://example.invalid/clover.git"
  "CLOVER_SECURITY_KURA_PLUGIN_CLIENT_ID=test-client"
  "CLOVER_SECURITY_KURA_PLUGIN_CLIENT_SECRET=test-secret"
  "CAS_CLOVER_PLUGIN_CLIENT_ID=legacy-client"
  "CAS_CLOVER_PLUGIN_CLIENT_SECRET=legacy-secret"
  "CLOVER_NO_PROMPT=1"
)
mkdir -p "$TEST_DIR/home"

# Developer mode: marketplace + plugin registration, verified binary,
# protected credentials, and a real doctor invocation all happen in one run.
CODEX_HOME="$TEST_DIR/codex-home"
CODEX_COMMAND_LOG="$TEST_DIR/codex-commands.log"
env "${COMMON_ENV[@]}" CODEX_HOME="$CODEX_HOME" CODEX_COMMAND_LOG="$CODEX_COMMAND_LOG" \
  bash "$TEST_DIR/install.sh" > "$TEST_DIR/developer.out"
grep -q 'plugin marketplace add https://example.invalid/clover.git' "$CODEX_COMMAND_LOG"
grep -q 'plugin marketplace upgrade clover-security' "$CODEX_COMMAND_LOG"
grep -q 'plugin add clover@clover-security' "$CODEX_COMMAND_LOG"
grep -q 'backend verification succeeded' "$TEST_DIR/developer.out"
test -x "$CODEX_HOME/plugins/data/clover-clover-security/bin/clover-hook"
python3 - "$CODEX_HOME/plugins/data/clover-clover-security/env.sh" <<'PY'
import os, stat, sys
path = sys.argv[1]
mode = stat.S_IMODE(os.stat(path).st_mode)
assert mode == 0o600, oct(mode)
content = open(path).read()
for name in (
    "CLOVER_SECURITY_KURA_PLUGIN_CLIENT_ID",
    "CLOVER_SECURITY_KURA_PLUGIN_CLIENT_SECRET",
    "CAS_CLOVER_PLUGIN_CLIENT_ID",
    "CAS_CLOVER_PLUGIN_CLIENT_SECRET",
):
    assert "export " + name + "=" in content, (name, content)
assert "CLOVER_SECURITY_KURA_PLUGIN_CLIENT_ID=test-client" in content
assert "CLOVER_SECURITY_KURA_PLUGIN_CLIENT_SECRET=test-secret" in content
assert "CAS_CLOVER_PLUGIN_CLIENT_ID=test-client" in content
assert "CAS_CLOVER_PLUGIN_CLIENT_SECRET=test-secret" in content
PY

# Binary-mode checksum manifests prefix the filename with `*`; the installer
# must accept both that standard format and the text-mode format above.
CHECKSUM="$(awk '{ print $1; exit }' "$FAKE_MARKETPLACE/bin/checksums.sha256")"
printf '%s *%s\n' "$CHECKSUM" "$BINARY_NAME" > "$FAKE_MARKETPLACE/bin/checksums.sha256"

# Beta mode must keep the same one-command install experience while selecting
# the beta marketplace identity. URL overrides keep this test offline.
BETA_CODEX_HOME="$TEST_DIR/beta-codex-home"
BETA_COMMAND_LOG="$TEST_DIR/beta-codex-commands.log"
env "${COMMON_ENV[@]}" CODEX_HOME="$BETA_CODEX_HOME" CODEX_COMMAND_LOG="$BETA_COMMAND_LOG" \
  bash "$TEST_DIR/install.sh" --beta > "$TEST_DIR/beta.out"
grep -q 'plugin marketplace add https://example.invalid/clover.git' "$BETA_COMMAND_LOG"
grep -q 'plugin add clover@clover-security-beta' "$BETA_COMMAND_LOG"
grep -q 'backend verification succeeded' "$TEST_DIR/beta.out"
test -x "$BETA_CODEX_HOME/plugins/data/clover-clover-security-beta/bin/clover-hook"
test -f "$BETA_CODEX_HOME/plugins/data/clover-clover-security-beta/env.sh"
test ! -e "$BETA_CODEX_HOME/plugins/data/clover-clover-security"

# The dispatcher must never guess between public and beta state directories.
# Codex supplies CLAUDE_PLUGIN_DATA; without it the safe behavior is fail-open.
mkdir -p "$BETA_CODEX_HOME/plugins/data/clover-clover-security/bin"
cp "$FAKE_MARKETPLACE/bin/$BINARY_NAME" "$BETA_CODEX_HOME/plugins/data/clover-clover-security/bin/clover-hook"
DISPATCHER_OUTPUT="$(env -u CLAUDE_PLUGIN_DATA \
  HOME="$TEST_DIR/home" CODEX_HOME="$BETA_CODEX_HOME" CLAUDE_PLUGIN_ROOT="$ROOT" \
  bash "$ROOT/codex/scripts/run-hook.sh" codex-doctor 2>&1)"
case "$DISPATCHER_OUTPUT" in
  *'fail-open (plugin data directory missing)'*) ;;
  *) printf 'dispatcher guessed a Clover data directory: %s\n' "$DISPATCHER_OUTPUT" >&2; exit 1 ;;
esac

# SessionStart must remember which plugin-cache version it bootstrapped from.
# A compatible binary self-update changes .version; a later SessionStart from
# the same cache must preserve that newer binary instead of restoring the
# bundled one and racing the Stop hook.
DEVELOPER_DATA="$CODEX_HOME/plugins/data/clover-clover-security"
CLAUDE_PLUGIN_ROOT="$ROOT" CLAUDE_PLUGIN_DATA="$DEVELOPER_DATA" \
  bash "$ROOT/codex/scripts/setup.sh"
test -s "$DEVELOPER_DATA/bin/.codex-source-version"
printf '%s\n' '#!/usr/bin/env bash' 'printf self-updated' > "$DEVELOPER_DATA/bin/clover-hook"
chmod +x "$DEVELOPER_DATA/bin/clover-hook"
printf '%s\n' '9.9.9' > "$DEVELOPER_DATA/bin/.version"
CLAUDE_PLUGIN_ROOT="$ROOT" CLAUDE_PLUGIN_DATA="$DEVELOPER_DATA" \
  bash "$ROOT/codex/scripts/setup.sh"
test "$("$DEVELOPER_DATA/bin/clover-hook")" = 'self-updated'
test "$(cat "$DEVELOPER_DATA/bin/.version")" = '9.9.9'

# An incomplete file from an earlier/manual setup must never be treated as
# configured. Otherwise a cached token can make doctor pass until that token
# expires, leaving the next session unable to authenticate.
INCOMPLETE_HOME="$TEST_DIR/incomplete-codex-home"
INCOMPLETE_DATA="$INCOMPLETE_HOME/plugins/data/clover-clover-security"
mkdir -p "$INCOMPLETE_DATA"
printf '%s\n' 'export CLOVER_CODEX_SELF_UPDATE=0' > "$INCOMPLETE_DATA/env.sh"
if env \
  "PATH=$MOCK_BIN:$PATH" \
  "HOME=$TEST_DIR/home" \
  "CLOVER_MARKETPLACE_URL=file://$FAKE_MARKETPLACE" \
  "CLOVER_MARKETPLACE_GIT_URL=https://example.invalid/clover.git" \
  "CLOVER_NO_PROMPT=1" \
  CODEX_HOME="$INCOMPLETE_HOME" \
  CODEX_COMMAND_LOG="$TEST_DIR/incomplete-codex-commands.log" \
  bash "$TEST_DIR/install.sh" > "$TEST_DIR/incomplete.out" 2>&1; then
  printf 'developer installer accepted an incomplete credential file\n' >&2
  exit 1
fi
grep -q 'client credentials are required' "$TEST_DIR/incomplete.out"

# Managed mode: render absolute hook commands, install the runtime without a
# plugin source, and keep broad allow_managed_hooks_only policy unset.
SYSTEM_DIR="$TEST_DIR/opt/clover/codex"
REQUIREMENTS_FILE="$TEST_DIR/etc/codex/requirements.toml"
MANAGED_DATA="$TEST_DIR/managed-data"
env "${COMMON_ENV[@]}" \
  CLOVER_CODEX_SYSTEM_DIR="$SYSTEM_DIR" \
  CLOVER_CODEX_REQUIREMENTS_FILE="$REQUIREMENTS_FILE" \
  CLOVER_CODEX_DATA_DIR="$MANAGED_DATA" \
  CLOVER_CODEX_NO_SUDO=1 \
  bash "$TEST_DIR/install.sh" --managed > "$TEST_DIR/managed.out"
grep -q 'backend verification succeeded' "$TEST_DIR/managed.out"
test -x "$SYSTEM_DIR/run-hook.sh"
test -x "$SYSTEM_DIR/bin/clover-hook"
python3 - "$REQUIREMENTS_FILE" "$SYSTEM_DIR" <<'PY'
import pathlib, sys, tomllib
path, managed_dir = pathlib.Path(sys.argv[1]), sys.argv[2]
config = tomllib.loads(path.read_text())
assert config["features"]["hooks"] is True
assert config["hooks"]["managed_dir"] == managed_dir
assert "allow_managed_hooks_only" not in config
assert set(config["hooks"]) == {"managed_dir", "PreToolUse", "Stop", "UserPromptSubmit"}
commands = [hook["command"] for event in ("PreToolUse", "Stop", "UserPromptSubmit") for group in config["hooks"][event] for hook in group["hooks"]]
assert all(command.startswith(managed_dir + "/run-hook.sh ") for command in commands), commands
PY

# An organization-owned requirements file is never replaced or appended to by
# the one-liner; the administrator must merge the shipped template centrally.
FOREIGN_REQUIREMENTS="$TEST_DIR/foreign/requirements.toml"
mkdir -p "$(dirname "$FOREIGN_REQUIREMENTS")"
printf '%s\n' 'allowed_sandbox_modes = ["read-only"]' > "$FOREIGN_REQUIREMENTS"
if env "${COMMON_ENV[@]}" \
  CLOVER_CODEX_SYSTEM_DIR="$TEST_DIR/foreign-system" \
  CLOVER_CODEX_REQUIREMENTS_FILE="$FOREIGN_REQUIREMENTS" \
  CLOVER_CODEX_DATA_DIR="$MANAGED_DATA" \
  CLOVER_CODEX_NO_SUDO=1 \
  bash "$TEST_DIR/install.sh" --managed > "$TEST_DIR/foreign.out" 2>&1; then
  printf 'managed installer overwrote an organization requirements file\n' >&2
  exit 1
fi
test "$(cat "$FOREIGN_REQUIREMENTS")" = 'allowed_sandbox_modes = ["read-only"]'

printf 'Codex developer and managed installers: OK\n'
