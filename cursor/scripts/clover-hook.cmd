:; exec "$(dirname "$0")/clover-hook.sh" "$@" #
@echo off
setlocal EnableExtensions
rem The single entry point named in cursor/hooks/hooks.json, for every platform.
rem
rem Line 1 is a polyglot. cmd.exe reads a leading ":" as a label and skips it, so
rem Windows falls through to the batch below. A POSIX shell instead runs it as a
rem command: it execs clover-hook.sh and never reads any further. The trailing "#"
rem starts a shell comment that swallows the CR of this file's CRLF endings, which
rem cmd.exe needs and a shell would otherwise choke on.
rem
rem Why one file with a .cmd name rather than two files sharing a base name:
rem Cursor allows one `command` string per hook with no per-OS variant, and it
rem runs Windows hook commands through PowerShell. Pointing hooks.json at an
rem extensionless `clover-hook` and relying on PowerShell's PATHEXT lookup to
rem reach a sibling .cmd does not work -- the extensionless POSIX launcher this
rem repo must also ship wins the literal match, PowerShell cannot execute it, and
rem ShellExecute spawns a detached console window that hangs reading stdin. That
rem was the same visible-window defect as the Git Bash one this replaces.
rem
rem Cursor pipes the hook payload in on stdin (on Windows via a temp file and a
rem PowerShell pipeline); cmd hands its own stdin to the child unchanged. Nothing
rem here shells out to bash.

set "ROOT=%CURSOR_PLUGIN_ROOT%"
if not defined ROOT set "ROOT=%~dp0..\.."

set "ARCH=amd64"
if /I "%PROCESSOR_ARCHITECTURE%"=="ARM64" set "ARCH=arm64"
if /I "%PROCESSOR_ARCHITEW6432%"=="ARM64" set "ARCH=arm64"

set "BIN=%ROOT%\bin\clover-hook-windows-%ARCH%.exe"

rem Windows on ARM runs x64 binaries under emulation, so an amd64 build is a
rem valid fallback when the arm64 one is missing from the install.
if not exist "%BIN%" set "BIN=%ROOT%\bin\clover-hook-windows-amd64.exe"

if not exist "%BIN%" (
    rem Fail open, mirroring clover-hook.sh: stderr for diagnosis, the per-hook
    rem safe default on stdout. sessionStart and the stop hook read empty stdout
    rem as "no opinion", so they print nothing.
    echo clover: hook binary not found at %BIN% 1>&2
    if /I "%~1"=="cursor-log-prompt" echo {"continue":true}
    if /I "%~1"=="cursor-review-plan" echo {"permission":"allow"}
    exit /b 0
)

"%BIN%" %*
exit /b %ERRORLEVEL%
