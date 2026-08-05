:; d="$(dirname "$0")"; case "${1:-}" in setup) exec bash "$d/setup.sh" "$@";; *) exec bash "$d/run-hook.sh" "$@";; esac #
@echo off
setlocal EnableExtensions
rem The single entry point named in cursor/hooks/hooks.json, for every platform.
rem
rem Cursor allows one `command` string per hook with no per-OS variant, and it
rem runs Windows hook commands through PowerShell. Naming bash or a .sh there
rem spawns Git Bash's console bash.exe -- a visible window on every prompt --
rem so the command must be a .cmd. Line 1 is a polyglot: cmd.exe reads it as a
rem label and skips to the batch below, while a POSIX shell executes it and
rem execs the existing setup.sh / run-hook.sh THROUGH BASH -- exactly how the
rem old hooks.json invoked them (they use pipefail, a bashism dash rejects) --
rem so macOS and Linux behavior is byte-identical to before this file existed.
rem cmd.exe never executes line 1, so the bash there is unreachable on Windows. The trailing "#" swallows the
rem CR of the CRLF endings cmd.exe requires.
rem
rem On Windows the shell scripts cannot run (no bash, no jq), so the hook
rem payload goes straight to the bundled executable, which speaks Cursor's
rem protocol natively via its cursor-* subcommands. Cursor pipes the payload in
rem on stdin; cmd hands its stdin to the child unchanged.

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
    rem Fail open: stderr for diagnosis; log-prompt gets its "carry on" payload;
    rem the other hooks stay silent, which Cursor treats as "no opinion".
    echo clover: hook binary not found at %BIN% 1>&2
    if /I "%~1"=="log-prompt" echo {"continue":true}
    exit /b 0
)

rem hooks.json keeps the same subcommand names the shell scripts use; map them
rem to the binary's Cursor-native equivalents.
set "SUB=cursor-review-plan-stop"
if /I "%~1"=="setup" set "SUB=cursor-setup"
if /I "%~1"=="log-prompt" set "SUB=cursor-log-prompt"

"%BIN%" %SUB%
exit /b %ERRORLEVEL%
