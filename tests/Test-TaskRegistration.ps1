# Integration check: requires Windows and permission to register a task.
# The uniquely named task is disabled before registration and removed afterward.
$ErrorActionPreference = 'Stop'
if ($env:OS -ne 'Windows_NT') { throw 'This test requires Windows Task Scheduler.' }
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'Install.ps1') -FunctionsOnly
Import-Module ScheduledTasks

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$session = [pscustomobject]@{
    Name=('MPV-Radio-Registration-Test-' + [guid]::NewGuid().ToString('N'))
    Playlist='https://www.youtube.com/playlist?list=PL_TEST-ID'
    At=(Get-Date).AddDays(7)
    Days=@([System.DayOfWeek]::Monday)
    Runtime=[timespan]::FromHours(1)
}
$definition = New-MusicTaskDefinition $session $identity.User.Value $env:TEMP
$definition.Settings.Enabled = $false
$registered = $false
try {
    # Exercise the same registration call as setup, including its principal.
    Register-ScheduledTask -TaskName $session.Name -TaskPath '\' -InputObject $definition | Out-Null
    $registered = $true
    $saved = Get-ScheduledTask -TaskName $session.Name -TaskPath '\'
    if ($saved.Settings.Enabled) { throw 'Test task must remain disabled.' }
    $userId = $saved.Principal.UserId
    if ($userId -like 'S-1-*') {
        $actualSid = (New-Object Security.Principal.SecurityIdentifier($userId)).Value
    } else {
        $actualSid = (New-Object Security.Principal.NTAccount($userId)).Translate([Security.Principal.SecurityIdentifier]).Value
    }
    if ($actualSid -ne $identity.User.Value) { throw 'Registered task belongs to the wrong account.' }
    if ([int]$saved.Principal.LogonType -ne 3) { throw 'Interactive logon was not retained.' }
    if ([int]$saved.Principal.RunLevel -ne 0) { throw 'Limited privileges were not retained.' }
    if ($saved.Actions.Count -ne 1) { throw 'Expected one launcher action.' }
    if ($saved.Actions[0].Arguments -ne $definition.Actions[0].Arguments) { throw 'Playback arguments changed during registration.' }
    Write-Host 'PASS: Windows registered the disabled task for the correct listener with limited, interactive logon.'
} finally {
    if ($registered) {
        Unregister-ScheduledTask -TaskName $session.Name -TaskPath '\' -Confirm:$false
        Write-Host 'Removed the test task. No music was played.'
    }
}
