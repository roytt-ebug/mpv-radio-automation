# MPV Radio Automation setup helper, guided setup revision 3.
# Requires Windows PowerShell 5.1. MPV must already be installed in C:\MPV.
# -FunctionsOnly is for offline parser tests; it does not run installation.
param(
    [switch]$FunctionsOnly,
    [string]$TaskUserSid = '',
    [string]$ShortcutDesktop = ''
)
$ErrorActionPreference = 'Stop'

function ConvertTo-ClockTime([string]$Text) {
    $s = $Text.Trim().ToUpperInvariant()
    $hour = 0; $minute = 0
    if ($s -match '^(?<h>[0-9]{1,2})(?::(?<m>[0-9]{2}))?\s*(?<ampm>AM|PM)$') {
        $hour = [int]$Matches.h; $minute = [int]$Matches.m
        $period = $Matches.ampm
        if ($hour -lt 1 -or $hour -gt 12 -or $minute -gt 59) {
            throw 'Use a valid AM/PM time, for example 6:35 PM or 6:45 AM.'
        }
        $hour = $hour % 12
        if ($period -eq 'PM') { $hour += 12 }
    } elseif ($s -match '^(?<h>[0-9]{1,2}):(?<m>[0-9]{2})$') {
        $hour = [int]$Matches.h; $minute = [int]$Matches.m
    } elseif ($s -match '^[0-9]{3,4}$') {
        $s = $s.PadLeft(4, '0')
        $hour = [int]$s.Substring(0, 2); $minute = [int]$s.Substring(2, 2)
    } else {
        throw 'Enter a clock time: 18:35, 1835, or 6:35 PM. For mornings: 06:45 or 6:45 AM.'
    }
    if ($hour -gt 23 -or $minute -gt 59) {
        throw 'Hours must be 00-23 and minutes 00-59. Example: 18:35 = 6:35 PM.'
    }
    return [datetime]::Today.AddHours($hour).AddMinutes($minute)
}

function ConvertTo-MusicDays([string]$Text) {
    $s = $Text.Trim().ToUpperInvariant()
    switch -Regex ($s) {
        '^(1|WEEKDAYS|MON-FRI|MONDAY-FRIDAY)$' { $s = 'MON,TUE,WED,THU,FRI'; break }
        '^(2|MON-SAT|MONDAY-SATURDAY)$' { $s = 'MON,TUE,WED,THU,FRI,SAT'; break }
        '^(3|ALL|DAILY|EVERY DAY|EVERYDAY)$' { $s = 'MON,TUE,WED,THU,FRI,SAT,SUN'; break }
        '^(4|WEEKENDS|SAT-SUN|SATURDAY-SUNDAY)$' { $s = 'SAT,SUN'; break }
    }
    $map = @{
        MON='Monday'; MONDAY='Monday'; TUE='Tuesday'; TUES='Tuesday'; TUESDAY='Tuesday'
        WED='Wednesday'; WEDNESDAY='Wednesday'; THU='Thursday'; THUR='Thursday'
        THURS='Thursday'; THURSDAY='Thursday'; FRI='Friday'; FRIDAY='Friday'
        SAT='Saturday'; SATURDAY='Saturday'; SUN='Sunday'; SUNDAY='Sunday'
    }
    if (-not $s) { throw 'Choose 1, 2, 3, or 4; or type days such as MON,WED,FRI.' }
    $days = @()
    foreach ($word in ($s -split '[,;\s]+' | Where-Object { $_ })) {
        if (-not $map.ContainsKey($word)) {
            throw "Unknown day '$word'. Choose a preset number or type MON,WED,FRI."
        }
        $day = [System.DayOfWeek]$map[$word]
        if ($days -notcontains $day) { $days += $day }
    }
    if ($days.Count -eq 0) { throw 'Select at least one day.' }
    return $days
}

