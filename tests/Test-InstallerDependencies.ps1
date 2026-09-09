# Offline fixtures only: no downloads, task registration, or real installation.
$ErrorActionPreference = 'Stop'
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'Install.ps1') -FunctionsOnly
$script:checks = 0
function Assert-Equal($Actual, $Expected, [string]$Label) {
    $script:checks++
    if ([string]$Actual -cne [string]$Expected) { throw "$Label : expected '$Expected', got '$Actual'." }
}
function Assert-Rejected([scriptblock]$Action, [string]$Pattern, [string]$Label) {
    $message = ''
    try { & $Action | Out-Null } catch { $message = $_.Exception.Message }
    $script:checks++
    if (-not $message -or $message -notmatch $Pattern) { throw "$Label : expected error matching '$Pattern', got '$message'." }
}

foreach ($v in @('2.3.0','2.9.6','3.0.0')) {
    Assert-Equal (ConvertFrom-DenoVersion "deno $v (stable, release, x86_64-pc-windows-msvc)`r`nv8 13.0`r`ntypescript 5.0") $v "version $v"
}
foreach ($bad in @('','v22.0.0','deno 2.3','deno 2.3.0-rc.1','text deno 2.3.0','deno 2.3.0garbage')) {
    Assert-Rejected { ConvertFrom-DenoVersion $bad } 'unrecognized' "invalid version $bad"
}
Assert-Rejected { ConvertFrom-DenoVersion 'deno 2.2.9' } 'too old' 'old runtime'

