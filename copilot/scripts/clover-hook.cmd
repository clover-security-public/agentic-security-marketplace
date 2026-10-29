@echo off
setlocal EnableExtensions
rem Clover Copilot plugin -- the Windows entry point named in the "powershell"
rem commands of copilot/hooks/hooks.json. POSIX runs copilot/scripts/run-hook.sh
rem from the "bash" commands instead, so unlike Cursor's and Devin's this is a
rem plain batch file, not a cmd/sh polyglot.
rem
rem There is no bash or jq on a stock Windows box, so the hook payload goes
rem straight to the bundled executable, which speaks Copilot's protocol natively
rem via its copilot-* subcommands. Copilot pipes the payload in on stdin; cmd
rem hands its stdin to the child unchanged. Credentials come from the
rem environment (CLOVER_SECURITY_KURA_PLUGIN_*), which hooks inherit.
rem
rem Copilot's preToolUse fails CLOSED on a non-zero exit, so every path ends in
rem exit /b 0 and the hooks.json command adds "; exit 0" behind this as well.

set "ROOT=%COPILOT_PLUGIN_ROOT%"
if not defined ROOT set "ROOT=%~dp0..\.."

set "ARCH=amd64"
if /I "%PROCESSOR_ARCHITECTURE%"=="ARM64" set "ARCH=arm64"
if /I "%PROCESSOR_ARCHITEW6432%"=="ARM64" set "ARCH=arm64"

set "BIN=%ROOT%\bin\clover-hook-windows-%ARCH%.exe"

rem Windows on ARM runs x64 binaries under emulation, so an amd64 build is a
rem valid fallback when the arm64 one is missing from the install.
if not exist "%BIN%" set "BIN=%ROOT%\bin\clover-hook-windows-amd64.exe"

if not exist "%BIN%" (
    echo clover: hook binary not found at %BIN% 1>&2
    exit /b 0
)

set "SUB="
if /I "%~1"=="setup" set "SUB=copilot-setup"
if /I "%~1"=="check-update" set "SUB=copilot-check-update"
if /I "%~1"=="log-prompt" set "SUB=copilot-log-prompt"
if /I "%~1"=="review-plan" set "SUB=copilot-review-plan"
if /I "%~1"=="should-review-plan" set "SUB=copilot-should-review-plan"
if not defined SUB (
    echo clover: unknown subcommand %~1 1>&2
    exit /b 0
)

"%BIN%" %SUB%
exit /b 0
