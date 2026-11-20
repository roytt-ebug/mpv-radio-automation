# Offline fixtures by default. -Integration also downloads and exercises the
# three real pinned upstream Windows components in a temporary application folder.
param([switch]$Integration)
$ErrorActionPreference = 'Stop'
if ($env:OS -ne 'Windows_NT' -or $PSVersionTable.PSEdition -ne 'Desktop') { throw 'These tests require Windows PowerShell 5.1.' }
$repo = Split-Path -Parent $PSScriptRoot
$componentScript = Join-Path $repo 'app\Install-Components.ps1'
$componentLockPath = Join-Path $repo 'app\components.lock.json'
. $componentScript -FunctionsOnly
$script:componentChecks = 0
function Assert-Component($Condition, [string]$Label) {
    $script:componentChecks++
    if (-not $Condition) { throw "Component test failed: $Label" }
}
function Assert-ComponentRejected([scriptblock]$Action, [string]$Label) {
    $rejected = $false
    try { & $Action | Out-Null } catch { $rejected = $true }
    Assert-Component $rejected $Label
}
function Get-ComponentTestHash([string]$Path) { return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash }
function New-ComponentTestZip([string]$Path, [string]$EntryName, [string]$Source) {
    $zip = [IO.Compression.ZipFile]::Open($Path, [IO.Compression.ZipArchiveMode]::Create)
    try { [void][IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, $Source, $EntryName) }
    finally { $zip.Dispose() }
}

