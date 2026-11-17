#!/usr/bin/env bash
# The kiro/ tree is one artifact with two jobs: the .kiro drop-in install.sh
# writes, and the Kiro *power* a developer imports from a GitHub URL. The
# assertions below defend the power's manifest and layout, and the installer's
# refusal to install Clover in two scopes at once.
#
# The power is in the Agent Plugins 1.0.0 format: a schema-valid plugin.json,
# standard skills in skills/<name>/SKILL.md, and Kiro's client-specific
# documentation and steering under dev.kiro/. A power that regressed to POWER.md
# would still install and still look fine while Kiro ignored half of it, hence
# the stale-path assertions.
#
# Run from the marketplace tree root: bash tests/kiro-power.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
POWER="$ROOT/kiro"
TEST_DIR="$(mktemp -d)"
trap 'rm -rf "$TEST_DIR"' EXIT

bash -n "$POWER/scripts/install.sh" "$POWER/scripts/run-hook.sh"

# --- the manifest Kiro's plugin loader and the submission form both gate on ---
python3 - "$POWER" <<'PY'
import json, pathlib, re, sys

power = pathlib.Path(sys.argv[1])
manifest = json.loads((power / "plugin.json").read_text())

# Every pattern here is copied from kiro.kiro-agent's own loader.
assert re.fullmatch(
    r"https://agent-plugins\.org/schemas/1\.\d+\.\d+/plugin\.schema\.json",
    manifest.get("$schema", ""),
), manifest.get("$schema")

name = manifest.get("name", "")
assert re.fullmatch(r"[a-z0-9]([a-z0-9.-]*[a-z0-9])?", name), name
assert 1 <= len(name) <= 64 and "--" not in name and ".." not in name, name

# Fields the Kiro powers submission form requires of a listing.
for field in ("version", "description", "license"):
    assert manifest.get(field), f"plugin.json is missing {field}"
assert manifest.get("author", {}).get("name"), "plugin.json author needs a name"
keywords = manifest.get("keywords") or []
assert keywords and all(isinstance(k, str) and k for k in keywords), keywords

# The manifest must validate against the schema it declares. The published
# agent-plugins 1.0.0 schema sets additionalProperties:false and has no
# displayName — Kiro reads one, but the powers registry review validates
# against the schema and rejected the listing for it (2026-11). Client-specific
# data belongs under extensions["<reverse-domain>"].
allowed = {
    "$schema", "name", "version", "description", "author",
    "homepage", "repository", "license", "keywords", "extensions",
}
unknown = set(manifest) - allowed
assert not unknown, f"plugin.json has fields the Agent Plugins 1.0.0 schema forbids: {sorted(unknown)}"
assert set(manifest["author"]) <= {"name", "email", "url"}, manifest["author"]
for namespace, data in (manifest.get("extensions") or {}).items():
    assert isinstance(data, dict), f"extensions[{namespace!r}] must be an object"

# The listing must not claim enforcement the power alone does not deliver:
# blocking needs the separately installed hooks.
description = manifest["description"].lower()
assert "install" in description and "separately" in description, manifest["description"]

# --- the standard skills surface (Agent Plugins 1.0.0 §7, Kiro's loader) ---
skills_dir = power / "skills"
skills = sorted(p for p in skills_dir.iterdir() if (p / "SKILL.md").is_file())
assert skills, "kiro/skills/ has no <name>/SKILL.md — the power needs a standard component"
skill_name = re.compile(r"[a-z0-9]([a-z0-9-]*[a-z0-9])?")
for skill in skills:
    text = (skill / "SKILL.md").read_text()
    match = re.match(r"---\n(.*?)\n---\n", text, re.S)
    assert match, f"{skill.name}/SKILL.md has no front matter"
    fields = {}
    for line in match.group(1).splitlines():
        key, _, value = line.partition(":")
        fields[key.strip()] = value.strip()
    name = fields.get("name", "")
    # Kiro skips a skill whose name is invalid and warns when it differs from
    # its directory name.
    assert skill_name.fullmatch(name) and len(name) <= 64 and "--" not in name, name
    assert name == skill.name, f"skill {skill.name} declares name {name!r}"
    assert 1 <= len(fields.get("description", "")) <= 1024, f"{skill.name} description length"

