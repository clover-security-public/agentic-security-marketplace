#!/usr/bin/env bash
# claude/scripts/setup.sh and devin/scripts/setup.sh redeploy the binary on
# every plugin update, and a hook may still be running the old one. Overwriting
# a running binary in place poisons that file on macOS arm64: every later launch
# is SIGKILLed, so every hook fails (on Devin the plan gate check fails too, and
# Clover silently turns off). A redeploy must land as a new file renamed over
# the old path — a new inode — never as a write into the live one. The kill
# itself is macOS-specific; the inode is the portable contract.
#
# The two scripts cannot share a file at runtime, so each keeps its own copy of
# the deploy logic; every case runs against both, so neither drifts untested.
# gh and curl are stubs that serve a local release asset, so the public-channel
# release fallbacks run without reaching GitHub.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEST_DIR="$(mktemp -d)"
trap 'rm -rf "$TEST_DIR"' EXIT

FAILED=0
fail() { echo "FAIL [$AGENT]: $*" >&2; FAILED=1; }

OS="$(uname -s | tr '[:upper:]' '[:lower:]')"
case "$OS" in darwin*) OS=darwin ;; linux*) OS=linux ;; esac
ARCH="$(uname -m)"
case "$ARCH" in x86_64) ARCH=amd64 ;; aarch64|arm64) ARCH=arm64 ;; esac
ASSET_NAME="clover-hook-${OS}-${ARCH}"

sha256_of() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}
# shellcheck disable=SC2012 # ls -i is the portable way to read an inode
inode_of() { ls -i "$1" | awk '{print $1}'; }

# new_tree <agent> <case> <version> <usage text> — a marketplace tree carrying
# <agent>'s setup.sh, whose bundled binary prints <usage text> when run bare,
# as the real one prints its subcommands, plus a data dir to deploy into.
new_tree() {
  AGENT="$1"
  TREE="$TEST_DIR/$1/$2/tree"
  DATA="$TEST_DIR/$1/$2/data"
  mkdir -p "$TREE/.claude-plugin" "$TREE/bin" "$TREE/$1/scripts" "$TEST_DIR/home"
  cp "$ROOT/$1/scripts/setup.sh" "$TREE/$1/scripts/"
  if [ "$1" = devin ]; then
    cp "$ROOT/devin/scripts/configure.sh" "$TREE/devin/scripts/"
  fi
  set_tree_version "$3" "$4"
}

# set_tree_version <version> <usage text> — the tree a marketplace sync leaves:
# a bundled binary and the manifest that verifies it.
set_tree_version() {
  printf '{"name":"clover","version":"%s"}\n' "$1" > "$TREE/.claude-plugin/plugin.json"
  printf '#!/bin/sh\necho "usage: clover-hook <%s>"\n' "$2" > "$TREE/bin/$ASSET_NAME"
  chmod +x "$TREE/bin/$ASSET_NAME"
  printf '%s  %s\n' "$(sha256_of "$TREE/bin/$ASSET_NAME")" "$ASSET_NAME" > "$TREE/bin/checksums.sha256"
}

# Stub gh and curl: each copies $RELEASE_ASSET to where the real one would save
# the download and logs its name, and fails when it is unset (or, for gh, when
# GH_FAILS is set).
STUBS="$TEST_DIR/stubs"
mkdir -p "$STUBS"
cat > "$STUBS/curl" <<'EOF'
#!/bin/sh
out=""
while [ $# -gt 0 ]; do
  case "$1" in -o) out="$2"; shift 2 ;; *) shift ;; esac
done
[ -n "${RELEASE_ASSET:-}" ] && [ -n "$out" ] || exit 22
cp "$RELEASE_ASSET" "$out" && echo curl >> "$STUB_LOG"
EOF
cat > "$STUBS/gh" <<'EOF'
#!/bin/sh
dir="" pattern=""
while [ $# -gt 0 ]; do
  case "$1" in
    --dir) dir="$2"; shift 2 ;;
    --pattern) pattern="$2"; shift 2 ;;
    *) shift ;;
  esac
done
[ -n "${RELEASE_ASSET:-}" ] && [ -z "${GH_FAILS:-}" ] && [ -n "$dir" ] || exit 1
cp "$RELEASE_ASSET" "$dir/$pattern" && echo gh >> "$STUB_LOG"
EOF
chmod +x "$STUBS/curl" "$STUBS/gh"
STUB_LOG="$TEST_DIR/stub.log"
RELEASE_ASSET=""
GH_FAILS=""

# publish_release <version> <usage text> — a public tree that bundles no binary,
# so setup falls back to the release asset, which the manifest verifies.
publish_release() {
  set_tree_version "$1" "$2"
  RELEASE_ASSET="$TEST_DIR/release/$ASSET_NAME"
  mkdir -p "$TEST_DIR/release"
  mv "$TREE/bin/$ASSET_NAME" "$RELEASE_ASSET"
  chmod -x "$RELEASE_ASSET" # served unexecutable, so assert_swapped checks setup's own chmod +x
}

run_setup() {
  set +e
  case "$AGENT" in
    claude)
      env PATH="$STUBS:$PATH" STUB_LOG="$STUB_LOG" RELEASE_ASSET="$RELEASE_ASSET" GH_FAILS="$GH_FAILS" \
        HOME="$TEST_DIR/home" CLAUDE_PLUGIN_ROOT="$TREE" CLAUDE_PLUGIN_DATA="$DATA" \
        bash "$TREE/claude/scripts/setup.sh" >/dev/null 2>&1 ;;
    devin)
      env PATH="$STUBS:$PATH" STUB_LOG="$STUB_LOG" RELEASE_ASSET="$RELEASE_ASSET" GH_FAILS="$GH_FAILS" \
        HOME="$TEST_DIR/home" CLOVER_DEVIN_DATA="$DATA" \
        bash "$TREE/devin/scripts/setup.sh" >/dev/null 2>&1 ;;
  esac
  RC=$?
  set -e
}

