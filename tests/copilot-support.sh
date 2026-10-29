#!/usr/bin/env bash
# GitHub Copilot packaging: the manifests Copilot reads, the hooks it runs, and
# the launcher between them and the binary.
#
# Copilot resolves a plugin's manifest from .plugin/ before .claude-plugin/, and
# a marketplace from .plugin/marketplace.json before .claude-plugin/ — so the
# .plugin/ pair is what keeps Copilot off the Claude hooks, whose ExitPlanMode
# matcher never fires there and whose .md gate cannot parse Copilot's payloads.
# A root plugin.json or marketplace.json would outrank both.
#
# Copilot's preToolUse fails CLOSED on a non-zero exit, so every launcher path
# here must end in exit 0 with nothing on stdout but the binary's own decision.
#
# Run from anywhere: bash tests/copilot-support.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_DIR="$(mktemp -d)"
trap 'rm -rf "$TEST_DIR"' EXIT

fail() { printf 'copilot-support: %s\n' "$*" >&2; exit 1; }

bash -n "$ROOT/copilot/scripts/run-hook.sh" "$ROOT/copilot/scripts/configure.sh"
for f in "$ROOT/copilot/scripts/run-hook.sh" "$ROOT/copilot/scripts/configure.sh"; do
  [ -x "$f" ] || fail "$f is not executable"
done

# --- manifests and hooks ------------------------------------------------------
python3 - "$ROOT" <<'PY'
import json, pathlib, re, sys
root = pathlib.Path(sys.argv[1])
load = lambda p: json.loads((root / p).read_text())

for outranking in ("plugin.json", "marketplace.json"):
    assert not (root / outranking).exists(), f"a root {outranking} would outrank .plugin/ in Copilot"

claude_plugin = load(".claude-plugin/plugin.json")
claude_market = load(".claude-plugin/marketplace.json")
plugin = load(".plugin/plugin.json")
market = load(".plugin/marketplace.json")

assert plugin["name"] == claude_plugin["name"] == "clover", plugin["name"]
assert plugin["version"] == claude_plugin["version"], (plugin["version"], claude_plugin["version"])
# A hooks field must name the Copilot file explicitly: without it Copilot falls
# back to the root hooks.json, which is Devin's.
assert plugin["hooks"] == "copilot/hooks/hooks.json", plugin.get("hooks")
assert (root / plugin["hooks"]).is_file()

assert market["name"] == claude_market["name"], (market["name"], claude_market["name"])
assert [p["name"] for p in market["plugins"]] == ["clover"], market["plugins"]
entry = market["plugins"][0]
claude_entry = next(p for p in claude_market["plugins"] if p["name"] == "clover")
assert entry["version"] == claude_plugin["version"], entry["version"]
assert entry["source"] == claude_entry["source"], (entry["source"], claude_entry["source"])
# The plugin's hooks.json is the one definition; an entry copy could drift.
assert "hooks" not in entry, "the Copilot marketplace entry must not inline hooks"

hooks = load("copilot/hooks/hooks.json")
assert hooks["version"] == 1, hooks.get("version")
events = hooks["hooks"]
assert set(events) == {"sessionStart", "userPromptSubmitted", "preToolUse"}, set(events)

def subcommand(hook):
    bash = hook["bash"]
    prefix = 'bash "${COPILOT_PLUGIN_ROOT}/copilot/scripts/run-hook.sh" '
    assert bash.startswith(prefix), bash
    sub = bash[len(prefix):]
    # PowerShell must end in exit 0 whatever the batch file returns.
    assert hook["powershell"] == f'& "$env:COPILOT_PLUGIN_ROOT\\copilot\\scripts\\clover-hook.cmd" {sub}; exit 0', hook["powershell"]
    assert hook.get("type", "command") == "command", hook
    return sub

assert [subcommand(h) for h in events["sessionStart"]] == ["setup", "check-update"]
assert [subcommand(h) for h in events["userPromptSubmitted"]] == ["log-prompt"]

gates = {h["matcher"]: subcommand(h) for h in events["preToolUse"]}
assert gates == {"^exit_plan_mode$": "review-plan", "^(create|edit|apply_patch)$": "should-review-plan"}, gates
for hook in events["preToolUse"]:
    # Copilot's default is 30s and a timeout fails open — mid-review.
    assert hook.get("timeoutSec", 0) >= 300, hook
plan, write = re.compile("^exit_plan_mode$"), re.compile("^(create|edit|apply_patch)$")
assert plan.search("exit_plan_mode") and not plan.search("exit_plan_mode_v2")
for tool in ("create", "edit", "apply_patch"):
    assert write.search(tool), tool
for tool in ("create_issue", "github-mcp-server-create_pull_request", "multi_edit", "view"):
    assert not write.search(tool), f"write gate must not fire on {tool}"
PY

