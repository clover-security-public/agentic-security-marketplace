#!/usr/bin/env bash
# A Clover hook runs on every prompt, and the developer waits for it. A customer
# once waited 78s per Cursor prompt because the launcher walked every repo under
# ~/.cursor/worktrees looking for credentials, and nothing caught it before they
# did. This runs each POSIX launcher end to end — the real launcher, the binary
# built from this tree, a local mock backend — against a home directory shaped
# like a heavy user's, and fails when a hook takes longer than the budget.
#
# The budget is generous (CLOVER_HOOK_BUDGET_MS, default 2000ms) so a slow CI
# runner does not flake it: a healthy hook here takes a few hundred
# milliseconds at most. A budget catches work that is expensive per file (a
# process per config, a network call, a retry loop); it cannot catch a plain
# walk, which costs microseconds a file on a fast runner — the incident's walk
# took 35s only because the customer's tree was millions of files, far more
# than CI can build. So every find a launcher runs is also recorded, and a walk
# of the home directory, ~/.cursor or its worktrees fails outright.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REPO="$(cd "$ROOT/.." && pwd)"
BUDGET_MS="${CLOVER_HOOK_BUDGET_MS:-2000}"
TEST_DIR="$(mktemp -d)"
SERVER_PID=""
cleanup() {
  if [ -n "$SERVER_PID" ]; then
    kill "$SERVER_PID" 2>/dev/null || true
    wait "$SERVER_PID" 2>/dev/null || true
  fi
  rm -rf "$TEST_DIR"
}
trap cleanup EXIT

for tool in go jq python3 perl; do
  command -v "$tool" >/dev/null || { echo "hook-latency.sh: $tool is required" >&2; exit 2; }
done

now_ms() { perl -MTime::HiRes=time -e 'printf "%d\n", time * 1000'; }

# --- The binary from this tree ---------------------------------------------------
BIN="$TEST_DIR/clover-hook"
(cd "$REPO" && CGO_ENABLED=0 go build -o "$BIN" ./cmd/clover-hook/)

# --- A find that records where it starts walking ---------------------------------
mkdir -p "$TEST_DIR/fakebin"
REAL_FIND="$(command -v find)"
cat > "$TEST_DIR/fakebin/find" <<EOF
#!/usr/bin/env bash
# The roots are the arguments before the first expression.
for arg in "\$@"; do
  case "\$arg" in -H|-L|-P) continue ;; -*|'('|'!') break ;; esac
  printf '%s\n' "\$arg" >> "$TEST_DIR/find-roots"
done
exec "$REAL_FIND" "\$@"
EOF
chmod +x "$TEST_DIR/fakebin/find"

# --- A mock backend: any POST gets a token, which every endpoint can parse -------
cat > "$TEST_DIR/backend.py" <<'EOF'
import http.server, sys

class Handler(http.server.BaseHTTPRequestHandler):
    def reply(self):
        length = int(self.headers.get("Content-Length") or 0)
        if length:
            self.rfile.read(length)
        body = b'{"accessToken":"t","expiresIn":3600}'
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)
    do_POST = do_GET = do_PUT = reply
    def log_message(self, *args):
        pass

server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
with open(sys.argv[1], "w") as port_file:
    port_file.write(str(server.server_address[1]))
server.serve_forever()
EOF
python3 "$TEST_DIR/backend.py" "$TEST_DIR/port" &
SERVER_PID=$!
for _ in $(seq 1 100); do [ -s "$TEST_DIR/port" ] && break; sleep 0.05; done
[ -s "$TEST_DIR/port" ] || { echo "hook-latency.sh: mock backend did not start" >&2; exit 2; }
BACKEND="http://127.0.0.1:$(cat "$TEST_DIR/port")"

# --- A heavy user's home ---------------------------------------------------------
# ~/.cursor/worktrees holds a checkout of every repo the user opened in Cursor:
# here 1500 of them, each with source files and the repo's own .cursor/mcp.json
# (which names no Clover server), ~30k files in all. A launcher that searches
# outside the plugin tree reads every one of those configs.
HOME_DIR="$TEST_DIR/home"
CURSOR_DIR="$HOME_DIR/.cursor"
WORKSPACE="$TEST_DIR/workspace"
mkdir -p "$WORKSPACE" "$CURSOR_DIR/plans"
for repo in $(seq 1 1500); do
  checkout="$CURSOR_DIR/worktrees/repo$repo/feature"
  mkdir -p "$checkout/.cursor" "$checkout/src/app" "$checkout/src/lib"
  printf '{"mcpServers":{"local-tools":{"command":"node","args":["tools.js"]}}}\n' > "$checkout/.cursor/mcp.json"
  (cd "$checkout/src/app" && touch a.ts b.ts c.ts d.ts e.ts f.ts g.ts h.ts)
  (cd "$checkout/src/lib" && touch a.ts b.ts c.ts d.ts e.ts f.ts g.ts h.ts)
