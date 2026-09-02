#!/usr/bin/env bash
# Install Clover for Codex.
#
# Developer install (one-time Codex hook trust remains):
#   curl -fsSL https://raw.githubusercontent.com/clover-security-public/agentic-security-marketplace/main/codex/scripts/install.sh | bash
#
# Administrator-managed install (system hooks are trusted by policy):
#   curl -fsSL https://raw.githubusercontent.com/clover-security-public/agentic-security-marketplace/main/codex/scripts/install.sh | bash -s -- --managed
#
# Beta marketplace install:
#   curl -fsSL https://raw.githubusercontent.com/clover-security-public/clover-security-marketplace-beta/main/codex/scripts/install.sh | bash -s -- --beta
set -euo pipefail

MODE="developer"
CHANNEL="public"

for argument in "$@"; do
  case "$argument" in
    --managed) MODE="managed" ;;
    --beta) CHANNEL="beta" ;;
    -h|--help)
      printf 'usage: install.sh [--managed] [--beta]\n'
      exit 0
      ;;
    *)
      printf 'clover: unknown argument: %s\n' "$argument" >&2
      exit 2
      ;;
  esac
done

case "$CHANNEL" in
  beta)
    DEFAULT_MARKETPLACE_URL="https://raw.githubusercontent.com/clover-security-public/clover-security-marketplace-beta/main"
    DEFAULT_MARKETPLACE_GIT_URL="https://github.com/clover-security-public/clover-security-marketplace-beta.git"
    MARKETPLACE_NAME="clover-security-beta"
    ;;
  *)
    DEFAULT_MARKETPLACE_URL="https://raw.githubusercontent.com/clover-security-public/agentic-security-marketplace/main"
    DEFAULT_MARKETPLACE_GIT_URL="https://github.com/clover-security-public/agentic-security-marketplace.git"
    MARKETPLACE_NAME="clover-security"
    ;;
esac
MARKETPLACE_URL="${CLOVER_SECURITY_KURA_PLUGIN_MARKETPLACE_URL:-${CLOVER_MARKETPLACE_URL:-$DEFAULT_MARKETPLACE_URL}}"
MARKETPLACE_GIT_URL="${CLOVER_SECURITY_KURA_PLUGIN_MARKETPLACE_GIT_URL:-${CLOVER_MARKETPLACE_GIT_URL:-$DEFAULT_MARKETPLACE_GIT_URL}}"
PLUGIN_ID="clover@${MARKETPLACE_NAME}"

command -v curl >/dev/null || { printf 'clover: curl is required\n' >&2; exit 1; }

OS="$(uname -s | tr '[:upper:]' '[:lower:]')"
case "$OS" in
  darwin*) OS="darwin" ;;
  linux*) OS="linux" ;;
  *) printf 'clover: this installer currently supports macOS and Linux (got %s)\n' "$OS" >&2; exit 1 ;;
esac
ARCH="$(uname -m)"
case "$ARCH" in
  x86_64) ARCH="amd64" ;;
  aarch64|arm64) ARCH="arm64" ;;
  *) printf 'clover: unsupported architecture: %s\n' "$ARCH" >&2; exit 1 ;;
esac
BINARY_NAME="clover-hook-${OS}-${ARCH}"

TREE=""
if [ -n "${BASH_SOURCE[0]:-}" ]; then
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd || true)"
  if [ -n "$SCRIPT_DIR" ] && [ -f "$SCRIPT_DIR/../managed/requirements.toml.template" ]; then
    TREE="$(cd "$SCRIPT_DIR/../.." && pwd)"
  fi
fi

obtain() {
  if [ -n "$TREE" ] && [ -f "$TREE/$1" ]; then
    cp "$TREE/$1" "$2"
  else
    curl -fsSL "$MARKETPLACE_URL/$1" -o "$2" \
      || { printf 'clover: failed to download %s\n' "$MARKETPLACE_URL/$1" >&2; return 1; }
  fi
}

sha256_of() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}

TEMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TEMP_DIR"' EXIT

stage_runtime() {
  STAGE="$1"
  mkdir -p "$STAGE/bin" "$STAGE/.codex-plugin" "$STAGE/.claude-plugin"
  obtain ".codex-plugin/plugin.json" "$STAGE/.codex-plugin/plugin.json"
  obtain ".claude-plugin/plugin.json" "$STAGE/.claude-plugin/plugin.json"
  obtain "bin/checksums.sha256" "$STAGE/checksums.sha256"
  obtain "bin/$BINARY_NAME" "$STAGE/bin/clover-hook"

  EXPECTED="$(awk -v name="$BINARY_NAME" '{ file=$2; sub(/^\*/, "", file); if (file == name) print $1 }' "$STAGE/checksums.sha256" | head -1)"
  [ -n "$EXPECTED" ] || { printf 'clover: %s is missing from checksums.sha256\n' "$BINARY_NAME" >&2; exit 1; }
  ACTUAL="$(sha256_of "$STAGE/bin/clover-hook")"
  [ "$EXPECTED" = "$ACTUAL" ] || { printf 'clover: checksum mismatch for %s\n' "$BINARY_NAME" >&2; exit 1; }
  chmod +x "$STAGE/bin/clover-hook"
}

