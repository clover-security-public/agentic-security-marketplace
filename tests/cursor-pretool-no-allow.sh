#!/usr/bin/env bash
# The Cursor shim must never grant a preToolUse permission.
#
# A hook emits a decision only when it blocks (CLAUDE.md, key invariants). For a
# preToolUse gate the only safe non-blocking outcome is exit 0 with nothing on
# stdout: Cursor parses that as "no response" and leaves the call to the user's
# own approval flow, exactly as the Windows path (the binary, called directly)
# already does. An explicit {"permission":"allow"} is a grant — Cursor forwards
# it to the agent backend as the hook's decision — so printing it on a
# pass-through or failure path would approve tool calls Clover never reviewed.
#
# These checks drive every preToolUse path of cursor/scripts/run-hook.sh —
# pass-through, binary approval, binary failure, and each safe_default — and
# assert none of them prints anything. A deny must still come through, and
# beforeSubmitPrompt's carry-on (not a permission decision) must stay.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SHIM="$ROOT/cursor/scripts/run-hook.sh"
TEST_DIR="$(mktemp -d)"
trap 'rm -rf "$TEST_DIR"' EXIT

command -v jq >/dev/null || { echo "cursor-pretool-no-allow.sh: jq is required" >&2; exit 2; }

TEST_HOME="$TEST_DIR/home"
EMPTY_ROOT="$TEST_DIR/empty-plugin"
MOCK_HOOK="$TEST_DIR/clover-hook"
# By absolute path: one case below runs the shim under a PATH without jq.
BASH_BIN="$(command -v bash)"
mkdir -p "$TEST_HOME" "$EMPTY_ROOT"

# Stand-in for the Claude-dialect binary the shim calls for review-plan.
# MOCK_MODE picks what the review returns.
cat > "$MOCK_HOOK" <<'EOF'
#!/usr/bin/env bash
cat >/dev/null
# MOCK_PLANS: the plans cursor-stop-plans names; each review records the
# deadline it inherited.
if [ -n "${MOCK_PLANS:-}" ]; then
  case "$1" in
    cursor-stop-plans) printf '%s\n' "$MOCK_PLANS" ;;
    review-plan) printf '%s\n' "${CLOVER_HOOK_DEADLINE:-}" >> "$MOCK_DEADLINES" ;;
  esac
  exit 0
fi
case "${MOCK_MODE:-}" in
  approve-silent) ;;
  approve-explicit) printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow"}}\n' ;;
  deny) printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"plan stores secrets in plaintext"}}\n' ;;
  deny-no-reason) printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny"}}\n' ;;
  junk) printf 'not json at all\n' ;;
  fail) exit 3 ;;
esac
exit 0
EOF
chmod +x "$MOCK_HOOK"

CREATE_PLAN='{"tool_name":"CreatePlan","tool_input":{"name":"Add login","overview":"o","plan":"body"},"conversation_id":"c1","generation_id":"g1"}'
OTHER_TOOL='{"tool_name":"Shell","tool_input":{"command":"rm -rf build"},"conversation_id":"c1","generation_id":"g1"}'

# run_shim <payload> <subcommand> [env assignments...]
# Runs the shim with a scratch HOME (so the ~/.cursor creds scan reads nothing
# real) and creds preset. Sets OUT and RC.
run_shim() {
  local payload="$1" sub="$2"; shift 2
  set +e
  OUT="$(printf '%s' "$payload" | \
    env \
      HOME="$TEST_HOME" \
      CAS_CLOVER_PLUGIN_CLIENT_ID=test-client \
      CURSOR_PLUGIN_ROOT="$EMPTY_ROOT" \
      CLOVER_STATE_DIR="$TEST_DIR/state" \
      "$@" \
      "$BASH_BIN" "$SHIM" "$sub" 2>/dev/null)"
  RC=$?
  set -e
}

FAILED=0
fail() { echo "FAIL: $*" >&2; FAILED=1; }

# A preToolUse path that does not block must exit 0 and print nothing at all —
# not {"permission":"allow"}, and not any other JSON Cursor could read as a
# decision.
assert_silent() {
  local label="$1"
  [ "$RC" = "0" ] || fail "$label — exit $RC, want 0 (fail-open)"
  if [ -n "$OUT" ]; then
    fail "$label — printed '$OUT', want nothing (silence leaves the call to the user's approval flow)"
  fi
}

# --- pass-through: a tool that is not CreatePlan ----------------------------
run_shim "$OTHER_TOOL" review-plan CLOVER_HOOK_BIN="$MOCK_HOOK" MOCK_MODE=approve-silent
assert_silent "review-plan pass-through (non-CreatePlan tool)"

# --- the review ran and did not deny ----------------------------------------
run_shim "$CREATE_PLAN" review-plan CLOVER_HOOK_BIN="$MOCK_HOOK" MOCK_MODE=approve-silent
assert_silent "review-plan approved (binary silent)"

run_shim "$CREATE_PLAN" review-plan CLOVER_HOOK_BIN="$MOCK_HOOK" MOCK_MODE=approve-explicit
assert_silent "review-plan approved (binary printed a Claude allow)"