$work = Join-Path ([IO.Path]::GetTempPath()) ('automatic music components ' + [guid]::NewGuid().ToString('N'))
$originalDownload = (Get-Item Function:\Get-RadioComponentDownload).ScriptBlock
$originalMpvExpand = (Get-Item Function:\Expand-RadioMpvArchive).ScriptBlock
$savedProbe = $env:AUTOMATIC_MUSIC_TEST_PROBE
$savedMode = $env:AUTOMATIC_MUSIC_TEST_MODE
New-Item -ItemType Directory -Path $work | Out-Null
try {
    $manifest = Read-RadioComponentManifest $componentLockPath
    Assert-Component ($manifest.components.Count -eq 3) 'packaged lock contains all three official components'
    foreach ($unsafe in @('../escape.exe','/absolute.exe','C:\absolute.exe','dir/../../escape','dir:stream','CON.txt','dir/file.','dir/file ')) {
        Assert-ComponentRejected { Get-RadioComponentChildPath $work $unsafe } ('reject archive path ' + $unsafe)
    }
    Assert-Component ((Get-RadioComponentChildPath $work './doc/readme.txt') -eq (Join-Path $work 'doc\readme.txt')) 'safe archive subdirectory'
    $badManifest = Join-Path $work 'invalid-lock.json'
    $mutated = [IO.File]::ReadAllText($componentLockPath).Replace('https://github.com/yt-dlp/', 'https://example.com/yt-dlp/')
    [IO.File]::WriteAllText($badManifest, $mutated)
    Assert-ComponentRejected { Read-RadioComponentManifest $badManifest } 'reject off-source component URL'

    $script:componentFixtureExe = Join-Path $work 'fixture.exe'
    Add-Type -OutputAssembly $script:componentFixtureExe -OutputType ConsoleApplication -TypeDefinition @'
using System;
using System.IO;
using System.Threading;
public static class ComponentFixture {
    public static int Main(string[] args) {
        if (Environment.GetEnvironmentVariable("AUTOMATIC_MUSIC_TEST_MODE") == "hang") Thread.Sleep(10000);
        if (Environment.GetEnvironmentVariable("AUTOMATIC_MUSIC_TEST_MODE") == "fail") return 23;
        string probe = Environment.GetEnvironmentVariable("AUTOMATIC_MUSIC_TEST_PROBE");
        if (!String.IsNullOrEmpty(probe)) File.AppendAllText(probe, "probe\n");
        string name = Path.GetFileName(Environment.GetCommandLineArgs()[0]);
        if (name == "mpv.exe" || name == "mpv.com") Console.WriteLine("mpv v0.0.0-gbcde6b93cc");
        else if (name == "yt-dlp.exe") Console.WriteLine("2026.10.26");
        else if (name == "deno.exe") Console.WriteLine("deno 2.9.8");
        else Console.WriteLine("fixture");
        return 0;
    }
}
'@
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $script:componentProbe = Join-Path $work 'probes.txt'
    $env:AUTOMATIC_MUSIC_TEST_PROBE = $script:componentProbe
    $env:AUTOMATIC_MUSIC_TEST_MODE = ''
    $script:componentArchives = @{
        mpv=(Join-Path $work 'mpv-fixture.7z');
        ytDlp=$script:componentFixtureExe;
        deno=(Join-Path $work 'deno-fixture.zip')
    }
    # Only MPV extraction is replaced. Archive pin checks remain real; Deno ZIP
    # extraction, native version checks, hashing and atomic activation are real.
    [IO.File]::WriteAllBytes($script:componentArchives.mpv, [byte[]]((0..255) * 8))
    New-ComponentTestZip $script:componentArchives.deno 'deno.exe' $script:componentFixtureExe
    foreach ($component in $manifest.components) {
        $component.sha256 = (Get-ComponentTestHash $script:componentArchives[$component.id]).ToLowerInvariant()
        $component.size = (Get-Item -LiteralPath $script:componentArchives[$component.id]).Length
    }
    $fixtureLock = Join-Path $work 'fixture-lock.json'
    Write-RadioComponentJson $fixtureLock $manifest
    $script:componentDownloadCount = 0
    $script:componentDownloadMode = 'good'
    function Get-RadioComponentDownload($Component, [string]$Destination) {
        $script:componentDownloadCount++
        [IO.File]::Copy($script:componentArchives[$Component.id], $Destination, $false)
        if ($script:componentDownloadMode -eq 'corrupt' -and $Component.id -eq 'mpv') {
            $bytes = [IO.File]::ReadAllBytes($Destination)
            $bytes[0] = $bytes[0] -bxor 255
            [IO.File]::WriteAllBytes($Destination, $bytes)
        }
        if ($script:componentDownloadMode -eq 'network-failure') { throw 'simulated network failure' }
    }
    function Expand-RadioMpvArchive([string]$Archive, [string]$Destination) {
        [IO.File]::Copy($script:componentFixtureExe, (Join-Path $Destination 'mpv.exe'), $false)
        [IO.File]::Copy($script:componentFixtureExe, (Join-Path $Destination 'mpv.com'), $false)
        New-Item -ItemType Directory -Path (Join-Path $Destination 'doc') | Out-Null
        [IO.File]::WriteAllText((Join-Path $Destination 'doc\README.txt'), 'fixture documentation retained')
    }

    $data = Join-Path $work 'User data'
    $first = Install-RadioComponents -Root $data -LockPath $fixtureLock
    Assert-Component ($script:componentDownloadCount -eq 3) 'first install downloads each component once'
    Assert-Component ($first.bundle -ceq $manifest.bundle) 'pointer identifies verified bundle'
    Assert-Component (Test-Path -LiteralPath (Join-Path $first.directory 'mpv.com')) 'full MPV companion executable retained'
    Assert-Component (Test-Path -LiteralPath (Join-Path $first.directory 'doc\README.txt')) 'full MPV archive contents retained'
    $pointer = Join-Path $data 'components.json'
    $pointerHash = Get-ComponentTestHash $pointer
    $null = Install-RadioComponents -Root $data -LockPath $fixtureLock -OnlyCheck
    $second = Install-RadioComponents -Root $data -LockPath $fixtureLock
    Assert-Component ($second.directory -ceq $first.directory -and $script:componentDownloadCount -eq 3) 'healthy repeat install skips all downloads'
    Assert-Component ((Get-ComponentTestHash $pointer) -ceq $pointerHash) 'CheckOnly and healthy repeat leave pointer bytes intact'

    $probeCount = [IO.File]::ReadAllLines($script:componentProbe).Count
    $script:componentDownloadMode = 'corrupt'
    Assert-ComponentRejected { Install-RadioComponents -Root $data -LockPath $fixtureLock -ForceRepair } 'reject corrupt download during repair'
    Assert-Component ((Get-ComponentTestHash $pointer) -ceq $pointerHash) 'failed repair preserves active pointer'
    Assert-Component (Test-Path -LiteralPath $first.directory) 'failed repair preserves working bundle'
    Assert-Component ([IO.File]::ReadAllLines($script:componentProbe).Count -eq ($probeCount + 3)) 'unverified downloaded executables never run'
    Assert-Component (@(Get-ChildItem -LiteralPath $data -Directory -Filter 'component-staging-*').Count -eq 0) 'failed staging is cleaned'
    $script:componentDownloadMode = 'network-failure'
    Assert-ComponentRejected { Install-RadioComponents -Root $data -LockPath $fixtureLock -ForceRepair } 'failed download is reported'
    Assert-Component ((Get-ComponentTestHash $pointer) -ceq $pointerHash) 'network failure preserves active pointer'
    $script:componentDownloadMode = 'good'
    $repaired = Install-RadioComponents -Root $data -LockPath $fixtureLock -ForceRepair
    Assert-Component ($repaired.directory -cne $first.directory) 'repair activates a separate bundle directory'
    Assert-Component (Test-Path -LiteralPath $first.directory) 'repair retains old bundle for recovery'
    Assert-Component ((Get-ComponentTestHash (Join-Path $data 'components.previous.json')) -ceq $pointerHash) 'previous pointer retained exactly'
    $null = Install-RadioComponents -Root $data -LockPath $fixtureLock -OnlyCheck

    $extra = Join-Path $repaired.directory 'unexpected.dll'
    [IO.File]::WriteAllText($extra, 'unexpected')
    Assert-ComponentRejected { Install-RadioComponents -Root $data -LockPath $fixtureLock -OnlyCheck } 'reject unrecorded binary added to bundle'
    Remove-Item -LiteralPath $extra
    $receiptPath = Join-Path $repaired.directory 'bundle.json'
    $receiptBytes = [IO.File]::ReadAllBytes($receiptPath)
    $receipt = Read-RadioComponentJson $receiptPath
    $receipt.files[0].sha256 = '0' * 64
    Write-RadioComponentJson $receiptPath $receipt
    Assert-ComponentRejected { Install-RadioComponents -Root $data -LockPath $fixtureLock -OnlyCheck } 'reject mismatched receipt before executing components'
    [IO.File]::WriteAllBytes($receiptPath, $receiptBytes)
    $pointerBytes = [IO.File]::ReadAllBytes($pointer)
    $outside = Read-RadioComponentJson $pointer
    $outside.directory = $work
    Write-RadioComponentJson $pointer $outside
    Assert-ComponentRejected { Install-RadioComponents -Root $data -LockPath $fixtureLock -OnlyCheck } 'reject component pointer outside app-owned directory'
    [IO.File]::WriteAllBytes($pointer, $pointerBytes)

    $evilZip = Join-Path $work 'traversal.zip'
    $unpack = Join-Path $work 'safe-unpack'
    New-ComponentTestZip $evilZip '../escaped.exe' $script:componentFixtureExe
    Assert-ComponentRejected { Expand-RadioDenoArchive $evilZip $unpack } 'reject ZIP path traversal before extraction'
    Assert-Component (-not (Test-Path -LiteralPath (Join-Path $work 'escaped.exe'))) 'archive cannot write outside staging'
    Assert-Component (@(Get-ChildItem -LiteralPath $unpack -Recurse -File).Count -eq 0) 'rejected archive extracts no files'
    $env:AUTOMATIC_MUSIC_TEST_MODE = 'fail'
    Assert-ComponentRejected { Invoke-RadioComponentProcess $script:componentFixtureExe @('--version') $work 2 } 'native nonzero exit is reported'
    $env:AUTOMATIC_MUSIC_TEST_MODE = 'hang'
    $clock = [Diagnostics.Stopwatch]::StartNew()
    Assert-ComponentRejected { Invoke-RadioComponentProcess $script:componentFixtureExe @('--version') $work 1 } 'native process timeout is enforced'
    Assert-Component ($clock.Elapsed.TotalSeconds -lt 8) 'timed-out native process is bounded'
    $env:AUTOMATIC_MUSIC_TEST_MODE = ''
    Write-Host "PASS: $script:componentChecks component installation, integrity, repair and extraction checks with offline fixtures."
} finally {
    Set-Item Function:\Get-RadioComponentDownload $originalDownload
    Set-Item Function:\Expand-RadioMpvArchive $originalMpvExpand
    $env:AUTOMATIC_MUSIC_TEST_PROBE = $savedProbe
    $env:AUTOMATIC_MUSIC_TEST_MODE = $savedMode
    if (Test-Path -LiteralPath $work) { Remove-Item -LiteralPath $work -Recurse -Force }
}