function ConvertTo-MusicRuntime([string]$Text) {
    $s = $Text.Trim().ToLowerInvariant()
    $minutes = 0.0
    if ($s -match '^(?<h>[0-9]{1,2}):(?<m>[0-9]{2})$') {
        if ([int]$Matches.m -gt 59) { throw 'For H:MM, minutes must be 00-59. Example: 1:30.' }
        $minutes = ([int]$Matches.h * 60) + [int]$Matches.m
    } elseif ($s -match '^(?<v>[0-9]+)\s*(m|min|mins|minute|minutes)$') {
        $minutes = [double]::Parse($Matches.v, [cultureinfo]::InvariantCulture)
    } elseif ($s -match '^(?<v>[0-9]+(?:\.[0-9]+)?)\s*(h|hr|hrs|hour|hours)?$') {
        $minutes = 60 * [double]::Parse($Matches.v, [cultureinfo]::InvariantCulture)
    } else {
        throw 'Enter a duration, not the time of day to stop: 3 = 3 hours; 1.5 or 1:30 = 90 minutes; 45 min = 45 minutes.'
    }
    if ($minutes -lt 1 -or $minutes -gt 1440) { throw 'Use a runtime between 1 minute and 24 hours.' }
    return [timespan]::FromSeconds([math]::Round($minutes * 60))
}

function ConvertTo-YouTubePlaylist([string]$Text) {
    $s = $Text.Trim()
    if (-not $s) { return $null }
    if ($s.Length -ge 2 -and (($s[0] -eq '"' -and $s[-1] -eq '"') -or ($s[0] -eq "'" -and $s[-1] -eq "'"))) {
        $s = $s.Substring(1, $s.Length - 2)
    }
    if ($s -match '[\s"<>|]') { throw 'Paste only the YouTube playlist link, without extra text or spaces.' }
    $uri = $null
    if (-not [uri]::TryCreate($s, [UriKind]::Absolute, [ref]$uri)) { throw 'Paste the complete link beginning with https://.' }
    $hosts = @('youtube.com','www.youtube.com','m.youtube.com','music.youtube.com','youtu.be')
    if ($uri.Scheme -notin @('https','http') -or $uri.DnsSafeHost -notin $hosts -or $uri.UserInfo -or -not $uri.IsDefaultPort) {
        throw 'Use a normal YouTube playlist URL, not a local file or a link to another website.'
    }
    if ($uri.Query -notmatch '(?:\?|&)list=([A-Za-z0-9_-]+)(?:&|$)') {
        throw 'This link has no playlist ID. Open the playlist and copy a link containing ?list= or &list=.'
    }
    # Remove share-tracking, watch/index and time parameters from scheduled playlists.
    return 'https://www.youtube.com/playlist?list=' + $Matches[1]
}

function Get-SamplePlaylist([string]$TaskName) {
    # Contributor-approved examples. Never selected just by pressing Enter.
    switch ($TaskName) {
        'Music - Morning' { return 'https://www.youtube.com/playlist?list=PLZAsCc2NQgn0' }
        'Music - Day Finisher' { return 'https://www.youtube.com/playlist?list=PLBejJIaDgbyQ' }
        default { return '' }
    }
}

function Resolve-PlaylistInput([string]$Text, [string]$SamplePlaylist) {
    $s = $Text.Trim()
    if ($s -in @('S','SAMPLE')) {
        if (-not $SamplePlaylist) { throw 'No sample is available for this task. Paste a playlist URL, or press Enter to skip.' }
        return ConvertTo-YouTubePlaylist $SamplePlaylist
    }
    # Blank still means skip. Custom links go through the same URL validation.
    return ConvertTo-YouTubePlaylist $s
}

function ConvertFrom-MpvDevices([string[]]$Lines) {
    $seen = @{}
    foreach ($line in $Lines) {
        if ($line -match "^\s*'(?<id>[^']+)'\s+\((?<name>.*)\)\s*$") {
            $id = $Matches.id; $name = $Matches.name
            if (-not $seen.ContainsKey($id)) {
                $seen[$id] = $true
                [pscustomobject]@{ Id = $id; Name = $name }
            }
        }
    }
}

function Resolve-MpvDevice([string]$Text, [object[]]$Devices) {
    $s = $Text.Trim().Trim([char[]]@([char]34, [char]39))
    $number = 0
    if ([int]::TryParse($s, [ref]$number)) {
        if ($number -ge 1 -and $number -le $Devices.Count) { return $Devices[$number - 1] }
    } else {
        # Accept a legacy pasted GUID, but only when it matches a detected output.
        $guid = $s.Trim([char[]]'{}')
        if ($guid -match '^[0-9a-fA-F]{8}-(?:[0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$') { $s = "wasapi/{$guid}" }
        $found = @($Devices | Where-Object { $_.Id -eq $s })
        if ($found.Count -eq 1) { return $found[0] }
    }
    throw "Choose a number from 1 to $($Devices.Count), or paste an exact ID from this detected list."
}

