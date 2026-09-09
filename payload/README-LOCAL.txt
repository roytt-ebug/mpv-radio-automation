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

OPTIONAL PLAYLIST RECOMMENDATIONS
---------------------------------
Morning Music:
https://www.youtube.com/playlist?list=PLZAsCc2NQgn0

Day Finisher:
https://www.youtube.com/playlist?list=PLBejJIaDgbyQ

These are optional external playlists, not automatic installer defaults.
Users may enter their own URLs. Playlist contents and availability can change.
At a fresh installer's playlist prompt, paste only the URL and press Enter.
A blank playlist prompt skips that task and leaves any existing task unchanged.

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
