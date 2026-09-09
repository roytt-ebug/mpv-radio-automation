MPV RADIO AUTOMATION - YouTube radio with overlapping crossfades

ACTIVE DEFAULTS
Sampling ON. Only recordings at least 15 minutes long qualify.
Each eligible recording receives a 10-30-minute allowance, capped to its
own duration. A starting point is chosen early enough to fit the sample.
Ordinary songs play through their endings. Crossfade is 5 seconds.

SETTINGS
C:\MPV\portable_config\script-opts\random-start.conf
section_mode=yes
min_duration_minutes=15
section_min_minutes=10
section_max_minutes=30
crossfade_seconds=5
fade_seconds=5

Restart after edits. section_mode=no disables sampling.
crossfade_seconds=0 disables overlap. fade_seconds only controls the
standalone Lua fade; direct MPV playback cannot overlap playlist tracks.

VERIFY THE RUNNING SCRIPT
While a radio task plays, double-click Check Radio.cmd. It queries both
actual MPV players and checks that Lua acknowledges a harmless ping.
Confirm two PASS reports, expected speaker, sampling ON, cutoff 15,
sample range 10-30 and crossfade 5. In standalone MPV, F8 shows status.

CONTROLS
Radio controller console: Space pause, N next, +/- volume, Q stop.
Stop Radio.cmd stops the current radio session. A new scheduled radio
session stops the old controller, leaving unrelated MPV windows alone.

SCHEDULED TASK ACTION (one action, no taskkill)
Program: C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe
Start in: C:\MPV
Morning arguments:
-NoProfile -ExecutionPolicy Bypass -File "C:\MPV\Radio.ps1" -Playlist "https://www.youtube.com/playlist?list=PLZAsCc2NQgn0" -DurationSeconds 10800
Day Finisher arguments:
-NoProfile -ExecutionPolicy Bypass -File "C:\MPV\Radio.ps1" -Playlist "https://www.youtube.com/playlist?list=PLBejJIaDgbyQ" -DurationSeconds 10800

Maximum runtime is a DURATION, not the time of day to stop.
10800 seconds = 3 hours; 5400 = 90 minutes; 2700 = 45 minutes.
The duration includes loading and pauses. Set Task Scheduler's backup
stop limit one minute longer to permit cleanup.

UPGRADING
Stop the old tasks and their MPV windows. Back up portable_config and
export tasks. Copy the new payload contents into C:\MPV, keeping your
mpv.conf and histories. The new random-start.conf supplies active defaults.
Replace each old task's two actions with the controller action above.
Keep your own triggers, days and duration. Run it and open Check Radio.cmd.
Replacing only random-start.lua does not enable overlapping crossfade.

HISTORY
portable_config/recent-track-history.txt: last 10 accepted starts.
portable_config/random-start-history.txt: last 10 accepted percentages.
portable_config/heard-sections.txt: estimated played ranges per recording.
Preloaded tracks are not marked played. The two decks checkpoint serially,
normally every 15 seconds. Do not run an unmanaged radio script against
these files simultaneously. Paused, buffering, muted and seek gaps are
excluded; this estimates player activity, not physical speaker output.

LIMITS
YouTube loading can still leave gaps. A killed controller's hidden players
exit after 15 seconds without heartbeats; the unsaved history tail may be
lost. Session endings are stops, not crossfades into the next session.
Keep Windows logged in, speaker connected and wake timers available.
Update yt-dlp and follow its current JavaScript-runtime instructions when
YouTube extraction fails. No Spotify setup is used.

Full instructions: https://github.com/roytt-ebug/mpv-radio-automation
