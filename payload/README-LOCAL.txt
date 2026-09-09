MPV RADIO AUTOMATION - LOCAL NOTES
==================================

Main folder:
C:\MPV

Important files:
C:\MPV\mpv.exe
C:\MPV\mpv.com
C:\MPV\yt-dlp.exe
C:\MPV\portable_config\mpv.conf
C:\MPV\portable_config\scripts\random-start.lua

History:
C:\MPV\portable_config\random-start-history.txt
C:\MPV\portable_config\recent-track-history.txt

The radio script retains the last 10 accepted track starts, including short
songs. Repeat protection uses a smaller, adaptive window. Tracks under
20 minutes are not randomly seeked; longer tracks get a 0%-75% random start.
Manual launchers disable the radio script and do not add to this history.

SAMPLE PLAYLISTS IN GUIDED SETUP (REVISION 3)
--------------------------------------------
Morning Music:
https://www.youtube.com/playlist?list=PLZAsCc2NQgn0

Day Finisher:
https://www.youtube.com/playlist?list=PLBejJIaDgbyQ

At each installer's playlist prompt, type S and press Enter to use the sample
shown for that task. Or paste your own complete URL. A blank answer skips that
task and leaves any existing task unchanged. S is an installer choice only;
do not put S into a Task Scheduler action.

These are optional external playlists. Contents and availability can change.

MAXIMUM RUNTIME
----------------
Maximum runtime is a DURATION, not the time of day to stop.
3 = 3 hours; 1.5 or 1:30 = 90 minutes; 45 min = 45 minutes.
For example, start 18:35 with a runtime of 1.5 means an approximate stop at
20:05. Retries, delayed starts or interruptions may change the actual stop.

CHANGE THE PLAYLIST IN AN EXISTING TASK
--------------------------------------
Open Task Scheduler -> existing music task -> Properties -> Actions.
Edit the action that starts C:\MPV\mpv.exe (normally the SECOND action).
Leave the first stop-old-MPV action unchanged.

Morning Music - Add arguments:
--shuffle --loop-playlist=inf "https://www.youtube.com/playlist?list=PLZAsCc2NQgn0"

Day Finisher - Add arguments:
--shuffle --loop-playlist=inf "https://www.youtube.com/playlist?list=PLBejJIaDgbyQ"

For both tasks keep:
Program/script: C:\MPV\mpv.exe
Start in: C:\MPV

Keep your existing times, days, runtime limits, audio output and Lua settings.
Save the task. Its new URL is used on its next start. To test immediately,
right-click the task and choose Run; it stops accessible MPV playback first.
No reinstallation is needed for a playlist-only change.
Updating GitHub does not automatically change tasks already on this computer.

TROUBLESHOOTING
---------------
List audio outputs independently of the current configuration:
C:\MPV\mpv.com --no-config --audio-device=help

If YouTube suddenly stops working, update yt-dlp from upstream:
C:\MPV\yt-dlp.exe -U

MPV Windows builds:
https://github.com/shinchiro/mpv-winbuild-cmake/releases

yt-dlp:
https://github.com/yt-dlp/yt-dlp/releases/latest

Project documentation:
https://github.com/roytt-ebug/mpv-radio-automation

Playlist recommendations and instructions:
https://github.com/roytt-ebug/mpv-radio-automation/blob/main/EXAMPLE-PLAYLISTS.md

MANUAL SETUP WITHOUT THE INSTALLER
----------------------------------
A complete step-by-step guide, including the full Lua code and all Task
Scheduler fields, is in MANUAL-SETUP.md in the downloaded repository, or at:
https://github.com/roytt-ebug/mpv-radio-automation/blob/main/MANUAL-SETUP.md
