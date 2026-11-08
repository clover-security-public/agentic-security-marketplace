#!/usr/bin/env bash
# Cursor's run-hook.sh forwards what Cursor reports about itself to the binary.
# Those fields are informational, so one Cursor sends in an unexpected shape is
# dropped rather than forwarded, and the rest still arrive.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEST_DIR="$(mktemp -d)"
trap 'rm -rf "$TEST_DIR"' EXIT

# A stand-in binary that records the payload the script hands it.
cat > "$TEST_DIR/clover-hook" <<EOF
#!/usr/bin/env bash
cat > "$TEST_DIR/received.json"
EOF
chmod +x "$TEST_DIR/clover-hook"

run_log_prompt() {
  rm -f "$TEST_DIR/received.json"
  printf '%s' "$1" | CLOVER_HOOK_BIN="$TEST_DIR/clover-hook" CLOVER_STATE_DIR="$TEST_DIR/state" \
    CURSOR_CODE_REMOTE="" CURSOR_VERSION="" bash "$ROOT/cursor/scripts/run-hook.sh" log-prompt >/dev/null
  cat "$TEST_DIR/received.json"
}

expect() {
  local label="$1" got="$2" want="$3"
  if [ "$got" != "$want" ]; then
    echo "ERROR: $label: got $got, want $want" >&2
    exit 1
  fi
}

report_of() {
  jq -c '{codingAgentVersion, model, userEmail, workspaceRoots, remote}' <<<"$1"
}

received="$(run_log_prompt '{"conversation_id":"c1","prompt":"hi","cursor_version":"1.7.2","model":"gpt-5","user_email":"dana@acme.com","workspace_roots":["/work/api","/work/web"]}')"
expect "well-formed report" "$(report_of "$received")" \
  '{"codingAgentVersion":"1.7.2","model":"gpt-5","userEmail":"dana@acme.com","workspaceRoots":["/work/api","/work/web"],"remote":null}'
expect "attribution" "$(jq -c '{codingAgent, prompt}' <<<"$received")" '{"codingAgent":"Cursor","prompt":"hi"}'

received="$(run_log_prompt '{"conversation_id":"c1","prompt":"hi","cursor_version":1.7,"model":{"id":"gpt-5"},"user_email":"dana@acme.com","workspace_roots":["/work/api",3,null]}')"
expect "odd-typed report" "$(report_of "$received")" \
  '{"codingAgentVersion":null,"model":null,"userEmail":"dana@acme.com","workspaceRoots":["/work/api"],"remote":null}'
expect "attribution with odd report" "$(jq -c '{codingAgent, prompt}' <<<"$received")" '{"codingAgent":"Cursor","prompt":"hi"}'

received="$(run_log_prompt '{"conversation_id":"c1","prompt":"hi","workspace_roots":"/work/api"}')"
expect "non-array workspace roots" "$(jq -c '.workspaceRoots' <<<"$received")" 'null'

echo "cursor-report: OK"
