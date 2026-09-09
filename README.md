# MPV Radio Automation for Windows

**Turn a Windows desktop into a scheduled background-music player that treats ordinary songs and long mixes differently.**

Choose a YouTube playlist, a speaker, and a schedule. Short songs play normally. Long recordings can begin at a less-recently-heard section, using a local record of the portions actually played. An optional sampling mode moves between long mixes after a chosen listening interval instead of letting a ten-hour video occupy the whole session.

This is a lightweight automation layer around **mpv + yt-dlp**, not a streaming service, a broadcast server, or a replacement for either player. MPV is installed separately. No music, account credentials or third-party executables are included.

## What it does

- Runs morning/day-finisher playlists through Windows Task Scheduler and a selected audio output, leaving the Windows default output unchanged.
- Uses MPV shuffle plus a small-playlist-safe recent-track filter. Keeps the last **10 accepted track starts**, including short songs, across sessions.
- Leaves recordings **under 20 minutes** unseeked. For seekable recordings **20 minutes or longer**, chooses a start in the first **0%-75%** while favoring sections played less recently.
- Records estimated forward-played intervals **per recording**, rather than assuming everything after the starting point was heard.
- Offers **optional 20-40-minute section sampling**, with a five-second fade-out before the next mix. **Off by default.** Normal songs are not shortened.
- Includes clipboard shortcuts for audio-only playback and resizable, always-on-top video capped at 720p with best available audio. Manual shortcuts bypass radio scripts and histories.

**Two independent settings:** the **20-minute recording-length cutoff** decides which recordings qualify; the **20-40-minute sampling interval** decides how long to play one qualifying recording when sampling is enabled. Neither is the morning/evening task's maximum runtime.

**Status: test build.** Automated tests cover input parsing, history, selection and playback transitions. Synthetic/headless checks do not establish real speaker behavior, YouTube availability, loudness quality or sleep/wake reliability on your PC. Test those locally before relying on unattended playback.

## Quick start: guided setup

