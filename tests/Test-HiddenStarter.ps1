# Tests the compiled GUI starter and its real Windows PowerShell child, not playback.
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'payload\Radio.ps1') -FunctionsOnly
function Assert($condition, [string]$message) { if (-not $condition) { throw $message } }
$work = Join-Path ([IO.Path]::GetTempPath()) ('radio hidden test ' + [guid]::NewGuid().ToString('N'))
$processes = @()
try {
    New-Item -ItemType Directory -Path $work | Out-Null
    $starter = Join-Path $work 'Radio-Hidden.exe'
    & (Join-Path $root 'payload\Build-HiddenStarter.ps1') -OutputPath $starter
    Assert (Test-Path -LiteralPath $starter) 'Build did not produce the starter'
    $bytes = [IO.File]::ReadAllBytes($starter)
    $pe = [BitConverter]::ToInt32($bytes, 0x3c)
    Assert ([BitConverter]::ToUInt16($bytes, $pe + 92) -eq 2) 'Helper must be a GUI executable, not a console executable'
    $before = (Get-FileHash -LiteralPath $starter).Hash
    $rejected = $false
    try { & (Join-Path $root 'payload\Build-HiddenStarter.ps1') -OutputPath $starter } catch { $rejected = $true }
    Assert $rejected 'Build must not overwrite an existing helper without an explicit backup'
    Assert ((Get-FileHash -LiteralPath $starter).Hash -eq $before) 'Rejected rebuild changed the existing helper'

    $mock = @'
param([string]$Playlist, [double]$DurationSeconds, [string]$MpvFolder)
$ErrorActionPreference = 'Stop'
Add-Type -TypeDefinition 'using System; using System.Runtime.InteropServices; public static class ConsoleProbe { [DllImport("kernel32.dll")] public static extern IntPtr GetConsoleWindow(); }'
@{ pid=$PID; console=[ConsoleProbe]::GetConsoleWindow().ToInt64(); playlist=$Playlist; duration=$DurationSeconds; folder=$MpvFolder; working=[Environment]::CurrentDirectory } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $PSScriptRoot 'child.json') -Encoding UTF8
Start-Sleep -Milliseconds 900
if ($Playlist -eq 'FAIL') { [Console]::Error.WriteLine('Expected test failure'); exit 23 }
if ($Playlist -eq 'LOUDFAIL') {
    for ($i=0; $i -lt 200; $i++) { [Console]::Error.WriteLine(('x' * 1000)); [Console]::Out.WriteLine(('y' * 1000)) }
    exit 9
}
exit 0
'@
    [IO.File]::WriteAllText((Join-Path $work 'Radio.ps1'), $mock)
    foreach ($case in @(
        @{ Playlist='https://www.youtube.com/playlist?list=PL_TEST&si=value'; Folder='C:\folder with spaces\'; Code=0 },
        @{ Playlist='literal "quote" ; & | < > $(not-a-command)'; Folder='C:\quoted"part\'; Code=0 },
        @{ Playlist='FAIL'; Folder='C:\MPV'; Code=23 },
        @{ Playlist='LOUDFAIL'; Folder='C:\MPV'; Code=9 }
    )) {
        $arguments = Join-NativeArguments @('-Playlist', $case.Playlist, '-DurationSeconds', '7200', '-MpvFolder', $case.Folder)
        $clock = [Diagnostics.Stopwatch]::StartNew()
        $start = [Diagnostics.ProcessStartInfo]::new($starter, $arguments)
        $start.UseShellExecute = $false
        $process = [Diagnostics.Process]::Start($start)
        $processes += $process
        Assert ($process.WaitForExit(20000)) 'Hidden starter or child hung'
        # Parameterless WaitForExit also completes Process exit bookkeeping.
        $process.WaitForExit()
        Assert ($process.ExitCode -eq $case.Code) "Child exit code not preserved: expected $($case.Code), got $($process.ExitCode)"
        Assert ($clock.Elapsed.TotalMilliseconds -ge 800) 'Starter returned before PowerShell completed'
        $record = Get-Content -LiteralPath (Join-Path $work 'child.json') -Raw | ConvertFrom-Json
        Assert ($record.console -eq 0) 'PowerShell has a console: CREATE_NO_WINDOW was not applied'
        Assert ($record.playlist -ceq $case.Playlist) 'Playlist quoting or literal argument forwarding changed'
        Assert ($record.folder -ceq $case.Folder) 'Embedded quotes or trailing backslashes changed'
        Assert ($record.duration -eq 7200) 'Session duration changed'
        Assert ($record.working -eq $work) 'PowerShell working folder is not the helper folder'
        if ($case.Code -eq 23) {
            $log = Get-Content -LiteralPath (Join-Path $work 'Radio-Hidden-error.log') -Raw
            Assert ($log.Contains('Expected test failure') -and $log.Contains('23')) 'Hidden failure was not recorded'
        }
        if ($case.Code -eq 9) {
            Assert ((Get-Item -LiteralPath (Join-Path $work 'Radio-Hidden-error.log')).Length -lt 33000) 'Hidden diagnostics are not bounded'
        }
    }
    Move-Item -LiteralPath (Join-Path $work 'Radio.ps1') -Destination (Join-Path $work 'Radio.saved.ps1')
    $start = [Diagnostics.ProcessStartInfo]::new($starter)
    $start.UseShellExecute = $false
    $process = [Diagnostics.Process]::Start($start)
    $processes += $process
    Assert ($process.WaitForExit(10000)) 'Missing-script failure hung'
    $process.WaitForExit()
    Assert ($process.ExitCode -ne 0) 'Missing Radio.ps1 must fail, not report success'
    Assert ((Get-Content -LiteralPath (Join-Path $work 'Radio-Hidden-error.log') -Raw).Contains('Missing adjacent Radio.ps1')) 'Missing-script failure was not recorded'
    Write-Host 'PASS: GUI executable; PowerShell has no console; literal arguments; wait and exit-code forwarding; bounded error log; safe build replacement.'
} finally {
    foreach ($process in $processes) {
        if (-not $process.HasExited) { $process.Kill(); $process.WaitForExit() }
        $process.Dispose()
    }
    # Remove only this test's uniquely created temporary directory.
    if (Test-Path -LiteralPath $work) { Remove-Item -LiteralPath $work -Recurse -Force }
}
