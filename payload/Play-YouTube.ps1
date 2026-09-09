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
    & (Join-Path $PSScriptRoot 'Radio.ps1') -Stop
    if (-not $?) { throw 'Radio could not stop. Close its window before starting manual playback.' }
    . (Join-Path $PSScriptRoot 'Radio.ps1') -FunctionsOnly
    $arguments = @('--load-scripts=no', "--config-dir=$PSScriptRoot\portable_config")
    if ($Video) { $arguments += @('--vid=auto','--ontop','--autofit=50%','--ytdl-format=bestvideo[height<=720]+bestaudio/best[height<=720]') }
    else { $arguments += '--vid=no' }
    $start = [Diagnostics.ProcessStartInfo]::new()
    $start.FileName = Join-Path $PSScriptRoot 'mpv.exe'
    $start.WorkingDirectory = $PSScriptRoot
    $start.UseShellExecute = $false
    $start.Arguments = Join-NativeArguments ($arguments + @('--', $url))
    $player = [Diagnostics.Process]::Start($start)
    $player.Dispose()
} catch {
    Write-Host $_.Exception.Message -ForegroundColor Red
    [void](Read-Host 'Press Enter to close')
    exit 1
}
