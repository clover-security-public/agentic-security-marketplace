#!/usr/bin/env bash
# Builds a self-contained organization-distribution zip:
#   - Plugin manifest (.claude-plugin/plugin.json + marketplace.json)
#   - Hook config (hooks/hooks.json)
#   - README.md
#   - All four platform binaries (darwin/linux × arm64/amd64) under bin/
#   - A setup script that copies the right binary at SessionStart instead
#     of fetching from GitHub Releases.
#
# Output: dist/clover-plugin-v<version>.zip
#
# Usage:
#   ./scripts/build-org-zip.sh

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

VERSION=$(grep -o '"version"[[:space:]]*:[[:space:]]*"[^"]*"' .claude-plugin/plugin.json | grep -o '[0-9][0-9.]*')
echo "Building offline distribution for clover-plugin v${VERSION}"

STAGE="dist/clover-plugin"
rm -rf dist
mkdir -p "$STAGE/.claude-plugin" "$STAGE/hooks" "$STAGE/scripts" "$STAGE/bin"

# Copy the static plugin files.
cp .claude-plugin/plugin.json "$STAGE/.claude-plugin/"
cp .claude-plugin/marketplace.json "$STAGE/.claude-plugin/"
cp hooks/hooks.json "$STAGE/hooks/"
cp scripts/run-hook.sh "$STAGE/scripts/"
chmod +x "$STAGE/scripts/run-hook.sh"
cp README.md "$STAGE/"

# Bundle skills (auto-discovered by Claude Code from skills/<name>/SKILL.md).
if [ -d skills ]; then
    cp -R skills "$STAGE/"
fi

# Bundle the four platform binaries from bin/. Source lives in a private
# repo now; bin/ is treated as the canonical artifact location and is
# kept in sync with the latest release.
for target in darwin-arm64 darwin-amd64 linux-arm64 linux-amd64; do
    SRC="bin/clover-hook-${target}"
    if [ ! -f "$SRC" ]; then
        echo "ERROR: ${SRC} is missing — pull binaries from the latest release first:" >&2
        echo "  gh release download v${VERSION} --repo clover-security/clover-claude-plugin --dir bin/ --clobber --pattern 'clover-hook-*'" >&2
        exit 1
    fi
    cp "$SRC" "$STAGE/bin/"
    echo "  bundled ${target}"
done

# Setup script: at SessionStart, detect OS/arch and copy the matching bundled
# binary into ${CLAUDE_PLUGIN_DATA}/bin/clover-hook. No network calls.
cat > "$STAGE/scripts/setup.sh" <<'SETUP'
#!/usr/bin/env bash
set -e

# Persist plugin options to env.sh on every SessionStart — see
# scripts/run-hook.sh for why. Must happen before any short-circuit return.
if [ -n "${CLAUDE_PLUGIN_DATA}" ]; then
  mkdir -p "${CLAUDE_PLUGIN_DATA}"
  ENV_FILE="${CLAUDE_PLUGIN_DATA}/env.sh"
  {
    [ -n "${CLAUDE_PLUGIN_OPTION_CLIENT_ID:-}" ]     && printf 'export CAS_CLOVER_PLUGIN_CLIENT_ID=%q\n'     "${CLAUDE_PLUGIN_OPTION_CLIENT_ID}"
    [ -n "${CLAUDE_PLUGIN_OPTION_CLIENT_SECRET:-}" ] && printf 'export CAS_CLOVER_PLUGIN_CLIENT_SECRET=%q\n' "${CLAUDE_PLUGIN_OPTION_CLIENT_SECRET}"
    [ -n "${CLAUDE_PLUGIN_OPTION_AUTH_URL:-}" ]      && printf 'export CAS_CLOVER_PLUGIN_AUTH_URL=%q\n'      "${CLAUDE_PLUGIN_OPTION_AUTH_URL}"
    [ -n "${CLAUDE_PLUGIN_OPTION_SERVER_URL:-}" ]    && printf 'export CAS_CLOVER_PLUGIN_SERVER_URL=%q\n'    "${CLAUDE_PLUGIN_OPTION_SERVER_URL}"
    true
  } > "$ENV_FILE"
  chmod 600 "$ENV_FILE"
fi

BINARY_DIR="${CLAUDE_PLUGIN_DATA:-${CLAUDE_PLUGIN_ROOT}}/bin"
BINARY="$BINARY_DIR/clover-hook"
VERSION_FILE="$BINARY_DIR/.version"

OS=$(uname -s | tr '[:upper:]' '[:lower:]')
ARCH=$(uname -m)
case "$ARCH" in
  x86_64) ARCH="amd64" ;;
  aarch64|arm64) ARCH="arm64" ;;
esac
ASSET_NAME="clover-hook-${OS}-${ARCH}"

PLUGIN_VERSION=$(grep -o '"version"[[:space:]]*:[[:space:]]*"[^"]*"' "${CLAUDE_PLUGIN_ROOT}/.claude-plugin/plugin.json" 2>/dev/null | grep -o '[0-9][0-9.]*')

# Same-version short-circuit so we don't reinstall every session.
if [ -x "$BINARY" ] && [ -f "$VERSION_FILE" ] && [ "$(cat "$VERSION_FILE")" = "$PLUGIN_VERSION" ]; then
  exit 0
fi

mkdir -p "$BINARY_DIR"

SRC="${CLAUDE_PLUGIN_ROOT}/bin/${ASSET_NAME}"
if [ ! -f "$SRC" ]; then
  echo "clover-plugin: bundled binary not found for ${OS}/${ARCH} (expected ${SRC})" >&2
  exit 1
fi

cp "$SRC" "$BINARY"
chmod +x "$BINARY"
echo "$PLUGIN_VERSION" > "$VERSION_FILE"
SETUP
chmod +x "$STAGE/scripts/setup.sh"

# Zip it.
ZIP="dist/clover-plugin-v${VERSION}.zip"
( cd dist && zip -r "$(basename "$ZIP")" clover-plugin >/dev/null )

SIZE=$(du -h "$ZIP" | cut -f1)
echo
echo "Done: $ZIP ($SIZE)"
echo
echo "To install in your Claude Code organization:"
echo "  unzip $ZIP -d ~/clover-plugin && \\"
echo "  claude plugin install ~/clover-plugin/clover-plugin"
echo
echo "Or distribute the zip directly — Claude Code can install from a local path."
