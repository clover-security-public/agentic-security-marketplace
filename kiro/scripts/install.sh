#!/usr/bin/env bash
# Install Clover for Kiro.
#
# One-liner (installs for every repo on this machine, prompts for credentials):
#
#   curl -fsSL https://raw.githubusercontent.com/clover-security-public/agentic-security-marketplace/main/kiro/scripts/install.sh | bash
#
# Or, into a single repository (the drop-in a team commits to git):
#
#   curl -fsSL .../kiro/scripts/install.sh | bash -s -- /path/to/repo
#
# The script works both piped (downloads what it needs from the marketplace's
# raw URLs) and from a local checkout of the marketplace tree (copies files).
# Credentials are prompted on a terminal and land in clover/env.sh (0600,
# gitignored); they are never downloaded and never committed.
set -euo pipefail

MARKETPLACE_URL="${CLOVER_MARKETPLACE_URL:-https://raw.githubusercontent.com/clover-security-public/agentic-security-marketplace/main}"

TARGET="${1:-}"

if [ -n "$TARGET" ] && [ ! -d "$TARGET" ]; then
  printf 'usage: install.sh [/path/to/repo]\n' >&2
  printf '  no argument: install machine-wide (~/.kiro), covers every repo\n' >&2
  printf '  with a path: install into that repository (.kiro drop-in)\n' >&2
  exit 1
fi

OS="$(uname -s | tr '[:upper:]' '[:lower:]')"
case "$OS" in mingw*|msys*|cygwin*|windows_nt*) OS="windows" ;; esac
ARCH="$(uname -m)"
case "$ARCH" in x86_64) ARCH="amd64" ;; aarch64|arm64) ARCH="arm64" ;; esac
EXE=""
[ "$OS" = "windows" ] && EXE=".exe"
BINARY_NAME="clover-hook-${OS}-${ARCH}${EXE}"

# A local marketplace tree is present when the script runs from one (a clone);
# piped through curl there is no tree, so files are downloaded instead.
TREE=""
if SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-/dev/null}")" 2>/dev/null && pwd)" \
  && [ -f "$SCRIPT_DIR/../hooks/clover.json" ]; then
  TREE="$(cd "$SCRIPT_DIR/../.." && pwd)"
fi

# obtain <path-in-marketplace-tree> <destination>
obtain() {
  if [ -n "$TREE" ] && [ -f "$TREE/$1" ]; then
    cp "$TREE/$1" "$2"
  else
    curl -fsSL "$MARKETPLACE_URL/$1" -o "$2" \
      || { printf 'clover: failed to download %s\n' "$MARKETPLACE_URL/$1" >&2; return 1; }
  fi
}

if [ -n "$TARGET" ]; then
  DEST="$TARGET/.kiro"
  HOOK_COMMAND_PREFIX=".kiro/clover"
else
  DEST="${HOME}/.kiro"
  HOOK_COMMAND_PREFIX="${HOME}/.kiro/clover"
fi
mkdir -p "$DEST/hooks" "$DEST/clover/scripts" "$DEST/clover/bin"

obtain "kiro/hooks/clover.json" "$DEST/hooks/clover.json.tmp"
# The shipped hook config invokes the launcher relative to a repo root; a
# machine-wide install needs the absolute path under $HOME instead.
sed "s|\.kiro/clover/scripts/run-hook.sh|${HOOK_COMMAND_PREFIX}/scripts/run-hook.sh|g" \
  "$DEST/hooks/clover.json.tmp" > "$DEST/hooks/clover.json"
rm -f "$DEST/hooks/clover.json.tmp"

obtain "kiro/scripts/run-hook.sh" "$DEST/clover/scripts/run-hook.sh"
chmod +x "$DEST/clover/scripts/run-hook.sh"