assert_no_leftovers() {
  local leftovers
  leftovers="$(find "$DATA/bin" -name '.clover-update-*' -o -name '.download-*' -o -name "$ASSET_NAME")"
  [ -z "$leftovers" ] || fail "$1 left staging files behind: $leftovers"
}

# assert_swapped <marker> <version> <old inode> <what> — <what> installed the
# new binary as a new file and recorded its version.
assert_swapped() {
  [ "$RC" = 0 ] || fail "$4 exited $RC"
  grep -q "$1" "$DATA/bin/clover-hook" 2>/dev/null || fail "$4 did not install the new binary"
  [ -x "$DATA/bin/clover-hook" ] || fail "$4 left a binary that is not executable"
  [ "$(cat "$DATA/bin/.version" 2>/dev/null)" = "$2" ] || fail "$4 did not record its version"
  [ "$(inode_of "$DATA/bin/clover-hook")" != "$3" ] \
    || fail "$4 wrote into the live binary (same inode) — a running hook's binary is overwritten in place"
  assert_no_leftovers "$4"
}

# assert_kept <marker> <version> <what> — a refused deploy left the working
# binary and its version marker alone, so the next session retries.
assert_kept() {
  grep -q "$1" "$DATA/bin/clover-hook" 2>/dev/null || fail "$3 removed or replaced the working binary"
  [ "$(cat "$DATA/bin/.version" 2>/dev/null)" = "$2" ] \
    || fail "$3 recorded its version, so it would never be retried"
  assert_no_leftovers "$3"
}

for agent in claude devin; do
  # --- a plugin update replaces the binary with a new file --------------------
  new_tree "$agent" redeploy "1.0.0-local" "should-review-plan v1"
  run_setup
  [ "$RC" = 0 ] || fail "first deploy exited $RC"
  [ "$(cat "$DATA/bin/.version" 2>/dev/null)" = "1.0.0-local" ] || fail "first deploy did not record its version"
  old_inode="$(inode_of "$DATA/bin/clover-hook")"

  set_tree_version "1.1.0-local" "should-review-plan v2"
  run_setup
  assert_swapped 'v2' "1.1.0-local" "$old_inode" "redeploy"

  # --- a bundle that fails verification never touches the working binary ------
  set_tree_version "1.2.0-local" "should-review-plan v3"
  echo "tampered" >> "$TREE/bin/$ASSET_NAME"
  run_setup
  [ "$RC" != 0 ] || fail "a bundled binary failing its checksum deployed without complaint"
  assert_kept 'v2' "1.1.0-local" "a bundle failing its checksum"

  # --- a bundled binary without the plan gate never replaces a working one -----
  # Only Devin's setup checks for the gate.
  if [ "$agent" = devin ]; then
    set_tree_version "1.2.0-local" "log-prompt only"
    run_setup
    [ "$RC" != 0 ] || fail "a bundled binary with no should-review-plan deployed without complaint"
    assert_kept 'v2' "1.1.0-local" "a bundled binary with no plan gate"
  fi

  # --- a binary-mode checksum line still verifies ------------------------------
  new_tree "$agent" binary-mode "1.0.0-local" "should-review-plan"
  printf '%s *%s\n' "$(sha256_of "$TREE/bin/$ASSET_NAME")" "$ASSET_NAME" > "$TREE/bin/checksums.sha256"
  run_setup
  [ "$RC" = 0 ] && [ -x "$DATA/bin/clover-hook" ] || fail "a '*'-prefixed checksum line did not verify"

  # --- a CRLF manifest still verifies --------------------------------------------
  # A Windows clone with core.autocrlf checks checksums.sha256 out with CRLF.
  new_tree "$agent" crlf "1.0.0-local" "should-review-plan"
  printf '%s  %s\r\n' "$(sha256_of "$TREE/bin/$ASSET_NAME")" "$ASSET_NAME" > "$TREE/bin/checksums.sha256"
  run_setup
  [ "$RC" = 0 ] && [ -x "$DATA/bin/clover-hook" ] || fail "a CRLF checksum manifest did not verify"

  # --- a release download is swapped in the same way, and verified -------------
  # Claude tries gh before curl; Devin's setup has only the curl fallback.
  for via in gh curl; do
    if [ "$agent" = devin ] && [ "$via" = gh ]; then
      continue
    fi
    GH_FAILS=""
    [ "$via" = curl ] && GH_FAILS=1
    RELEASE_ASSET=""
    new_tree "$agent" "release-$via" "1.0.0" "should-review-plan v1"
    run_setup
    old_inode="$(inode_of "$DATA/bin/clover-hook")"

    publish_release "1.1.0" "should-review-plan v2"
    : > "$STUB_LOG"
    run_setup
    assert_swapped 'v2' "1.1.0" "$old_inode" "a release download via $via"
    [ "$(tail -n 1 "$STUB_LOG")" = "$via" ] || fail "the release download did not come through $via"

    publish_release "1.2.0" "should-review-plan v3"
    echo "tampered" >> "$RELEASE_ASSET"
    run_setup
    [ "$RC" != 0 ] || fail "a release download via $via failing its checksum deployed without complaint"
    assert_kept 'v2' "1.1.0" "a release download via $via failing its checksum"
  done
  RELEASE_ASSET=""
  GH_FAILS=""
done

if [ "$FAILED" != 0 ]; then
  exit 1
fi
echo "setup-deploy.sh: ok"
