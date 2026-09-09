param([string]$MpvFolder=$PSScriptRoot)
$ErrorActionPreference='Stop'
$radioTargetFolder=$MpvFolder
. (Join-Path $PSScriptRoot 'Radio.ps1') -FunctionsOnly
$MpvFolder=$radioTargetFolder
try {
    $path=Join-Path $MpvFolder 'radio-session.json'
    if (-not (Test-Path -LiteralPath $path)) { throw 'No radio controller is running. Start a music task or Radio.ps1 first.' }
    $session=Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
    if (((Get-Date).ToUniversalTime()-[datetime]$session.updated).TotalSeconds -gt 10) { throw 'The controller status is stale. Restart the radio task.' }
    foreach ($endpoint in $session.endpoints) {
        $client=Open-MpvConnection $endpoint
        try {
            $raw=Invoke-Mpv $client @('get_property','user-data/radio-status')
            $status=$raw | ConvertFrom-Json
            $null=Send-RadioCommand ([pscustomobject]@{Client=$client}) 'radio-ping'
            Write-Host "`nPASS: MPV replied and random-start.lua acknowledged a command." -ForegroundColor Green
            $status | Select-Object version,managed,playing,title,audio_device,section_mode,min_duration_minutes,section_min_minutes,section_max_minutes,crossfade_seconds | Format-List
        } finally { Close-MpvConnection $client }
    }
} catch { Write-Error $_; exit 1 }