credential_file() {
  if [ "$OS" = "darwin" ]; then
    printf '%s\n' "${CLOVER_CODEX_DATA_DIR:-${HOME}/Library/Application Support/Clover/Codex}/env.sh"
  else
    printf '%s\n' "${CLOVER_CODEX_DATA_DIR:-${XDG_DATA_HOME:-${HOME}/.local/share}/clover/codex}/env.sh"
  fi
}

configure_credentials() {
  ENV_FILE="$1"
  if [ -f "$ENV_FILE" ] && {
    { grep -Eq '^export CLOVER_SECURITY_KURA_PLUGIN_CLIENT_ID=.+$' "$ENV_FILE" \
      && grep -Eq '^export CLOVER_SECURITY_KURA_PLUGIN_CLIENT_SECRET=.+$' "$ENV_FILE"; } \
      || { grep -Eq '^export CAS_CLOVER_PLUGIN_CLIENT_ID=.+$' "$ENV_FILE" \
        && grep -Eq '^export CAS_CLOVER_PLUGIN_CLIENT_SECRET=.+$' "$ENV_FILE"; }
  } && [ -z "${CLOVER_SECURITY_KURA_PLUGIN_CLIENT_ID:-}${CLOVER_SECURITY_KURA_PLUGIN_CLIENT_SECRET:-}${CAS_CLOVER_PLUGIN_CLIENT_ID:-}${CAS_CLOVER_PLUGIN_CLIENT_SECRET:-}" ]; then
    chmod 600 "$ENV_FILE"
    printf 'clover: preserving credentials in %s\n' "$ENV_FILE"
    return
  fi

  CLIENT_ID="${CLOVER_SECURITY_KURA_PLUGIN_CLIENT_ID:-${CAS_CLOVER_PLUGIN_CLIENT_ID:-}}"
  CLIENT_SECRET="${CLOVER_SECURITY_KURA_PLUGIN_CLIENT_SECRET:-${CAS_CLOVER_PLUGIN_CLIENT_SECRET:-}}"
  AUTH_URL="${CLOVER_SECURITY_KURA_PLUGIN_AUTH_URL:-${CAS_CLOVER_PLUGIN_AUTH_URL:-https://auth.cloversec.io}}"
  SERVER_URL="${CLOVER_SECURITY_KURA_PLUGIN_SERVER_URL:-${CAS_CLOVER_PLUGIN_SERVER_URL:-https://api.cloversec.io}}"

  if { [ -z "$CLIENT_ID" ] || [ -z "$CLIENT_SECRET" ]; } \
    && [ -z "${CLOVER_SECURITY_KURA_PLUGIN_NO_PROMPT:-${CLOVER_NO_PROMPT:-}}" ] \
    && { exec 3<>/dev/tty; } 2>/dev/null; then
    printf 'Clover credentials (Clover Settings > API Tokens)\n' >&3
    printf 'Client ID: ' >&3
    IFS= read -r CLIENT_ID <&3 || CLIENT_ID=""
    printf 'Client secret: ' >&3
    IFS= read -rs CLIENT_SECRET <&3 || CLIENT_SECRET=""
    printf '\n' >&3
    exec 3>&- 2>/dev/null || true
  fi
  if [ -z "$CLIENT_ID" ] || [ -z "$CLIENT_SECRET" ]; then
    printf 'clover: client credentials are required; set CLOVER_SECURITY_KURA_PLUGIN_CLIENT_ID and CLOVER_SECURITY_KURA_PLUGIN_CLIENT_SECRET or run interactively\n' >&2
    exit 1
  fi

  mkdir -p "$(dirname "$ENV_FILE")"
  umask 077
  {
    printf 'export CLOVER_SECURITY_KURA_PLUGIN_CLIENT_ID=%q\n' "$CLIENT_ID"
    printf 'export CLOVER_SECURITY_KURA_PLUGIN_CLIENT_SECRET=%q\n' "$CLIENT_SECRET"
    printf 'export CLOVER_SECURITY_KURA_PLUGIN_AUTH_URL=%q\n' "$AUTH_URL"
    printf 'export CLOVER_SECURITY_KURA_PLUGIN_SERVER_URL=%q\n' "$SERVER_URL"
    # Compatibility for binaries and existing automation using the old names.
    printf 'export CAS_CLOVER_PLUGIN_CLIENT_ID=%q\n' "$CLIENT_ID"
    printf 'export CAS_CLOVER_PLUGIN_CLIENT_SECRET=%q\n' "$CLIENT_SECRET"
    printf 'export CAS_CLOVER_PLUGIN_AUTH_URL=%q\n' "$AUTH_URL"
    printf 'export CAS_CLOVER_PLUGIN_SERVER_URL=%q\n' "$SERVER_URL"
  } > "$ENV_FILE"
  chmod 600 "$ENV_FILE"
}

