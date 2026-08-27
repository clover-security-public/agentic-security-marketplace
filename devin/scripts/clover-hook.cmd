:; d="$(dirname "$0")"; case "${1:-}" in setup) exec bash "$d/setup.sh" "$@";; *) exec bash "$d/run-hook.sh" "$@";; esac #
@echo off
setlocal EnableExtensions
rem The single entry point named in devin/hooks.json, for every platform.
rem
rem Line 1 is a polyglot: cmd.exe reads it as a label and skips to the batch
rem below, while a POSIX shell executes it and execs the existing setup.sh /
rem run-hook.sh THROUGH BASH (they use pipefail, a bashism dash rejects), so
rem macOS and Linux behaviour is byte-identical to calling those scripts
rem directly. cmd.exe never executes line 1, so the bash there is unreachable
rem on Windows. The trailing "#" swallows the CR of the CRLF endings cmd.exe
rem requires.
rem
rem On Windows the shell scripts cannot run -- no bash, no jq -- so the hook
rem payload goes straight to the bundled executable, which speaks Devin's
rem protocol natively via its devin-* subcommands. Devin pipes the payload in
rem on stdin; cmd hands its stdin to the child unchanged.

rem The plugin IS the tree root (a remote subdir install materialises only the
rem subdir, with no bin\), so DEVIN_PLUGIN_ROOT already points at the tree.
rem %~dp0..\.. is the same place, script-relative, when the variable is absent.
set "ROOT=%DEVIN_PLUGIN_ROOT%"
if not defined DEVIN_PLUGIN_ROOT set "ROOT=%~dp0..\.."

set "ARCH=amd64"
if /I "%PROCESSOR_ARCHITECTURE%"=="ARM64" set "ARCH=arm64"
if /I "%PROCESSOR_ARCHITEW6432%"=="ARM64" set "ARCH=arm64"

set "BIN=%ROOT%\bin\clover-hook-windows-%ARCH%.exe"

rem Windows on ARM runs x64 binaries under emulation, so an amd64 build is a
rem valid fallback when the arm64 one is missing from the install.
if not exist "%BIN%" set "BIN=%ROOT%\bin\clover-hook-windows-amd64.exe"

if not exist "%BIN%" (
    rem Fail open: stderr for diagnosis, no stdout. A PreToolUse hook that says
    rem nothing leaves the write to Devin's own permission flow.
    echo clover: hook binary not found at %BIN% 1>&2
    exit /b 0
)

rem hooks.json keeps the same subcommand names the shell scripts use; map them
rem to the binary's Devin-native equivalents.
set "SUB=devin-review-write"
if /I "%~1"=="setup" set "SUB=devin-setup"
if /I "%~1"=="log-prompt" set "SUB=devin-log-prompt"
if /I "%~1"=="check-update" set "SUB=devin-check-update"

"%BIN%" %SUB%
exit /b %ERRORLEVEL%