# The registry review requires the license to be stated in the README and shipped.
readme = (power / "README.md").read_text()
assert re.search(r"^## License\n\nAGPL-3\.0-only", readme, re.M), "README has no License section naming AGPL-3.0-only"
assert (power / "LICENSE").read_text().lstrip().startswith("GNU AFFERO GENERAL PUBLIC LICENSE"), "kiro/LICENSE missing"
PY

# --- the power's own payload -------------------------------------------------
[ -s "$POWER/dev.kiro/INSTRUCTIONS.md" ] \
  || { echo "ERROR: kiro/dev.kiro/INSTRUCTIONS.md is missing or empty — an agent-plugin power's documentation is read from there, not POWER.md" >&2; exit 1; }

steering_count=$(find "$POWER/dev.kiro/steering" -maxdepth 1 -name '*.md' 2>/dev/null | wc -l | tr -d ' ')
[ "$steering_count" -ge 1 ] \
  || { echo "ERROR: kiro/dev.kiro/steering has no .md files — the power would install with no steering" >&2; exit 1; }

# Legacy layout must be gone, not merely unused: plugin.json wins when both are
# present, so a leftover POWER.md is a second source of truth that drifts unseen.
for stale in POWER.md steering clover-power; do
  [ ! -e "$POWER/$stale" ] \
    || { echo "ERROR: kiro/$stale still exists — the power is the whole kiro/ tree in the Agent Plugins format" >&2; exit 1; }
done

# --- the hooks the power carries ---------------------------------------------
python3 - "$POWER/hooks/clover.json" <<'PY'
import json, pathlib, sys

hooks = json.loads(pathlib.Path(sys.argv[1]).read_text())["hooks"]
triggers = {hook["trigger"] for hook in hooks}
assert triggers == {"SessionStart", "UserPromptSubmit", "PostFileSave", "PreTaskExec"}, triggers
# Kiro renders an unsuppressable card per hook; one shared name keeps four cards
# reading as one feature.
assert {hook["name"] for hook in hooks} == {"Clover Security"}, [h["name"] for h in hooks]
assert all(hook["action"]["command"].startswith("bash .kiro/clover/scripts/run-hook.sh") for hook in hooks)
# Both review hooks run a plan review, which the binary bounds at 270s
# (hookBudget). A shorter timeout kills capture mid-poll: the verdict is lost
# and the spec's capture lock stays held for ten minutes.
for hook in hooks:
    if hook["action"]["command"].endswith(("kiro-capture-spec", "kiro-pre-task")):
        assert hook.get("timeout", 0) >= 300, hook
PY

# --- fixtures for the installer cases -------------------------------------
# A remote holding only the binary: the installer copies everything else from
# the local tree. A clean HOME, because the installer refuses a repo install
# beside a machine-wide one and the developer's real ~/.kiro must not decide
# what a case exercises.
OS="$(uname -s | tr '[:upper:]' '[:lower:]')"
case "$OS" in darwin*) OS=darwin ;; linux*) OS=linux ;; esac
ARCH="$(uname -m)"
case "$ARCH" in x86_64) ARCH=amd64 ;; aarch64|arm64) ARCH=arm64 ;; esac
BINARY_NAME="clover-hook-${OS}-${ARCH}"

REMOTE="$TEST_DIR/remote"
mkdir -p "$REMOTE/bin"
printf '#!/usr/bin/env bash\nexit 0\n' > "$REMOTE/bin/$BINARY_NAME"
chmod +x "$REMOTE/bin/$BINARY_NAME"
(
  cd "$REMOTE/bin"
  if command -v sha256sum >/dev/null; then
    sha256sum "$BINARY_NAME" > checksums.sha256
  else
    shasum -a 256 "$BINARY_NAME" > checksums.sha256
  fi
)

CLEAN_HOME="$TEST_DIR/clean-home"
mkdir -p "$CLEAN_HOME"