run_doctor() {
  WRAPPER="$1"
  RESULT="$(printf '{"cwd":".","session_id":"codex-install-check"}\n' | "$WRAPPER" codex-doctor)"
  case "$RESULT" in
    *'"ok":true'*) printf 'clover: backend verification succeeded\n' ;;
    *) printf 'clover: backend verification failed: %s\n' "$RESULT" >&2; exit 1 ;;
  esac
}

if [ "$MODE" = "developer" ]; then
  command -v codex >/dev/null || { printf 'clover: Codex CLI is required\n' >&2; exit 1; }

  if ! codex plugin marketplace add "$MARKETPLACE_GIT_URL" >/dev/null 2>&1; then
    : # Older Codex versions can report an existing marketplace as an error.
  fi
  codex plugin marketplace upgrade "$MARKETPLACE_NAME" >/dev/null
  codex plugin add "$PLUGIN_ID" >/dev/null

  DATA_DIR="${CODEX_HOME:-${HOME}/.codex}/plugins/data/clover-${MARKETPLACE_NAME}"
  STAGE="$TEMP_DIR/runtime"
  stage_runtime "$STAGE"
  mkdir -p "$DATA_DIR/bin"
  install -m 755 "$STAGE/bin/clover-hook" "$DATA_DIR/bin/clover-hook"
  VERSION="$(awk -F'"' '/"version"[[:space:]]*:/ { print $4; exit }' "$STAGE/.codex-plugin/plugin.json")"
  printf '%s\n' "$VERSION" > "$DATA_DIR/bin/.version"
  configure_credentials "$DATA_DIR/env.sh"
  export CLAUDE_PLUGIN_ROOT="$STAGE"
  export CLAUDE_PLUGIN_DATA="$DATA_DIR"
  # shellcheck disable=SC1090,SC1091
  . "$DATA_DIR/env.sh"
  run_doctor "$DATA_DIR/bin/clover-hook"

  printf 'clover: installed %s\n' "$PLUGIN_ID"
  printf 'clover: final one-time step: start Codex and choose "Trust all and continue" when it reports 4 new or changed hooks\n'
  printf 'clover: if the prompt does not appear, run /hooks and confirm all 4 Clover hooks are active\n'
  exit 0
fi

SYSTEM_DIR="${CLOVER_CODEX_SYSTEM_DIR:-/opt/clover/codex}"
REQUIREMENTS_FILE="${CLOVER_CODEX_REQUIREMENTS_FILE:-/etc/codex/requirements.toml}"
if [ -e "$REQUIREMENTS_FILE" ] && ! grep -q '^# Clover Codex managed hooks$' "$REQUIREMENTS_FILE"; then
  printf 'clover: refusing to overwrite existing %s\n' "$REQUIREMENTS_FILE" >&2
  printf 'clover: merge codex/managed/requirements.toml.template into your organization requirements instead\n' >&2
  exit 1
fi

STAGE="$TEMP_DIR/runtime"
stage_runtime "$STAGE"
obtain "codex/managed/run-hook.sh" "$STAGE/run-hook.sh"
chmod +x "$STAGE/run-hook.sh"
obtain "codex/managed/requirements.toml.template" "$TEMP_DIR/requirements.toml.template"
sed "s|@CLOVER_CODEX_MANAGED_DIR@|$SYSTEM_DIR|g" "$TEMP_DIR/requirements.toml.template" > "$TEMP_DIR/requirements.toml"
configure_credentials "$(credential_file)"

as_root() {
  if [ "${CLOVER_CODEX_NO_SUDO:-}" = "1" ]; then
    "$@"
  else
    sudo "$@"
  fi
}

as_root install -d -m 755 "$SYSTEM_DIR/bin" "$SYSTEM_DIR/.claude-plugin" "$(dirname "$REQUIREMENTS_FILE")"
as_root install -m 755 "$STAGE/bin/clover-hook" "$SYSTEM_DIR/bin/clover-hook"
as_root install -m 755 "$STAGE/run-hook.sh" "$SYSTEM_DIR/run-hook.sh"
as_root install -m 644 "$STAGE/.claude-plugin/plugin.json" "$SYSTEM_DIR/.claude-plugin/plugin.json"
as_root install -m 644 "$TEMP_DIR/requirements.toml" "$REQUIREMENTS_FILE"

run_doctor "$SYSTEM_DIR/run-hook.sh"
printf 'clover: managed Codex hooks installed in %s\n' "$SYSTEM_DIR"
printf 'clover: hooks are trusted by administrator policy; restart Codex to load them\n'
