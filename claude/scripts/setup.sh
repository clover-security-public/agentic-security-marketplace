#!/bin/bash
# Downloads the correct clover-hook binary from GitHub releases on first run.
# Uses ${CLAUDE_PLUGIN_DATA} for persistent storage across plugin updates.

REPO="clover-security/clover-claude-plugin"

# Persist plugin options to env.sh so other hook events
# (UserPromptSubmit, PreToolUse) — which do not receive
# CLAUDE_PLUGIN_OPTION_* env vars — can read them via run-hook.sh.
# printf %q quotes values safely for re-sourcing.
#
# Only rewrite env.sh when at least one CLAUDE_PLUGIN_OPTION_* is non-empty.
# This guard is load-bearing for two reasons:
#   1. setup.sh is invoked from run-hook.sh (self-bootstrap path) where
#      CLAUDE_PLUGIN_OPTION_* are not in scope. Without the guard we'd
#      truncate env.sh on every hook fire, clobbering values the user
#      provided via settings.json's `env` block.
#   2. Empty exports inside env.sh override real values inherited from
#      Claude Code's process env, breaking auth.
HAS_OPTIONS="${CLAUDE_PLUGIN_OPTION_CLIENT_ID:-}${CLAUDE_PLUGIN_OPTION_CLIENT_SECRET:-}${CLAUDE_PLUGIN_OPTION_AUTH_URL:-}${CLAUDE_PLUGIN_OPTION_SERVER_URL:-}"
if [ -n "${CLAUDE_PLUGIN_DATA}" ] && [ -n "$HAS_OPTIONS" ]; then
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
# Make sure CLAUDE_PLUGIN_DATA exists even when no options are supplied,
# so the binary install below has a stable target dir.
[ -n "${CLAUDE_PLUGIN_DATA}" ] && mkdir -p "${CLAUDE_PLUGIN_DATA}"

# ---------------------------------------------------------------------------
# Registry self-heal — workaround for split-brain plugin state.
#
# TODO(clover-coding-plugin): investigate the root cause and remove this
# block once Claude Code reliably writes installed_plugins.json for managed
# plugin installs.
#
# Some users hit a state where:
#   - The plugin cache is fully populated (~/.claude/plugins/cache/...).
#   - The marketplace is registered (~/.claude/plugins/known_marketplaces.json).
#   - But installed_plugins.json has NO entry for clover@clover-security.
# Claude Code then prints "Plugin clover not cached at (not recorded)" on
# every new session until the user runs /reload-plugins (which patches the
# in-memory state for that session but never persists back to the registry).
#
# Diagnosis (read-only Claude Code agent run on an affected machine,
# 2026-05-13) confirmed this is the case for at least one user (Ron):
#   - cache dir contained .orphaned_at + .in_use markers simultaneously
#   - hook log showed the binary successfully auth+POSTing
#   - claude plugin list omitted clover entirely
#
# Suspected triggers (NOT confirmed):
#   - A previous uninstall that didn't propagate to cache/data dirs.
#   - Interrupted update / scope migration.
#   - A managed-settings deployment race where the install record was
#     lost between manifest reads.
#
# This block is fully idempotent and safe to run on healthy machines:
#   - If installed_plugins.json already has a valid entry, it's a no-op.
#   - If it doesn't, it writes a 'user'-scope entry pointing at the
#     current CLAUDE_PLUGIN_ROOT (which IS the cache dir Claude Code
#     itself would have referenced if the registry write had succeeded).
#   - Atomic write (temp file + rename) so we never leave the file in
#     a torn state if interrupted.
#   - Wrapped in try/except — any failure logs to stderr and exits 0,
#     never blocks setup.sh from completing the rest of its work.
#
# Removal criteria: when we have evidence (Datadog + Claude Code release
# notes) that managed plugins reliably write installed_plugins.json on
# install, this whole block can be deleted. The investigation issue should
# track that evidence.
if [ -n "${CLAUDE_PLUGIN_ROOT}" ] && command -v python3 >/dev/null 2>&1; then
  python3 - "$CLAUDE_PLUGIN_ROOT" <<'PYEOF' 2>&1 || true
import json
import os
import pathlib
import sys
import tempfile
import datetime