# --- installing from a marketplace clone (the published one-liner) -----------
# Same script, the other shape. The marketplace's own version manifest must win
# over the power's copy: it is the file the self-update compares against.
CLONE="$TEST_DIR/marketplace"
mkdir -p "$CLONE/.claude-plugin" "$CLONE/bin"
cp -R "$POWER" "$CLONE/kiro"
cp "$REMOTE/bin/$BINARY_NAME" "$CLONE/bin/$BINARY_NAME"
cp "$REMOTE/bin/checksums.sha256" "$CLONE/bin/checksums.sha256"
jq '.version = "9.9.9-marketplace"' "$ROOT/.claude-plugin/plugin.json" > "$CLONE/.claude-plugin/plugin.json"

CLONE_REPO="$TEST_DIR/clone-repo"
mkdir -p "$CLONE_REPO"
HOME="$CLEAN_HOME" CLOVER_MARKETPLACE_URL="file://$TEST_DIR/does-not-exist" CLOVER_NO_PROMPT=1 \
  bash "$CLONE/kiro/scripts/install.sh" "$CLONE_REPO" >/dev/null

version=$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["version"])' \
  "$CLONE_REPO/.kiro/clover/.kiro-plugin/plugin.json")
[ "$version" = "9.9.9-marketplace" ] \
  || { echo "ERROR: a marketplace clone install took its version from $version, not the marketplace manifest" >&2; exit 1; }

# --- consent before anything is written --------------------------------------
# AWS's publisher terms require a privacy notice and consent where user data is
# collected. An unattended install prints the notice; a developer at a terminal
# who does not answer y gets nothing written at all.
NOTICE_REPO="$TEST_DIR/notice-repo"
mkdir -p "$NOTICE_REPO"
notice=$(HOME="$CLEAN_HOME" CLOVER_MARKETPLACE_URL="file://$TEST_DIR/does-not-exist" CLOVER_NO_PROMPT=1 \
  bash "$CLONE/kiro/scripts/install.sh" "$NOTICE_REPO" 2>&1)
for disclosed in "your prompts to Kiro" ".kiro/specs" "git user.email" "https://clover.security/privacy-policy/"; do
  printf '%s' "$notice" | grep -qF "$disclosed" \
    || { echo "ERROR: the unattended install's privacy notice does not mention '$disclosed'" >&2; exit 1; }
done

# The decline runs on a real pseudo-terminal, since the installer asks on
# /dev/tty (under curl | bash, stdin is the script).
DECLINE_REPO="$TEST_DIR/decline-repo"
mkdir -p "$DECLINE_REPO"
python3 - "$CLONE/kiro/scripts/install.sh" "$DECLINE_REPO" "$CLEAN_HOME" "$TEST_DIR" <<'PY'
import os, pty, sys, time

script, repo, home, test_dir = sys.argv[1:]
pid, fd = pty.fork()
if pid == 0:
    os.environ.update(HOME=home, CLOVER_MARKETPLACE_URL=f"file://{test_dir}/does-not-exist")
    os.environ.pop("CLOVER_NO_PROMPT", None)
    os.execvp("bash", ["bash", script, repo])
output = b""
deadline = time.time() + 30
answered = False
while time.time() < deadline:
    try:
        chunk = os.read(fd, 4096)
    except OSError:
        break
    if not chunk:
        break
    output += chunk
    if not answered and b"Install Clover? [y/N]" in output:
        os.write(fd, b"n\n")
        answered = True
_, status = os.waitpid(pid, 0)
assert answered, f"the installer never asked for consent:\n{output.decode(errors='replace')}"
assert b"not installed" in output, output.decode(errors="replace")
assert os.waitstatus_to_exitcode(status) == 0, status
PY
[ ! -e "$DECLINE_REPO/.kiro" ] && ! grep -qs clover "$DECLINE_REPO/.gitignore" \
  || { echo "ERROR: a declined install still wrote into $DECLINE_REPO" >&2; exit 1; }

# --- the installer refuses to mix the two scopes -----------------------------
# Kiro loads a repository's .kiro/hooks/ and the machine-wide ~/.kiro/hooks/
# together, so an install in both scopes runs every Clover hook twice — and a
# repo install starts from FILL_ME credentials, so one of each pair fails open.
MIXED_HOME="$TEST_DIR/mixed-home"
mkdir -p "$MIXED_HOME/.kiro/hooks"
cp "$POWER/hooks/clover.json" "$MIXED_HOME/.kiro/hooks/clover.json"
MIXED_REPO="$TEST_DIR/mixed-repo"
mkdir -p "$MIXED_REPO"

