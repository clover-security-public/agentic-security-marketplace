@echo off
setlocal EnableExtensions
rem Windows half of the Cursor hook launcher -- see the sibling `clover-hook`
rem for why the two files share one extensionless name in hooks.json.
rem
rem Cursor runs hook commands on Windows through PowerShell
rem (-NoProfile -NonInteractive -ExecutionPolicy Bypass), writes the hook payload
rem to a temp file and pipes it in as stdin. So this launcher only has to pick the
rem right executable and forward stdin plus the subcommand; cmd hands its own
rem stdin to the child unchanged.
rem
rem Nothing here shells out to bash. That is the entire reason this file exists:
rem hooks.json used to run `bash "<...>/run-hook.sh"`, and on Windows PowerShell
rem resolved `bash` to Git Bash's console bash.exe, which pops a visible window
rem and ships no `jq` for the script to use.

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
    rem Fail open, mirroring the unix launcher: stderr for diagnosis, the
    rem per-hook safe default on stdout. sessionStart and the stop hook read
    rem empty stdout as "no opinion", so they print nothing.
    echo clover: hook binary not found at %BIN% 1>&2
    if /I "%~1"=="cursor-log-prompt" echo {"continue":true}
    if /I "%~1"=="cursor-review-plan" echo {"permission":"allow"}
    exit /b 0
)

"%BIN%" %*
exit /b %ERRORLEVEL%
