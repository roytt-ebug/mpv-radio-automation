$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
foreach ($path in @('payload/Radio.ps1','payload/Check-Radio.ps1','Install.ps1')) {
    $errors=$null
    [void][System.Management.Automation.Language.Parser]::ParseFile((Join-Path $root $path),[ref]$null,[ref]$errors)
    if ($errors.Count) { throw ($errors | Out-String) }
}
. (Join-Path $root 'payload/Radio.ps1') -FunctionsOnly
function Assert($Condition,$Message) { if (-not $Condition) { throw $Message } }
Assert ((Get-TrackKey 'https://youtu.be/abcdefghi01') -eq (Get-TrackKey 'https://www.youtube.com/watch?v=abcdefghi01&list=x')) 'YouTube aliases must match'
foreach ($count in @(1,2,4,20)) {
    $tracks=[Collections.Generic.List[string]]::new()
    for ($i=0;$i -lt $count;$i++) { $tracks.Add("https://www.youtube.com/watch?v=test$i") }
    $bag=[Collections.Generic.List[string]]::new(); $recent=[Collections.Generic.List[string]]::new()
    $pass=@{}; $previous=''
    for ($i=0;$i -lt 1000;$i++) {
        $next=Get-RadioChoice $tracks $bag $recent
        Assert ($tracks.Contains($next)) 'Unknown track selected'
        if ($count -gt 1) { Assert ($next -ne $previous) 'Immediate repeat across a shuffle boundary' }
        Assert (-not $pass.ContainsKey($next)) 'Repeated inside one shuffled pass'
        $pass[$next]=$true
        if ($pass.Count -eq $count) { $pass=@{} }
        $recent.Add((Get-TrackKey $next)); while ($recent.Count -gt 10) { $recent.RemoveAt(0) }
        $previous=$next
    }
}
$quarter=Get-FadeGains 0.25 80
Assert ([math]::Abs($quarter[0]-60) -lt 0.001 -and [math]::Abs($quarter[1]-20) -lt 0.001) 'Quarter fade must produce intermediate gains, not an integer step'
$half=Get-FadeGains 0.5 80
Assert ($half[0] -eq 40 -and $half[1] -eq 40) 'Midpoint must overlap at half gain'
foreach ($p in @(-1,0,0.25,0.5,0.75,1,2)) {
    $gains=Get-FadeGains $p 80
    Assert ([math]::Abs($gains[0]+$gains[1]-80) -lt 0.001) 'Crossfade combined gain exceeded master volume'
    Assert ($gains[0] -ge 0 -and $gains[1] -ge 0) 'Negative fade gain'
}
Assert ((Join-NativeArguments @('C:\MPV Folder\Radio.ps1','abc"def','C:\trailing\')) -eq '"C:\MPV Folder\Radio.ps1" "abc\"def" "C:\trailing\\"') 'Native argument escaping'
Write-Host 'PASS: controller syntax, 4,000 queue selections, fade envelopes, and argument quoting.'
