# Two MPV decks controlled through local JSON IPC. Windows PowerShell 5.1+, no modules.
[CmdletBinding()]
param(
    [string]$Playlist,
    [ValidateRange(1,86400)][double]$DurationSeconds = 10800,
    [string]$MpvFolder = $PSScriptRoot,
    [string]$MpvExecutable,
    [switch]$Stop,
    [switch]$FunctionsOnly
)
$ErrorActionPreference = 'Stop'

function Join-NativeArguments([string[]]$Values) {
    return (($Values | ForEach-Object {
        $escaped = [regex]::Replace($_, '(\\*)"', '$1$1\"')
        '"' + [regex]::Replace($escaped, '(\\+)$', '$1$1') + '"'
    }) -join ' ')
}
function Open-MpvConnection([string]$Endpoint, [int]$Timeout = 2000) {
    if ($env:OS -eq 'Windows_NT') {
        $stream = [IO.Pipes.NamedPipeClientStream]::new('.', $Endpoint, [IO.Pipes.PipeDirection]::InOut, [IO.Pipes.PipeOptions]::Asynchronous)
        try { $stream.Connect($Timeout) } catch { $stream.Dispose(); throw }
    } else {
        # Used by the real-player regression test on Linux; Windows uses named pipes.
        $socket = [Net.Sockets.Socket]::new([Net.Sockets.AddressFamily]::Unix, [Net.Sockets.SocketType]::Stream, [Net.Sockets.ProtocolType]::Unspecified)
        try { $socket.Connect([Net.Sockets.UnixDomainSocketEndPoint]::new($Endpoint)) } catch { $socket.Dispose(); throw }
        $stream = [Net.Sockets.NetworkStream]::new($socket, $true)
    }
    $utf8 = [Text.UTF8Encoding]::new($false)
    $client = [pscustomobject]@{ Stream=$stream; Reader=[IO.StreamReader]::new($stream,$utf8); Writer=[IO.StreamWriter]::new($stream,$utf8); Request=0 }
    $client.Writer.AutoFlush = $true
    $client.Writer.NewLine = "`n"
    try { $null = Invoke-Mpv $client @('disable_event','all') } catch { $stream.Dispose(); throw }
    return $client
}
function Close-MpvConnection($Client) {
    if ($null -ne $Client) { $Client.Stream.Dispose() }
}
function Invoke-Mpv($Client, [object[]]$Command) {
    $Client.Request++
    $id = $Client.Request
    $Client.Writer.WriteLine((@{ command=$Command; request_id=$id } | ConvertTo-Json -Depth 8 -Compress))
    $deadline = [Diagnostics.Stopwatch]::StartNew()
    while ($deadline.Elapsed.TotalSeconds -lt 3) {
        $read = $Client.Reader.ReadLineAsync()
        if (-not $read.Wait(3000)) { throw 'MPV IPC response timed out.' }
        if ($null -eq $read.Result) { throw 'MPV IPC disconnected.' }
        $reply = $read.Result | ConvertFrom-Json
        if ($reply.request_id -eq $id) {
            if ($reply.error -ne 'success') { throw "MPV command '$($Command[0])': $($reply.error)" }
            return $reply.data
        }
    }
    throw 'MPV did not acknowledge the requested command.'
}
function Get-RadioStatus($Deck) {
    $null = Invoke-Mpv $Deck.Client @('script-message','radio-heartbeat')
    try {
        $raw = Invoke-Mpv $Deck.Client @('get_property','user-data/radio-status')
        if ($raw) { return ($raw | ConvertFrom-Json) }
    } catch {
        if ($_.Exception.Message -notmatch 'property (unavailable|not found)') { throw }
    }
    return $null
}
function Send-RadioCommand($Deck, [string]$Name) {
    $before = Get-RadioStatus $Deck
    if ($null -eq $before) { throw 'random-start.lua has not published its status.' }
    $null = Invoke-Mpv $Deck.Client @('script-message',$Name)
    $timer = [Diagnostics.Stopwatch]::StartNew()
    while ($timer.Elapsed.TotalSeconds -lt 3) {
        $after = Get-RadioStatus $Deck
        if ($after.sequence -gt $before.sequence) { return $after }
        Start-Sleep -Milliseconds 25
    }
    throw "Lua script did not acknowledge $Name. Check that the current random-start.lua is installed."
}
function Start-RadioDeck([string]$Name, [string]$Executable, [string]$Folder, [string]$Token) {
    $endpoint = "mpv-radio-$Token-$Name"
    if ($env:OS -ne 'Windows_NT') { $endpoint = Join-Path ([IO.Path]::GetTempPath()) "$endpoint.sock" }
    $start = [Diagnostics.ProcessStartInfo]::new()
    $start.FileName = $Executable
    $start.WorkingDirectory = $Folder
    $start.UseShellExecute = $false
    $start.CreateNoWindow = $true
    $start.Arguments = Join-NativeArguments @(
        "--config-dir=$Folder/portable_config", '--load-scripts=no',
        "--script=$Folder/portable_config/scripts/random-start.lua",
        '--script-opts-append=random-start-managed=yes', "--input-ipc-server=$endpoint",
        '--idle=yes', '--pause=yes', '--keep-open=always', '--loop-playlist=no', '--loop-file=no',
        '--shuffle=no', '--audio-exclusive=no', '--vid=no', '--force-window=no', '--terminal=no',
        '--input-terminal=no', '--input-media-keys=no', '--volume=0', '--cache=yes', '--demuxer-readahead-secs=20'
    )
    $process = [Diagnostics.Process]::Start($start)
    try {
        $timer = [Diagnostics.Stopwatch]::StartNew()
        do {
            if ($process.HasExited) { throw "MPV deck $Name exited before connecting. Check mpv.conf and MPV's Lua support." }
            try { $client = Open-MpvConnection $endpoint 300; break } catch { $lastConnectionError=$_.Exception.Message; Start-Sleep -Milliseconds 100 }
        } while ($timer.Elapsed.TotalSeconds -lt 8)
        if ($null -eq $client) { throw "Could not connect to MPV deck $Name. $lastConnectionError" }
        $deck = [pscustomobject]@{ Name=$Name; Process=$process; Endpoint=$endpoint; Client=$client; LoadingSince=-1; Failures=0 }
        $timer.Restart()
        while (-not (Get-RadioStatus $deck)) {
            if ($timer.Elapsed.TotalSeconds -gt 3) { throw 'MPV did not load random-start.lua.' }
            Start-Sleep -Milliseconds 50
        }
        return $deck
    } catch {
        if (-not $process.HasExited) { $process.Kill() }
        throw
    }
}
function Load-RadioTrack($Deck, [string]$Path) {
    # Clear and acknowledge the previous readiness before reloading even the same URL.
    $null=Send-RadioCommand $Deck 'radio-finish'
    $null=Invoke-Mpv $Deck.Client @('set_property','pause',$true)
    Set-DeckVolume $Deck 0
    $null=Invoke-Mpv $Deck.Client @('loadfile',$Path,'replace')
}
function Get-TrackKey([string]$Path) {
    if ($Path -match '[?&]v=([\w-]+)' -or $Path -match 'youtu\.be/([\w-]+)') { return 'youtube:' + $Matches[1] }
    return $Path
}
function Get-RadioChoice($Tracks, $Bag, $Recent) {
    if ($Bag.Count -eq 0) {
        $items = @($Tracks)
        for ($i=$items.Count-1; $i -gt 0; $i--) {
            $j = Get-Random -Minimum 0 -Maximum ($i+1)
            $swap=$items[$i]; $items[$i]=$items[$j]; $items[$j]=$swap
        }
        foreach ($item in $items) { $Bag.Add($item) }
    }
    $limit = [Math]::Min(5, [Math]::Max(0, $Tracks.Count-2))
    if ($Tracks.Count -eq 2) { $limit=1 }
    $blocked = @{}
    for ($i=[Math]::Max(0,$Recent.Count-$limit); $i -lt $Recent.Count; $i++) { $blocked[$Recent[$i]]=$true }
    $index = -1
    for ($i=0; $i -lt $Bag.Count; $i++) {
        if (-not $blocked.ContainsKey((Get-TrackKey $Bag[$i]))) { $index=$i; break }
    }
    if ($index -lt 0) {
        # When a pass has only blocked entries left, choose its least-recent item.
        $best = [int]::MaxValue
        for ($i=0; $i -lt $Bag.Count; $i++) {
            $key=Get-TrackKey $Bag[$i]; $last=-1
            for ($j=0; $j -lt $Recent.Count; $j++) { if ($Recent[$j] -eq $key) { $last=$j } }
            if ($last -lt $best) { $best=$last; $index=$i }
        }
    }
    $chosen=$Bag[$index]; $Bag.RemoveAt($index)
    return $chosen
}
function Wait-RadioReady($Deck, $Decks, [double]$Timeout=60) {
    $timer=[Diagnostics.Stopwatch]::StartNew()
    do {
        if ($clock -and ($clock.Elapsed.TotalSeconds -ge $DurationSeconds -or (Test-Path -LiteralPath $stopFile))) {
            throw [OperationCanceledException]::new('Radio session ended while loading.')
        }
        foreach ($other in $Decks) { $null=Get-RadioStatus $other }
        $status=Get-RadioStatus $Deck
        if ($status -and $status.ready -and -not $status.seeking) { return $status }
        Start-Sleep -Milliseconds 100
    } while ($timer.Elapsed.TotalSeconds -lt $Timeout)
    throw 'MPV did not load the playlist/track within 60 seconds. Check YouTube, yt-dlp and the audio output.'
}
function Set-DeckVolume($Deck, [double]$Value) { $null=Invoke-Mpv $Deck.Client @('set_property','volume',$Value) }
function Get-FadeGains([double]$Fraction, [double]$Volume) {
    $p=[Math]::Min(1,[Math]::Max(0,$Fraction))
    return @(($Volume*(1-$p)), ($Volume*$p))
}
if ($FunctionsOnly) { return }

