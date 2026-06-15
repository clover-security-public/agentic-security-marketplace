#!/usr/bin/env bash
#
# Clover Cursor plugin — sessionStart hook.
# Analog of the Claude plugin's scripts/setup.sh. Two jobs:
#   1. Select the bundled platform binary (clover/bin/clover-hook-<os>-<arch>)
#      and expose its path as CLOVER_HOOK_BIN.
#   2. Inject the env the Claude-built binary needs (CLAUDE_PLUGIN_ROOT/DATA)
#      plus Clover credentials forwarded from the machine environment.
#
# Cursor makes the env returned here available to every later hook in the
# session (https://cursor.com/docs/hooks#sessionstart), which is how the
# preToolUse / beforeSubmitPrompt hooks reach the binary and authenticate.
#
# Output (stdout): { "env": { ... } }
set -uo pipefail

IN="$(cat 2>/dev/null || true)"
ROOT="${CURSOR_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"

OS="$(uname -s | tr '[:upper:]' '[:lower:]')"
ARCH="$(uname -m)"
case "$ARCH" in
  x86_64) ARCH=amd64 ;;
  aarch64|arm64) ARCH=arm64 ;;
esac
BIN="${ROOT}/bin/clover-hook-${OS}-${ARCH}"
chmod +x "$BIN" 2>/dev/null || true

# Persistent data dir for the binary's token cache + session state. Cursor has
# no CLAUDE_PLUGIN_DATA, so we pick a stable path and drop a copy of the
# manifest under the name the binary expects (it reads
# ${CLAUDE_PLUGIN_ROOT}/.claude-plugin/plugin.json to resolve its version).
DATA="${HOME}/.cursor/clover"
mkdir -p "$DATA/.claude-plugin" 2>/dev/null || true
cp "${ROOT}/.cursor-plugin/plugin.json" "$DATA/.claude-plugin/plugin.json" 2>/dev/null || true

# Credentials. GUI-launched Cursor has no shell env, so CAS_* vars are usually
# absent here. Acquire them, in order, from: machine env -> our persisted
# env.sh -> the Claude plugin's persisted env.sh (same binary, same creds),
# then persist to $DATA/env.sh so run-hook.sh can source them on every fire.
ENV_FILE="$DATA/env.sh"
if [ -z "${CAS_CLOVER_PLUGIN_CLIENT_ID:-}" ] && [ -f "$ENV_FILE" ]; then
  . "$ENV_FILE" 2>/dev/null || true
fi
if [ -z "${CAS_CLOVER_PLUGIN_CLIENT_ID:-}" ]; then
  CLAUDE_ENV="$HOME/.claude/plugins/data/clover-clover-security/env.sh"
  if [ -f "$CLAUDE_ENV" ]; then . "$CLAUDE_ENV" 2>/dev/null || true; fi
fi
if [ -n "${CAS_CLOVER_PLUGIN_CLIENT_ID:-}" ]; then
  {
    printf 'export CAS_CLOVER_PLUGIN_CLIENT_ID=%q\n'     "${CAS_CLOVER_PLUGIN_CLIENT_ID}"
    [ -n "${CAS_CLOVER_PLUGIN_CLIENT_SECRET:-}" ] && printf 'export CAS_CLOVER_PLUGIN_CLIENT_SECRET=%q\n' "${CAS_CLOVER_PLUGIN_CLIENT_SECRET}"
    [ -n "${CAS_CLOVER_PLUGIN_AUTH_URL:-}" ]      && printf 'export CAS_CLOVER_PLUGIN_AUTH_URL=%q\n'      "${CAS_CLOVER_PLUGIN_AUTH_URL}"
    [ -n "${CAS_CLOVER_PLUGIN_SERVER_URL:-}" ]    && printf 'export CAS_CLOVER_PLUGIN_SERVER_URL=%q\n'    "${CAS_CLOVER_PLUGIN_SERVER_URL}"
    true
  } > "$ENV_FILE" 2>/dev/null || true
  chmod 600 "$ENV_FILE" 2>/dev/null || true
fi


if ! command -v jq >/dev/null 2>&1; then
  printf '{"env":{"CLOVER_HOOK_BIN":"%s","CLAUDE_PLUGIN_ROOT":"%s","CLAUDE_PLUGIN_DATA":"%s"}}\n' "$BIN" "$DATA" "$DATA"
  exit 0
fi

# Forward creds only when present, so we never clobber real values with blanks.
jq -nc \
  --arg bin "$BIN" --arg data "$DATA" \
  --arg cid "${CAS_CLOVER_PLUGIN_CLIENT_ID:-}" \
  --arg sec "${CAS_CLOVER_PLUGIN_CLIENT_SECRET:-}" \
  --arg au  "${CAS_CLOVER_PLUGIN_AUTH_URL:-}" \
  --arg su  "${CAS_CLOVER_PLUGIN_SERVER_URL:-}" \
  '{env: ({CLOVER_HOOK_BIN:$bin, CLAUDE_PLUGIN_ROOT:$data, CLAUDE_PLUGIN_DATA:$data}
      + (if $cid!="" then {CAS_CLOVER_PLUGIN_CLIENT_ID:$cid} else {} end)
      + (if $sec!="" then {CAS_CLOVER_PLUGIN_CLIENT_SECRET:$sec} else {} end)
      + (if $au!=""  then {CAS_CLOVER_PLUGIN_AUTH_URL:$au} else {} end)
      + (if $su!=""  then {CAS_CLOVER_PLUGIN_SERVER_URL:$su} else {} end))}'
