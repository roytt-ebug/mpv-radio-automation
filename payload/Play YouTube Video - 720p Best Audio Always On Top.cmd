@echo off
setlocal

REM ------------------------------------------------------------
REM Play YouTube Video - 720p Max, Best Audio, Always On Top
REM
REM Usage:
REM   1. Copy a YouTube video URL to the clipboard.
REM   2. Double-click this file.
REM
REM Behavior:
REM   - Stops any currently running mpv.exe instance.
REM   - Opens the copied YouTube URL in a resizable MPV window.
REM   - Keeps the MPV window always on top.
REM   - Limits video quality to 720p or lower.
REM   - Uses the best available separate audio stream when available.
REM   - Keeps the normal MPV config, including configured audio routing.
REM   - Disables automatic Lua scripts so radio randomization is not applied.
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

taskkill /IM mpv.exe /F >nul 2>&1

start "" "C:\MPV\mpv.exe" ^
    --load-scripts=no ^
    --vid=auto ^
    --ontop ^
    --autofit=50%% ^
    "--ytdl-format=bestvideo[height<=720]+bestaudio/best[height<=720]" ^
    "%URL%"

exit /b 0
