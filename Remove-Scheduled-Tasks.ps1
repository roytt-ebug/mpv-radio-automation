$ErrorActionPreference = "Stop"
$tasks = @("Music - Morning", "Music - Day Finisher")
foreach ($name in $tasks) {
    $task = Get-ScheduledTask -TaskName $name -ErrorAction SilentlyContinue
    if ($task) {
        Unregister-ScheduledTask -TaskName $name -Confirm:$false
        Write-Host "Removed scheduled task: $name"
    } else {
        Write-Host "Task not found: $name"
    }
}
Write-Host ""
Write-Host "C:\MPV and its files were NOT deleted. This script only removes the scheduled tasks."