1. Install MPV yourself from the [official installation page](https://mpv.io/installation/). This project has used [Shinchiro Windows builds](https://github.com/shinchiro/mpv-winbuild-cmake/releases). For an x64 PC choose `mpv-x86_64-...7z`, not developer, 32-bit or ARM packages. Extract the **whole build** into `C:\MPV`, including `mpv.exe` and `mpv.com`.
2. On this repository choose **Code -> Download ZIP**. Extract the whole project to a separate folder. Keep `INSTALL.cmd`, `Install.ps1`, and `payload` together.
3. Run `INSTALL.cmd` as the Windows user who will listen. Setup requests elevation while carrying that user's identity forward. It does not install or replace MPV.
4. Select a detected speaker by **number**. At each playlist question, type **S** for the displayed sample, paste your own URL, or press **Enter to skip** that task.
5. Enter schedules using the examples below, review the summary, and type **YES** to save. Existing matching files/tasks are backed up first; playback histories are retained. Missing yt-dlp is downloaded from upstream only after approval.
6. In Task Scheduler, right-click a configured task and choose **Run**. Check the speaker, playlist, and repeat behavior before waiting for the next scheduled start.

The guided installer still identifies itself as **revision 3**; this update changes the Lua radio engine and documentation, not the input workflow. See [sample playlists and existing-task instructions](EXAMPLE-PLAYLISTS.md).

### Exactly what to type

Type only your answer, not the prompt or brackets. Enter accepts a displayed default; **Q cancels** at an input prompt.

| Question | Example answer | Meaning |
| --- | --- | --- |
| Speaker | `2` | Use the device numbered 2 in YOUR detected list. No device code to copy. |
| Playlist | `S` | Use the sample displayed for this task. |
| Playlist | Full `https://...playlist?list=...` URL | Use your own playlist; no `--shuffle` or quotes needed. |
| Playlist | Press Enter on an empty line | Skip this task and its remaining questions; leave an existing task unchanged. |
| Start time | `06:45`, `0645`, or `6:45 AM` | 6:45 in the morning. |
| Start time | `18:35`, `1835`, or `6:35 PM` | 6:35 in the evening. |
| Days | `1` / `2` / `3` / `4` | Monday-Friday / Monday-Saturday / every day / weekends. |
| Custom days | `MON,WED,FRI` | Only those days. |
| Maximum runtime | `3` | Three hours. |
| Maximum runtime | `1.5` or `1:30` | One hour thirty minutes. |
| Maximum runtime | `45 min` | Forty-five minutes. |
| Confirmation | `YES` | Apply the reviewed changes; Enter defaults to NO. |

**Maximum runtime is a DURATION, not the time of day to stop.** A start of 18:35 plus 1.5 hours has an approximate stop of 20:05, assuming an on-time uninterrupted run. Defaults remain Morning **06:45, Mon-Sat, 3 hours** and Day Finisher **15:45, Mon-Fri, 3 hours**. All clock times use the computer's local time.

The installer validates URL structure, not playlist existence or playback rights. Share/index/time parameters are removed from scheduled playlist URLs. Skipping a task does not disable or remove an existing task; use Task Scheduler for that.

## Listening modes

### Default: continuous long mixes with smarter starting points

Sampling is off. Every eligible long recording gets a start within 0%-75%, favoring less-recently-played parts of **that same recording**, and then continues until it ends or playback is stopped. The script checks every half-second for forward playback and periodically saves the intervals it observed.

For example, it can remember `Classical mix: 42:37-68:10` and prefer a different portion next time. The old ten-percentage log is still retained, but it is no longer the only source of variety. Existing track-start logs cannot reconstruct past listening intervals; the new history builds from this update onward.

**This is a preference, not a guarantee of zero repeated audio.** Selection compares a fixed look-ahead window (normally up to 20 minutes), with recently heard overlap penalized more than older overlap. A sufficiently short recording uses a shorter equal-sized window so all 0%-75% candidates are comparable. Starts are selected on a one-percentage-point grid, excluding the recent percentage values. Continuous playback can eventually overlap a section heard previously.

### Optional: sample a section, then move on

Create this file using Notepad's **Save as type: All files**:

```text
C:\MPV\portable_config\script-opts\random-start.conf
```

Create the `script-opts` folder if needed. Paste:

```ini
section_mode=yes
section_min_minutes=20
section_max_minutes=40
fade_seconds=5
```

Restart MPV. Each eligible recording now gets an independently chosen **20-40 minutes of forward, unmuted playback**, or its remaining duration if shorter, followed by a fade-out and the next playlist item. Pauses, buffering and detected seeks do not consume the listening allowance. A normal song under 20 minutes still plays normally. Set `section_mode=no` to return to continuous mode.

The settings are read from the config file when MPV starts. They are not a new installer question. A commented template is provided at `payload/portable_config/script-opts/random-start.conf.example`; the installer does not copy this optional template automatically. Copy/rename it yourself only when configuring these options.

For just one scheduled task, append `--script-opts-append=random-start-section_mode=yes` to that task's MPV arguments instead. This lets morning stay continuous and the day-finisher sample sections, or vice versa. Do not add `--load-scripts=no` to a scheduled radio task.

The fade is an MPV volume ramp, **not an overlapping crossfade**. Volume is restored before the next track; an intervening manual volume adjustment is respected. Network loading can leave a gap. Task Scheduler's forced runtime stop does not receive this fade. Finite playlist-loop counts are not managed by the sampler; use the documented `--loop-playlist=inf` radio workflow or a non-looping playlist.

## History, privacy and limits

All histories stay on this PC under `C:\MPV\portable_config`; they are not uploaded or synchronized.

| File | Purpose |
| --- | --- |
| `recent-track-history.txt` | Last 10 accepted starts: timestamp, video ID and title. Not proof a song finished. |
| `random-start-history.txt` | Last 10 selected long-track percentages. |
| `heard-sections.txt` | Estimated played ranges, recording ID, duration, last-heard time and title; final column is readable `minutes:seconds-minutes:seconds`. |
| `heard-sections.txt.bak` | Previous complete section checkpoint, used for recovery. |

The recent-track exclusion window is separate from history retention: at most five recent starts, reduced using the number of **unique** videos so small/duplicate-filled playlists remain playable. This is not yet a persistent shuffle bag of all unplayed songs.

Section history skips paused, buffering, muted and detected seek gaps, and refuses to bridge long timer gaps such as computer sleep. It estimates **player activity**, not human attention or physical sound output; silent media or a powered-off external speaker cannot be detected reliably. Precision is roughly the polling interval, not sample-accurate audio measurement.

Section history checkpoints every **15 seconds** by default and at normal file transitions/shutdown. A force-kill can lose the unsaved tail (normally up to a checkpoint interval, potentially longer during blocked execution or write failures). Complete files are rotated through a backup. One player must own the histories: concurrent writers are unsupported.

By default the section log retains up to **40 intervals per recording**, **2,000 overall**, and **180 days**. Recent overlap uses a **14-day half-life**; these are configurable in the template. Large changes to a recording's duration make old offsets ineligible for selection, rather than assuming an edited timeline still matches. Unknown-duration/non-seekable streams are left to ordinary MPV playback.

## Update an existing working computer

For this radio-engine update, **do not rerun the installer or recreate tasks**:

1. Close MPV. Back up your existing Lua file **outside** `portable_config\scripts`.
2. Copy the repository's `payload\portable_config\scripts\random-start.lua` over `C:\MPV\portable_config\scripts\random-start.lua`.
3. Keep both existing history files and your `mpv.conf`. Restart playback. New section history appears after qualifying playback is observed.
4. Only to enable sampling, create the optional `script-opts\random-start.conf` described above.

Do not leave two active radio `.lua` files in the scripts directory. No changes to your speaker, sample playlists, task times, or runtime limits are required.

## Scheduler, safeguards and troubleshooting

Tasks use two actions: stop accessible `mpv.exe` processes, then launch `C:\MPV\mpv.exe --shuffle --loop-playlist=inf "PLAYLIST_URL"`, with `C:\MPV` as the working directory. Starting a scheduled session currently closes accessible manual MPV windows too; this is not isolated IPC control.

Tasks request wake-to-run, require the selected user to stay logged in (locked is okay), retry failures every five minutes up to three times, reject a duplicate instance of the same task, and stop at the chosen runtime. Missed-start catch-up is off. The speaker must be connected; wake timers/hardware must permit waking. A powered-off PC is not started by Task Scheduler. AC-power conditions are retained; review them on laptops.

Setup backs up replaced files, matching tasks and shortcuts under `C:\MPV\setup-backups`. It warns about other MPV tasks but leaves them unchanged. Unexpected errors remain visible with a log path in the Windows temporary folder; partial installation has **no automatic rollback**. Keep backups/private logs out of public repositories.

Useful commands in Command Prompt:

```bat
C:\MPV\mpv.com --no-config --load-scripts=no --audio-device=help
C:\MPV\yt-dlp.exe --version
C:\MPV\yt-dlp.exe -U
```

Use the complete detected `wasapi/{GUID}` in `mpv.conf`, not the GUID alone, when configuring manually. Enable File Explorer's **File name extensions**; avoid `mpv.conf.txt`, `random-start.lua.txt` and `random-start.conf.txt`. Keep the default Windows output on your normal headset if the music uses a separate speaker.

MPV and yt-dlp remain upstream dependencies. For extraction failures follow [yt-dlp's current guidance](https://github.com/yt-dlp/yt-dlp/wiki/EJS), including a supported JavaScript runtime when required. This installer does not install that runtime. Upstream/network/region restrictions can still interrupt YouTube playback.

## Development and attribution

See the tests and workflows for reproducible checks. Section tests simulate MPV events and file errors; a headless smoke test uses generated local media, not YouTube or a physical speaker. Windows tests validate installer inputs and that the complete Lua code in the manual matches the shipped file.

Project automation code uses the MIT license. See `THIRD_PARTY.md` for upstream licenses. Sample playlists are suggestions, not music distributed by the project or permission for public/commercial playback. Do not publish personal authentication files or listening logs.

## Alternative: set everything up manually (no installer)

**[Open the complete manual setup guide](MANUAL-SETUP.md).** It includes the folder structure, audio device selection, `mpv.conf`, the **entire current Lua script**, optional sampling configuration, sample playlists, both Task Scheduler actions and testing steps. Use this instead of the installer, not as an additional installation that creates duplicate tasks.
