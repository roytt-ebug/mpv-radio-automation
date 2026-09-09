MPV RADIO AUTOMATION - ONE PLAYER

Copy all payload files into C:\MPV. MPV itself is installed separately.
Scheduled sessions use Radio-Hidden.exe to start the unchanged Radio.ps1
supervisor without a PowerShell console. MPV's control window stays visible.
The crossfade engine and second player have been removed.

The installer builds Radio-Hidden.exe automatically using Windows .NET.
For manual setup, copy Radio-Hidden.cs and Build-HiddenStarter.ps1 here,
then run this once in PowerShell or Command Prompt (no downloads):
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\MPV\Build-HiddenStarter.ps1"
The build refuses to overwrite an existing helper. Stop playback and back
up that executable before rebuilding. Do not bypass security restrictions.

DEFAULTS
Sampling ON; recordings at least 15 minutes qualify; sample allowance
10-30 minutes, capped to the source length. Short songs play normally.
Edit portable_config\script-opts\random-start.conf, then restart MPV.
section_mode=no disables sampling. fade_seconds=0 disables the simple
sample fade-out. Tracks do not overlap; YouTube loading may leave gaps.

CONTROLS AND CHECKS
In MPV: Space = pause, > = next, 9/0 = volume, Q = quit.
F8 shows the loaded Lua version and settings.
Check Radio.cmd verifies a fresh acknowledgement from the running MPV/Lua.
Stop Radio.cmd stops only this installation's radio.
Clipboard shortcuts use Play-YouTube.ps1 and bypass radio histories.

TASK ACTION (one action per task)
Program: C:\MPV\Radio-Hidden.exe
Start in: C:\MPV
Morning arguments:
-Playlist "https://www.youtube.com/playlist?list=PLZAsCc2NQgn0" -DurationSeconds 10800
Day Finisher arguments:
-Playlist "https://www.youtube.com/playlist?list=PLBejJIaDgbyQ" -DurationSeconds 10800

Maximum runtime is a DURATION, not the time of day to stop.
Installer input is HOURS only: 1 = 1 hour, 1.5 = 90 minutes, 11.5 = 11.5 hours.
Use 0.75 for 45 minutes. Maximum: 24 hours. H:MM and unit words are rejected.
Manual task arguments use seconds: 10800 = three hours; 86400 = 24 hours.
Loading and pauses count. Set the Task Scheduler backup stop limit one
minute longer for cleanup. Keep Windows logged in and the speaker on.

UPDATING
Stop music and close its windows. Back up portable_config and export tasks.
Already using Radio.ps1? Copy ONLY Radio-Hidden.cs and Build-HiddenStarter.ps1,
build the helper as above, and change the task program to Radio-Hidden.exe.
Remove the PowerShell options through -File "C:\MPV\Radio.ps1"; retain the
-Playlist and -DurationSeconds values, working folder, triggers and settings.
No changes to Radio.ps1, Lua, sampling settings or any history are needed.
For older crossfade/taskkill setups, follow the full README upgrade instead.
The unused radio-session.json from the crossfade version can be deleted.
Run the task, check F8/Check Radio, and confirm one player and your speaker.
Hidden failures return a nonzero Task Scheduler Last Run Result and write
the latest error to Radio-Hidden-error.log when the folder is writable.
This bounded log is not erased on success; check its timestamp. Diagnostic
and manual CMD windows are intentionally unchanged by this helper update.

HISTORY
portable_config\recent-track-history.txt retains ten accepted starts.
portable_config\random-start-history.txt retains ten starting percentages.
portable_config\heard-sections.txt records estimated played ranges.
Sections checkpoint about every 15 seconds and on normal stops. Forced
termination can lose the unsaved tail. Do not run another radio script
against the same histories while a scheduled session is playing.

If the launcher is killed, MPV may remain until Lua's session limit. Use Q
or Stop Radio to stop sooner. Update yt-dlp and follow its current guidance
for a supported JavaScript runtime if YouTube extraction fails.

Full instructions: https://github.com/roytt-ebug/mpv-radio-automation
