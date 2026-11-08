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

sha256_of() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}

DEST="${TARGET:-$HOME}/.kiro"

# Kiro loads a repository's .kiro/hooks/ and the machine-wide ~/.kiro/hooks/
# together, so installing in both scopes runs every Clover hook twice - and a
# repo install starts from FILL_ME credentials, so one of each pair fails open.
# Refuse the second scope unless explicitly asked for it. The home-directory
# check keeps a machine-wide re-run from reading its own install as a repo one.
if [ -z "${CLOVER_ALLOW_DUPLICATE_INSTALL:-}" ]; then
  if [ -n "$TARGET" ] && [ -f "${HOME}/.kiro/hooks/clover.json" ]; then
    printf 'clover: already installed machine-wide (%s), which covers every repository - nothing installed into %s\n' "${HOME}/.kiro" "$TARGET"
    printf 'clover: installing here as well would run every Clover hook twice; set CLOVER_ALLOW_DUPLICATE_INSTALL=1 to do it anyway\n'
    exit 0
  fi
  if [ -z "$TARGET" ] && [ -f "$PWD/.kiro/hooks/clover.json" ] \
    && [ "$(cd "$PWD" && pwd -P)" != "$(cd "$HOME" && pwd -P)" ]; then
    printf 'clover: already installed in this repository (%s) - nothing installed machine-wide\n' "$PWD/.kiro"
    printf 'clover: installing machine-wide as well would run every Clover hook twice here; set CLOVER_ALLOW_DUPLICATE_INSTALL=1 to do it anyway\n'
    exit 0
  fi
fi

mkdir -p "$DEST/clover/bin"

# The binary goes first, so an install refused here wires up no hooks. It is
# downloaded beside its final path and renamed in only once it matches the
# marketplace's checksum manifest: re-running this script is how an install
# updates, and run-hook.sh execs whatever sits at that path, so a dropped
# connection or a mismatch must leave the installed binary as it was - a
# truncated one exits 126, which Kiro reads as a block on every spec task. With
# no manifest there is nothing to verify against, so the install is refused, as
# every other Clover installer refuses it. The .clover-update- prefix is the one
# the binary's self-update sweeps and the repository .gitignore below covers.
BINARY="$DEST/clover/bin/$BINARY_NAME"
STAGED="$DEST/clover/bin/.clover-update-install-$$${EXE}"
CHECKSUMS="$(mktemp)"
trap 'rm -f "$STAGED" "$CHECKSUMS"' EXIT
obtain "bin/checksums.sha256" "$CHECKSUMS" \
  || { printf 'clover: no checksum manifest to verify %s against - aborting\n' "$BINARY_NAME" >&2; exit 1; }
# sha256sum -b marks each name with a leading '*'.
EXPECTED="$(awk -v name="$BINARY_NAME" '{ file=$2; sub(/\r$/, "", file); sub(/^\*/, "", file); if (file == name) print $1 }' "$CHECKSUMS" | head -1)"
[ -n "$EXPECTED" ] \
  || { printf 'clover: %s has no entry in checksums.sha256 - aborting\n' "$BINARY_NAME" >&2; exit 1; }
obtain "bin/$BINARY_NAME" "$STAGED"
ACTUAL="$(sha256_of "$STAGED")"
if [ "$EXPECTED" != "$ACTUAL" ]; then
  printf 'clover: checksum mismatch for %s - aborting\n' "$BINARY_NAME" >&2
  exit 1
fi
chmod +x "$STAGED"
# Windows refuses to rename over a binary a running hook holds; the installed
# one then stays, and a later re-run retries.
mv -f "$STAGED" "$BINARY"

mkdir -p "$DEST/hooks" "$DEST/clover/scripts"

obtain "kiro/hooks/clover.json" "$DEST/hooks/clover.json.tmp"
# The shipped hook config invokes the launcher relative to a repo root; a
# machine-wide install needs the absolute path under $HOME instead. Git Bash
# homes carry spaces and Kiro reads a failed PreTaskExec as a block, so that
# path is double-quoted (the one quoting bash, cmd and PowerShell share), then
# escaped for the JSON string and for sed's replacement.
if [ -n "$TARGET" ]; then
  mv "$DEST/hooks/clover.json.tmp" "$DEST/hooks/clover.json"
