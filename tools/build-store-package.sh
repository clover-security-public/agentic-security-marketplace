#!/usr/bin/env bash
# Builds the single-plugin zip that the agent plugin stores accept on upload.
#
#   ./tools/build-store-package.sh            # both targets
#   ./tools/build-store-package.sh claude     # dist/clover-claude-v<version>.zip
#   ./tools/build-store-package.sh cursor     # dist/clover-cursor-v<version>.zip
#
# This is NOT claude/scripts/build-org-zip.sh. That one builds the air-gapped
# ORG bundle: it rewrites marketplace.json to source "." so the bundle is its
# own offline marketplace, and strips the check-update hook. Uploading that to
# the store fails, because the store wants one self-contained plugin, not a
# marketplace.
#
# Two store rules are the whole reason this script exists, both learned from
# rejected uploads:
#
#   1. No top-level bin/. Claude Code adds a plugin's bin/ to PATH on the CLI,
#      and those executables never surface on the admin approval surface, so the
#      store refuses the package. Clover's payload therefore lives in runtime/,
#      which setup.sh copies into CLAUDE_PLUGIN_DATA at SessionStart.
#   2. Exactly one plugin.json. The repo is a marketplace holding several
#      plugins (clover, clover-for-developers, clover-for-security-teams) plus
#      the Cursor manifest, so shipping the whole tree presents 3 manifests and
#      is rejected. Each plugin uploads as its own package.
#
# Both rules are asserted against the staged tree below before zipping, so a
# future change cannot quietly produce a package the store will bounce.
#
# Output: dist/clover-<target>-v<version>.zip

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

command -v zip >/dev/null 2>&1 || { echo "ERROR: zip is required" >&2; exit 1; }

PLATFORM_BINARIES=(
  clover-hook-darwin-arm64
  clover-hook-darwin-amd64
  clover-hook-linux-amd64
  clover-hook-linux-arm64
  clover-hook-windows-amd64.exe
  clover-hook-windows-arm64.exe
)

# Stage and zip one target. $1 is "claude" or "cursor"; the manifest directory
# and the agent's script/hook directory follow from it.
build_target() {
  local target="$1" manifest_dir agent_dir version stage out

  case "$target" in
    claude) manifest_dir=".claude-plugin" ;;
    cursor) manifest_dir=".cursor-plugin" ;;
    *) echo "ERROR: unknown target '$target' (expected claude or cursor)" >&2; return 1 ;;
  esac
  agent_dir="$target"

  version=$(grep -o '"version"[[:space:]]*:[[:space:]]*"[^"]*"' "$manifest_dir/plugin.json" \
            | grep -o '[0-9][0-9.]*' | head -1)
  [ -n "$version" ] || { echo "ERROR: no version in $manifest_dir/plugin.json" >&2; return 1; }

  stage="dist/store-$target/clover"
  out="$ROOT/dist/clover-${target}-v${version}.zip"
  rm -rf "dist/store-$target" "$out"
  mkdir -p "$stage/$manifest_dir" "$stage/$agent_dir/hooks" "$stage/$agent_dir/scripts" "$stage/runtime"

  # The plugin's own manifest — and ONLY its own. Sibling plugins and the other
  # agent's manifest are deliberately excluded (store rule 2).
  cp "$manifest_dir/plugin.json" "$stage/$manifest_dir/"

  # Hook config + the two runtime scripts, shipped verbatim so the package runs
  # the same code the repo does. build-org-zip.sh's dev tooling is not runtime.
  cp "$agent_dir/hooks/hooks.json" "$stage/$agent_dir/hooks/"
  cp "$agent_dir/scripts/setup.sh" "$agent_dir/scripts/run-hook.sh" "$stage/$agent_dir/scripts/"
  chmod +x "$stage/$agent_dir/scripts/setup.sh" "$stage/$agent_dir/scripts/run-hook.sh"

  # Bundled skills, if this agent ships any (auto-discovered from SKILL.md).
  if [ -d "$agent_dir/skills" ]; then
    cp -R "$agent_dir/skills" "$stage/$agent_dir/"
  fi

  # The hook payload. Named runtime/, never bin/ (store rule 1).
  local b
  for b in "${PLATFORM_BINARIES[@]}"; do
    if [ ! -f "runtime/$b" ]; then
      echo "ERROR: runtime/$b is missing — pull the binaries from the latest release first" >&2
      return 1
    fi
    cp "runtime/$b" "$stage/runtime/$b"
    chmod +x "$stage/runtime/$b"
  done

  cp README.md "$stage/"
  find "$stage" -name '.DS_Store' -delete

  verify_stage "$target" "$manifest_dir" "$agent_dir" "$stage"

  ( cd "$(dirname "$stage")/clover" && zip -qr9 "$out" . )
  echo "  $out ($(du -h "$out" | cut -f1))"
}

# Assert the staged tree satisfies both store rules and is self-sufficient.
# Runs before zipping so a bad package is never produced at all.
verify_stage() {
  local target="$1" manifest_dir="$2" agent_dir="$3" stage="$4" count hooks_rel

  count=$(find "$stage" -name 'plugin.json' | wc -l | tr -d ' ')
  if [ "$count" != "1" ]; then
    echo "ERROR: $target package has $count plugin.json files, expected exactly 1" >&2
    find "$stage" -name 'plugin.json' >&2
    return 1
  fi

  if [ -e "$stage/bin" ]; then
    echo "ERROR: $target package contains a top-level bin/ — the store rejects it" >&2
    return 1
  fi

  local b
  for b in "${PLATFORM_BINARIES[@]}"; do
    if [ ! -x "$stage/runtime/$b" ]; then
      echo "ERROR: $target package is missing an executable runtime/$b" >&2
      return 1
    fi
  done

  # The manifest points at its hook config by relative path; that file has to
  # exist inside the package or the plugin loads with no hooks at all.
  hooks_rel=$(grep -o '"hooks"[[:space:]]*:[[:space:]]*"[^"]*"' "$stage/$manifest_dir/plugin.json" \
              | sed 's/.*"hooks"[[:space:]]*:[[:space:]]*"//; s/"$//; s|^\./||')
  if [ -n "$hooks_rel" ] && [ ! -f "$stage/$hooks_rel" ]; then
    echo "ERROR: $target manifest references $hooks_rel, which is not in the package" >&2
    return 1
  fi

  # Every script the hooks invoke must be present and executable.
  local f
  for f in "$stage/$agent_dir/scripts/setup.sh" "$stage/$agent_dir/scripts/run-hook.sh"; do
    [ -x "$f" ] || { echo "ERROR: $f missing or not executable" >&2; return 1; }
  done
}

TARGETS=("$@")
[ "${#TARGETS[@]}" -eq 0 ] && TARGETS=(claude cursor)

mkdir -p dist
for t in "${TARGETS[@]}"; do
  echo "Building store package for ${t}:"
  build_target "$t"
done

echo
echo "Upload the zip for the agent's plugin store. Each plugin uploads separately;"
echo "clover-for-developers and clover-for-security-teams are their own packages."
