#!/usr/bin/env bash
# Builds a self-contained organization-distribution zip for the `clover` plugin.
#
# The zip mirrors the plugin's real on-disk layout so it installs offline with
# `claude plugin install <path>` — no marketplace, no git, no GitHub Releases:
#   .claude-plugin/plugin.json + marketplace.json   (manifest)
#   claude/hooks/hooks.json                          (hook config)
#   claude/scripts/{setup.sh,run-hook.sh}            (runtime, shipped as-is)
#   claude/skills/                                   (if present)
#   bin/clover-hook-{darwin,linux}-{arm64,amd64}
#   bin/clover-hook-windows-{arm64,amd64}.exe        (all six binaries)
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

# Manifest. plugin.json ships as-is; marketplace.json is rewritten so the
# bundle is a self-contained offline marketplace: point the clover plugin's
# source at the bundle root (".") so `claude plugin install clover@clover-security`
# resolves from disk instead of cloning from GitHub (unreachable when air-gapped),
# and drop the sibling plugins that this bundle does not ship.
if ! command -v jq >/dev/null 2>&1; then
    echo "ERROR: jq is required to build the offline marketplace manifest." >&2
    exit 1
fi
cp .claude-plugin/plugin.json "$STAGE/.claude-plugin/"
jq '(.plugins |= map(select(.name == "clover"))) | (.plugins[0].source = ".")' \
    .claude-plugin/marketplace.json > "$STAGE/.claude-plugin/marketplace.json"

# Hook config: strip the check-update SessionStart hook. Air-gapped installs
# can't reach GitHub to self-update (updates arrive by re-shipping this bundle),
# so it would only hang on the 30s timeout and spam the hook log. The setup.sh
# SessionStart hook and the review hooks (PreToolUse/UserPromptSubmit) stay.
jq '.hooks.SessionStart[].hooks |= map(select((.command // "") | test("check-update") | not))' \
    claude/hooks/hooks.json > "$STAGE/claude/hooks/hooks.json"

# Runtime scripts (shipped verbatim — single source of truth).
cp claude/scripts/setup.sh "$STAGE/claude/scripts/"
cp claude/scripts/run-hook.sh "$STAGE/claude/scripts/"
chmod +x "$STAGE/claude/scripts/setup.sh" "$STAGE/claude/scripts/run-hook.sh"

cp README.md "$STAGE/"

# Bundle skills if the plugin ships any (auto-discovered from skills/<name>/SKILL.md).
if [ -d claude/skills ]; then
    cp -R claude/skills "$STAGE/claude/"
fi

# Bundle the six platform binaries from bin/. Source lives in a private repo;
# bin/ is the canonical artifact location, kept in sync with the latest release.
for target in darwin-arm64 darwin-amd64 linux-arm64 linux-amd64 windows-arm64.exe windows-amd64.exe; do
    SRC="bin/clover-hook-${target}"
    if [ ! -f "$SRC" ]; then
        echo "ERROR: ${SRC} is missing — pull binaries from the latest release first:" >&2
        echo "  gh release download v${VERSION} --repo clover-security/clover-claude-plugin --dir bin/ --clobber --pattern 'clover-hook-*'" >&2
        exit 1
    fi
    cp "$SRC" "$STAGE/bin/"
    echo "  bundled ${target}"
done

# The integrity manifest ships with the binaries: setup.sh verifies every
# binary against it before deploying and refuses when it is absent, so a bundle
# without it would install a dead plugin on exactly the air-gapped machines
# that cannot fall back to a download.
if [ ! -f bin/checksums.sha256 ]; then
    echo "ERROR: bin/checksums.sha256 is missing — the tree must be assembled by" >&2
    echo "  clover-hook-source/scripts/assemble-plugin-tree.sh before building the bundle." >&2
    exit 1
fi
cp bin/checksums.sha256 "$STAGE/bin/"
echo "  bundled checksums.sha256"

# Zip it.
ZIP="dist/clover-plugin-v${VERSION}.zip"
( cd dist && zip -r "$(basename "$ZIP")" clover-plugin >/dev/null )

SIZE=$(du -h "$ZIP" | cut -f1)
echo
echo "Done: $ZIP ($SIZE)"
echo
echo "To install offline in Claude Code (per developer):"
echo "  unzip $ZIP -d ~/clover-plugin"
echo "  claude plugin marketplace add ~/clover-plugin/clover-plugin"
echo "  claude plugin install clover@clover-security"
echo
echo "Org rollout: ship the unzipped clover-plugin/ dir to a fleet path"
echo "(e.g. /opt/clover-plugin) and point managed settings at it:"
echo '  "extraKnownMarketplaces": { "clover-security": {'
echo '    "source": { "source": "directory", "path": "/opt/clover-plugin" } } }'
