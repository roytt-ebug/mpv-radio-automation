MPV RADIO AUTOMATION - LOCAL NOTES
==================================
Scheduled Windows background music using MPV + yt-dlp and your selected speaker.
Short songs play normally. Long recordings favor less-recently-heard sections.
Optional sampling rotates between long mixes; it is OFF by default.

Main folder: C:\MPV
Player: C:\MPV\mpv.exe (use mpv.com for console diagnostics)
YouTube helper: C:\MPV\yt-dlp.exe
Player configuration: C:\MPV\portable_config\mpv.conf
Radio script: C:\MPV\portable_config\scripts\random-start.lua

PLAYBACK RULES
--------------
Under 20 minutes: no random seek or sampling; normal playback.
20+ minutes and seekable: choose a less-recently-heard start within 0%-75%.
Ten accepted track starts persist, independently of the smaller repeat filter.
Ten selected long-track percentages are retained separately.

New per-recording interval history:
C:\MPV\portable_config\heard-sections.txt
Final column shows minutes:seconds-minutes:seconds, e.g. 42:37-68:10.
This estimates forward player activity, not human attention or physical sound.
Pauses, buffering, mute and detected seeks are excluded. State checkpoints
normally every 15 seconds; hard termination can lose the unsaved tail.
The .bak file is a previous complete checkpoint. Only one player should write.
Defaults: up to 40 intervals per recording, 2000 overall, at most 180 days old.

Existing histories remain:
C:\MPV\portable_config\recent-track-history.txt
C:\MPV\portable_config\random-start-history.txt
Old start logs cannot reconstruct what sections were heard before this update.

OPTIONAL SECTION SAMPLING
-------------------------
Create C:\MPV\portable_config\script-opts\random-start.conf with:
section_mode=yes
section_min_minutes=20
section_max_minutes=40
fade_seconds=5

Restart MPV. Long mixes play 20-40 minutes of forward unmuted playback,
or remaining content if shorter, then fade out and advance. Short songs
are not cut. Set section_mode=no for uninterrupted long mixes again.
The fade is not a crossfade or a fade for Task Scheduler's force-stop.
This optional file is not created by the installer.

The 20-minute eligibility cutoff, 20-40-minute optional sample length,
and a task's maximum runtime are three separate settings.
Maximum runtime is a DURATION, not the time of day to stop.

SAMPLE PLAYLISTS AND TASK ARGUMENTS
----------------------------------
Morning:
--shuffle --loop-playlist=inf "https://www.youtube.com/playlist?list=PLZAsCc2NQgn0"
Day Finisher:
--shuffle --loop-playlist=inf "https://www.youtube.com/playlist?list=PLBejJIaDgbyQ"

In Task Scheduler edit the existing SECOND action that runs C:\MPV\mpv.exe.
Keep Start in: C:\MPV and the first stop-old-MPV action unchanged.
Do not create duplicate tasks. Keep your preferred times/days/runtime.
For a fresh installer: S uses the displayed sample, URL uses your own,
Enter skips that task and leaves any existing task unchanged.

UPDATE ONLY THE RADIO SCRIPT
-----------------------------
Close MPV. Back up the old Lua OUTSIDE the scripts folder. Replace
C:\MPV\portable_config\scripts\random-start.lua with the new version.
Keep mpv.conf, optional sampling settings and all histories. Restart.
Do not rerun the installer solely for a Lua update.
Manual launchers use --load-scripts=no and bypass histories and radio modes.

TROUBLESHOOTING AND DOCUMENTATION
---------------------------------
C:\MPV\mpv.com --no-config --load-scripts=no --audio-device=help
C:\MPV\yt-dlp.exe --version
C:\MPV\yt-dlp.exe -U

Windows must remain logged in; locked is okay. Wake timers/speaker availability
must permit playback. A powered-off PC is not started by Task Scheduler.
Current scheduled starts close accessible MPV windows, including manual videos.
For YouTube failures follow yt-dlp's current JavaScript-runtime guidance.

https://github.com/roytt-ebug/mpv-radio-automation
https://github.com/roytt-ebug/mpv-radio-automation/blob/main/MANUAL-SETUP.md
https://github.com/roytt-ebug/mpv-radio-automation/blob/main/EXAMPLE-PLAYLISTS.md
https://mpv.io/installation/
https://github.com/yt-dlp/yt-dlp/releases/latest
