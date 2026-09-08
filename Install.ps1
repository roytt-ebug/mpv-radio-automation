$ErrorActionPreference = "Stop"

$InstallDir = "C:\MPV"
$ProjectDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$PayloadDir = Join-Path $ProjectDir "payload"

function Ensure-Admin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    $isAdmin = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

    if (-not $isAdmin) {
        Write-Host "Administrator permission is needed to install to C:\MPV and register scheduled tasks."
        $args = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
        $p = Start-Process powershell.exe -Verb RunAs -ArgumentList $args -Wait -PassThru
        exit $p.ExitCode
    }
}

function Read-WithDefault([string]$Prompt, [string]$Default) {
    $answer = Read-Host "$Prompt [$Default]"
    if ([string]::IsNullOrWhiteSpace($answer)) { return $Default }
    return $answer.Trim()
}

function Parse-Days([string]$Text) {
    $map = @{
        "MON"="Monday"; "MONDAY"="Monday"
        "TUE"="Tuesday"; "TUESDAY"="Tuesday"
        "WED"="Wednesday"; "WEDNESDAY"="Wednesday"
        "THU"="Thursday"; "THURSDAY"="Thursday"
        "FRI"="Friday"; "FRIDAY"="Friday"
        "SAT"="Saturday"; "SATURDAY"="Saturday"
        "SUN"="Sunday"; "SUNDAY"="Sunday"
    }

    $days = @()
    foreach ($part in ($Text -split ",")) {
        $key = $part.Trim().ToUpperInvariant()
        if ($map.ContainsKey($key)) { $days += $map[$key] }
        else { throw "Unknown day '$part'. Use MON,TUE,WED,THU,FRI,SAT,SUN." }
    }
    return $days
}

function Register-MusicTask {
    param(
        [string]$TaskName,
        [string]$Playlist,
        [string]$TimeText,
        [string]$DaysText,
        [double]$RuntimeHours
    )

    if ([string]::IsNullOrWhiteSpace($Playlist)) {
        Write-Host "Skipping '$TaskName' because no playlist URL was supplied."
        return
    }

    $days = Parse-Days $DaysText
    $at = [datetime]::Parse($TimeText)

    $killAction = New-ScheduledTaskAction `
        -Execute "$env:SystemRoot\System32\cmd.exe" `
        -Argument '/c "taskkill /F /IM mpv.exe >nul 2>&1 & exit /b 0"'

    $safePlaylist = $Playlist.Replace('"', '')
    $playArgs = "--shuffle --loop-playlist=inf `"$safePlaylist`""

    $playAction = New-ScheduledTaskAction `
        -Execute "$InstallDir\mpv.exe" `
        -Argument $playArgs `
        -WorkingDirectory $InstallDir

    $trigger = New-ScheduledTaskTrigger `
        -Weekly `
        -WeeksInterval 1 `
        -DaysOfWeek $days `
        -At $at

    $settings = New-ScheduledTaskSettingsSet `
        -WakeToRun `
        -ExecutionTimeLimit (New-TimeSpan -Hours $RuntimeHours) `
        -RestartInterval (New-TimeSpan -Minutes 5) `
        -RestartCount 3 `
        -MultipleInstances IgnoreNew

    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent().Name
    $principal = New-ScheduledTaskPrincipal `
        -UserId $currentUser `
        -LogonType Interactive `
        -RunLevel Limited

    $task = New-ScheduledTask `
        -Action @($killAction, $playAction) `
        -Trigger $trigger `
        -Settings $settings `
        -Principal $principal

    Register-ScheduledTask -TaskName $TaskName -InputObject $task -Force | Out-Null
    Write-Host "Installed scheduled task: $TaskName"
}

function New-DesktopShortcut {
    param([string]$Target, [string]$Name)
    $desktop = [Environment]::GetFolderPath("Desktop")
    $shortcutPath = Join-Path $desktop "$Name.lnk"
    $ws = New-Object -ComObject WScript.Shell
    $shortcut = $ws.CreateShortcut($shortcutPath)
    $shortcut.TargetPath = $Target
    $shortcut.WorkingDirectory = $InstallDir
    $shortcut.Save()
}

Ensure-Admin

Write-Host ""
Write-Host "========================================"
Write-Host " MPV Radio Automation Installer"
Write-Host "========================================"
Write-Host ""

