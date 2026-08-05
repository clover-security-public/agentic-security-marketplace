#!/bin/sh
# POSIX half of the Cursor hook launcher.
#
# Reached only from clover-hook.cmd's first line, never named in hooks.json.
# That indirection is deliberate: hooks.json must name a single command string
# for every OS (Cursor has no per-OS variant), and it must NOT name a .sh --
# Cursor runs Windows hook commands through PowerShell, which hands a .sh to the
# shell association, and `bash` there resolves to Git Bash's console bash.exe.
#
# An earlier attempt pointed hooks.json at one extensionless `clover-hook` and
# relied on PowerShell appending PATHEXT to reach a sibling .cmd. That fails: the
# extensionless file this repo also has to ship for POSIX wins the literal match,
# PowerShell cannot execute it, and ShellExecute spawns a detached console that
# hangs reading stdin. Hence: one file per platform, distinct names, and the .cmd
# is the only entry point.

set -u

ROOT="${CURSOR_PLUGIN_ROOT:-}"
if [ -z "$ROOT" ]; then
    # scripts live at <root>/cursor/scripts/, so the root is two levels up.
    ROOT="$(cd "$(dirname "$0")/../.." 2>/dev/null && pwd)" || ROOT=""
fi

OS="$(uname -s 2>/dev/null | tr '[:upper:]' '[:lower:]')"
ARCH="$(uname -m 2>/dev/null)"
case "$OS" in
    darwin*) OS=darwin ;;
    linux*) OS=linux ;;
esac
case "$ARCH" in
    x86_64 | amd64) ARCH=amd64 ;;
    aarch64 | arm64) ARCH=arm64 ;;
esac

BIN="${ROOT}/bin/clover-hook-${OS}-${ARCH}"

# Zip and tarball extraction both drop the executable bit; restore it rather
# than failing the hook.
if [ ! -x "$BIN" ] && [ -f "$BIN" ]; then
    chmod +x "$BIN" 2>/dev/null || true
fi

if [ ! -x "$BIN" ]; then
    # Fail open: Clover must never stand between a developer and their agent.
    # stderr is surfaced in Cursor's hook log for diagnosis. log-prompt gets its
    # "carry on" payload; the other hooks stay silent, which Cursor already
    # treats as "no opinion" (hooks fail open by default).
    echo "clover: hook binary not found at ${BIN}" >&2
    case "${1:-}" in
        cursor-log-prompt) printf '{"continue":true}\n' ;;
    esac
    exit 0
fi

exec "$BIN" "$@"
