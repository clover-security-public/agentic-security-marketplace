#!/usr/bin/env bash
# A Cursor prompt waits for the beforeSubmitPrompt hook, so Clover must never
# hold it for long. The launcher caps the credential search at 5s (on every
# hook) and gives the prompt audit a deadline 5s after the hook started; past
# either, the prompt goes through without Clover (fail open).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEST_DIR="$(mktemp -d)"
trap 'rm -rf "$TEST_DIR"' EXIT

# A stand-in binary that records the subcommand, the deadline it was handed
# and the time it ran.
cat > "$TEST_DIR/clover-hook" <<EOF
#!/usr/bin/env bash
cat >/dev/null
printf '%s %s %s\n' "\$1" "\${CLOVER_HOOK_DEADLINE:-none}" "\$(date +%s)" >> "$TEST_DIR/calls"
EOF
chmod +x "$TEST_DIR/clover-hook"

# A find that hangs the way a search of a huge tree does: it never answers.
mkdir -p "$TEST_DIR/fakebin"
cat > "$TEST_DIR/fakebin/find" <<'EOF'
#!/usr/bin/env bash
exec sleep 60
EOF
chmod +x "$TEST_DIR/fakebin/find"
mkdir -p "$TEST_DIR/home/.cursor/plugins"

fail() { echo "ERROR: $*" >&2; exit 1; }

# run <sub> [env...] runs the launcher, waiting for every process that still
# holds its stdout (as Cursor does), and prints its output.
run() {
  local sub="$1"; shift
  rm -f "$TEST_DIR/calls"
  printf '{"conversation_id":"c1","prompt":"hi"}' |
    env -u CLOVER_SECURITY_KURA_PLUGIN_CLIENT_ID -u CAS_CLOVER_PLUGIN_CLIENT_ID -u CURSOR_PLUGIN_ROOT \
      -u CLOVER_HOOK_DEADLINE HOME="$TEST_DIR/home" CLOVER_HOOK_BIN="$TEST_DIR/clover-hook" \
      CLOVER_STATE_DIR="$TEST_DIR/state" "$@" bash "$ROOT/cursor/scripts/run-hook.sh" "$sub"
}

# A hung credential search is cut at 5s, and the prompt still goes through.
start=$(date +%s)
out="$(run log-prompt PATH="$TEST_DIR/fakebin:$PATH")"
elapsed=$(( $(date +%s) - start ))
[ "$out" = '{"continue":true}' ] || fail "hung search: printed '$out', want the carry-on payload"
[ "$elapsed" -le 7 ] || fail "hung search: the prompt waited ${elapsed}s, want at most ~5s"
grep -q '^log-prompt ' "$TEST_DIR/calls" || fail "hung search: the audit was never attempted"

# The audit is handed a deadline at most 5s after the hook started, which the
# binary honors for every backend request, token fetch included.
start=$(date +%s)
out="$(run log-prompt)"
[ "$out" = '{"continue":true}' ] || fail "audit: printed '$out', want the carry-on payload"
read -r _ deadline _ < <(grep '^log-prompt ' "$TEST_DIR/calls")
[ "$deadline" != none ] || fail "audit: the binary got no CLOVER_HOOK_DEADLINE"
[ "$deadline" -gt "$start" ] && [ "$deadline" -le $(( start + 5 )) ] ||
  fail "audit: deadline $deadline is not within 5s of the hook's start $start"

# After a hung search, the audit's deadline has already passed: it gives up at
# once instead of adding another 5s.
start=$(date +%s)
run log-prompt PATH="$TEST_DIR/fakebin:$PATH" >/dev/null
read -r _ deadline _ < <(grep '^log-prompt ' "$TEST_DIR/calls")
[ "$deadline" -le $(( start + 5 )) ] || fail "after a hung search: deadline $deadline is past the hook's 5s"

# The stop hook's credential search is capped too; its plan reviews keep their
# own, longer budget.
start=$(date +%s)
run review-plan-stop PATH="$TEST_DIR/fakebin:$PATH" >/dev/null
elapsed=$(( $(date +%s) - start ))
[ "$elapsed" -le 7 ] || fail "stop: waited ${elapsed}s on a hung search, want at most ~5s"

echo "cursor prompt budget: ok"
