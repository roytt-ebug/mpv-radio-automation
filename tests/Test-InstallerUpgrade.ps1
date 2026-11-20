# Real temporary files: verify reconfiguration preserves listener preferences.
# No installation, downloads, tasks, UAC, or playback.
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'Install.ps1') -FunctionsOnly
$script:checks = 0
function Assert-UpgradeEqual($Actual, $Expected, [string]$Label) {
    $script:checks++
    if ([string]$Actual -cne [string]$Expected) { throw "$Label : expected '$Expected', got '$Actual'." }
}
function Assert-UpgradeRejected([scriptblock]$Action, [string]$Label) {
    $failed = $false
    try { & $Action | Out-Null } catch { $failed = $true }
    Assert-UpgradeEqual $failed $true $Label
}
function Get-UpgradeBytes([string]$Path) { return [Convert]::ToBase64String([IO.File]::ReadAllBytes($Path)) }

$work = Join-Path ([IO.Path]::GetTempPath()) ('radio upgrade ' + [guid]::NewGuid().ToString('N'))
$utf8 = New-Object Text.UTF8Encoding($false)
$device = 'wasapi/{11111111-2222-3333-4444-555555555555}'
New-Item -ItemType Directory -Path $work | Out-Null
try {
    $config = Join-Path $work 'mpv.conf'
    Update-RadioMpvConfig $config $device
    $expected = (@("audio-device=$device", 'vid=no', 'ytdl-format=bestaudio/best', 'force-window=yes') -join [Environment]::NewLine) + [Environment]::NewLine
    Assert-UpgradeEqual ([IO.File]::ReadAllText($config)) $expected 'fresh install retains all four defaults'
    $bytes = [IO.File]::ReadAllBytes($config)
    Assert-UpgradeEqual $bytes[0] 97 'fresh config is UTF-8 without a BOM'

    # Whitespace, comments, custom volume/format, duplicate global definitions,
    # Unicode, and named profiles survive; [default] returns to global scope.
    $label = 'Caf' + [char]0x00e9
    $before = "# $label speaker`r`nvolume=37`r`naudio-device=auto  # first output`r`nytdl-format=bestaudio`r`n  audio-device = 'old#device' `r`n[headphones] # keep this profile`r`naudio-device=wasapi/profile`r`nvolume=22`r`n[default]`r`naudio-device=%7%old#dev # final output`r`ncache=yes"
    $after = "# $label speaker`r`nvolume=37`r`naudio-device=$device  # first output`r`nytdl-format=bestaudio`r`n  audio-device = $device `r`n[headphones] # keep this profile`r`naudio-device=wasapi/profile`r`nvolume=22`r`n[default]`r`naudio-device=$device # final output`r`ncache=yes"
    [IO.File]::WriteAllBytes($config, [byte[]](@(239,187,191) + $utf8.GetBytes($before)))
    Update-RadioMpvConfig $config $device
    Assert-UpgradeEqual (Get-UpgradeBytes $config) ([Convert]::ToBase64String([byte[]](@(239,187,191) + $utf8.GetBytes($after)))) 'upgrade preserves unrelated bytes, BOM, CRLF, comments and profiles'
    $unchanged = Get-UpgradeBytes $config
    $stamp = [datetime]::SpecifyKind([datetime]'2020-01-02T03:04:05', [DateTimeKind]::Utc)
    [IO.File]::SetLastWriteTimeUtc($config, $stamp)
    Update-RadioMpvConfig $config $device
    Assert-UpgradeEqual (Get-UpgradeBytes $config) $unchanged 'repeated identical setup is byte-idempotent'
    Assert-UpgradeEqual ([IO.File]::GetLastWriteTimeUtc($config).Ticks) $stamp.Ticks 'identical settings do not rewrite the file'

    $profileOnly = "# device lives only in a custom profile`n[headphones]`naudio-device=wasapi/profile`nvolume=22"
    [IO.File]::WriteAllText($config, $profileOnly, $utf8)
    Update-RadioMpvConfig $config $device
    Assert-UpgradeEqual ([IO.File]::ReadAllText($config)) ("audio-device=$device`n" + $profileOnly) 'missing global device is inserted outside profiles and LF preserved'
    $unchanged = Get-UpgradeBytes $config
    Update-RadioMpvConfig $config $device
    Assert-UpgradeEqual (Get-UpgradeBytes $config) $unchanged 'profile-only insertion is idempotent'

    [IO.File]::WriteAllText($config, "--audio-device=auto # mpv also accepts the leading dashes`nvolume=22", $utf8)
    Update-RadioMpvConfig $config $device
    Assert-UpgradeEqual ([IO.File]::ReadAllText($config)) ("--audio-device=$device # mpv also accepts the leading dashes`nvolume=22") 'legacy leading dashes do not override the newly selected speaker'

    $quoted = "audio-device=`"old#speaker`" # keep me`nvolume=44`n"
    [IO.File]::WriteAllText($config, $quoted, $utf8)
    $unusualDevice = 'wasapi/speaker#' + [char]0x00e9
    $unusualValue = '%' + $utf8.GetByteCount($unusualDevice) + '%' + $unusualDevice
    Update-RadioMpvConfig $config $unusualDevice
    Assert-UpgradeEqual ([IO.File]::ReadAllText($config)) ("audio-device=$unusualValue # keep me`nvolume=44`n") 'quoted hash and UTF-8 device IDs retain comments safely'
    Update-RadioMpvConfig $config $device
    Assert-UpgradeEqual ([IO.File]::ReadAllText($config)) ("audio-device=$device # keep me`nvolume=44`n") 'fixed-length UTF-8 device value can be updated again'
    $unchanged = Get-UpgradeBytes $config
    Assert-UpgradeRejected { Update-RadioMpvConfig $config "auto`nvolume=0" } 'reject injected config line'
    Assert-UpgradeEqual (Get-UpgradeBytes $config) $unchanged 'rejected device leaves original file intact'

    [IO.File]::WriteAllBytes($config, [byte[]]@(255,254,97,0))
    $unchanged = Get-UpgradeBytes $config
    Assert-UpgradeRejected { Update-RadioMpvConfig $config $device } 'reject incompatible encoding instead of destroying settings'
    Assert-UpgradeEqual (Get-UpgradeBytes $config) $unchanged 'unsupported encoding remains byte-exact'
    foreach ($invalid in @('audio-device="unclosed', 'audio-device=%99%short', 'audio-device="auto" unexpected')) {
        [IO.File]::WriteAllText($config, $invalid, $utf8)
        $unchanged = Get-UpgradeBytes $config
        Assert-UpgradeRejected { Update-RadioMpvConfig $config $device } 'reject malformed current audio value'
        Assert-UpgradeEqual (Get-UpgradeBytes $config) $unchanged 'malformed current audio value remains unchanged'
    }

    $source = Join-Path $root 'payload\portable_config\script-opts\random-start.conf'
    $sampling = Join-Path $work 'script-opts\random-start.conf'
    Initialize-RadioSamplingConfig $source $sampling
    Assert-UpgradeEqual (Get-UpgradeBytes $sampling) (Get-UpgradeBytes $source) 'fresh sampling config copies shipped defaults exactly'
    $custom = "# $label custom settings`r`nsection_mode=no`r`nmin_duration_minutes=25`r`nsection_min_minutes=4`r`nsection_max_minutes=8`r`nfade_seconds=0"
    [IO.File]::WriteAllBytes($sampling, [byte[]](@(239,187,191) + $utf8.GetBytes($custom)))
    $unchanged = Get-UpgradeBytes $sampling
    Initialize-RadioSamplingConfig $source $sampling
    Initialize-RadioSamplingConfig $source $sampling
    Assert-UpgradeEqual (Get-UpgradeBytes $sampling) $unchanged 'repeated setup keeps customized sampling byte-for-byte'
    Assert-UpgradeEqual @(Get-ChildItem -LiteralPath $work -Filter '*.setup-*').Count 0 'no config staging files remain'
    Write-Host "PASS: $script:checks installer-upgrade checks; settings, profiles and sampling preferences preserved."
} finally {
    Remove-Item -LiteralPath $work -Recurse -Force
}
