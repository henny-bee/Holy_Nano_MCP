@echo off
setlocal
cd /d "%~dp0"

set "ACTION=%~1"

if "%ACTION%"=="" goto setup
if /i "%ACTION%"=="setup" goto setup
if /i "%ACTION%"=="install" goto setup
if /i "%ACTION%"=="start" goto start
if /i "%ACTION%"=="status" goto status
if /i "%ACTION%"=="test" goto test
if /i "%ACTION%"=="help" goto help

:help
echo.
echo =======================================================
echo   Holy Nano MCP - Windows Quick CLI
echo =======================================================
echo.
echo Usage:
echo   holy-nano setup      Run automatic one-click installer
echo   holy-nano start      Start SSE localhost server
echo   holy-nano status     Check provider status and credentials
echo   holy-nano test       Run HolyC unit and integration tests
echo.
goto end

:setup
python scripts\setup_windows.py
goto end

:start
python scripts\holy_server.py
goto end

:status
wsl.exe -d Ubuntu -e bash -lc "cd $(wslpath '%CD%') && ./build/holy-nano-mcp --status --config config/vertex.json 2>/dev/null || ./build/holy-nano-mcp --status"
goto end

:test
powershell.exe -ExecutionPolicy Bypass -File .\scripts\build.ps1 -Test
goto end

:end
endlocal