if ($Integration) {
    $live = Join-Path ([IO.Path]::GetTempPath()) ('automatic music live components ' + [guid]::NewGuid().ToString('N'))
    try {
        $installed = Install-RadioComponents -Root $live -LockPath $componentLockPath
        Assert-Component (Test-Path -LiteralPath (Join-Path $installed.directory 'mpv.exe')) 'real MPV installed'
        Assert-Component (Test-Path -LiteralPath (Join-Path $installed.directory 'yt-dlp.exe')) 'real yt-dlp installed'
        Assert-Component (Test-Path -LiteralPath (Join-Path $installed.directory 'deno.exe')) 'real Deno installed'
        $before = Get-ComponentTestHash (Join-Path $live 'components.json')
        $same = Install-RadioComponents -Root $live -LockPath $componentLockPath
        $null = Install-RadioComponents -Root $live -LockPath $componentLockPath -OnlyCheck
        Assert-Component ($same.directory -ceq $installed.directory) 'real repeat install reuses verified bundle'
        Assert-Component ((Get-ComponentTestHash (Join-Path $live 'components.json')) -ceq $before) 'real CheckOnly preserves pointer'
        $receiptPath = Join-Path $installed.directory 'bundle.json'
        $savedReceipt = [IO.File]::ReadAllBytes($receiptPath)
        [IO.File]::WriteAllText($receiptPath, '{"schema":1}')
        Assert-ComponentRejected { Install-RadioComponents -Root $live -LockPath $componentLockPath -OnlyCheck } 'real incomplete receipt is rejected'
        [IO.File]::WriteAllBytes($receiptPath, $savedReceipt)
        $null = Install-RadioComponents -Root $live -LockPath $componentLockPath -OnlyCheck
        Write-Host ('PASS: real pinned Windows MPV + yt-dlp + Deno download, extraction, versions, receipt, repeat installation and CheckOnly; bundle ' + $installed.bundle)
    } finally {
        if (Test-Path -LiteralPath $live) { Remove-Item -LiteralPath $live -Recurse -Force }
    }
}
