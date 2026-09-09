MPV RADIO AUTOMATION - ONE PLAYER

Copy all payload files into C:\MPV. MPV itself is installed separately.
Scheduled sessions use Radio.ps1, which starts one visible MPV window.
The crossfade engine and second player have been removed.

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
Program: C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe
Start in: C:\MPV
Morning arguments:
-NoProfile -ExecutionPolicy Bypass -File "C:\MPV\Radio.ps1" -Playlist "https://www.youtube.com/playlist?list=PLZAsCc2NQgn0" -DurationSeconds 10800
Day Finisher arguments:
-NoProfile -ExecutionPolicy Bypass -File "C:\MPV\Radio.ps1" -Playlist "https://www.youtube.com/playlist?list=PLBejJIaDgbyQ" -DurationSeconds 10800

Maximum runtime is a DURATION, not the time of day to stop.
10800 seconds = three hours; 5400 = 90 minutes; 2700 = 45 minutes.
Loading and pauses count. Set the Task Scheduler backup stop limit one
minute longer for cleanup. Keep Windows logged in and the speaker on.

UPDATING
Stop music and close its windows. Back up portable_config and export tasks.
Copy ALL new payload files, keeping mpv.conf and history files. The supplied
random-start.conf replaces sampling settings; save your customized copy.
If a task already uses Radio.ps1, keep its action, URL and duration.
If it uses taskkill + direct MPV, replace those with the single action above.
The unused radio-session.json from the crossfade version can be deleted.
Run the task, check F8/Check Radio, and confirm one player and your speaker.

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