run_shim "$CREATE_PLAN" review-plan CLOVER_HOOK_BIN="$MOCK_HOOK" MOCK_MODE=deny-no-reason
assert_silent "review-plan deny without a reason"

# --- the binary failed -------------------------------------------------------
run_shim "$CREATE_PLAN" review-plan CLOVER_HOOK_BIN="$MOCK_HOOK" MOCK_MODE=fail
assert_silent "review-plan binary exits non-zero"

run_shim "$CREATE_PLAN" review-plan CLOVER_HOOK_BIN="$MOCK_HOOK" MOCK_MODE=junk
assert_silent "review-plan binary prints junk"

# --- safe_default: binary missing -------------------------------------------
run_shim "$CREATE_PLAN" review-plan CLOVER_HOOK_BIN="$TEST_DIR/no-such-binary"
assert_silent "review-plan with no binary installed"

# --- safe_default: jq missing -----------------------------------------------
# A PATH holding only what the shim needs before its jq check, so jq is absent.
NOJQ="$TEST_DIR/nojq-bin"
mkdir -p "$NOJQ"
for tool in cat dirname uname tr; do ln -s "$(command -v "$tool")" "$NOJQ/$tool"; done
run_shim "$CREATE_PLAN" review-plan PATH="$NOJQ" CLOVER_HOOK_BIN="$MOCK_HOOK" MOCK_MODE=approve-silent
assert_silent "review-plan with jq missing"

# --- safe_default: unrecognised subcommand ----------------------------------
run_shim "$OTHER_TOOL" some-future-pretool-gate CLOVER_HOOK_BIN="$MOCK_HOOK"
assert_silent "unrecognised subcommand"

# --- a deny must still block -------------------------------------------------
# Guards the checks above from passing vacuously on a shim that prints nothing.
run_shim "$CREATE_PLAN" review-plan CLOVER_HOOK_BIN="$MOCK_HOOK" MOCK_MODE=deny
[ "$RC" = "0" ] || fail "review-plan deny — exit $RC, want 0"
if [ "$(printf '%s' "$OUT" | jq -r '.permission' 2>/dev/null)" != "deny" ] \
   || [ "$(printf '%s' "$OUT" | jq -r '.user_message' 2>/dev/null)" != "plan stores secrets in plaintext" ]; then
  fail "review-plan deny — want {permission:deny, user_message:<reason>}, got '$OUT'"
fi

# --- non-permission hooks keep their protocol -------------------------------
# beforeSubmitPrompt's carry-on is not a permission decision and must survive.
run_shim '{"prompt":"hi","generation_id":"g2"}' log-prompt CLOVER_HOOK_BIN="$TEST_DIR/no-such-binary"
[ "$OUT" = '{"continue":true}' ] || fail "log-prompt fail-open — want {\"continue\":true}, got '$OUT'"

run_shim '{"generation_id":"g3"}' review-plan-stop CLOVER_HOOK_BIN="$TEST_DIR/no-such-binary"
assert_silent "review-plan-stop with no binary installed"

# --- a stop's plans share one hook deadline ---------------------------------
# Each plan is its own binary process; without a shared deadline each would
# start a fresh budget and the stop could outlive its 300s timeout.
printf '# A\n' > "$TEST_DIR/a.plan.md"
printf '# B\n' > "$TEST_DIR/b.plan.md"
DEADLINES="$TEST_DIR/deadlines"
before="$(date +%s)"
run_shim '{"conversation_id":"c4","generation_id":"g4"}' review-plan-stop CLOVER_HOOK_BIN="$MOCK_HOOK" \
  MOCK_PLANS="$TEST_DIR/a.plan.md
$TEST_DIR/b.plan.md" MOCK_DEADLINES="$DEADLINES"
after="$(date +%s)"
assert_silent "review-plan-stop with two approved plans"
deadlines="$(sort -u "$DEADLINES" 2>/dev/null)"
if [ "$(wc -l < "$DEADLINES" 2>/dev/null | tr -d ' ')" != 2 ] || [ "$(printf '%s\n' "$deadlines" | wc -l | tr -d ' ')" != 1 ] \
   || ! [ "$deadlines" -ge $((before + 270)) ] 2>/dev/null || ! [ "$deadlines" -le $((after + 270)) ] 2>/dev/null; then
  fail "review-plan-stop — want both plans reviewed under one deadline 270s from the stop's start, got '$(cat "$DEADLINES" 2>/dev/null)'"
fi

# --- no Cursor entry point can emit an allow --------------------------------
# Catches a path the runs above do not reach, in either launcher. Comment lines
# (# in the shell script, rem in the batch file) may name it.
if grep -nE '"?permission"?[[:space:]]*:[[:space:]]*\\?"allow' \
     "$ROOT/cursor/scripts/run-hook.sh" "$ROOT/cursor/scripts/clover-hook.cmd" \
   | grep -viE '^[^:]+:[0-9]+:[[:space:]]*(#|rem[[:space:]])' >&2; then
  fail "a Cursor launcher contains a permission allow (lines above)"
fi

if [ "$FAILED" != 0 ]; then
  echo "cursor-pretool-no-allow.sh: FAILED" >&2
  exit 1
fi
echo "cursor-pretool-no-allow.sh: all checks passed"