# --- Windows entry point ------------------------------------------------------
CMD="$ROOT/copilot/scripts/clover-hook.cmd"
python3 - "$CMD" <<'PY'
import sys
raw = open(sys.argv[1], "rb").read()
lines = raw.split(b"\n")[:-1]
# cmd.exe misparses LF-only batch files.
assert lines and all(line.endswith(b"\r") for line in lines), "clover-hook.cmd must use CRLF line endings"
text = raw.decode()
for sub in ("setup", "check-update", "log-prompt", "review-plan", "should-review-plan"):
    assert f'"{sub}" set "SUB=copilot-{sub}"' in text, f"clover-hook.cmd does not map {sub}"
assert text.rstrip().endswith("exit /b 0"), "clover-hook.cmd must always exit 0"
PY

# --- launcher -----------------------------------------------------------------
FAKE_TREE="$TEST_DIR/tree"
mkdir -p "$FAKE_TREE/.claude-plugin" "$FAKE_TREE/claude/scripts" "$FAKE_TREE/copilot/scripts" "$FAKE_TREE/bin"
cp "$ROOT/.claude-plugin/plugin.json" "$FAKE_TREE/.claude-plugin/plugin.json"
cp "$ROOT/claude/scripts/setup.sh" "$FAKE_TREE/claude/scripts/setup.sh"
cp "$ROOT/copilot/scripts/run-hook.sh" "$ROOT/copilot/scripts/configure.sh" "$FAKE_TREE/copilot/scripts/"

OS="$(uname -s | tr '[:upper:]' '[:lower:]')"
case "$OS" in darwin*) OS=darwin ;; linux*) OS=linux ;; esac
ARCH="$(uname -m)"
case "$ARCH" in x86_64) ARCH=amd64 ;; aarch64|arm64) ARCH=arm64 ;; esac
BINARY_NAME="clover-hook-${OS}-${ARCH}"

# The fake binary records how it was called and answers like the real one.
write_fake_binary() {
  cat > "$FAKE_TREE/bin/$BINARY_NAME" <<EOF
#!/usr/bin/env bash
{ printf 'argv=%s\n' "\$*"; printf 'stdin=%s\n' "\$(cat)"; printf 'client=%s\n' "\${CLOVER_SECURITY_KURA_PLUGIN_CLIENT_ID:-}"; printf 'build=$1\n'; } >> "\$FAKE_LOG"
printf '%s' "\${FAKE_STDOUT:-}"
exit "\${FAKE_EXIT:-0}"
EOF
  chmod +x "$FAKE_TREE/bin/$BINARY_NAME"
  (
    cd "$FAKE_TREE/bin"
    if command -v sha256sum >/dev/null; then sha256sum "$BINARY_NAME" > checksums.sha256
    else shasum -a 256 "$BINARY_NAME" > checksums.sha256; fi
  )
}
write_fake_binary one

DATA="$TEST_DIR/data"
FAKE_LOG="$TEST_DIR/fake.log"
# Only the variables Copilot sets for a plugin hook — the COPILOT_* names; the
# launcher must not need the CLAUDE_* aliases.
launch() {
  env -i PATH="$PATH" HOME="$TEST_DIR/home" FAKE_LOG="$FAKE_LOG" \
    COPILOT_PLUGIN_ROOT="$FAKE_TREE" COPILOT_PLUGIN_DATA="$DATA" "$@"
}
run_hook() { bash "$FAKE_TREE/copilot/scripts/run-hook.sh" "$@"; }

# First hook of a session deploys the verified binary and forwards stdin.
out="$(printf '%s' '{"toolName":"exit_plan_mode"}' | launch FAKE_STDOUT='{"permissionDecision":"deny"}' \
  bash "$FAKE_TREE/copilot/scripts/run-hook.sh" review-plan 2>/dev/null)"
[ "$out" = '{"permissionDecision":"deny"}' ] || fail "decision not passed through: $out"
[ -x "$DATA/bin/clover-hook" ] || fail "binary was not deployed to the plugin data dir"
grep -qx 'argv=copilot-review-plan' "$FAKE_LOG" || fail "review-plan did not reach copilot-review-plan: $(cat "$FAKE_LOG")"
grep -qx 'stdin={"toolName":"exit_plan_mode"}' "$FAKE_LOG" || fail "stdin was not forwarded"

for sub in setup check-update log-prompt should-review-plan; do
  : > "$FAKE_LOG"
  printf '{}' | launch bash "$FAKE_TREE/copilot/scripts/run-hook.sh" "$sub" >/dev/null 2>&1
  grep -qx "argv=copilot-$sub" "$FAKE_LOG" || fail "$sub did not reach copilot-$sub"
done

# A crashing binary must not deny the developer's tool call.
set +e
out="$(printf '{}' | launch FAKE_EXIT=3 bash "$FAKE_TREE/copilot/scripts/run-hook.sh" should-review-plan 2>/dev/null)"
status=$?
set -e
[ "$status" -eq 0 ] || fail "launcher exited $status when the binary failed"

# Credentials written by configure.sh reach the binary.
: > "$FAKE_LOG"
printf "export CLOVER_SECURITY_KURA_PLUGIN_CLIENT_ID='from-env-sh'\n" > "$DATA/env.sh"
printf '{}' | launch bash "$FAKE_TREE/copilot/scripts/run-hook.sh" log-prompt >/dev/null 2>&1
grep -qx 'client=from-env-sh' "$FAKE_LOG" || fail "env.sh was not sourced"
rm -f "$DATA/env.sh"