$temporary = Join-Path ([IO.Path]::GetTempPath()) ('mpv-dependency-tests-' + [guid]::NewGuid().ToString('N'))
$mpvFolder = Join-Path $temporary 'MPV with spaces'
$pathFolder = Join-Path $temporary 'user runtime'
$downloadFolder = Join-Path $temporary 'download'
$script:destination = Join-Path $downloadFolder 'yt-dlp.exe'
$savedTls = [Net.ServicePointManager]::SecurityProtocol
New-Item -ItemType Directory -Path $mpvFolder,$pathFolder,$downloadFolder | Out-Null
try {
    # A real tiny native-process fixture exercises invocation, timeout, and
    # stdout/stderr handling under Windows PowerShell 5.1, not a mocked process.
    $fixture = Join-Path $pathFolder 'deno.exe'
    Add-Type -OutputAssembly $fixture -OutputType ConsoleApplication -TypeDefinition @'
using System;
using System.IO;
using System.Threading;
public class DenoFixture {
    public static int Main(string[] args) {
        if (args.Length != 1 || args[0] != "--version") return 91;
        string mode = File.ReadAllText(Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "mode.txt"));
        if (mode == "hang") Thread.Sleep(15000);
        if (mode == "stderr") Console.Error.Write(new string('x', 100000));
        Console.WriteLine(mode == "old" ? "deno 2.2.9" : "deno 2.3.0");
        return mode == "fail" ? 12 : 0;
    }
}
'@
    [IO.File]::WriteAllText((Join-Path $pathFolder 'mode.txt'), 'good')
    $result = Get-YouTubeRuntime $mpvFolder $pathFolder '.COM;.EXE;.BAT;.CMD'
    Assert-Equal $result.Path $fixture 'same-account PATH runtime'
    Assert-Equal $result.Version '2.3.0' 'actual version process'
    Assert-Rejected { Get-YouTubeRuntime $mpvFolder '' '.EXE' } 'No supported Deno' 'different account does not use administrator PATH'
    Assert-Rejected { Get-YouTubeRuntime $mpvFolder $downloadFolder '.EXE' } 'No supported Deno' 'missing runtime'
    Copy-Item -LiteralPath $fixture -Destination (Join-Path $mpvFolder 'deno.exe')
    $localMode = Join-Path $mpvFolder 'mode.txt'
    [IO.File]::WriteAllText($localMode, 'good')
    $result = Get-YouTubeRuntime $mpvFolder $pathFolder '.EXE'
    Assert-Equal $result.Path (Join-Path $mpvFolder 'deno.exe') 'portable runtime takes precedence'
    Assert-Equal (Get-YouTubeRuntime $mpvFolder '' '.EXE').Version '2.3.0' 'portable runtime works without user PATH'
    [IO.File]::WriteAllText($localMode, 'old')
    Assert-Rejected { Get-YouTubeRuntime $mpvFolder $pathFolder '.EXE' } 'too old' 'old portable runtime must not fall through to newer PATH'
    [IO.File]::WriteAllText($localMode, 'fail')
    Assert-Rejected { Get-YouTubeRuntime $mpvFolder $pathFolder '.EXE' } 'exit 12' 'version failure stops setup'
    [IO.File]::WriteAllText($localMode, 'stderr')
    Assert-Equal (Get-YouTubeRuntime $mpvFolder '' '.EXE').Version '2.3.0' 'stderr drained without deadlock'
    [IO.File]::WriteAllText($localMode, 'hang')
    Assert-Rejected { Get-DenoVersion (Join-Path $mpvFolder 'deno.exe') $mpvFolder 250 } 'timed out' 'runtime timeout'
    [IO.File]::WriteAllText((Join-Path $mpvFolder 'deno.cmd'), '@exit /b 0')
    Assert-Rejected { Get-YouTubeRuntime $mpvFolder $pathFolder '.CMD;.EXE' } 'command wrappers' 'respect executable shadowing'

    $script:bytes = [byte[]]((0..255) * 8)
    $sha = [Security.Cryptography.SHA256]::Create()
    try { $script:hash = ([BitConverter]::ToString($sha.ComputeHash($script:bytes))).Replace('-','').ToLowerInvariant() }
    finally { $sha.Dispose() }
    Assert-Equal (Get-YtDlpChecksum "$script:hash  yt-dlp.exe`n") $script:hash 'GNU text checksum'
    Assert-Equal (Get-YtDlpChecksum "$script:hash *yt-dlp.exe`r`n") $script:hash 'GNU binary checksum'
    foreach ($bad in @('',"$script:hash  yt-dlp_x86.exe","$script:hash  YT-DLP.EXE","$script:hash  ./yt-dlp.exe","$script:hash  yt-dlp.exe`n$script:hash  yt-dlp.exe")) {
        Assert-Rejected { Get-YtDlpChecksum $bad } 'exactly one' 'missing or ambiguous checksum entry'
    }
    Assert-Rejected { Get-YtDlpChecksum "not-a-hash  yt-dlp.exe" } 'malformed' 'malformed checksum'
    Assert-Rejected { Get-YtDlpChecksum "$script:hash  yt-dlp.exe`n<html>error</html>" } 'malformed' 'malformed extra line'

    # Stub only network boundaries; staging, SHA-256, acceptance and cleanup are real.
    function Invoke-RestMethod {
        param($Uri, $TimeoutSec)
        [void]$script:requests.Add([string]$Uri)
        Assert-Equal $Uri 'https://api.github.com/repos/yt-dlp/yt-dlp/releases/latest' 'official metadata endpoint'
        if ($script:mode -eq 'api-failure') { throw 'fixture API failure' }
        $tag = '2026.09.01'
        if ($script:mode -eq 'invalid-tag') { $tag = '../escape' }
        return [pscustomobject]@{ tag_name=$tag; draft=$false; prerelease=($script:mode -eq 'prerelease') }
    }
    function Invoke-WebRequest {
        param([switch]$UseBasicParsing, $Uri, $OutFile, $TimeoutSec)
        [void]$script:requests.Add([string]$Uri)
        $prefix = 'https://github.com/yt-dlp/yt-dlp/releases/download/2026.09.01/'
        if ($Uri -eq ($prefix + 'SHA2-256SUMS')) {
            if ($script:mode -eq 'manifest-failure') { throw 'fixture checksum network failure' }
            $text = "$script:hash  yt-dlp.exe`n"
            switch ($script:mode) {
                'mismatch' { $text = ('0' * 64) + "  yt-dlp.exe`n" }
                'missing' { $text = "$script:hash  yt-dlp_x86.exe`n" }
                'duplicate' { $text += $text }
                'malformed' { $text = 'broken checksum' }
                'uppercase' { $text = $script:hash.ToUpperInvariant() + " *yt-dlp.exe`r`n" }
                'oversize-manifest' { $text = 'x' * (1MB + 1) }
            }
            [IO.File]::WriteAllText($OutFile, $text)
        } elseif ($Uri -eq ($prefix + 'yt-dlp.exe')) {
            if ($script:mode -eq 'partial-download') {
                [IO.File]::WriteAllText($OutFile, 'partial')
                throw 'fixture executable network failure'
            }
            if ($script:mode -eq 'tiny') { [IO.File]::WriteAllText($OutFile, 'tiny') }
            else { [IO.File]::WriteAllBytes($OutFile, $script:bytes) }
            if ($script:mode -eq 'race') { [IO.File]::WriteAllText($script:destination, 'preserve competing file') }
        } else { throw "Unexpected URL: $Uri" }
    }
    foreach ($mode in @('good','uppercase','mismatch','missing','duplicate','malformed','oversize-manifest','api-failure','invalid-tag','prerelease','manifest-failure','partial-download','tiny','race')) {
        $script:mode = $mode
        $script:requests = New-Object 'System.Collections.Generic.List[string]'
        $failure = ''
        try { Install-VerifiedYtDlp $downloadFolder } catch { $failure = $_.Exception.Message }
        if ($mode -in @('good','uppercase')) {
            Assert-Equal $failure '' "download succeeds: $mode"
            Assert-Equal (Get-FileHash -LiteralPath $script:destination -Algorithm SHA256).Hash.ToLowerInvariant() $script:hash 'installed verified bytes'
            Assert-Equal $script:requests.Count 3 'one release lookup, manifest, executable'
            # A second invocation must neither download nor change an existing executable.
            $before = $script:requests.Count
            Install-VerifiedYtDlp $downloadFolder
            Assert-Equal $script:requests.Count $before 'existing executable left alone'
        } else {
            Assert-Equal ([bool]$failure) $true "reject $mode"
            $patterns = @{
                mismatch='checksum mismatch'; missing='exactly one'; duplicate='exactly one'
                malformed='malformed'; 'oversize-manifest'='unexpectedly large'
                'api-failure'='fixture API failure'; 'invalid-tag'='valid stable release'
                prerelease='valid stable release'; 'manifest-failure'='checksum network failure'
                'partial-download'='executable network failure'; tiny='unexpectedly small'
            }
            if ($patterns.ContainsKey($mode)) { Assert-Equal ($failure -match $patterns[$mode]) $true "correct failure: $mode" }
            if ($mode -in @('missing','duplicate','malformed','oversize-manifest','manifest-failure')) {
                Assert-Equal $script:requests.Count 2 'invalid checksum stops before executable download'
            }
            if ($mode -eq 'race') {
                Assert-Equal ([IO.File]::ReadAllText($script:destination)) 'preserve competing file' 'no overwrite race'
            } else { Assert-Equal (Test-Path -LiteralPath $script:destination) $false "not installed: $mode" }
        }
        Assert-Equal @(Get-ChildItem -LiteralPath $downloadFolder -Directory).Count 0 "staging cleaned: $mode"
        if (Test-Path -LiteralPath $script:destination) { Remove-Item -LiteralPath $script:destination }
    }

    # These tests do not run the interactive installer; guard preflight order
    # and account handling so no player is stopped before dependency validation.
    $source = [IO.File]::ReadAllText((Join-Path (Split-Path -Parent $PSScriptRoot) 'Install.ps1'))
    Assert-Equal ($source.IndexOf('$youtubeRuntime = Get-YouTubeRuntime') -lt $source.IndexOf("`$stage = 'stopping this installation radio")) $true 'preflight before mutations'
    Assert-Equal ($source -match '\$identity.User.Value -ne \$TaskUserSid') $true 'different UAC user guarded'
    Assert-Equal ($source -match "\`$runtimeSearchPath = ''") $true 'different UAC user excludes administrator PATH'
    Write-Host "Passed $script:checks dependency and checksum checks. No real downloads or tasks." -ForegroundColor Green
} finally {
    [Net.ServicePointManager]::SecurityProtocol = $savedTls
    Remove-Item Function:\Invoke-RestMethod,Function:\Invoke-WebRequest -ErrorAction SilentlyContinue
    # Delete only this test's explicitly created temporary fixture directory.
    if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Recurse -Force }
}