function Read-Validated([string]$Prompt, [string]$Default, [scriptblock]$Parser) {
    while ($true) {
        $label = $Prompt
        if ($Default) { $label += " [Enter = $Default]" }
        $answer = (Read-Host $label).Trim()
        if ($answer -eq 'Q') { throw [System.OperationCanceledException]::new('Setup cancelled.') }
        if (-not $answer -and $Default) { $answer = $Default }
        try { return (& $Parser $answer) }
        catch { Write-Host ("  Please try again: " + $_.Exception.Message) -ForegroundColor Yellow }
    }
}

function Read-MusicSession([string]$Name, [string]$DefaultTime, [string]$DefaultDays) {
    Write-Host "`n--- $Name ---" -ForegroundColor Cyan
    $sample = Get-SamplePlaylist $Name
    if ($sample) {
        Write-Host ('Sample playlist: ' + $sample) -ForegroundColor Green
        Write-Host 'Type S to use this sample, or paste your own full YouTube playlist link.'
        Write-Host 'S selects the sample shown ABOVE for this task; no copying is needed.'
    } else {
        Write-Host 'Paste the full playlist link from your browser.'
    }
    Write-Host 'No command or quotation marks are needed. Press Enter to SKIP this task.'
    Write-Host 'Skipping leaves any existing task unchanged. Type Q to cancel setup.'
    $playlist = Read-Validated 'YouTube playlist (S = sample, URL = your own, Enter = skip)' '' { param($v) Resolve-PlaylistInput $v $sample }
    if (-not $playlist) { Write-Host 'Skipped. No time/day/runtime questions for this task.'; return $null }
    Write-Host ('  Selected playlist: ' + $playlist) -ForegroundColor Green
    Write-Host 'Start time is a LOCAL CLOCK TIME. 18:35, 1835, and 6:35 PM all mean 6:35 in the evening.'
    Write-Host 'For morning use 06:45, 0645, or 6:45 AM. A task named Morning may use any time for testing.'
    $at = Read-Validated 'Start time' $DefaultTime { param($v) ConvertTo-ClockTime $v }
    Write-Host ("  Start: " + $at.ToString('HH:mm (h:mm tt)', [cultureinfo]::InvariantCulture)) -ForegroundColor Green
    Write-Host 'Days: 1 = Monday-Friday; 2 = Monday-Saturday; 3 = every day; 4 = Saturday-Sunday.'
    Write-Host 'Or type a custom list: MON,WED,FRI. Capitalization does not matter.'
    $days = @(Read-Validated 'Days (preset number or list)' $DefaultDays { param($v) ConvertTo-MusicDays $v })
    Write-Host 'Maximum runtime is a DURATION, not the time of day to stop.'
    Write-Host 'Examples: 3 = 3 hours; 1.5 or 1:30 = 90 minutes; 45 min = 45 minutes.'
    $runtime = Read-Validated 'Maximum runtime' '3' { param($v) ConvertTo-MusicRuntime $v }
    return [pscustomobject]@{ Name=$Name; Playlist=$playlist; At=$at; Days=$days; Runtime=$runtime }
}

function New-MusicTaskDefinition($Session, [string]$UserSid, [string]$MpvFolder) {
    $kill = New-ScheduledTaskAction -Execute "$env:SystemRoot\System32\cmd.exe" -Argument '/c "taskkill /F /IM mpv.exe >nul 2>&1 & exit /b 0"'
    $play = New-ScheduledTaskAction -Execute "$MpvFolder\mpv.exe" -Argument ('--shuffle --loop-playlist=inf "' + $Session.Playlist + '"') -WorkingDirectory $MpvFolder
    $trigger = New-ScheduledTaskTrigger -Weekly -WeeksInterval 1 -DaysOfWeek ([System.DayOfWeek[]]$Session.Days) -At $Session.At
    $settings = New-ScheduledTaskSettingsSet -WakeToRun -ExecutionTimeLimit $Session.Runtime -RestartInterval (New-TimeSpan -Minutes 5) -RestartCount 3 -MultipleInstances IgnoreNew
    $principal = New-ScheduledTaskPrincipal -UserId $UserSid -LogonType Interactive -RunLevel Limited
    return New-ScheduledTask -Action @($kill, $play) -Trigger $trigger -Settings $settings -Principal $principal
}

