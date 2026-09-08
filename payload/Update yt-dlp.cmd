@echo off
cd /d C:\MPV
if not exist yt-dlp.exe (
    echo yt-dlp.exe was not found in C:\MPV
    pause
    exit /b 1
)
yt-dlp.exe -U
pause