else
  LAUNCHER="$(printf '"%s"' "${HOME}/.kiro/clover/scripts/run-hook.sh" \
    | sed 's/[\\"]/\\&/g' | sed 's/[\\&|]/\\&/g')"
  sed "s|\.kiro/clover/scripts/run-hook\.sh|${LAUNCHER}|g" \
    "$DEST/hooks/clover.json.tmp" > "$DEST/hooks/clover.json"
  rm -f "$DEST/hooks/clover.json.tmp"
fi

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

if [ -n "$TARGET" ] && ! grep -qs 'clover/env.sh' "$TARGET/.gitignore" 2>/dev/null; then
  printf '\n# Clover credentials - never commit\n.kiro/clover/env.sh\n' >> "$TARGET/.gitignore"
fi
# A Windows self-update leaves the old binary beside the new one until a later
# hook can delete it; a hook killed mid-update can leave a temp file.
if [ -n "$TARGET" ] && ! grep -qs 'clover-update' "$TARGET/.gitignore" 2>/dev/null; then
  printf '\n# Clover self-update leftovers\n.kiro/clover/bin/.clover-update-*\n.kiro/clover/bin/*.replaced-*\n' >> "$TARGET/.gitignore"
fi

# Credentials: prompt on a terminal, otherwise leave a template. /dev/tty is
# read directly because under `curl | bash` stdin is the script itself. The
# probe must actually OPEN /dev/tty: in headless shells the node exists and
# passes -r/-w, but opening it fails with "Device not configured" — and an
# unguarded redirect there would kill the whole install under `set -e`.
# The Clover hosts. These are the values the shipping Claude Code plugin
# authenticates against; earlier Kiro installs wrote clover.frontegg.com (not a
# registered Frontegg vendor host, so auth 404'd) and app.cloversec.io (the
# webapp, which redirects) — every hook then failed auth and fail-opened, so
# nothing reached Clover. Overridable for a non-production tenant.
AUTH_URL="${CLOVER_AUTH_URL:-https://auth.cloversec.io}"
SERVER_URL="${CLOVER_SERVER_URL:-https://api.cloversec.io}"

ENV_FILE="$DEST/clover/env.sh"
if [ ! -f "$ENV_FILE" ]; then
  CLIENT_ID=""
  CLIENT_SECRET=""
  if [ -z "${CLOVER_NO_PROMPT:-}" ] && { exec 3<>/dev/tty; } 2>/dev/null; then
    {
      printf 'Clover setup (from the Clover admin page - leave empty to fill in later)\n' >&3
      printf 'Client ID: ' >&3
      IFS= read -r CLIENT_ID <&3 || CLIENT_ID=""
      printf 'Client secret: ' >&3
      IFS= read -rs CLIENT_SECRET <&3 || CLIENT_SECRET=""
      printf '\n' >&3
      # Asked, not assumed: a self-hosted or non-production tenant has its own
      # hosts, and a wrong one here fails auth silently at every hook.
      printf 'Clover API URL [%s]: ' "$SERVER_URL" >&3
      IFS= read -r ANSWER <&3 || ANSWER=""
      [ -n "$ANSWER" ] && SERVER_URL="$ANSWER"
      printf 'Auth URL [%s]: ' "$AUTH_URL" >&3
      IFS= read -r ANSWER <&3 || ANSWER=""
      [ -n "$ANSWER" ] && AUTH_URL="$ANSWER"
    } 2>/dev/null || true
    exec 3>&- 2>/dev/null || true
  fi
  # Every hook sources env.sh, so each value is %q-quoted: a secret holding
  # $, & or a backtick must come back as typed, never expanded or run. The
  # file is private before the secret reaches it.
  ( umask 077
    {
      printf 'export CLOVER_SECURITY_KURA_PLUGIN_CLIENT_ID=%q\n' "${CLIENT_ID:-FILL_ME}"
      printf 'export CLOVER_SECURITY_KURA_PLUGIN_CLIENT_SECRET=%q\n' "${CLIENT_SECRET:-FILL_ME}"
      printf 'export CLOVER_SECURITY_KURA_PLUGIN_AUTH_URL=%q\n' "$AUTH_URL"
      printf 'export CLOVER_SECURITY_KURA_PLUGIN_SERVER_URL=%q\n' "$SERVER_URL"
    } > "$ENV_FILE"
  )
fi

printf 'clover: installed to %s\n' "$DEST"
printf 'clover: api=%s auth=%s\n' "$SERVER_URL" "$AUTH_URL"
if grep -q 'FILL_ME' "$ENV_FILE"; then
  printf 'clover: add your credentials to %s\n' "$ENV_FILE"
fi
printf 'clover: trust each workspace in Kiro - untrusted workspaces silently disable all hooks\n'