$MpvFolder = [IO.Path]::GetFullPath($MpvFolder).TrimEnd([char[]]'\/')
$stopFile=Join-Path $MpvFolder 'radio-stop.request'
$sessionFile=Join-Path $MpvFolder 'radio-session.json'
if ($Stop) { [IO.File]::WriteAllText($stopFile,'stop'); return }
if (-not $Playlist) { throw 'Supply -Playlist "https://www.youtube.com/playlist?list=...".' }
if (-not $MpvExecutable) { $MpvExecutable=Join-Path $MpvFolder 'mpv.exe' }
if (-not (Test-Path -LiteralPath $MpvExecutable -PathType Leaf)) { throw "MPV was not found at $MpvExecutable." }
$sha=[Security.Cryptography.SHA256]::Create()
try { $key=([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($MpvFolder.ToLowerInvariant())))).Replace('-','').Substring(0,20) } finally { $sha.Dispose() }
$mutex=[Threading.Mutex]::new($false,"mpv-radio-$key")
$owns=$false; $decks=@(); $clock=[Diagnostics.Stopwatch]::StartNew(); $token=[guid]::NewGuid().ToString('N')
try {
    try { $owns=$mutex.WaitOne(0) } catch [Threading.AbandonedMutexException] { $owns=$true }
    if (-not $owns) {
        [IO.File]::WriteAllText($stopFile,'next scheduled session')
        try { $owns=$mutex.WaitOne(10000) } catch [Threading.AbandonedMutexException] { $owns=$true }
        if (-not $owns) { throw 'The previous radio session did not stop in time.' }
    }
    Remove-Item -LiteralPath $stopFile -Force -ErrorAction SilentlyContinue
    $a=Start-RadioDeck A $MpvExecutable $MpvFolder $token; $decks+=,$a
    $b=Start-RadioDeck B $MpvExecutable $MpvFolder $token; $decks+=,$b
    Load-RadioTrack $a $Playlist
    $initial=Wait-RadioReady $a $decks
    $list=@(Invoke-Mpv $a.Client @('get_property','playlist'))
    $seen=@{}; $tracks=[Collections.Generic.List[string]]::new()
    foreach ($entry in $list) {
        $id=Get-TrackKey $entry.filename
        if ($id -and -not $seen.ContainsKey($id)) { $seen[$id]=$true; $tracks.Add($entry.filename) }
    }
    if (-not $tracks.Count) { throw 'The playlist has no playable entries.' }
    $recent=[Collections.Generic.List[string]]::new()
    $history=Join-Path $MpvFolder 'portable_config/recent-track-history.txt'
    if (Test-Path -LiteralPath $history) {
        foreach ($line in [IO.File]::ReadAllLines($history)) {
            $parts=$line.Split('|'); if ($parts.Count -ge 2) { $recent.Add($parts[1]) }
        }
    }
    $bag=[Collections.Generic.List[string]]::new()
    $first=Get-RadioChoice $tracks $bag $recent
    if ((Get-TrackKey $initial.path) -ne (Get-TrackKey $first)) {
        Load-RadioTrack $a $first
        $null=Wait-RadioReady $a $decks
    }
    $active=$a; $spare=$b; $volume=100.0; $paused=$false; $fading=$false; $fadeElapsed=0.0
    $null=Send-RadioCommand $active 'radio-activate'
    $recent.Add((Get-TrackKey $first))
    Set-DeckVolume $active $volume
    $null=Invoke-Mpv $active.Client @('set_property','pause',$false)
    $spare.LoadingSince=-1
    $requestedSkip=$false
    $lastTick=$clock.Elapsed.TotalSeconds; $lastSave=$lastTick; $lastStatus=-10; $progressPosition=0; $stallSince=0
    Write-Host 'Radio started. Space = pause/resume, N = next, +/- = volume, Q = stop.'
    Write-Host 'Check Radio.cmd queries both running players to verify the Lua script and settings.'
    while ($clock.Elapsed.TotalSeconds -lt $DurationSeconds -and -not (Test-Path -LiteralPath $stopFile)) {
        $now=$clock.Elapsed.TotalSeconds; $dt=[Math]::Min(0.5,$now-$lastTick); $lastTick=$now
        $current=Get-RadioStatus $active; $incoming=Get-RadioStatus $spare
        if (-not $current) { throw 'The active MPV lost its radio script.' }
        try {
            if ([Console]::KeyAvailable) {
                $keyPressed=[Console]::ReadKey($true)
                switch ($keyPressed.Key) {
                    'Q' { [IO.File]::WriteAllText($stopFile,'keyboard stop') }
                    'Spacebar' {
                        $paused=-not $paused
                        $null=Invoke-Mpv $active.Client @('set_property','pause',$paused)
                        if ($fading) { $null=Invoke-Mpv $spare.Client @('set_property','pause',$paused) }
                    }
                    'N' { $requestedSkip=$true }
                }
                if ($keyPressed.KeyChar -eq '+') { $volume=[Math]::Min(100,$volume+5) }
                if ($keyPressed.KeyChar -eq '-') { $volume=[Math]::Max(0,$volume-5) }
            }
        } catch [InvalidOperationException] { } # Scheduled/no-console session.
        if (-not $fading) { Set-DeckVolume $active $volume }
        if (-not $fading -and $spare.LoadingSince -lt 0 -and ($requestedSkip -or $current.eof -or $current.remaining -le 60)) {
            # Prepare near the handoff, using the latest heard sections and fresh URLs.
            $null=Send-RadioCommand $active 'radio-checkpoint'
            $next=Get-RadioChoice $tracks $bag $recent
            Load-RadioTrack $spare $next
            $spare.LoadingSince=$now
            $incoming=Get-RadioStatus $spare
        }
        $ready=$incoming -and $incoming.ready -and -not $incoming.seeking
        if (-not $ready -and $spare.LoadingSince -ge 0 -and $now-$spare.LoadingSince -gt 60) {
            $spare.Failures++
            if ($spare.Failures -ge [Math]::Max(3,$tracks.Count)) { throw 'No next track could be loaded after repeated attempts.' }
            Write-Warning 'Next track failed to load; trying another playlist entry.'
            $next=Get-RadioChoice $tracks $bag $recent
            Load-RadioTrack $spare $next
            $spare.LoadingSince=$now
        }
        $fadeSeconds=[double]$current.crossfade_seconds
        if (-not $fading -and $ready -and -not $paused -and ($requestedSkip -or $current.eof -or ($current.remaining -ge 0 -and $current.remaining -le $fadeSeconds))) {
            # Start the incoming decoder first. Outgoing gain stays up until it progresses.
            $null=Send-RadioCommand $spare 'radio-activate'
            $null=Invoke-Mpv $spare.Client @('set_property','pause',$false)
            $progressPosition=$incoming.position; $stallSince=$now
            $fading=$true; $fadeElapsed=0; $requestedSkip=$false
            $spare.Failures=0
            $recent.Add((Get-TrackKey $incoming.path))
            while ($recent.Count -gt 10) { $recent.RemoveAt(0) }
            Write-Host ('Crossfade: ' + $current.title + ' -> ' + $incoming.title)
        }
        if ($fading -and -not $paused) {
            # Query the playback clock directly; Lua status is intentionally sampled.
            $position=[double](Invoke-Mpv $spare.Client @('get_property','time-pos'))
            $speed=[double](Invoke-Mpv $spare.Client @('get_property','speed'))
            $progress=$position-$progressPosition
            if (-not $incoming.buffering -and -not $incoming.seeking -and $progress -gt 0 -and $speed -gt 0) {
                $fadeElapsed += [Math]::Min(0.5,$progress/$speed)
                $stallSince=$now
            }
            $progressPosition=$position
            # Finish a sample at its allowance even if the next source is slow.
            $fraction=1.0
            if ($fadeSeconds -gt 0) { $fraction=$fadeElapsed/$fadeSeconds }
            $gains=Get-FadeGains $fraction $volume
            Write-Verbose ("Fade {0}->{1}: remaining={2:N2}, progress={3:N2}, fraction={4:N2}, gains={5:N1}/{6:N1}" -f $active.Name,$spare.Name,$current.remaining,$fadeElapsed,$fraction,$gains[0],$gains[1])
            Set-DeckVolume $active $gains[0]; Set-DeckVolume $spare $gains[1]
            if ($now-$stallSince -gt 15) { throw 'The incoming track stalled during crossfade. Stopping so the scheduled retry can recover.' }
            if ($fraction -ge 1 -or ($current.remaining -ge 0 -and $current.remaining -le 0.05 -and $fadeElapsed -gt 0)) {
                Set-DeckVolume $active 0; Set-DeckVolume $spare $volume
                $null=Send-RadioCommand $active 'radio-finish'
                $null=Invoke-Mpv $active.Client @('stop')
                $null=Invoke-Mpv $active.Client @('set_property','pause',$true)
                $old=$active; $active=$spare; $spare=$old
                $fading=$false
                $spare.LoadingSince=-1
                $current=Get-RadioStatus $active
            }
        }
        # Never play beyond the sample limit while a failed/slow next item loads.
        if (-not $fading -and $current.sample_limit -gt 0 -and $current.remaining -le 0.05) {
            $null=Invoke-Mpv $active.Client @('set_property','pause',$true)
        }
        if ($now-$lastSave -ge $current.checkpoint_seconds) {
            foreach ($deck in $decks) { $null=Send-RadioCommand $deck 'radio-checkpoint' }
            $lastSave=$now
        }
        if ($now-$lastStatus -ge 1) {
            $snapshot=@{ controller_pid=$PID; token=$token; updated=(Get-Date).ToUniversalTime().ToString('o'); active=$active.Name;
                endpoints=@($a.Endpoint,$b.Endpoint); duration_seconds=$DurationSeconds; elapsed_seconds=$now; fading=$fading }
            $temporary=$sessionFile+'.tmp'
            [IO.File]::WriteAllText($temporary,($snapshot | ConvertTo-Json -Compress))
            Move-Item -LiteralPath $temporary -Destination $sessionFile -Force
            $lastStatus=$now
        }
        Start-Sleep -Milliseconds 100
    }
} catch [OperationCanceledException] {
    Write-Host $_.Exception.Message
} finally {
    # Only processes started by this controller are touched. Lua's 15-second
    # heartbeat watchdog also exits the decks if Task Scheduler kills this host.
    foreach ($deck in $decks) {
        try { $null=Send-RadioCommand $deck 'radio-finish' } catch { }
        try { $null=Invoke-Mpv $deck.Client @('quit') } catch { }
        Close-MpvConnection $deck.Client
        if (-not $deck.Process.WaitForExit(2000)) { $deck.Process.Kill() }
        $deck.Process.Dispose()
    }
    if ($owns) {
        Remove-Item -LiteralPath $sessionFile,$stopFile -Force -ErrorAction SilentlyContinue
        $mutex.ReleaseMutex()
    }
    $mutex.Dispose()
}