refused=$(HOME="$MIXED_HOME" CLOVER_MARKETPLACE_URL="file://$REMOTE" CLOVER_NO_PROMPT=1 \
  bash "$CLONE/kiro/scripts/install.sh" "$MIXED_REPO" 2>&1)
case "$refused" in
  *"already installed machine-wide"*) ;;
  *) echo "ERROR: a repo install beside a machine-wide one did not refuse: $refused" >&2; exit 1 ;;
esac
[ ! -e "$MIXED_REPO/.kiro" ] && [ ! -e "$MIXED_REPO/.gitignore" ] \
  || { echo "ERROR: the refused repo install still wrote into $MIXED_REPO" >&2; exit 1; }

# The other direction: a machine-wide install started inside a repository that
# carries its own copy.
REPO_HOME="$TEST_DIR/repo-home"
mkdir -p "$REPO_HOME" "$MIXED_REPO/.kiro/hooks"
cp "$POWER/hooks/clover.json" "$MIXED_REPO/.kiro/hooks/clover.json"
refused=$(cd "$MIXED_REPO" && HOME="$REPO_HOME" CLOVER_MARKETPLACE_URL="file://$REMOTE" CLOVER_NO_PROMPT=1 \
  bash "$CLONE/kiro/scripts/install.sh" 2>&1)
case "$refused" in
  *"already installed in this repository"*) ;;
  *) echo "ERROR: a machine-wide install inside a repo with its own copy did not refuse: $refused" >&2; exit 1 ;;
esac
[ ! -e "$REPO_HOME/.kiro" ] \
  || { echo "ERROR: the refused machine-wide install still wrote into $REPO_HOME" >&2; exit 1; }

# Re-running a machine-wide install is how a hook change lands, and from the
# home directory ~/.kiro/hooks/clover.json is both the "repo" copy and the
# machine-wide one — that must not read as a second scope.
(cd "$MIXED_HOME" && HOME="$MIXED_HOME" CLOVER_MARKETPLACE_URL="file://$REMOTE" CLOVER_NO_PROMPT=1 \
  bash "$CLONE/kiro/scripts/install.sh" >/dev/null 2>&1)
[ -f "$MIXED_HOME/.kiro/clover/scripts/run-hook.sh" ] \
  || { echo "ERROR: re-running a machine-wide install from the home directory was refused" >&2; exit 1; }

# An explicit override still installs, for a team deliberately committing the
# drop-in from a machine that also has Clover machine-wide.
rm -rf "$MIXED_REPO/.kiro"
HOME="$MIXED_HOME" CLOVER_ALLOW_DUPLICATE_INSTALL=1 CLOVER_MARKETPLACE_URL="file://$REMOTE" CLOVER_NO_PROMPT=1 \
  bash "$CLONE/kiro/scripts/install.sh" "$MIXED_REPO" >/dev/null
[ -f "$MIXED_REPO/.kiro/hooks/clover.json" ] \
  || { echo "ERROR: CLOVER_ALLOW_DUPLICATE_INSTALL=1 did not install" >&2; exit 1; }

# --- a home directory the shell would split -----------------------------------
# Git Bash on Windows gives HOME=/c/Users/<display name>, spaces included. Kiro
# reads any non-zero exit from PreTaskExec as a block, so a hook command that
# word-splits blocks every spec task: each installed command must run as-is.
ODD_HOME="$TEST_DIR/odd home & co|ltd"
mkdir -p "$ODD_HOME"
(cd "$ODD_HOME" && HOME="$ODD_HOME" CLOVER_MARKETPLACE_URL="file://$REMOTE" CLOVER_NO_PROMPT=1 \
  CLOVER_SERVER_URL='https://api.test/a b$HOME`x`' \
  bash "$CLONE/kiro/scripts/install.sh" >/dev/null)