# Tests import only the functions above. No Windows calls, files or downloads.
if ($FunctionsOnly) { return }

$InstallDir = 'C:\MPV'
$PayloadDir = Join-Path $PSScriptRoot 'payload'
$stage = 'starting setup'
$backup = $null
$registered = @()
try {
    if ($env:OS -ne 'Windows_NT') { throw 'Run INSTALL.cmd on Windows, not Linux or macOS.' }
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    if (-not $TaskUserSid) { $TaskUserSid = $identity.User.Value }
    if (-not $ShortcutDesktop) { $ShortcutDesktop = [Environment]::GetFolderPath('Desktop') }
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        # Preserve the launching user's identity even if UAC uses another administrator.
        $launchArgs = '-NoProfile -ExecutionPolicy Bypass -File "{0}" -TaskUserSid "{1}" -ShortcutDesktop "{2}"' -f $PSCommandPath, $TaskUserSid, $ShortcutDesktop
        Write-Host 'Windows will request permission to update C:\MPV and register the selected tasks.'
        $child = Start-Process powershell.exe -Verb RunAs -ArgumentList $launchArgs -Wait -PassThru
        exit $child.ExitCode
    }
    $sid = New-Object Security.Principal.SecurityIdentifier($TaskUserSid)
    $taskUser = $sid.Translate([Security.Principal.NTAccount]).Value
    Write-Host "`nMPV Radio Automation - guided setup (revision 3)" -ForegroundColor Cyan
    Write-Host 'Type only your answer, then press Enter. Do not type the prompt or [brackets].'
    Write-Host 'Press Enter to accept a displayed default. Type Q at any input prompt to cancel.'
    Write-Host ("Computer time now: " + (Get-Date).ToString('yyyy-MM-dd HH:mm (h:mm tt)', [cultureinfo]::InvariantCulture))
    Write-Host "Tasks will play in this Windows account: $taskUser"

    $stage = 'checking the existing MPV installation'
    foreach ($exe in @('mpv.exe','mpv.com')) {
        if (-not (Test-Path -LiteralPath (Join-Path $InstallDir $exe) -PathType Leaf)) {
            throw "Missing $InstallDir\$exe. Install MPV yourself first, then rerun INSTALL.cmd."
        }
    }
    $payloadFiles = @('portable_config\scripts\random-start.lua','Play YouTube on MPV Audio.cmd','Play YouTube Video - 720p Best Audio Always On Top.cmd','Update yt-dlp.cmd','README-LOCAL.txt')
    foreach ($relative in $payloadFiles) {
        if (-not (Test-Path -LiteralPath (Join-Path $PayloadDir $relative) -PathType Leaf)) {
            throw "Missing payload file: $relative. Extract the WHOLE project ZIP before running INSTALL.cmd."
        }
    }
    Import-Module ScheduledTasks -ErrorAction Stop

    $stage = 'detecting audio outputs'
    # Ignore a malformed mpv.conf left by an earlier failed installation.
    $rawDevices = @(& "$InstallDir\mpv.com" --no-config --load-scripts=no --audio-device=help)
    if ($LASTEXITCODE -ne 0) { throw 'MPV could not list audio devices. Run mpv.com --no-config --audio-device=help to inspect the error.' }
    $devices = @(ConvertFrom-MpvDevices $rawDevices)
    if ($devices.Count -eq 0) { throw 'No audio devices were parsed. Connect your speaker and rerun setup.' }
    Write-Host "`n--- 1. Choose the music speaker ---" -ForegroundColor Cyan
    for ($i=0; $i -lt $devices.Count; $i++) {
        $note = ''
        if ($devices[$i].Id -eq 'auto') { $note = ' [follows Windows default; NOT a dedicated output]' }
        Write-Host ('  {0}. {1}{2}' -f ($i+1), $devices[$i].Name, $note)
    }
    Write-Host 'Type the NUMBER printed on the left, for example 2. No long device code needs copying.'
    Write-Host 'Monitor names are monitor/HDMI outputs; Realtek Speakers is a different output.'
    $audio = Read-Validated 'Audio output number (no default)' '' { param($v) Resolve-MpvDevice $v $devices }
    Write-Host ("  Selected: " + $audio.Name) -ForegroundColor Green

    $stage = 'collecting and validating schedules'
    $sessions = @()
    $session = Read-MusicSession 'Music - Morning' '06:45' '2'
    if ($null -ne $session) { $sessions += $session }
    $session = Read-MusicSession 'Music - Day Finisher' '15:45' '1'
    if ($null -ne $session) { $sessions += $session }

    $existing = @(Get-ScheduledTask -TaskPath '\' -ErrorAction Stop)
    $definitions = @{}
    foreach ($session in $sessions) {
        $definitions[$session.Name] = New-MusicTaskDefinition $session $TaskUserSid $InstallDir
    }
    Write-Host "`n--- Review BEFORE saving ---" -ForegroundColor Cyan
    Write-Host "Folder: $InstallDir"
    Write-Host "Windows account: $taskUser"
    Write-Host "Speaker: $($audio.Name)"
    Write-Host "Device ID (filled automatically): $($audio.Id)"
    foreach ($session in $sessions) {
        $end = $session.At.Add($session.Runtime)
        $dayNote = ''; if ($end.Date -gt $session.At.Date) { $dayNote = ' next day' }
        $verb = 'CREATE'; if (@($existing | Where-Object { $_.TaskName -eq $session.Name }).Count) { $verb = 'REPLACE after backup' }
        Write-Host ("`n$verb : " + $session.Name)
        Write-Host ('  Days: ' + ($session.Days -join ', '))
        Write-Host ('  Start: ' + $session.At.ToString('HH:mm (h:mm tt)', [cultureinfo]::InvariantCulture))
        Write-Host ('  Maximum runtime: ' + $session.Runtime.TotalMinutes + ' minutes')
        Write-Host ('  Approximate stop: ' + $end.ToString('HH:mm (h:mm tt)', [cultureinfo]::InvariantCulture) + $dayNote)
        Write-Host ('  Playlist: ' + $session.Playlist)
    }
    if (-not $sessions.Count) { Write-Host 'No scheduled tasks selected; configure audio and manual launchers only.' }
    $otherMpv = @($existing | Where-Object {
        $_.TaskName -notin @($sessions | ForEach-Object { $_.Name }) -and
        @($_.Actions | Where-Object { $_.Execute -ieq "$InstallDir\mpv.exe" }).Count -gt 0
    })
    foreach ($old in $otherMpv) { Write-Warning "Existing task '$($old.TaskName)' will remain unchanged. Check for overlapping schedules." }
    Write-Host "`nScheduled starts close any accessible mpv.exe, including manually opened videos."
    Write-Host 'Tasks require the selected user to be logged in. Locked is OK. AC-power conditions are retained.'
    Write-Host 'Wake request ON; catch-up after a missed start OFF; retry 5 minutes x 3; ignore duplicate task starts.'
    Write-Host 'A start time already passed today waits for the next selected day. Use Run in Task Scheduler to test now.'
    Write-Host 'Existing configuration and matching tasks will be backed up. Histories are not replaced.'
    if (-not (Test-Path -LiteralPath "$InstallDir\yt-dlp.exe")) { Write-Host 'yt-dlp.exe is missing; approval also allows downloading it from the official GitHub release.' }
    $approved = Read-Validated 'Apply the settings shown above? Type YES to save, or NO to cancel' 'NO' {
        param($v)
        if ($v -in @('Y','YES')) { return $true }
        if ($v -in @('N','NO')) { return $false }
        throw 'Type YES or NO.'
    }
    if (-not $approved) { Write-Host 'Cancelled. No project files or tasks were changed.'; exit 0 }

    $stage = 'backing up existing settings'
    $backup = Join-Path $InstallDir ('setup-backups\' + (Get-Date -Format 'yyyyMMdd-HHmmss-fff'))
    New-Item -ItemType Directory -Path $backup -Force | Out-Null
    foreach ($relative in (@('portable_config\mpv.conf') + $payloadFiles)) {
        $source = Join-Path $InstallDir $relative
        if (Test-Path -LiteralPath $source -PathType Leaf) {
            $destination = Join-Path $backup $relative
            New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force | Out-Null
            Copy-Item -LiteralPath $source -Destination $destination -Force
        }
    }
    foreach ($session in $sessions) {
        if (@($existing | Where-Object { $_.TaskName -eq $session.Name }).Count) {
            Export-ScheduledTask -TaskName $session.Name -TaskPath '\' | Set-Content -LiteralPath (Join-Path $backup ($session.Name + '.xml')) -Encoding Unicode
        }
    }
    $stage = 'downloading yt-dlp if missing'
    if (-not (Test-Path -LiteralPath "$InstallDir\yt-dlp.exe")) {
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
        $download = Join-Path $InstallDir ('yt-dlp-' + [guid]::NewGuid().ToString('N') + '.download')
        try {
            Invoke-WebRequest -UseBasicParsing -Uri 'https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp.exe' -OutFile $download -TimeoutSec 180
            if ((Get-Item -LiteralPath $download).Length -lt 1024) { throw 'Downloaded yt-dlp file is unexpectedly small.' }
            Move-Item -LiteralPath $download -Destination "$InstallDir\yt-dlp.exe"
        } finally { if (Test-Path -LiteralPath $download) { Remove-Item -LiteralPath $download -Force } }
    }
    $stage = 'copying project files and writing the selected audio device'
    foreach ($relative in $payloadFiles) {
        $destination = Join-Path $InstallDir $relative
        New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force | Out-Null
        Copy-Item -LiteralPath (Join-Path $PayloadDir $relative) -Destination $destination -Force
    }
    $configLines = [string[]]@("audio-device=$($audio.Id)",'vid=no','ytdl-format=bestaudio/best','force-window=yes')
    [IO.File]::WriteAllLines("$InstallDir\portable_config\mpv.conf", $configLines, (New-Object Text.UTF8Encoding($false)))
    foreach ($session in $sessions) {
        $stage = 'registering ' + $session.Name
        Register-ScheduledTask -TaskName $session.Name -TaskPath '\' -InputObject $definitions[$session.Name] -Force | Out-Null
        $registered += $session.Name
        Write-Host ('Saved task: ' + $session.Name) -ForegroundColor Green
    }
    $stage = 'creating desktop shortcuts'
    $shell = New-Object -ComObject WScript.Shell
    foreach ($entry in @(
        @{ Name='Play YouTube on MPV Audio'; File='Play YouTube on MPV Audio.cmd' },
        @{ Name='Play YouTube Video - 720p'; File='Play YouTube Video - 720p Best Audio Always On Top.cmd' }
    )) {
        $shortcutPath = Join-Path $ShortcutDesktop ($entry.Name + '.lnk')
        if (Test-Path -LiteralPath $shortcutPath) { Copy-Item -LiteralPath $shortcutPath -Destination $backup -Force }
        $shortcut = $shell.CreateShortcut($shortcutPath)
        $shortcut.TargetPath = Join-Path $InstallDir $entry.File
        $shortcut.WorkingDirectory = $InstallDir
        $shortcut.Save()
    }
    Write-Host "`nSetup completed. Backup folder: $backup" -ForegroundColor Green
    Write-Host 'Open Task Scheduler, right-click a configured music task, and choose Run to test.'
    Write-Host 'MPV itself was not installed or replaced. Existing history files were kept.'
    [void](Read-Host 'Press Enter to close')
} catch [System.OperationCanceledException] {
    Write-Host 'Setup cancelled. No changes applied.'
    exit 0
} catch {
    Write-Host "`nSETUP STOPPED while $stage" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Yellow
    if ($backup) { Write-Host "Backup folder: $backup" }
    if ($registered.Count) { Write-Host ('Tasks already saved: ' + ($registered -join ', ')) }
    Write-Host 'No automatic rollback was performed. Check existing tasks before retrying.'
    try {
        $errorFile = Join-Path $env:TEMP ('MPV-Radio-Setup-error-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.txt')
        @("Stage: $stage", $_.ToString(), $_.ScriptStackTrace, "Backup: $backup", ('Tasks saved: ' + ($registered -join ', '))) | Set-Content -LiteralPath $errorFile -Encoding UTF8
        Write-Host "Error details saved to: $errorFile"
    } catch { Write-Host 'Could not save an error log. Please copy the error text above.' }
    [void](Read-Host 'Press Enter to close')
    exit 1
}