# Unknown subcommands, and a missing data dir, fail open without the binary.
: > "$FAKE_LOG"
out="$(printf '{}' | launch bash "$FAKE_TREE/copilot/scripts/run-hook.sh" no-such-hook 2>/dev/null)"
[ -z "$out" ] && [ ! -s "$FAKE_LOG" ] || fail "unknown subcommand ran the binary or printed: $out"
out="$(printf '{}' | env -i PATH="$PATH" HOME="$TEST_DIR/home" FAKE_LOG="$FAKE_LOG" \
  bash "$FAKE_TREE/copilot/scripts/run-hook.sh" review-plan 2>&1)"
case "$out" in *'fail-open'*) ;; *) fail "missing data dir did not fail open: $out" ;; esac
[ ! -s "$FAKE_LOG" ] || fail "binary ran without a data dir"

# A newer tree (copilot plugin update) redeploys; an equal one does not.
python3 - "$FAKE_TREE/.claude-plugin/plugin.json" <<'PY'
import json, sys
p = sys.argv[1]; m = json.load(open(p)); m["version"] = "99.0.0"; json.dump(m, open(p, "w"))
PY
write_fake_binary two
: > "$FAKE_LOG"
printf '{}' | launch bash "$FAKE_TREE/copilot/scripts/run-hook.sh" log-prompt >/dev/null 2>&1
grep -qx 'build=two' "$FAKE_LOG" || fail "an updated tree did not redeploy the binary"
[ "$(cat "$DATA/bin/.version")" = "99.0.0" ] || fail "redeploy did not record the tree version"

# A tree whose binary fails its checksum deploys nothing and prints nothing:
# sessionStart stdout is parsed as hook output.
BROKEN_DATA="$TEST_DIR/broken-data"
printf 'tampered' >> "$FAKE_TREE/bin/$BINARY_NAME"
set +e
out="$(printf '{}' | env -i PATH="$PATH" HOME="$TEST_DIR/home" FAKE_LOG="$FAKE_LOG" \
  COPILOT_PLUGIN_ROOT="$FAKE_TREE" COPILOT_PLUGIN_DATA="$BROKEN_DATA" \
  bash "$FAKE_TREE/copilot/scripts/run-hook.sh" setup 2>/dev/null)"
status=$?
set -e
[ "$status" -eq 0 ] && [ -z "$out" ] || fail "tampered tree: status=$status stdout=$out"
[ ! -e "$BROKEN_DATA/bin/clover-hook" ] || fail "a binary failing its checksum was deployed"

# --- configure.sh -------------------------------------------------------------
CONFIG_DATA="$TEST_DIR/config data"
env -i PATH="$PATH" HOME="$TEST_DIR/home" \
  CLOVER_SECURITY_KURA_PLUGIN_CLIENT_ID=test-client CLOVER_SECURITY_KURA_PLUGIN_CLIENT_SECRET=test-secret \
  bash "$ROOT/copilot/scripts/configure.sh" "$CONFIG_DATA" --from-env >/dev/null
python3 - "$CONFIG_DATA/env.sh" <<'PY'
import os, stat, sys
path = sys.argv[1]
assert stat.S_IMODE(os.stat(path).st_mode) == 0o600, oct(os.stat(path).st_mode)
content = open(path).read()
assert "export CLOVER_SECURITY_KURA_PLUGIN_CLIENT_ID=test-client" in content, content
assert "export CLOVER_SECURITY_KURA_PLUGIN_CLIENT_SECRET=test-secret" in content, content
PY
# A marketplace install puts the tree at <home>/installed-plugins/<market>/<plugin>
# and its data at <home>/plugin-data/<market>/<plugin>, so the documented
# command needs no argument.
INSTALLED="$TEST_DIR/copilot-home/installed-plugins/clover-security/clover"
mkdir -p "$INSTALLED/copilot/scripts" "$INSTALLED/devin/scripts"
cp "$ROOT/copilot/scripts/configure.sh" "$INSTALLED/copilot/scripts/"
cp "$ROOT/devin/scripts/configure.sh" "$INSTALLED/devin/scripts/"
env -i PATH="$PATH" HOME="$TEST_DIR/home" \
  CLOVER_SECURITY_KURA_PLUGIN_CLIENT_ID=derived CLOVER_SECURITY_KURA_PLUGIN_CLIENT_SECRET=derived \
  bash "$INSTALLED/copilot/scripts/configure.sh" --from-env >/dev/null
grep -q 'CLIENT_ID=derived' "$TEST_DIR/copilot-home/plugin-data/clover-security/clover/env.sh" \
  || fail "configure.sh did not derive the marketplace install's data dir"

# Anywhere else (a direct install, a checkout) there is nothing to derive from.
set +e
env -i PATH="$PATH" HOME="$TEST_DIR/home" bash "$ROOT/copilot/scripts/configure.sh" >/dev/null 2>&1
status=$?
set -e
[ "$status" -eq 2 ] || fail "configure.sh without a derivable data dir must exit 2, got $status"

printf 'Copilot packaging and launcher: OK\n'