jq -r '.hooks[].action.command' "$ODD_HOME/.kiro/hooks/clover.json" | while IFS= read -r command; do
  (cd "$TEST_DIR" && HOME="$ODD_HOME" bash -c "$command" </dev/null >/dev/null 2>&1) \
    || { echo "ERROR: installed hook command fails under a home with spaces: $command" >&2; exit 1; }
done

# env.sh is sourced by every hook, so what the developer typed must come back
# byte for byte, never expanded or run.
server_url=$(env -i bash -c '. "$1" && printf %s "$CLOVER_SECURITY_KURA_PLUGIN_SERVER_URL"' _ \
  "$ODD_HOME/.kiro/clover/env.sh")
[ "$server_url" = 'https://api.test/a b$HOME`x`' ] \
  || { echo "ERROR: env.sh did not round-trip the configured value, got '$server_url'" >&2; exit 1; }
[ -n "$(find "$ODD_HOME/.kiro/clover/env.sh" -perm 600)" ] \
  || { echo "ERROR: env.sh holds the client secret but is not private (600)" >&2; exit 1; }

# --- a re-run replaces the binary only with a verified one ---------------------
# Re-running the installer is the update path, and run-hook.sh execs whatever
# sits at the binary's path: a truncated or rejected binary exits 126, which
# Kiro reads as a block on every spec task. A download that fails or does not
# verify must leave the installed binary exactly as it was.
UPDATE_REPO="$TEST_DIR/update-repo"
mkdir -p "$UPDATE_REPO"
HOME="$CLEAN_HOME" CLOVER_MARKETPLACE_URL="file://$TEST_DIR/does-not-exist" CLOVER_NO_PROMPT=1 \
  bash "$CLONE/kiro/scripts/install.sh" "$UPDATE_REPO" >/dev/null
INSTALLED="$UPDATE_REPO/.kiro/clover/bin/$BINARY_NAME"
cp "$INSTALLED" "$TEST_DIR/installed-binary"

assert_binary_kept() {
  { cmp -s "$INSTALLED" "$TEST_DIR/installed-binary" && [ -x "$INSTALLED" ]; } \
    || { echo "ERROR: $1 replaced or removed the installed binary" >&2; exit 1; }
  leftovers="$(find "$UPDATE_REPO/.kiro/clover/bin" -name '.clover-update-*')"
  [ -z "$leftovers" ] || { echo "ERROR: $1 left a staging file behind: $leftovers" >&2; exit 1; }
}

# variant_tree <name> — the clone with a newer binary and the old manifest.
variant_tree() {
  VARIANT="$TEST_DIR/$1"
  cp -R "$CLONE" "$VARIANT"
  printf '#!/usr/bin/env bash\n# newer\nexit 0\n' > "$VARIANT/bin/$BINARY_NAME"
}
reinstall_from() {
  HOME="$CLEAN_HOME" CLOVER_MARKETPLACE_URL="file://$TEST_DIR/does-not-exist" CLOVER_NO_PROMPT=1 \
    bash "$1/kiro/scripts/install.sh" "$UPDATE_REPO" >/dev/null 2>&1
}

# A connection dropped mid-download, through the piped one-liner: curl has
# written part of the binary when it fails, and set -e stops the installer.
REAL_CURL="$(command -v curl)"
FAKE_PATH="$TEST_DIR/fake-path"
mkdir -p "$FAKE_PATH"
cat > "$FAKE_PATH/curl" <<EOF
#!/usr/bin/env bash
out=""; url=""
while [ \$# -gt 0 ]; do
  case "\$1" in -o) out="\$2"; shift ;; -*) ;; *) url="\$1" ;; esac
  shift
done
case "\$url" in
  */bin/$BINARY_NAME) head -c 10 "$CLONE/bin/$BINARY_NAME" > "\$out"; exit 18 ;;
esac
exec "$REAL_CURL" -fsSL "\$url" -o "\$out"
EOF
chmod +x "$FAKE_PATH/curl"
if (cd "$TEST_DIR" && PATH="$FAKE_PATH:$PATH" HOME="$CLEAN_HOME" CLOVER_MARKETPLACE_URL="file://$CLONE" \
  CLOVER_NO_PROMPT=1 bash -s -- "$UPDATE_REPO" < "$CLONE/kiro/scripts/install.sh" >/dev/null 2>&1); then
  echo "ERROR: a re-run whose binary download dropped reported success" >&2; exit 1
