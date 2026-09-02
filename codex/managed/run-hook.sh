#!/usr/bin/env bash
# Runtime wrapper for administrator-managed Codex hooks. MDM owns this file and
# the binary beside it; credentials remain per-user and are never embedded in
# requirements.toml or a world-readable system directory.
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
case "$(uname -s | tr '[:upper:]' '[:lower:]')" in
  darwin*)
    DEFAULT_DATA_DIR="${HOME}/Library/Application Support/Clover/Codex"
    ;;
  *)
    DEFAULT_DATA_DIR="${XDG_DATA_HOME:-${HOME}/.local/share}/clover/codex"
    ;;
esac

export CLAUDE_PLUGIN_ROOT="$ROOT"
export CLAUDE_PLUGIN_DATA="${CLOVER_CODEX_DATA_DIR:-$DEFAULT_DATA_DIR}"
export CLOVER_CODEX_SELF_UPDATE=0
mkdir -p "$CLAUDE_PLUGIN_DATA" 2>/dev/null || true

ENV_FILE="${CLOVER_CODEX_CONFIG_FILE:-${CLAUDE_PLUGIN_DATA}/env.sh}"
if [ -r "$ENV_FILE" ]; then
  # shellcheck disable=SC1090
  . "$ENV_FILE"
fi

BINARY="$ROOT/bin/clover-hook"
if [ ! -x "$BINARY" ]; then
  printf 'clover: fail-open (managed binary missing) bin=%s\n' "$BINARY" >&2
  exit 0
fi

exec "$BINARY" "$@"
