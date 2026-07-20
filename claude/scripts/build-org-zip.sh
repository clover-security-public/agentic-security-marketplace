#!/usr/bin/env bash
# Builds a self-contained organization-distribution zip for the `clover` plugin.
#
# The zip mirrors the plugin's real on-disk layout so it installs offline with
# `claude plugin install <path>` — no marketplace, no git, no GitHub Releases:
#   .claude-plugin/plugin.json + marketplace.json   (manifest)
#   claude/hooks/hooks.json                          (hook config)
#   claude/scripts/{setup.sh,run-hook.sh}            (runtime, shipped as-is)
#   claude/skills/                                   (if present)
#   bin/clover-hook-{darwin,linux}-{arm64,amd64}     (all four binaries)
#   README.md
#
# setup.sh already prefers the bundled binary under ${CLAUDE_PLUGIN_ROOT}/bin,
# so it runs fully offline; the GitHub Releases path is only a fallback when a
# bundled binary is missing. That's why we ship the real setup.sh verbatim
# rather than regenerating a stripped-down copy.
#
# Output: dist/clover-plugin-v<version>.zip
#
# Usage:
#   ./claude/scripts/build-org-zip.sh

set -euo pipefail

# Repo root is two levels up from this script (claude/scripts/ -> repo root).
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

VERSION=$(grep -o '"version"[[:space:]]*:[[:space:]]*"[^"]*"' .claude-plugin/plugin.json | grep -o '[0-9][0-9.]*')
echo "Building offline distribution for clover-plugin v${VERSION}"

STAGE="dist/clover-plugin"
rm -rf dist
mkdir -p "$STAGE/.claude-plugin" "$STAGE/claude/hooks" "$STAGE/claude/scripts" "$STAGE/bin"

# Manifest.
cp .claude-plugin/plugin.json "$STAGE/.claude-plugin/"
cp .claude-plugin/marketplace.json "$STAGE/.claude-plugin/"

# Hook config + runtime scripts (shipped verbatim — single source of truth).
cp claude/hooks/hooks.json "$STAGE/claude/hooks/"
cp claude/scripts/setup.sh "$STAGE/claude/scripts/"
cp claude/scripts/run-hook.sh "$STAGE/claude/scripts/"
chmod +x "$STAGE/claude/scripts/setup.sh" "$STAGE/claude/scripts/run-hook.sh"

cp README.md "$STAGE/"

# Bundle skills if the plugin ships any (auto-discovered from skills/<name>/SKILL.md).
if [ -d claude/skills ]; then
    cp -R claude/skills "$STAGE/claude/"
fi

# Bundle the four platform binaries from bin/. Source lives in a private repo;
# bin/ is the canonical artifact location, kept in sync with the latest release.
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