try:
    plugin_root = sys.argv[1] if len(sys.argv) > 1 else os.environ.get("CLAUDE_PLUGIN_ROOT", "")
    if not plugin_root or not pathlib.Path(plugin_root).is_dir():
        sys.exit(0)

    registry_path = pathlib.Path.home() / ".claude" / "plugins" / "installed_plugins.json"
    if not registry_path.parent.exists():
        # No plugins dir at all — first-time user. Let Claude Code do its
        # normal thing; don't pre-create state we don't own.
        sys.exit(0)

    if registry_path.exists():
        try:
            data = json.loads(registry_path.read_text())
        except Exception:
            # Corrupt registry — don't risk a worse rewrite. Bail loudly.
            sys.stderr.write("clover setup.sh: installed_plugins.json is unreadable, skipping registry self-heal\n")
            sys.exit(0)
    else:
        data = {"version": 2, "plugins": {}}

    plugins = data.setdefault("plugins", {})
    existing = plugins.get("clover@clover-security", [])

    # Happy-path check: do we already have a valid entry whose installPath
    # actually points at an existing directory? If yes, no-op.
    if existing:
        valid = any(
            isinstance(e, dict)
            and e.get("installPath")
            and pathlib.Path(e["installPath"]).is_dir()
            for e in existing
        )
        if valid:
            sys.exit(0)

    # Read version from the plugin's own plugin.json so the entry matches
    # what Claude Code would have written itself.
    version = "unknown"
    plugin_json = pathlib.Path(plugin_root) / ".claude-plugin" / "plugin.json"
    if plugin_json.exists():
        try:
            version = json.loads(plugin_json.read_text()).get("version", "unknown") or "unknown"
        except Exception:
            pass

    # Best-effort: read HEAD SHA from the marketplace clone so the entry
    # shape matches what Claude Code's own writer produces for installs
    # (working plugins like csharp-lsp/superpowers have gitCommitSha set).
    # Field is genuinely optional — Claude Code accepts entries without it
    # (e.g., playground@claude-plugins-official has none).
    git_commit_sha = None
    head_file = (
        pathlib.Path.home()
        / ".claude" / "plugins" / "marketplaces"
        / "clover-security" / ".git" / "HEAD"
    )
    if head_file.exists():
        try:
            head = head_file.read_text().strip()
            if head.startswith("ref: "):
                ref_path = head_file.parent / head[5:]
                if ref_path.exists():
                    git_commit_sha = ref_path.read_text().strip()
            else:
                git_commit_sha = head
        except Exception:
            pass

    now = datetime.datetime.now(datetime.timezone.utc).replace(microsecond=0, tzinfo=None).isoformat() + "Z"
    entry = {
        "scope": "user",
        "installPath": plugin_root,
        "version": version,
        "installedAt": now,
        "lastUpdated": now,
    }
    if git_commit_sha:
        entry["gitCommitSha"] = git_commit_sha
    plugins["clover@clover-security"] = [entry]

    # Atomic write: temp file + rename, so we never leave registry.json
    # half-written if the process is killed mid-write.
    tmp_fd, tmp_path = tempfile.mkstemp(
        prefix=".installed_plugins.", suffix=".tmp", dir=str(registry_path.parent)
    )
    try:
        with os.fdopen(tmp_fd, "w") as fh:
            json.dump(data, fh, indent=2)
            fh.write("\n")
        os.replace(tmp_path, registry_path)
    except Exception:
        try:
            os.unlink(tmp_path)
        except Exception:
            pass
        raise

    sys.stderr.write(
        f"clover setup.sh: registry self-heal — wrote installed_plugins entry for {version} at {plugin_root}\n"
    )
except Exception as exc:
    # Never let registry-heal failures block setup.sh.
    sys.stderr.write(f"clover setup.sh: registry self-heal skipped due to error: {exc}\n")
    sys.exit(0)
PYEOF
fi
# ---------------------------------------------------------------------------

BINARY_DIR="${CLAUDE_PLUGIN_DATA:-${CLAUDE_PLUGIN_ROOT}}/bin"
BINARY="$BINARY_DIR/clover-hook"
VERSION_FILE="$BINARY_DIR/.version"

# Detect platform
OS=$(uname -s | tr '[:upper:]' '[:lower:]')
ARCH=$(uname -m)
case "$ARCH" in
  x86_64) ARCH="amd64" ;;
  aarch64|arm64) ARCH="arm64" ;;
esac
ASSET_NAME="clover-hook-${OS}-${ARCH}"

# Get current plugin version
PLUGIN_VERSION=$(grep -o '"version"[[:space:]]*:[[:space:]]*"[^"]*"' "${CLAUDE_PLUGIN_ROOT}/.claude-plugin/plugin.json" 2>/dev/null | grep -o '[0-9][0-9.]*')

# Skip if binary exists and version matches
if [ -x "$BINARY" ] && [ -f "$VERSION_FILE" ] && [ "$(cat "$VERSION_FILE")" = "$PLUGIN_VERSION" ]; then
  exit 0
fi

mkdir -p "$BINARY_DIR"

# Primary path: copy the bundled binary that ships with the plugin clone.
# This is the only reliable path — it works without gh CLI auth, without
# a working network, and across all org rollout configurations.
BUNDLED="${CLAUDE_PLUGIN_ROOT}/bin/${ASSET_NAME}"
if [ -f "$BUNDLED" ]; then
  cp "$BUNDLED" "$BINARY"
  chmod +x "$BINARY"
  echo "$PLUGIN_VERSION" > "$VERSION_FILE"
  exit 0
fi

# Fallback: GitHub Releases (kept for shallow clones or future detached-bin layouts)
if command -v gh >/dev/null 2>&1; then
  gh release download "v${PLUGIN_VERSION}" \
    --repo "$REPO" \
    --pattern "$ASSET_NAME" \
    --dir "$BINARY_DIR" \
    --clobber 2>/dev/null
  if [ -f "$BINARY_DIR/$ASSET_NAME" ]; then
    mv "$BINARY_DIR/$ASSET_NAME" "$BINARY"
    chmod +x "$BINARY"
    echo "$PLUGIN_VERSION" > "$VERSION_FILE"
    exit 0
  fi
fi

URL="https://github.com/$REPO/releases/download/v${PLUGIN_VERSION}/${ASSET_NAME}"
curl -sL "$URL" -o "$BINARY" 2>/dev/null
if [ -s "$BINARY" ]; then
  chmod +x "$BINARY"
  echo "$PLUGIN_VERSION" > "$VERSION_FILE"
  exit 0
fi

echo "clover-plugin setup.sh: failed to install binary for ${OS}/${ARCH} (looked at ${BUNDLED}, gh release, curl)" >&2
exit 1
