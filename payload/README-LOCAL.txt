MPV RADIO AUTOMATION FOR WINDOWS

Scheduled YouTube music with one MPV player, playlist shuffle, and listening
history. Short songs play normally; long mixes can rotate between samples.
MPV's controls stay visible. The PowerShell supervisor has no terminal window.

SETUP
Install the complete x64 MPV build separately in C:\MPV. Download and extract
the project ZIP, then run INSTALL.cmd from the extracted project folder.
The installer selects your speaker, creates your schedules, obtains a missing
yt-dlp with checksum verification, and builds Radio-Hidden.exe from source.
Deno is optional. Test each task with Task Scheduler > right-click > Run.
The selected Windows user must remain logged in; locking the screen is fine.

Full setup, input examples, and manual alternative:
https://github.com/roytt-ebug/mpv-radio-automation

DEFAULTS AND LIMITS
Eligibility cutoff: 15 minutes; adjustable from 0.01 to 1,440 minutes.
Sampling: ON; choose yes or no.
Minimum sample: 10 minutes; adjustable from 0.01 to 1,440 minutes.
Maximum sample: 30 minutes; adjustable from 0.01 to 1,440 minutes.
Keep minimum <= maximum. Invalid pairs return to 10-30 minutes. Allowances
use whole seconds, at least one second, and are shortened to fit the content.
Sample fade-out: 5 seconds; adjustable from 0 to 60 seconds. Zero = off.
Whole session: 3 hours; allowed range 1 minute to 24 hours, entered in hours.
Use 1.5 for 90 minutes or 0.75 for 45 minutes. This is a duration, not a stop
time. Pauses/loading count toward the whole session, but not the sample.

Edit C:\MPV\portable_config\script-opts\random-start.conf, then restart MPV:
section_mode=yes
min_duration_minutes=15
section_min_minutes=10
section_max_minutes=30
fade_seconds=5

OPTIONAL DENO
Deno helps yt-dlp handle YouTube's JavaScript checks. Some playlists work
without it; consider adding it for JavaScript/signature or missing-format
errors. Setup continues without Deno and does not download it automatically.

Check Settings > System > About > System type, then choose from:
https://github.com/denoland/deno/releases/latest
64-bit Windows, x64 Intel/AMD: deno-x86_64-pc-windows-msvc.zip
64-bit Windows, ARM64: deno-aarch64-pc-windows-msvc.zip
These are Deno downloads; this radio project is tested for Windows x64 only.
There is no current official Windows 32-bit Deno build. Use stable Deno 2.3.0
or newer, on Windows 10 version 1709 or newer (including Windows 11).

Choose the complete deno-...zip. .bsdiff files are update patches; .sha256sum
files are checksum text. denort/libdenort and source files are for developers.
Extract deno.exe directly into C:\MPV beside mpv.exe and yt-dlp.exe, not into
an extra folder or left inside the archive. Check C:\MPV\deno.exe --version.
Restart MPV after adding it. You do not need to leave Deno's window open.

CONTROLS
Space = pause/resume; > = next; 9/0 = volume; Q = quit.
F8 in MPV shows the loaded script and settings.
Check Radio.cmd checks that the scheduled player and Lua script respond.
Stop Radio.cmd stops this installation's radio.
Clipboard audio/video shortcuts play normally without radio-history updates.

HISTORY
Files are stored in C:\MPV\portable_config:
recent-track-history.txt: last ten accepted starts, with dates and titles.
random-start-history.txt: last ten selected starting percentages.
heard-sections.txt: estimated played ranges for each recording.
heard-sections.txt.bak: previous section-history save for recovery.
Sections save about every 15 seconds and on normal stops. A forced shutdown
can lose the latest unsaved portion. Keep script backups outside scripts.

START OVER WITH A FRESH SETUP
1. Run Stop Radio.cmd and close MPV.
2. In Task Scheduler > Task Scheduler Library, delete only this project's
   music tasks (normally Music - Morning and Music - Day Finisher), including
   any older copies you renamed.
3. Delete C:\MPV\portable_config. This erases settings AND listening history;
   copy it elsewhere first if you want a backup.
4. Download and extract a fresh project ZIP. Run INSTALL.cmd and choose your
   speaker, playlists, and schedules again. Test each saved task.
Keep MPV, yt-dlp, and any optional deno.exe. Setup replaces its helper files.

TROUBLESHOOTING
YouTube errors: run Update yt-dlp.cmd, check the link/internet, consider Deno.
No player: check Task Scheduler's Last Run Result and Radio-Hidden-error.log.
Check the log's date; successful runs do not erase the previous error.
Antivirus message: record the product and exact message; do not disable
protection. The helper is built locally and unsigned.
Download checksum failure: read the error and retry the official download.
Existing yt-dlp copies are retained; only new downloads are checksum-checked.
Setup backups are in C:\MPV\setup-backups. Setup does not automatically undo
completed changes after a failure. Review the reported step before retrying.
