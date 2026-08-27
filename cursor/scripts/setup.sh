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
# The plugin tree root: bin/, .cursor-plugin/ and the per-agent script dirs all
# hang off it. This script lives at <tree>/cursor/scripts, so the fallback has
# to climb twice — one level lands on <tree>/cursor, where nothing it reads
# exists. Cursor normally exports CURSOR_PLUGIN_ROOT, which is why the short
# climb never surfaced.
ROOT="${CURSOR_PLUGIN_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"

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

# Refresh the installed binary. Cursor's marketplace Auto Refresh re-indexes a
# marketplace, not an installed copy, so without this a machine stays on the
# version it was installed with: a clone under ~/.cursor/plugins/local never
# pulls, and a team-marketplace import of Clover's repo cannot enable Auto
# Refresh at all, since the Cursor GitHub App cannot be installed on a repo the
# customer does not own.
#
# The refresh already exists in the binary (cursor-check-update): channel-aware,
# checksum-verified before the swap, reported to the server. It is invoked from
# here because hooks.json's sessionStart runs clover-hook.cmd, whose POSIX
# branch routes to this script instead of the binary's cursor-setup where that
# call sits — so on macOS and Linux it would otherwise never run. Windows
# reaches cursor-setup directly and skips the swap inside the binary, because a
# running .exe cannot be replaced.
#
# Best-effort and bounded by the binary's own timeouts (10s for the manifest,
# 60s per download): any failure leaves the installed binary in place, and both
# streams are discarded so only the env contract below reaches Cursor.
# CLOVER_CURSOR_SELF_UPDATE=0 opts a machine out.
if [ -x "$BIN" ]; then
  CURSOR_PLUGIN_ROOT="$ROOT" \
  CLAUDE_PLUGIN_ROOT="$DATA" \
  CLAUDE_PLUGIN_DATA="$DATA" \
    "$BIN" cursor-check-update >/dev/null 2>&1 || true
fi

if ! command -v jq >/dev/null 2>&1; then
  printf '{"env":{"CLOVER_HOOK_BIN":"%s","CLAUDE_PLUGIN_ROOT":"%s","CLAUDE_PLUGIN_DATA":"%s"}}\n' "$BIN" "$DATA" "$DATA"
  exit 0
fi

jq -nc \
  --arg bin "$BIN" --arg data "$DATA" \
  '{env: {CLOVER_HOOK_BIN:$bin, CLAUDE_PLUGIN_ROOT:$data, CLAUDE_PLUGIN_DATA:$data}}'
