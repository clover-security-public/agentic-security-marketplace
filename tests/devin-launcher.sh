#!/usr/bin/env bash
# The Devin launcher (devin/scripts/run-hook.sh) hands every hook to the
# binary's devin-* subcommands and needs nothing but bash and the binary.
#
# jq used to sit between the hook and the binary, and a machine without it
# allowed every write unreviewed. These checks run the launcher under a PATH
# with no jq and assert that each hook still reaches its subcommand with the
# payload intact, that the binary's block reaches Devin unchanged, that the
# self-update keeps stdout clean, and that env.sh supplies credentials only when
# the environment carries none.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LAUNCHER="$ROOT/devin/scripts/run-hook.sh"
TEST_DIR="$(mktemp -d)"
trap 'rm -rf "$TEST_DIR"' EXIT

BASH_BIN="$(command -v bash)"
NO_JQ_PATH="$TEST_DIR/path"
mkdir -p "$NO_JQ_PATH"
for tool in cat dirname chmod date; do
  ln -s "$(command -v "$tool")" "$NO_JQ_PATH/$tool"
done

MOCK_HOOK="$TEST_DIR/clover-hook"
CALLS="$TEST_DIR/calls"
DATA="$TEST_DIR/data"
mkdir -p "$DATA/.claude-plugin"
printf '{"version":"0.0.0"}\n' > "$DATA/.claude-plugin/plugin.json"

cat > "$MOCK_HOOK" <<EOF
#!$BASH_BIN
payload="\$(cat)"
printf '%s id=%s payload=%s\n' "\$1" "\${CLOVER_SECURITY_KURA_PLUGIN_CLIENT_ID:-}" "\$payload" >> "$CALLS"
case "\$1" in
  devin-review-write) printf '{"decision":"block","reason":"needs rate limiting"}\n' ;;
  devin-check-update) printf 'update chatter\n' ;;
esac
EOF
chmod +x "$MOCK_HOOK"

fail() { echo "ERROR: $*" >&2; exit 1; }

run_launcher() {
  local sub="$1" payload="$2"; shift 2
  printf '%s' "$payload" | env -i PATH="$NO_JQ_PATH" HOME="$TEST_DIR" \
    CLOVER_HOOK_BIN="$MOCK_HOOK" CLOVER_DEVIN_DATA="$DATA" "$@" \
    "$BASH_BIN" "$LAUNCHER" "$sub"
}

if env -i PATH="$NO_JQ_PATH" "$BASH_BIN" -c 'command -v jq' >/dev/null 2>&1; then
  fail "the test PATH still resolves jq"
fi

WRITE_PLAN='{"tool_name":"write_plan","session_id":"s1","cwd":"/w","tool_input":{"title":"T","summary":"S","plan":"P"}}'
ENV_CREDS=(CLOVER_SECURITY_KURA_PLUGIN_CLIENT_ID=env-id CLOVER_SECURITY_KURA_PLUGIN_CLIENT_SECRET=env-secret)

: > "$CALLS"
out="$(run_launcher review-write "$WRITE_PLAN" "${ENV_CREDS[@]}")"
grep -qF "devin-review-write id=env-id payload=$WRITE_PLAN" "$CALLS" \
  || fail "review-write did not reach devin-review-write with the payload intact: $(cat "$CALLS")"
[ "$out" = '{"decision":"block","reason":"needs rate limiting"}' ] || fail "the binary's block was not relayed unchanged: $out"

: > "$CALLS"
run_launcher review-exec '{"tool_name":"exec","session_id":"s1","tool_input":{"command":"ls"}}' "${ENV_CREDS[@]}" >/dev/null
grep -q '^devin-review-exec ' "$CALLS" || fail "review-exec did not reach devin-review-exec"

: > "$CALLS"
run_launcher log-prompt '{"prompt":"hi","session_id":"s1"}' "${ENV_CREDS[@]}" >/dev/null
grep -q '^devin-log-prompt ' "$CALLS" || fail "log-prompt did not reach devin-log-prompt"

: > "$CALLS"
out="$(run_launcher check-update '{"session_id":"s1"}' "${ENV_CREDS[@]}")"
grep -q '^devin-check-update ' "$CALLS" || fail "check-update did not reach devin-check-update"
[ -z "$out" ] || fail "check-update printed to stdout: $out"

printf 'export CLOVER_SECURITY_KURA_PLUGIN_CLIENT_ID=file-id\nexport CLOVER_SECURITY_KURA_PLUGIN_CLIENT_SECRET=file-secret\n' > "$DATA/env.sh"

: > "$CALLS"
run_launcher review-write "$WRITE_PLAN" >/dev/null
grep -q '^devin-review-write id=file-id ' "$CALLS" || fail "env.sh credentials did not reach the binary: $(cat "$CALLS")"

: > "$CALLS"
run_launcher review-write "$WRITE_PLAN" "${ENV_CREDS[@]}" >/dev/null
grep -q '^devin-review-write id=env-id ' "$CALLS" || fail "env.sh overrode credentials the environment carried: $(cat "$CALLS")"

: > "$CALLS"
run_launcher review-write "$WRITE_PLAN" CLOVER_SECURITY_KURA_PLUGIN_CLIENT_ID=secret:personal:CLOVER_KURA_CLIENT_ID \
  CLOVER_SECURITY_KURA_PLUGIN_CLIENT_SECRET=secret:personal:CLOVER_KURA_CLIENT_SECRET >/dev/null
grep -q '^devin-review-write id=file-id ' "$CALLS" \
  || fail "unresolved secret: references from the manifest kept env.sh from supplying credentials: $(cat "$CALLS")"

out="$(printf '%s' "$WRITE_PLAN" | env -i PATH="$NO_JQ_PATH" HOME="$TEST_DIR" CLOVER_HOOK_BIN="$TEST_DIR/missing" \
  CLOVER_DEVIN_DATA="$DATA" "$BASH_BIN" "$LAUNCHER" review-write)"
[ -z "$out" ] || fail "a missing binary printed a decision: $out"

echo "devin-launcher.sh: ok"
