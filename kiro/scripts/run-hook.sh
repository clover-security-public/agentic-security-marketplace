#!/usr/bin/env bash
# Launches the Clover binary for a Kiro hook.
#
# All Kiro logic lives in the binary (agent_kiro.go); this only resolves the
# platform binary, loads credentials, and hands stdin straight through. Kiro
# reads the exit code as the decision, so every path here that cannot reach the
# binary must exit 0 — a non-zero exit would block the developer.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"          # .../.kiro/clover
export CLAUDE_PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$ROOT}"
export CLAUDE_PLUGIN_DATA="${CLAUDE_PLUGIN_DATA:-$ROOT}"

if [ -f "$ROOT/env.sh" ]; then
  # shellcheck disable=SC1091
  . "$ROOT/env.sh" 2>/dev/null || true
fi

OS="$(uname -s | tr '[:upper:]' '[:lower:]')"
case "$OS" in mingw*|msys*|cygwin*|windows_nt*) OS="windows" ;; esac
ARCH="$(uname -m)"
case "$ARCH" in x86_64) ARCH="amd64" ;; aarch64|arm64) ARCH="arm64" ;; esac
EXE=""
[ "$OS" = "windows" ] && EXE=".exe"

BINARY="${CLOVER_HOOK_BIN:-${ROOT}/bin/clover-hook-${OS}-${ARCH}${EXE}}"
chmod +x "$BINARY" 2>/dev/null || true

if [ ! -x "$BINARY" ]; then
  [ -n "${CLOVER_DEBUG:-}" ] && printf 'clover(kiro): no binary at %s\n' "$BINARY" >&2
  exit 0
fi

exec "$BINARY" "$@"