# The version manifest. Kiro has no plugin system to report a version, so the
# binary reads it from here and every backend row can name the release it came
# from. Sourced from the tree's own manifest, which the release workflow stamps
# per channel; a missing one costs only the version, so it must not fail the
# install.
mkdir -p "$DEST/clover/.kiro-plugin"
obtain ".claude-plugin/plugin.json" "$DEST/clover/.kiro-plugin/plugin.json" \
  || printf 'clover: version manifest unavailable - activity will report version "unknown"\n' >&2

obtain "bin/$BINARY_NAME" "$DEST/clover/bin/$BINARY_NAME"
chmod +x "$DEST/clover/bin/$BINARY_NAME"

# Verify the binary against the marketplace's checksum manifest. A missing
# manifest is tolerated; a mismatching binary is not.
CHECKSUMS="$(mktemp)"
if obtain "bin/checksums.sha256" "$CHECKSUMS" 2>/dev/null; then
  EXPECTED="$(awk -v name="$BINARY_NAME" '$2 == name { print $1 }' "$CHECKSUMS" | head -1)"
  if [ -n "$EXPECTED" ]; then
    if command -v sha256sum >/dev/null; then
      ACTUAL="$(sha256sum "$DEST/clover/bin/$BINARY_NAME" | cut -d' ' -f1)"
    else
      ACTUAL="$(shasum -a 256 "$DEST/clover/bin/$BINARY_NAME" | cut -d' ' -f1)"
    fi
    if [ "$EXPECTED" != "$ACTUAL" ]; then
      printf 'clover: checksum mismatch for %s - aborting\n' "$BINARY_NAME" >&2
      rm -f "$DEST/clover/bin/$BINARY_NAME" "$CHECKSUMS"
      exit 1
    fi
  fi
fi
rm -f "$CHECKSUMS"

if [ -n "$TARGET" ] && ! grep -qs 'clover/env.sh' "$TARGET/.gitignore" 2>/dev/null; then
  printf '\n# Clover credentials - never commit\n.kiro/clover/env.sh\n' >> "$TARGET/.gitignore"
fi

# Credentials: prompt on a terminal, otherwise leave a template. /dev/tty is
# read directly because under `curl | bash` stdin is the script itself. The
# probe must actually OPEN /dev/tty: in headless shells the node exists and
# passes -r/-w, but opening it fails with "Device not configured" — and an
# unguarded redirect there would kill the whole install under `set -e`.
ENV_FILE="$DEST/clover/env.sh"
if [ ! -f "$ENV_FILE" ]; then
  CLIENT_ID=""
  CLIENT_SECRET=""
  if [ -z "${CLOVER_NO_PROMPT:-}" ] && { exec 3<>/dev/tty; } 2>/dev/null; then
    {
      printf 'Clover credentials (from the Clover admin page - leave empty to fill in later)\n' >&3
      printf 'Client ID: ' >&3
      IFS= read -r CLIENT_ID <&3 || CLIENT_ID=""
      printf 'Client secret: ' >&3
      IFS= read -rs CLIENT_SECRET <&3 || CLIENT_SECRET=""
      printf '\n' >&3
    } 2>/dev/null || true
    exec 3>&- 2>/dev/null || true
  fi
  cat > "$ENV_FILE" <<EOF
export CAS_CLOVER_PLUGIN_CLIENT_ID=${CLIENT_ID:-FILL_ME}
export CAS_CLOVER_PLUGIN_CLIENT_SECRET=${CLIENT_SECRET:-FILL_ME}
export CAS_CLOVER_PLUGIN_AUTH_URL=https://clover.frontegg.com
export CAS_CLOVER_PLUGIN_SERVER_URL=https://app.cloversec.io
EOF
  chmod 600 "$ENV_FILE"
fi

printf 'clover: installed to %s\n' "$DEST"
if grep -q 'FILL_ME' "$ENV_FILE"; then
  printf 'clover: add your credentials to %s\n' "$ENV_FILE"
fi
printf 'clover: trust each workspace in Kiro - untrusted workspaces silently disable all hooks\n'
