@echo off
setlocal
if not exist "%~dp0yt-dlp.exe" (
    echo yt-dlp.exe was not found beside this update shortcut.
    pause
    exit /b 1
)
"%~dp0yt-dlp.exe" -U
set "radio_update_exit=%ERRORLEVEL%"
if not "%radio_update_exit%"=="0" echo yt-dlp update failed with exit code %radio_update_exit%.
pause
exit /b %radio_update_exit%