New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null
New-Item -ItemType Directory -Force -Path "$InstallDir\portable_config\scripts" | Out-Null

if (-not (Test-Path "$InstallDir\mpv.exe") -or -not (Test-Path "$InstallDir\mpv.com")) {
    Write-Host ""
    Write-Host "MPV is not installed in C:\MPV." -ForegroundColor Yellow
    Write-Host "Install MPV yourself before running this setup helper."
    Write-Host "Use the normal x86_64 Windows build (NOT dev, i686, or aarch64)."
    Write-Host "Windows builds: https://github.com/shinchiro/mpv-winbuild-cmake/releases"
    Write-Host "Extract the complete MPV build into C:\MPV, then run INSTALL.cmd again."
    Write-Host ""
    Read-Host "Press ENTER to close"
    exit 1
}

if (-not (Test-Path "$InstallDir\yt-dlp.exe")) {
    Write-Host "Downloading the official current yt-dlp.exe..."
    Invoke-WebRequest -UseBasicParsing `
        -Uri "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp.exe" `
        -OutFile "$InstallDir\yt-dlp.exe"
}

Copy-Item "$PayloadDir\portable_config\scripts\random-start.lua" "$InstallDir\portable_config\scripts\random-start.lua" -Force
Copy-Item "$PayloadDir\Play YouTube on MPV Audio.cmd" "$InstallDir\Play YouTube on MPV Audio.cmd" -Force
Copy-Item "$PayloadDir\Play YouTube Video - 720p Best Audio Always On Top.cmd" "$InstallDir\Play YouTube Video - 720p Best Audio Always On Top.cmd" -Force
Copy-Item "$PayloadDir\Update yt-dlp.cmd" "$InstallDir\Update yt-dlp.cmd" -Force
Copy-Item "$PayloadDir\README-LOCAL.txt" "$InstallDir\README-LOCAL.txt" -Force

Write-Host ""
Write-Host "Detected MPV audio outputs:"
Write-Host "---------------------------"
& "$InstallDir\mpv.com" --audio-device=help
Write-Host ""

$audioDevice = Read-Host "Paste the exact audio-device identifier you want MPV to use (example: wasapi/{...})"
if ([string]::IsNullOrWhiteSpace($audioDevice)) { throw "An audio device identifier is required." }

$conf = @"
audio-device=$audioDevice
vid=no
ytdl-format=bestaudio/best
force-window=yes
"@
Set-Content -Path "$InstallDir\portable_config\mpv.conf" -Value $conf -Encoding ASCII

Write-Host ""
Write-Host "Morning task (leave playlist blank to skip)"
$morningPlaylist = Read-Host "Morning YouTube playlist URL"
$morningTime = Read-WithDefault "Morning start time" "06:45"
$morningDays = Read-WithDefault "Morning days" "MON,TUE,WED,THU,FRI,SAT"
$morningHours = [double](Read-WithDefault "Morning maximum runtime in hours" "3")

Write-Host ""
Write-Host "Day-finisher task (leave playlist blank to skip)"
$eveningPlaylist = Read-Host "Day-finisher YouTube playlist URL"
$eveningTime = Read-WithDefault "Day-finisher start time" "15:45"
$eveningDays = Read-WithDefault "Day-finisher days" "MON,TUE,WED,THU,FRI"
$eveningHours = [double](Read-WithDefault "Day-finisher maximum runtime in hours" "3")

Register-MusicTask -TaskName "Music - Morning" -Playlist $morningPlaylist -TimeText $morningTime -DaysText $morningDays -RuntimeHours $morningHours
Register-MusicTask -TaskName "Music - Day Finisher" -Playlist $eveningPlaylist -TimeText $eveningTime -DaysText $eveningDays -RuntimeHours $eveningHours

New-DesktopShortcut -Target "$InstallDir\Play YouTube on MPV Audio.cmd" -Name "Play YouTube on MPV Audio"
New-DesktopShortcut -Target "$InstallDir\Play YouTube Video - 720p Best Audio Always On Top.cmd" -Name "Play YouTube Video - 720p"

Write-Host ""
Write-Host "========================================"
Write-Host " Installation complete"
Write-Host "========================================"
Write-Host "Installed folder: C:\MPV"
Write-Host "Open Task Scheduler to review/test the new tasks."
Write-Host "Right-click a task and choose Run to test it."
Write-Host ""
Read-Host "Press ENTER to close"
