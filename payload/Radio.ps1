# Start one MPV window. MPV owns the playlist; Lua owns sampling and history.
# The launcher only coordinates this installation's start, stop and duration.
[CmdletBinding()]
param(
    [string]$Playlist,
    [ValidateRange(1,86400)][double]$DurationSeconds = 10800,
    [string]$MpvFolder = '',
    [string]$MpvExecutable,
    [switch]$Stop,
    [switch]$FunctionsOnly
)
$ErrorActionPreference = 'Stop'
# Resolve script location after parameter binding (also on Windows PowerShell 5.1).
if (-not $MpvFolder) { $MpvFolder = $PSScriptRoot }

function Join-NativeArguments([string[]]$Values) {
    return (($Values | ForEach-Object {
        $escaped = [regex]::Replace($_, '(\\*)"', '$1$1\"')
        '"' + [regex]::Replace($escaped, '(\\+)$', '$1$1') + '"'
    }) -join ' ')
}
function Get-RadioKey([string]$Folder) {
    $path = [IO.Path]::GetFullPath($Folder).TrimEnd([char[]]'\/').ToLowerInvariant()
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        return ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($path)))).Replace('-','').Substring(0,20)
    } finally { $sha.Dispose() }
}
function Invoke-RadioCommand([string]$Endpoint, [object[]]$Command) {
    # Local Windows pipe, one bounded request. No network server or background RPC loop.
    $pipe = [IO.Pipes.NamedPipeClientStream]::new('.', $Endpoint, [IO.Pipes.PipeDirection]::InOut, [IO.Pipes.PipeOptions]::Asynchronous)
    try {
        $pipe.Connect(1000)
        $utf8 = [Text.UTF8Encoding]::new($false)
        $reader = [IO.StreamReader]::new($pipe, $utf8)
        $writer = [IO.StreamWriter]::new($pipe, $utf8)
        $writer.AutoFlush = $true
        $writer.WriteLine((@{command=$Command; request_id=1} | ConvertTo-Json -Depth 4 -Compress))
        if ($Command[0] -eq 'quit') { return }
        $clock = [Diagnostics.Stopwatch]::StartNew()
        while ($clock.ElapsedMilliseconds -lt 3000) {
            $read = $reader.ReadLineAsync()
            if (-not $read.Wait([Math]::Max(1, 3000 - [int]$clock.ElapsedMilliseconds))) { throw 'MPV response timed out.' }
            if ($null -eq $read.Result) { throw 'MPV disconnected.' }
            $reply = $read.Result | ConvertFrom-Json
            if ($reply.request_id -eq 1) {
                if ($reply.error -ne 'success') { throw "MPV: $($reply.error)" }
                return $reply.data
            }
        }
        throw 'MPV response timed out.'
    } finally { $pipe.Dispose() }
}
if ($FunctionsOnly) { return }
if ($env:OS -ne 'Windows_NT') { throw 'Radio.ps1 requires Windows. Use mpv directly on other systems.' }
$MpvFolder = [IO.Path]::GetFullPath($MpvFolder).TrimEnd([char[]]'\/')
if (-not $Stop) {
    if (-not $Playlist) { throw 'Supply -Playlist "https://www.youtube.com/playlist?list=...".' }
    if (-not $MpvExecutable) { $MpvExecutable = Join-Path $MpvFolder 'mpv.exe' }
    $lua = Join-Path $MpvFolder 'portable_config\scripts\random-start.lua'
    foreach ($file in @($MpvExecutable, $lua)) {
        if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { throw "Missing required file: $file" }
    }
}
$key = Get-RadioKey $MpvFolder
$endpoint = "mpv-radio-$key"
$stopFile = Join-Path $MpvFolder 'radio-stop.request'
$mutex = [Threading.Mutex]::new($false, "mpv-radio-$key")
$owns = $false
$player = $null
try {
    try { $owns = $mutex.WaitOne(0) } catch [Threading.AbandonedMutexException] { $owns = $true }
    if (-not $owns) {
        [IO.File]::WriteAllText($stopFile, 'stop')
        try { $owns = $mutex.WaitOne(10000) } catch [Threading.AbandonedMutexException] { $owns = $true }
        if (-not $owns) { throw 'The previous radio session did not stop. Close its MPV window before retrying.' }
    }
    # Also stop an MPV left alive after its launcher was forcibly ended.
    # This pipe belongs only to the radio instance for this installation.
    $previousId = $null
    try { $previousId = Invoke-RadioCommand $endpoint @('get_property','pid') } catch { }
    if ($previousId) {
        $previous = Get-Process -Id $previousId -ErrorAction SilentlyContinue
        try {
            $null = Invoke-RadioCommand $endpoint @('quit')
            if ($previous -and -not $previous.WaitForExit(5000)) {
                throw 'The previous MPV did not close. Close its radio window before retrying.'
            }
        } finally { if ($previous) { $previous.Dispose() } }
    }
    Remove-Item -LiteralPath $stopFile -Force -ErrorAction SilentlyContinue
    if ($Stop) { return }
    $seconds = $DurationSeconds.ToString([cultureinfo]::InvariantCulture)
    $start = [Diagnostics.ProcessStartInfo]::new()
    $start.FileName = $MpvExecutable
    $start.WorkingDirectory = $MpvFolder
    $start.UseShellExecute = $false
    $start.Arguments = Join-NativeArguments @(
        "--config-dir=$MpvFolder\portable_config", '--load-scripts=no', "--script=$lua",
        "--script-opts-append=random-start-session_seconds=$seconds", "--input-ipc-server=$endpoint",
        '--shuffle', '--loop-playlist=inf', '--loop-file=no', '--vid=no', '--force-window=yes',
        '--', $Playlist
    )
    $clock = [Diagnostics.Stopwatch]::StartNew()
    $player = [Diagnostics.Process]::Start($start)
    while (-not $player.WaitForExit(250)) {
        if ($clock.Elapsed.TotalSeconds -ge $DurationSeconds -or (Test-Path -LiteralPath $stopFile)) { break }
    }
    if ($player.HasExited -and $player.ExitCode -ne 0) { throw "MPV exited with code $($player.ExitCode). Check the playlist, yt-dlp and audio output." }
} finally {
    if ($null -ne $player) {
        if (-not $player.HasExited) {
            try { $null = Invoke-RadioCommand $endpoint @('quit') } catch { }
            # Kill only the process started above if graceful shutdown fails.
            if (-not $player.WaitForExit(5000)) { $player.Kill(); $player.WaitForExit() }
        }
        $player.Dispose()
    }
    if ($owns) { $mutex.ReleaseMutex() }
    $mutex.Dispose()
}
