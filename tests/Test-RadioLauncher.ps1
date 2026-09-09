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
Write-Host 'PASS: PowerShell syntax, native argument quoting, scoped installation IDs, and clipboard URL validation.'