done
# The Clover credentials, where the team-pushed clover-mcp plugin ships them.
MCP="$CURSOR_DIR/plugins/cache/org/clover-mcp/sha1/.mcp.json"
mkdir -p "$(dirname "$MCP")"
printf '{"mcpServers":{"Clover MCP":{"url":"%s/mcp","auth":{"CLIENT_ID":"id","CLIENT_SECRET":"secret","AUTH_URL":"%s"}}}}\n' \
  "$BACKEND" "$BACKEND" > "$MCP"

FAILED=0
# timed <label> <command...> runs one hook with the payload on stdin and fails
# the test if it takes longer than the budget.
timed() {
  local label="$1" started elapsed
  shift
  started="$(now_ms)"
  "$@" >/dev/null 2>"$TEST_DIR/stderr" || true
  elapsed=$(( $(now_ms) - started ))
  if [ "$elapsed" -gt "$BUDGET_MS" ]; then
    echo "FAIL: $label took ${elapsed}ms, budget ${BUDGET_MS}ms" >&2
    sed 's/^/    /' "$TEST_DIR/stderr" >&2
    FAILED=1
  else
    echo "  $label: ${elapsed}ms"
  fi
}

# A clean environment: nothing from the developer's machine or the runner (real
# credentials, CLAUDE_PLUGIN_DATA, CURSOR_PLUGIN_ROOT) reaches the hooks.
clean_env() { env -i HOME="$HOME_DIR" PATH="$TEST_DIR/fakebin:$PATH" TMPDIR="$TEST_DIR" "$@"; }

CREDS=(CAS_CLOVER_PLUGIN_CLIENT_ID=id CAS_CLOVER_PLUGIN_CLIENT_SECRET=secret
  CAS_CLOVER_PLUGIN_AUTH_URL="$BACKEND" CAS_CLOVER_PLUGIN_SERVER_URL="$BACKEND")

# --- Cursor: credentials from the plugin tree, then the binary -------------------
echo "cursor:"
cursor_hook() {
  printf '%s' "$2" | clean_env CLOVER_HOOK_BIN="$BIN" \
    bash "$ROOT/cursor/scripts/clover-hook.cmd" "$1"
}
PROMPT='{"conversation_id":"c1","generation_id":"g1","prompt":"add a login endpoint","workspace_roots":["'"$WORKSPACE"'"]}'
STOP='{"conversation_id":"c1","generation_id":"g1","status":"completed","loop_count":0,"workspace_roots":["'"$WORKSPACE"'"]}'
timed "log-prompt (first, searches for credentials)" cursor_hook log-prompt "$PROMPT"
timed "log-prompt (remembered credentials)" cursor_hook log-prompt "$PROMPT"
# A plan written during the turn, so the stop runs a review, not just the lookup.
printf -- '---\nname: Login\noverview: Add a login endpoint\n---\n\n# Plan\n\nPOST /login with bcrypt.\n' \
  > "$CURSOR_DIR/plans/login_1234.plan.md"
timed "review-plan-stop" cursor_hook review-plan-stop "$STOP"

# The binary logs each invocation's time, including the launcher's own share
# where the launcher's bash has $EPOCHREALTIME (bash 5; macOS's bash 3.2 has
# none, and reports no share rather than a wrong one). Cursor's macOS/Linux
# launcher sets no CLAUDE_PLUGIN_DATA for the shared log-prompt, so that line
# lands in the temp dir's log.
cursor_prompt_line='hook_duration cmd=log-prompt agent="cursor" coding_agent="Cursor" '
if bash -c '[ -n "${EPOCHREALTIME:-}" ]'; then
  if ! grep -q "$cursor_prompt_line.*since_launch_ms=" "$TEST_DIR/.clover-hook.log" 2>/dev/null; then
    echo "FAIL: no hook_duration line with since_launch_ms for Cursor's log-prompt" >&2
    FAILED=1
  fi
elif ! grep "$cursor_prompt_line" "$TEST_DIR/.clover-hook.log" 2>/dev/null | grep -qv since_launch_ms; then
  echo "FAIL: no hook_duration line without since_launch_ms for Cursor's log-prompt under a bash without EPOCHREALTIME" >&2
  FAILED=1
fi

# --- The other POSIX launchers, each with a deployed binary and credentials ------
# Every launcher's prompt hook runs with its install already set up, so the
# timing is the steady state a developer sees on each prompt.
CLAUDE_PROMPT='{"session_id":"s1","cwd":"'"$WORKSPACE"'","prompt":"add a login endpoint","hook_event_name":"UserPromptSubmit"}'

