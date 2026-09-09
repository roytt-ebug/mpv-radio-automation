# No MPV, audio output, external downloads or persistent task registration required.
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$installer = Join-Path $root 'Install.ps1'
$tokens = $null; $parseErrors = $null
[void][System.Management.Automation.Language.Parser]::ParseFile($installer, [ref]$tokens, [ref]$parseErrors)
if ($parseErrors.Count) { throw ($parseErrors | Out-String) }
. $installer -FunctionsOnly
$script:checks = 0
function Assert-Equal($Actual, $Expected, [string]$Label) {
    $script:checks++
    if ([string]$Actual -cne [string]$Expected) { throw "$Label : expected '$Expected', got '$Actual'." }
}
function Assert-Rejected([scriptblock]$Action, [string]$Label) {
    $rejected = $false
    try { & $Action | Out-Null } catch { $rejected = $true }
    Assert-Equal $rejected $true $Label
}
# All minutes of the day: both compact and colon formats, independent of locale.
$savedCulture = [threading.thread]::CurrentThread.CurrentCulture
try {
    foreach ($culture in @('en-US','en-GB','de-DE')) {
        [threading.thread]::CurrentThread.CurrentCulture = [cultureinfo]::GetCultureInfo($culture)
        for ($h=0; $h -lt 24; $h++) {
            for ($m=0; $m -lt 60; $m++) {
                $expected = $h * 60 + $m
                foreach ($inputValue in @(('{0:00}:{1:00}' -f $h,$m), ('{0:00}{1:00}' -f $h,$m))) {
                    Assert-Equal (ConvertTo-ClockTime $inputValue).TimeOfDay.TotalMinutes $expected "clock $culture $inputValue"
                }
            }
        }
    }
} finally { [threading.thread]::CurrentThread.CurrentCulture = $savedCulture }
foreach ($case in @(
    @('1835','18:35'), @('6:35 PM','18:35'), @('6:35pm','18:35'),
    @('6:45 AM','06:45'), @('645','06:45'), @('12 AM','00:00'),
    @('12 PM','12:00'), @(' 7:00 am ','07:00')
)) { Assert-Equal (ConvertTo-ClockTime $case[0]).ToString('HH:mm') $case[1] ('clock ' + $case[0]) }
foreach ($bad in @('','7','2400','1860','6:5 PM','00:30 PM','13:35 AM','18.35','3 hours','tomorrow')) {
    Assert-Rejected { ConvertTo-ClockTime $bad } ('bad time ' + $bad)
}
Assert-Equal ((ConvertTo-MusicDays '1') -join ',') 'Monday,Tuesday,Wednesday,Thursday,Friday' 'weekday preset'
Assert-Equal ((ConvertTo-MusicDays '2') -join ',') 'Monday,Tuesday,Wednesday,Thursday,Friday,Saturday' 'Mon-Sat preset'
Assert-Equal @(ConvertTo-MusicDays '3').Count 7 'all days'
Assert-Equal ((ConvertTo-MusicDays '4') -join ',') 'Saturday,Sunday' 'weekends'
Assert-Equal ((ConvertTo-MusicDays 'mon, WED,friday,MON') -join ',') 'Monday,Wednesday,Friday' 'custom deduplicated days'
Assert-Equal ((ConvertTo-MusicDays 'MON-FRI') -join ',') 'Monday,Tuesday,Wednesday,Thursday,Friday' 'named preset'
foreach ($bad in @('','5','MON-FUN','1,2','FUNDAY')) { Assert-Rejected { ConvertTo-MusicDays $bad } ('bad days ' + $bad) }
foreach ($case in @(@('3',180),@('1.5',90),@('1:30',90),@('45 min',45),@('0.5',30),@('24 hours',1440),@('1m',1))) {
    Assert-Equal (ConvertTo-MusicRuntime $case[0]).TotalMinutes $case[1] ('runtime ' + $case[0])
}
foreach ($bad in @('','0','-2','25','1:90','1,5','6:35 PM','999999999999999999999999 hours')) {
    Assert-Rejected { ConvertTo-MusicRuntime $bad } ('bad runtime ' + $bad)
}
Assert-Equal (ConvertTo-YouTubePlaylist '') '' 'blank skips playlist'
foreach ($url in @(
    'https://youtube.com/playlist?list=PL_TEST-ID&si=EXAMPLE',
    'https://www.youtube.com/watch?v=TEST_VIDEO&list=PL_TEST-ID&t=300s',
    '"https://music.youtube.com/playlist?list=PL_TEST-ID"'
)) { Assert-Equal (ConvertTo-YouTubePlaylist $url) 'https://www.youtube.com/playlist?list=PL_TEST-ID' 'playlist normalization' }
foreach ($bad in @('not a url','https://youtube.com/watch?v=TEST','https://youtube.com.evil.test/playlist?list=x','file:///C:/test','https://user@youtube.com/playlist?list=x','https://youtube.com/playlist?list=x" --evil','https://youtube.com:444/playlist?list=x')) {
    Assert-Rejected { ConvertTo-YouTubePlaylist $bad } ('bad URL ' + $bad)
}
# Approved samples must select the right playlist, not silently change Enter=skip.
$morningSample = 'https://www.youtube.com/playlist?list=PLZAsCc2NQgn0'
$finisherSample = 'https://www.youtube.com/playlist?list=PLBejJIaDgbyQ'
Assert-Equal (Get-SamplePlaylist 'Music - Morning') $morningSample 'morning sample mapping'
Assert-Equal (Get-SamplePlaylist 'Music - Day Finisher') $finisherSample 'finisher sample mapping'
Assert-Equal (Get-SamplePlaylist 'Other task') '' 'unknown task has no sample'
foreach ($sample in @($morningSample,$finisherSample)) {
    foreach ($choice in @('S','s','sample',' SAMPLE ')) {
        Assert-Equal (Resolve-PlaylistInput $choice $sample) $sample ('sample choice ' + $choice)
    }
    Assert-Equal (Resolve-PlaylistInput '' $sample) '' 'Enter skips even with a sample'
    Assert-Equal (Resolve-PlaylistInput 'https://youtube.com/playlist?list=PL_CUSTOM&si=x' $sample) 'https://www.youtube.com/playlist?list=PL_CUSTOM' 'custom URL overrides sample'
    Assert-Rejected { Resolve-PlaylistInput 'https://example.com/playlist?list=x' $sample } 'sample option does not bypass URL validation'
}
Assert-Rejected { Resolve-PlaylistInput 'S' '' } 'S requires an available sample'
$guid = '11111111-2222-3333-4444-555555555555'
$lines = @('List of detected audio devices:', " 'auto' (Autoselect device)", " 'wasapi/{$guid}' (Speakers (Example USB))", " 'openal' (Default (openal))")
$devices = @(ConvertFrom-MpvDevices $lines)
Assert-Equal $devices.Count 3 'parse devices'
Assert-Equal (Resolve-MpvDevice '2' $devices).Id "wasapi/{$guid}" 'device number'
Assert-Equal (Resolve-MpvDevice $guid $devices).Id "wasapi/{$guid}" 'bare GUID repaired'
Assert-Equal (Resolve-MpvDevice "{$guid}" $devices).Id "wasapi/{$guid}" 'braced GUID repaired'
Assert-Equal (Resolve-MpvDevice "'wasapi/{$guid}'" $devices).Id "wasapi/{$guid}" 'quoted ID'
Assert-Equal (Resolve-MpvDevice 'auto' $devices).Id 'auto' 'auto selection'
foreach ($bad in @('','0','4','999999999999999999999999','11111111-2222-3333-4444-000000000000')) {
    Assert-Rejected { Resolve-MpvDevice $bad $devices } ('bad device ' + $bad)
}
# Exercise retry/default/skip behavior with a fake input queue.
$script:answers = New-Object 'System.Collections.Generic.Queue[string]'
function Read-Host { param($Prompt); return $script:answers.Dequeue() }
try {
    $script:answers.Enqueue('invalid'); $script:answers.Enqueue('1835')
    $value = Read-Validated 'Time' '06:45' { param($v) ConvertTo-ClockTime $v }
    Assert-Equal $value.ToString('HH:mm') '18:35' 'retry accepts corrected time'
    Assert-Equal $script:answers.Count 0 'one retry used'
    $script:answers.Enqueue('')
    $value = Read-Validated 'Time' '06:45' { param($v) ConvertTo-ClockTime $v }
    Assert-Equal $value.ToString('HH:mm') '06:45' 'Enter accepts default'
    $script:answers.Enqueue('')
    Assert-Equal ($null -eq (Read-MusicSession 'Test' '06:45' '2')) $true 'blank playlist skips all later prompts'
    $script:answers.Enqueue('')
    Assert-Equal ($null -eq (Read-MusicSession 'Music - Morning' '06:45' '2')) $true 'morning sample not selected on blank'
    $script:answers.Enqueue('')
    Assert-Equal ($null -eq (Read-MusicSession 'Music - Day Finisher' '15:45' '1')) $true 'finisher sample not selected on blank'
    foreach ($answer in @('S','','','')) { $script:answers.Enqueue($answer) }
    $session = Read-MusicSession 'Music - Morning' '06:45' '2'
    Assert-Equal $session.Playlist $morningSample 'morning S end to end'
    Assert-Equal $session.At.ToString('HH:mm') '06:45' 'morning time unchanged'
    Assert-Equal $session.Days.Count 6 'morning days unchanged'
    Assert-Equal $session.Runtime.TotalMinutes 180 'morning runtime unchanged'
    foreach ($answer in @('s','1708','2','45 min')) { $script:answers.Enqueue($answer) }
    $session = Read-MusicSession 'Music - Day Finisher' '15:45' '1'
    Assert-Equal $session.Playlist $finisherSample 'finisher s end to end'
    Assert-Equal $session.At.ToString('HH:mm') '17:08' 'custom time with sample'
    Assert-Equal $session.Days.Count 6 'custom days with sample'
    Assert-Equal $session.Runtime.TotalMinutes 45 'custom runtime with sample'
    foreach ($answer in @('bad','https://youtube.com/playlist?list=PL_CUSTOM&si=x','','','1:30')) { $script:answers.Enqueue($answer) }
    $session = Read-MusicSession 'Music - Day Finisher' '15:45' '1'
    Assert-Equal $session.Playlist 'https://www.youtube.com/playlist?list=PL_CUSTOM' 'retry then custom playlist'
    Assert-Equal $session.Runtime.TotalMinutes 90 'runtime format still accepted'
    Assert-Equal $script:answers.Count 0 'no extra prompts consumed'
    $script:answers.Enqueue('Q')
    Assert-Rejected { Read-Validated 'Time' '06:45' { param($v) ConvertTo-ClockTime $v } } 'Q cancels'
} finally { Remove-Item Function:\Read-Host }
# Keep the complete copy/paste Lua block identical to the shipped source.
$manual = [IO.File]::ReadAllText((Join-Path $root 'MANUAL-SETUP.md')).Replace("`r`n", "`n")
$lua = [IO.File]::ReadAllText((Join-Path $root 'payload\portable_config\scripts\random-start.lua')).Replace("`r`n", "`n")
$code = [regex]::Match($manual, '(?s)<!-- BEGIN RADIO LUA -->\n```lua\n(?<code>.*?)\n```\n<!-- END RADIO LUA -->')
Assert-Equal $code.Success $true 'manual contains a complete marked Lua block'
Assert-Equal $code.Groups['code'].Value.TrimEnd([char[]]"`r`n") $lua.TrimEnd([char[]]"`r`n") 'manual Lua is identical to payload'
$installerText = [IO.File]::ReadAllText($installer)
$runtimeWording = 'Maximum runtime is a DURATION, not the time of day to stop.'
Assert-Equal $installerText.Contains($runtimeWording) $true 'precise installer duration wording'
Assert-Equal $manual.Contains($runtimeWording) $true 'manual duration wording'
Assert-Equal ([IO.File]::ReadAllText((Join-Path $root 'README.md'))).Contains('MANUAL-SETUP.md') $true 'README links manual option'
# Build a real Windows task definition without registering or running a task.
if ($env:OS -eq 'Windows_NT') {
    Import-Module ScheduledTasks
    $session = [pscustomobject]@{
        Name='Parser test only'; Playlist='https://www.youtube.com/playlist?list=PL_TEST-ID'
        At=(ConvertTo-ClockTime '1835'); Days=@(ConvertTo-MusicDays '2'); Runtime=(ConvertTo-MusicRuntime '1.5')
    }
    $task = New-MusicTaskDefinition $session ([Security.Principal.WindowsIdentity]::GetCurrent().User.Value) 'C:\MPV'
    Assert-Equal $task.Actions.Count 1 'one radio launcher action'
    Assert-Equal $task.Actions[0].Execute "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" 'PowerShell launcher executable'
    Assert-Equal $task.Actions[0].WorkingDirectory 'C:\MPV' 'working folder'
    Assert-Equal ([xml.xmlconvert]::ToTimeSpan($task.Settings.ExecutionTimeLimit)).TotalMinutes 91 '90 minutes plus one minute safety cleanup'
    Assert-Equal $task.Actions[0].Arguments.Contains('-DurationSeconds 5400') $true 'launcher enforces the requested 90 minutes'
    Assert-Equal $task.Settings.WakeToRun $true 'wake enabled'
    Assert-Equal $task.Settings.StartWhenAvailable $false 'missed-start catchup disabled'
    Assert-Equal $task.Settings.RestartCount 3 'restart count'
    Assert-Equal ([datetime]$task.Triggers[0].StartBoundary).ToString('HH:mm') '18:35' 'actual trigger time'
}
Write-Host "PASS: $script:checks checks. No tasks were registered and no music was played."