fi
assert_binary_kept "a dropped binary download"

variant_tree tree-mismatch
if reinstall_from "$TEST_DIR/tree-mismatch"; then
  echo "ERROR: a binary that fails its checksum installed" >&2; exit 1
fi
assert_binary_kept "a binary that fails its checksum"

# No manifest means nothing to verify against, so nothing is installed — as
# every other installer refuses. A first install refused this way hooks nothing.
variant_tree tree-no-manifest
rm "$TEST_DIR/tree-no-manifest/bin/checksums.sha256"
if reinstall_from "$TEST_DIR/tree-no-manifest"; then
  echo "ERROR: a binary with no checksum manifest installed" >&2; exit 1
fi
assert_binary_kept "a missing checksum manifest"
FRESH_REPO="$TEST_DIR/fresh-repo"
mkdir -p "$FRESH_REPO"
if HOME="$CLEAN_HOME" CLOVER_MARKETPLACE_URL="file://$TEST_DIR/does-not-exist" CLOVER_NO_PROMPT=1 \
  bash "$TEST_DIR/tree-no-manifest/kiro/scripts/install.sh" "$FRESH_REPO" >/dev/null 2>&1; then
  echo "ERROR: a first install with no checksum manifest reported success" >&2; exit 1
fi
[ ! -e "$FRESH_REPO/.kiro/hooks/clover.json" ] && [ ! -e "$FRESH_REPO/.kiro/clover/bin/$BINARY_NAME" ] \
  || { echo "ERROR: a refused first install still wired hooks or a binary into $FRESH_REPO" >&2; exit 1; }

# sha256sum -b writes "<hash> *<name>". That line must be checked, never read
# as no entry and skipped.
variant_tree tree-binary-mode
awk '{ print $1 " *" $2 }' "$CLONE/bin/checksums.sha256" > "$TEST_DIR/tree-binary-mode/bin/checksums.sha256"
if reinstall_from "$TEST_DIR/tree-binary-mode"; then
  echo "ERROR: a binary-mode checksum line was skipped, so a mismatching binary installed" >&2; exit 1
fi
assert_binary_kept "a mismatching binary-mode checksum line"

# And a binary that verifies does land, as a new file renamed into place.
(
  cd "$TEST_DIR/tree-binary-mode/bin"
  if command -v sha256sum >/dev/null; then
    sha256sum -b "$BINARY_NAME" > checksums.sha256
  else
    printf '%s *%s\n' "$(shasum -a 256 "$BINARY_NAME" | cut -d' ' -f1)" "$BINARY_NAME" > checksums.sha256
  fi
)
reinstall_from "$TEST_DIR/tree-binary-mode" \
  || { echo "ERROR: a binary matching its binary-mode checksum line did not install" >&2; exit 1; }
{ cmp -s "$INSTALLED" "$TEST_DIR/tree-binary-mode/bin/$BINARY_NAME" && [ -x "$INSTALLED" ]; } \
  || { echo "ERROR: a verified update did not replace the installed binary" >&2; exit 1; }
leftovers="$(find "$UPDATE_REPO/.kiro/clover/bin" -name '.clover-update-*')"
[ -z "$leftovers" ] || { echo "ERROR: a verified update left a staging file behind: $leftovers" >&2; exit 1; }

# A Windows clone with core.autocrlf checks the manifest out with CRLF; its
# lines must still match, not read as no entry and refuse the install.
variant_tree tree-crlf
awk '{ printf "%s\r\n", $0 }' "$CLONE/bin/checksums.sha256" > "$TEST_DIR/tree-crlf/bin/checksums.sha256"
cp "$CLONE/bin/$BINARY_NAME" "$TEST_DIR/tree-crlf/bin/$BINARY_NAME"
reinstall_from "$TEST_DIR/tree-crlf" \
  || { echo "ERROR: a CRLF checksum manifest refused a binary that matches it" >&2; exit 1; }

echo "kiro-power.sh: OK"