deployed_data() {
  local data="$TEST_DIR/data-$1"
  mkdir -p "$data/bin"
  cp "$BIN" "$data/bin/clover-hook"
  printf '%s' "$data"
}

echo "claude:"
CLAUDE_DATA="$(deployed_data claude)"
mkdir -p "$TEST_DIR/claude-root/.claude-plugin" "$HOME_DIR/.claude/plugins"
printf '{"name":"clover","version":"1.0.0"}\n' > "$TEST_DIR/claude-root/.claude-plugin/plugin.json"
echo "1.0.0" > "$CLAUDE_DATA/bin/.version"
printf '{"plugins":{"clover@clover-security":[]}}\n' > "$HOME_DIR/.claude/plugins/installed_plugins.json"
claude_hook() {
  printf '%s' "$CLAUDE_PROMPT" | clean_env "${CREDS[@]}" CLAUDE_PLUGIN_ROOT="$TEST_DIR/claude-root" \
    CLAUDE_PLUGIN_DATA="$CLAUDE_DATA" bash "$ROOT/claude/scripts/run-hook.sh" log-prompt
}
timed "log-prompt" claude_hook

echo "codex:"
CODEX_DATA="$(deployed_data codex)"
mkdir -p "$TEST_DIR/codex-root/.codex-plugin"
printf '{"name":"clover","version":"1.0.0"}\n' > "$TEST_DIR/codex-root/.codex-plugin/plugin.json"
printf '1.0.0' > "$CODEX_DATA/bin/.codex-source-version"
codex_hook() {
  printf '%s' "$CLAUDE_PROMPT" | clean_env "${CREDS[@]}" CLAUDE_PLUGIN_ROOT="$TEST_DIR/codex-root" \
    CLAUDE_PLUGIN_DATA="$CODEX_DATA" bash "$ROOT/codex/scripts/run-hook.sh" codex-log-prompt
}
timed "codex-log-prompt" codex_hook

echo "copilot:"
COPILOT_DATA="$(deployed_data copilot)"
mkdir -p "$TEST_DIR/copilot-root/.claude-plugin"
printf '{"name":"clover","version":"1.0.0"}\n' > "$TEST_DIR/copilot-root/.claude-plugin/plugin.json"
echo "1.0.0" > "$COPILOT_DATA/bin/.version"
copilot_hook() {
  printf '{"sessionId":"s1","cwd":"%s","prompt":"add a login endpoint","timestamp":1}' "$WORKSPACE" |
    clean_env "${CREDS[@]}" COPILOT_PLUGIN_ROOT="$TEST_DIR/copilot-root" COPILOT_PLUGIN_DATA="$COPILOT_DATA" \
      bash "$ROOT/copilot/scripts/run-hook.sh" log-prompt
}
timed "log-prompt" copilot_hook

echo "devin:"
DEVIN_DATA="$(deployed_data devin)"
mkdir -p "$DEVIN_DATA/.claude-plugin"
printf '{"name":"clover","version":"1.0.0"}\n' > "$DEVIN_DATA/.claude-plugin/plugin.json"
devin_hook() {
  printf '%s' "$CLAUDE_PROMPT" | clean_env "${CREDS[@]}" CLOVER_DEVIN_DATA="$DEVIN_DATA" \
    bash "$ROOT/devin/scripts/run-hook.sh" log-prompt
}
timed "log-prompt" devin_hook

echo "kiro:"
# The Kiro launcher treats its own parent as the install, so it runs from a copy.
KIRO_ROOT="$TEST_DIR/kiro-install"
mkdir -p "$KIRO_ROOT/scripts"
cp "$ROOT/kiro/scripts/run-hook.sh" "$KIRO_ROOT/scripts/run-hook.sh"
kiro_hook() {
  printf '{"session_id":"s1","cwd":"%s","prompt":"add a login endpoint","hook_event_name":"UserPromptSubmit"}' "$WORKSPACE" |
    clean_env "${CREDS[@]}" CLOVER_HOOK_BIN="$BIN" bash "$KIRO_ROOT/scripts/run-hook.sh" kiro-log-prompt
}
timed "kiro-log-prompt" kiro_hook

# No hook may walk the home directory, ~/.cursor, or any checkout under it.
while IFS= read -r walked; do
  walked="${walked%/}"
  case "$walked" in
    "$HOME_DIR" | "$HOME_DIR/.cursor" | "$HOME_DIR/.cursor/worktrees" | "$HOME_DIR/.cursor/worktrees/"*)
      echo "FAIL: a hook ran find over $walked, which grows with every repo the user opens" >&2
      FAILED=1 ;;
  esac
done < <(sort -u "$TEST_DIR/find-roots" 2>/dev/null)

if [ "$FAILED" != 0 ]; then
  exit 1
fi
echo "hook-latency.sh: ok"
