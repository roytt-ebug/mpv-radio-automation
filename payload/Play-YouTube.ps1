# Keep clipboard text out of cmd.exe's command parser.
param([switch]$Video, [switch]$FunctionsOnly)
$ErrorActionPreference = 'Stop'
function ConvertTo-ClipboardYouTubeUrl([string]$Text) {
    $url = $Text.Trim()
    $uri = $null
    if ($url -match '[\s"<>|]' -or -not [uri]::TryCreate($url, [UriKind]::Absolute, [ref]$uri) -or
        $uri.Scheme -notin @('https','http') -or $uri.UserInfo -or -not $uri.IsDefaultPort -or
        $uri.DnsSafeHost -notin @('youtube.com','www.youtube.com','m.youtube.com','music.youtube.com','youtu.be')) {
        throw 'Copy one complete YouTube video or playlist URL, with no quotes or extra text.'
    }
    return $url
}
if ($FunctionsOnly) { return }
try {
    $url = ConvertTo-ClipboardYouTubeUrl (Get-Clipboard -Raw)
    $manualVideoRequested = [bool]$Video
    . (Join-Path $PSScriptRoot 'Radio.ps1') -FunctionsOnly
    $starter = Join-Path $PSScriptRoot 'Radio-Hidden.exe'
    if (-not (Test-Path -LiteralPath $starter -PathType Leaf)) {
        throw 'Radio-Hidden.exe is missing. Run setup again to restore the playback launcher.'
    }
    # Both manual and scheduled playback belong to the same supervisor. It stops
    # the previous owned player before starting this one, without touching other MPV windows.
    $arguments = @('-Manual', '-Playlist', $url)
    if ($manualVideoRequested) { $arguments += '-Video' }
    $start = [Diagnostics.ProcessStartInfo]::new()
    $start.FileName = $starter
    $start.WorkingDirectory = $PSScriptRoot
    $start.UseShellExecute = $false
    $start.CreateNoWindow = $true
    $start.Arguments = Join-NativeArguments $arguments
    $player = [Diagnostics.Process]::Start($start)
    $player.Dispose()
} catch {
    Write-Host $_.Exception.Message -ForegroundColor Red
    [void](Read-Host 'Press Enter to close')
    exit 1
}
