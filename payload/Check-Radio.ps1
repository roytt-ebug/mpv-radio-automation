param([string]$MpvFolder='')
$ErrorActionPreference = 'Stop'
# Resolve script location after parameter binding (also on Windows PowerShell 5.1).
if (-not $MpvFolder) { $MpvFolder = $PSScriptRoot }
. (Join-Path $PSScriptRoot 'Radio.ps1') -MpvFolder $MpvFolder -FunctionsOnly
try {
    $endpoint = 'mpv-radio-' + (Get-RadioKey $MpvFolder)
    $before = (Invoke-RadioCommand $endpoint @('get_property','user-data/radio-status')) | ConvertFrom-Json
    $null = Invoke-RadioCommand $endpoint @('script-message','radio-ping')
    $clock = [Diagnostics.Stopwatch]::StartNew()
    do {
        $status = (Invoke-RadioCommand $endpoint @('get_property','user-data/radio-status')) | ConvertFrom-Json
        if ($status.sequence -gt $before.sequence) { break }
        Start-Sleep -Milliseconds 50
    } while ($clock.Elapsed.TotalSeconds -lt 3)
    if ($status.sequence -le $before.sequence) { throw 'random-start.lua did not acknowledge the check.' }
    Write-Host 'PASS: the running MPV replied and random-start.lua acknowledged a command.' -ForegroundColor Green
    $status | Format-List
} catch {
    Write-Host ('Check failed: ' + $_.Exception.Message) -ForegroundColor Red
    Write-Host 'Start a radio task first. For a directly opened MPV window, press F8 to check the script.'
    exit 1
}
