@echo off
setlocal

REM ------------------------------------------------------------
REM Play YouTube on MPV Audio
REM
REM Usage:
REM   1. Copy a YouTube video/playlist URL to the clipboard.
REM   2. Double-click this file.
REM
REM This requests the radio session to stop, then starts the
REM copied URL in MPV. The normal MPV config still routes audio
REM to the configured output, but automatic Lua scripts are
REM disabled so manually selected media plays from its normal start.
REM ------------------------------------------------------------

for /f "usebackq delims=" %%U in (`powershell.exe -NoProfile -Command "$u = Get-Clipboard -Raw; if ($u) { $u.Trim() }"`) do set "URL=%%U"

if not defined URL (
    echo.
    echo No link was found in the clipboard.
    echo Copy a YouTube link first, then run this file again.
    echo.
    pause
    exit /b 1
)

if exist "%~dp0Radio.ps1" powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Radio.ps1" -Stop
start "" "C:\MPV\mpv.exe" --load-scripts=no "%URL%"
exit /b 0
