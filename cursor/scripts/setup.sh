#!/usr/bin/env bash
#
# Clover Cursor plugin — sessionStart hook. Two jobs:
#   1. Select the bundled platform binary (bin/clover-hook-<os>-<arch>) and
#      expose its path as CLOVER_HOOK_BIN.
#   2. Set up the binary's data dir (token cache + session state) and drop a
#      copy of the manifest where the binary reads its version.
#
#
# Cursor makes the env returned here available to every later hook in the
# session (https://cursor.com/docs/hooks#sessionstart), which is how the
# beforeSubmitPrompt / stop hooks reach the binary.
#
# Output (stdout): { "env": { ... } }  (binary path + data dir; no secrets)
set -uo pipefail

IN="$(cat 2>/dev/null || true)"
ROOT="${CURSOR_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"

OS="$(uname -s | tr '[:upper:]' '[:lower:]')"
EXE_SUFFIX=""
case "$OS" in
  darwin*) OS=darwin ;;
  linux*) OS=linux ;;
  mingw*|msys*|cygwin*|windows_nt*)
    OS=windows
    EXE_SUFFIX=.exe
    ;;
esac
ARCH="$(uname -m)"
case "$ARCH" in
  x86_64) ARCH=amd64 ;;
  aarch64|arm64) ARCH=arm64 ;;
esac
BIN="${ROOT}/bin/clover-hook-${OS}-${ARCH}${EXE_SUFFIX}"
chmod +x "$BIN" 2>/dev/null || true

# Persistent data dir for the binary's token cache + session state. Cursor has
# no CLAUDE_PLUGIN_DATA, so we pick a stable path and drop a copy of the
# manifest under the name the binary expects (it reads
# ${CLAUDE_PLUGIN_ROOT}/.claude-plugin/plugin.json to resolve its version).
DATA="${HOME}/.cursor/clover"
mkdir -p "$DATA/.claude-plugin" 2>/dev/null || true
cp "${ROOT}/.cursor-plugin/plugin.json" "$DATA/.claude-plugin/plugin.json" 2>/dev/null || true

if ! command -v jq >/dev/null 2>&1; then
  printf '{"env":{"CLOVER_HOOK_BIN":"%s","CLAUDE_PLUGIN_ROOT":"%s","CLAUDE_PLUGIN_DATA":"%s"}}\n' "$BIN" "$DATA" "$DATA"
  exit 0
fi

jq -nc \
  --arg bin "$BIN" --arg data "$DATA" \
  '{env: {CLOVER_HOOK_BIN:$bin, CLAUDE_PLUGIN_ROOT:$data, CLAUDE_PLUGIN_DATA:$data}}'
