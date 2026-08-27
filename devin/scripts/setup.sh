#!/usr/bin/env bash
# Deploys the clover-hook binary bundled with the plugin tree, verified against
# the tree's checksum manifest. Mirrors claude/scripts/setup.sh — same integrity
# gate, same channel model — with the paths Devin gives a plugin.
#
# Layout: the plugin is the marketplace tree root — a remote `#subdir` install
# materialises only the subdir, with no bin/ and no channel manifest, so the
# whole tree has to be the plugin. These scripts live at <tree>/devin/scripts,
# so the shared binaries are at <tree>/bin. Version and channel come from the
# tree's .claude-plugin/plugin.json, which the assembly and carry-forward
# scripts stamp per channel.
#
# There is no polling auto-update: updates arrive by the marketplace re-syncing
# the tree, exactly as on Claude. Polling public releases from a beta install
# would deploy a build that never soaked in the ring.
set -uo pipefail

REPO="clover-security-public/agentic-security-marketplace"

# -P resolves symlinks: Devin installs a plugin as a symlink under its cache
# (cache/<hash>/<version> -> the source dir), so a logical cd would put ROOT
# inside the cache and TREE somewhere with no bin/ or manifest at all.
ROOT="$(cd -P "$(dirname "$0")/.." && pwd -P)"
TREE="$(cd -P "$ROOT/.." && pwd -P)"
DATA="${CLOVER_DEVIN_DATA:-${HOME}/.devin/clover}"

read_version() {
  grep -o '"version"[[:space:]]*:[[:space:]]*"[^"]*"' "$1" 2>/dev/null | head -1 | sed 's/.*"\([^"]*\)"$/\1/'
}

TREE_MANIFEST="$TREE/.claude-plugin/plugin.json"
FULL_VERSION="$(read_version "$TREE_MANIFEST")"
case "$FULL_VERSION" in
  *-beta*)  CHANNEL="beta" ;;
  *-local*) CHANNEL="local" ;;
  *)        CHANNEL="public" ;;
esac

OS=$(uname -s | tr '[:upper:]' '[:lower:]')
EXE_SUFFIX=""
case "$OS" in
  darwin*) OS="darwin" ;;
  linux*) OS="linux" ;;
  mingw*|msys*|cygwin*|windows_nt*) OS="windows"; EXE_SUFFIX=".exe" ;;
esac
ARCH=$(uname -m)
case "$ARCH" in
  x86_64) ARCH="amd64" ;;
  aarch64|arm64) ARCH="arm64" ;;
esac
ASSET_NAME="clover-hook-${OS}-${ARCH}${EXE_SUFFIX}"

BINARY_DIR="$DATA/bin"
BINARY="$BINARY_DIR/clover-hook${EXE_SUFFIX}"
VERSION_FILE="$BINARY_DIR/.version"

# The binary reads its version from ${CLAUDE_PLUGIN_ROOT}/.claude-plugin/plugin.json
# and run-hook.sh points CLAUDE_PLUGIN_ROOT at DATA, so stage the tree's manifest
# there — the channel-stamped one, so audit rows carry the build actually running.
mkdir -p "$DATA/.claude-plugin" 2>/dev/null || true
cp "$TREE_MANIFEST" "$DATA/.claude-plugin/plugin.json" 2>/dev/null || true

# Devin has no equivalent of Claude's prompted userConfig (verified: it ignores
# a userConfig/secrets block in the manifest entirely), so credentials are set
# by a script. Copy it to a stable path so onboarding is one memorable command
# rather than a path dug out of `devin plugins info`.
cp "$ROOT/scripts/configure.sh" "$DATA/configure.sh" 2>/dev/null && chmod +x "$DATA/configure.sh" 2>/dev/null || true

if [ -x "$BINARY" ] && [ -f "$VERSION_FILE" ] && [ "$(cat "$VERSION_FILE")" = "$FULL_VERSION" ]; then
  exit 0
fi

mkdir -p "$BINARY_DIR"

# Integrity gate: every binary deployed must match the SHA-256 manifest shipped
# in the same tree. A missing manifest or a mismatch refuses the deploy — a
# tampered or half-synced tree must surface loudly, never run.
sha256_of() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}
verify_binary() {
  local candidate="$1" checksums="$TREE/bin/checksums.sha256" expected actual
  if [ ! -f "$checksums" ]; then
    echo "clover(devin) setup.sh: bin/checksums.sha256 is missing — refusing to deploy ${ASSET_NAME}" >&2
    return 1
  fi
  expected=$(awk -v name="$ASSET_NAME" '{ file=$2; sub(/^\*/, "", file); if (file == name) print $1 }' "$checksums" | head -1)
  if [ -z "$expected" ]; then
    echo "clover(devin) setup.sh: ${ASSET_NAME} has no entry in checksums.sha256 — refusing to deploy" >&2
    return 1
  fi
  actual=$(sha256_of "$candidate")
  if [ "$expected" != "$actual" ]; then
    echo "clover(devin) setup.sh: checksum mismatch for ${ASSET_NAME} — refusing to deploy" >&2
    return 1
  fi
  return 0
}

# A binary without should-review-plan cannot run the plan gate: it exits
# "Unknown command", the shim fails open on every write, and the gate is
# silently absent rather than visibly broken.
has_plan_gate() {
  printf '%s' "$("$1" 2>&1 || true)" | grep -q 'should-review-plan'
}

BUNDLED="$TREE/bin/$ASSET_NAME"
if [ -f "$BUNDLED" ]; then
  verify_binary "$BUNDLED" || exit 1
  cp "$BUNDLED" "$BINARY"
  chmod +x "$BINARY"
  if ! has_plan_gate "$BINARY"; then
    echo "clover(devin) setup.sh: bundled ${ASSET_NAME} has no should-review-plan subcommand — the plan gate would never fire" >&2
    rm -f "$BINARY"
    exit 1
  fi
  echo "$FULL_VERSION" > "$VERSION_FILE"
  exit 0
fi

# Release-download fallback exists only on the public channel: beta and local
# trees always bundle their binaries, and their repos are private, so a download
# could neither authenticate nor be verified against a public source.
if [ "$CHANNEL" != "public" ]; then
  echo "clover(devin) setup.sh: bundled binary missing for ${OS}/${ARCH} on channel ${CHANNEL} — refusing remote fallback" >&2
  exit 1
fi

DOWNLOAD="$BINARY_DIR/.download-${ASSET_NAME}"
curl -sL "https://github.com/$REPO/releases/download/v${FULL_VERSION}/${ASSET_NAME}" -o "$DOWNLOAD" 2>/dev/null
if [ -s "$DOWNLOAD" ] && verify_binary "$DOWNLOAD"; then
  mv "$DOWNLOAD" "$BINARY"
  chmod +x "$BINARY"
  echo "$FULL_VERSION" > "$VERSION_FILE"
  exit 0
fi
rm -f "$DOWNLOAD"

echo "clover(devin) setup.sh: failed to install a verified binary for ${OS}/${ARCH}" >&2
exit 1
