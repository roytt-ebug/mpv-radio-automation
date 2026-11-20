$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Get-ChildItem $root -Filter '*.ps1' -Recurse | ForEach-Object {
    $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($_.FullName,[ref]$null,[ref]$errors)
    if ($errors.Count) { throw ($errors | Out-String) }
}
. (Join-Path $root 'payload/Radio.ps1') -FunctionsOnly
. (Join-Path $root 'payload/Play-YouTube.ps1') -FunctionsOnly
function Assert($Condition,$Message) { if (-not $Condition) { throw $Message } }
Assert ((Join-NativeArguments @('C:\MPV Folder\Radio.ps1','abc"def','C:\trailing\')) -eq '"C:\MPV Folder\Radio.ps1" "abc\"def" "C:\trailing\\"') 'Native argument escaping'
Assert ((Get-RadioKey 'C:\MPV') -ne (Get-RadioKey 'C:\Other')) 'Separate installations must have separate locks/pipes'
if ($env:OS -eq 'Windows_NT') {
    Assert ((Get-RadioKey 'C:\MPV\') -eq (Get-RadioKey 'c:\mpv')) 'Same installation must reuse lock/pipe'
}
foreach ($url in @('https://youtube.com/watch?v=abc&list=PL123','https://youtu.be/abc?t=30','https://www.youtube.com/playlist?list=PL123')) {
    Assert ((ConvertTo-ClipboardYouTubeUrl $url) -eq $url) 'Valid clipboard URL changed'
}
foreach ($url in @('', 'file:///C:/test', 'https://youtube.com.evil.test/watch?v=x', 'https://evil.test@youtube.com/watch?v=x', 'https://youtube.com:1234/watch?v=x', 'https://youtube.com/" & calc & "', "https://youtube.com/watch?v=x`nhttps://youtu.be/y")) {
    $rejected = $false
    try { $null = ConvertTo-ClipboardYouTubeUrl $url } catch { $rejected = $true }
    Assert $rejected ('Unsafe clipboard input accepted: ' + $url)
}
if ($env:OS -eq 'Windows_NT') {
    # Exercise the real clipboard-launch script through a native child boundary.
    # The fixture captures arguments instead of accessing YouTube or playing audio.
    $manualWork = Join-Path ([IO.Path]::GetTempPath()) ('radio clipboard test ' + [guid]::NewGuid().ToString('N'))
    try {
        New-Item -ItemType Directory -Path $manualWork | Out-Null
        Copy-Item -LiteralPath (Join-Path $root 'payload\Radio.ps1') -Destination $manualWork
        Copy-Item -LiteralPath (Join-Path $root 'payload\Play-YouTube.ps1') -Destination $manualWork
        $fixture = @'
using System;
using System.Diagnostics;
using System.IO;
public static class ManualLauncherFixture {
    public static int Main(string[] args) {
        string path = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "manual-arguments.txt");
        File.WriteAllText(path + ".pid", Process.GetCurrentProcess().Id.ToString());
        File.WriteAllLines(path + ".tmp", args);
        File.Move(path + ".tmp", path);
        return 0;
    }
}
'@
        Add-Type -TypeDefinition $fixture -OutputAssembly (Join-Path $manualWork 'Radio-Hidden.exe') -OutputType WindowsApplication
        $script:manualTestUrl = 'https://www.youtube.com/watch?v=abc&list=PL123&si=literal_value'
        function Get-Clipboard { param([switch]$Raw) return 'https://www.youtube.com/watch?v=abc&list=PL123&si=literal_value' }
        foreach ($manualVideo in @($false, $true)) {
            $capture = Join-Path $manualWork 'manual-arguments.txt'
            Remove-Item -LiteralPath $capture -ErrorAction SilentlyContinue
            & (Join-Path $manualWork 'Play-YouTube.ps1') -Video:$manualVideo
            Assert $? 'Clipboard launcher failed'
            $clock = [Diagnostics.Stopwatch]::StartNew()
            while (-not (Test-Path -LiteralPath $capture) -and $clock.Elapsed.TotalSeconds -lt 5) {
                Start-Sleep -Milliseconds 50
            }
            Assert (Test-Path -LiteralPath $capture) 'Clipboard launcher did not reach its owned supervisor'
            $fixtureProcess = Get-Process -Id ([int][IO.File]::ReadAllText($capture + '.pid')) -ErrorAction SilentlyContinue
            if ($fixtureProcess) {
                try { Assert ($fixtureProcess.WaitForExit(5000)) 'Clipboard capture fixture did not finish' }
                finally { $fixtureProcess.Dispose() }
            }
            $received = [IO.File]::ReadAllLines($capture)
            Assert ($received[0] -eq '-Manual' -and $received[1] -eq '-Playlist') 'Manual playback must use the supervisor'
            Assert ($received[2] -ceq $script:manualTestUrl) 'Clipboard URL changed across the native argument boundary'
            Assert (($received -contains '-Video') -eq $manualVideo) 'Manual video mode was lost or unexpectedly enabled'
            Assert ($received -notcontains '-DurationSeconds') 'Manual shortcut must not impose a new session limit'
        }
    } finally {
        Remove-Item Function:\Get-Clipboard -ErrorAction SilentlyContinue
        if (Test-Path -LiteralPath $manualWork) { Remove-Item -LiteralPath $manualWork -Recurse -Force }
    }
}
Write-Host 'PASS: PowerShell syntax, native argument quoting, scoped installation IDs, clipboard URL validation, and owned manual audio/video launch.'
