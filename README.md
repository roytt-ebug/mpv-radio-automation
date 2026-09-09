# MPV Radio Automation for Windows

**Turn a Windows desktop into a scheduled background-music player that treats ordinary songs and long mixes differently.**

Choose a YouTube playlist, a speaker, and a schedule. Short songs play normally. Long recordings can begin at a less-recently-heard section, using a local record of the portions actually played. Sampling is enabled by default: rotate between 10-30-minute sections of long mixes, with overlapping crossfades between tracks.

This is a lightweight automation layer around **mpv + yt-dlp**, not a streaming service, a broadcast server, or a replacement for either player. MPV is installed separately. No music, account credentials or third-party executables are included.

## What it does

- Runs morning/day-finisher playlists through Windows Task Scheduler and a selected audio output, leaving the Windows default output unchanged.
- Shuffles distinct videos, plays through each pass, and uses a small-playlist-safe recent-track filter. Keeps the last **10 accepted track starts**, including short songs, across sessions.
- Leaves recordings **under 15 minutes** unseeked. For seekable recordings **15 minutes or longer**, chooses a start in the first **0%-75%** while favoring sections played less recently.
- Records estimated forward-played intervals **per recording**, rather than assuming everything after the starting point was heard.
- Enables **10-30-minute section sampling** for eligible recordings and **five-second overlapping crossfades** through two controlled MPV players. Normal songs play through their ending, overlapping the next intro.
- Includes clipboard shortcuts for audio-only playback and resizable, always-on-top video capped at 720p with best available audio. Manual shortcuts bypass radio scripts and histories.

| Setting | Default | Meaning |
| --- | --- | --- |
| Eligibility cutoff | **15 minutes** | Only recordings at least this long receive smart seeking and sampling. |
| Sample length | **10-30 minutes** | A new allowance for each eligible recording, capped to its duration. |
| Crossfade | **5 seconds** | Next track fades in while the current one fades out. |
| Session duration | **3 hours** | Maximum runtime of the whole scheduled session. |

A start is chosen early enough to fit the sample. For example, a 15-minute video cannot provide a 30-minute sample: its allowance is capped to 15 minutes. Sampling can be disabled independently of crossfades.

**Status: test build.** Automated tests cover input parsing, history, selection and playback transitions. Synthetic/headless checks do not establish real speaker behavior, YouTube availability, loudness quality or sleep/wake reliability on your PC. Test those locally before relying on unattended playback.

## Quick start: guided setup

1. Install MPV yourself from the [official installation page](https://mpv.io/installation/). This project has used [Shinchiro Windows builds](https://github.com/shinchiro/mpv-winbuild-cmake/releases). For an x64 PC choose `mpv-x86_64-...7z`, not developer, 32-bit or ARM packages. Extract the **whole build** into `C:\MPV`, including `mpv.exe` and `mpv.com`.
2. On this repository choose **Code -> Download ZIP**. Extract the whole project to a separate folder. Keep `INSTALL.cmd`, `Install.ps1`, and `payload` together.
3. Run `INSTALL.cmd` as the Windows user who will listen. Setup requests elevation while carrying that user's identity forward. It does not install or replace MPV.
4. Select a detected speaker by **number**. At each playlist question, type **S** for the displayed sample, paste your own URL, or press **Enter to skip** that task.
5. Enter schedules using the examples below, review the summary, and type **YES** to save. Existing matching files/tasks are backed up first; playback histories are retained. Missing yt-dlp is downloaded from upstream only after approval.
6. In Task Scheduler, right-click a configured task and choose **Run**. Check the speaker, playlist, and repeat behavior before waiting for the next scheduled start.

The guided installer is **revision 4** and now creates a controller action for each radio task. See [sample playlists and existing-task instructions](EXAMPLE-PLAYLISTS.md).

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

## Listening and transitions

The active settings file is `C:\MPV\portable_config\script-opts\random-start.conf`. The installer now copies it automatically:

```ini
section_mode=yes
min_duration_minutes=15
section_min_minutes=10
section_max_minutes=30
crossfade_seconds=5
fade_seconds=5
```

Restart the radio session after edits. `section_mode=no` restores uninterrupted long mixes, still using smart starting points. `crossfade_seconds=0` disables overlap in the controller. `fade_seconds` controls the sequential fade-out only when the Lua script runs on its own.

The script compares estimated heard intervals separately for each recording. It can remember `Classical mix: 42:37-68:10` and favor a less recently heard section next time. Recent overlap counts more than old overlap. With sampling, candidate starts must leave room for the selected sample; percentage exclusions relax if necessary to fit it. With sampling disabled, starts remain within 0%-75% and scoring looks ahead up to 20 minutes. Section selection favors variety; it cannot guarantee entirely new audio forever.

`Radio.ps1` starts two MPV players using the same speaker configuration, preloads the next item while paused near the end of the current section, then overlaps their volume ramps. It waits for the incoming player to advance before reducing the outgoing gain. It handles both ordinary track endings and sample endings. The next source can still fail or load too slowly; gaps remain possible. Failed loads are retried with another entry, with a bounded failure limit. Sampling stops at its allowance if the next source is still unavailable.

MPV already provides [playlist shuffle, seeking, script options and audio routing](https://mpv.io/manual/stable/). Its [gapless-audio option](https://mpv.io/manual/stable/#options-gapless-audio) tries to avoid disruption at a file change; it does not overlap two tracks. There is no native playlist-crossfade switch in the current manual. Our controller uses MPV's documented [JSON IPC](https://mpv.io/manual/stable/#json-ipc), with local named pipes on Windows, to supply that overlap. Windows mixes the two outputs in shared mode; exclusive audio mode is disabled for these players.

The controller console accepts **Space** (pause/resume), **N** (next), **+/-** (volume), and **Q** (stop). `Stop Radio.cmd` also stops the session. The session duration is a wall-clock limit, including pauses. A normal session stop closes both owned players; it is not an additional track crossfade.

### Verify that MPV is listening

While a radio task is playing, double-click **`C:\MPV\Check Radio.cmd`**. It connects to each actual MPV process, reads the Lua script's status, sends a harmless ping, and waits for the script to acknowledge it. A PASS reports the running version, speaker, sampling state, 15-minute cutoff, 10-30-minute range, and five-second crossfade setting. Merely having a file in `scripts` does not count as a pass.

When using the Lua script directly in a visible MPV window, press **F8**. Its status explicitly says **standalone** and **sequential fade (no overlap)**. To get crossfades, launch through `Radio.ps1`. The controller explicitly loads this script once and disables automatic loading of other scripts in its two managed players. It requires MPV with Lua and `user-data` support (tested from MPV 0.37).

## History, privacy and limits

All histories stay on this PC under `C:\MPV\portable_config`; they are not uploaded or synchronized.

| File | Purpose |
| --- | --- |
| `recent-track-history.txt` | Last 10 accepted starts: timestamp, video ID and title. Not proof a song finished. |
| `random-start-history.txt` | Last 10 selected long-track percentages. |
| `heard-sections.txt` | Estimated played ranges, recording ID, duration, last-heard time and title; final column is readable `minutes:seconds-minutes:seconds`. |
| `heard-sections.txt.bak` | Previous complete section checkpoint, used for recovery. |

The recent-track exclusion window is separate from history retention: at most five recent starts, reduced using the number of **unique** videos so small/duplicate-filled playlists remain playable. The controller keeps an in-memory shuffled pass; its remaining queue is rebuilt on restart. Ten-track history persists across restarts.

Section history skips paused, buffering, muted and detected seek gaps, and refuses to bridge long timer gaps such as computer sleep. It estimates **player activity**, not human attention or physical sound output; silent media or a powered-off external speaker cannot be detected reliably. Precision is roughly the polling interval, not sample-accurate audio measurement.

Section history checkpoints every **15 seconds** by default and at normal file transitions/shutdown. A force-kill can lose the unsaved tail (normally up to a checkpoint interval, potentially longer during blocked execution or write failures). Complete files are rotated through a backup. The controller serializes checkpoints and merges both players' intervals into the shared history. Do not run a separate standalone radio script at the same time; that unmanaged writer is not coordinated.

By default the section log retains up to **40 intervals per recording**, **2,000 overall**, and **180 days**. Recent overlap uses a **14-day half-life**; these are configurable in the template. Large changes to a recording's duration make old offsets ineligible for selection, rather than assuming an edited timeline still matches. Unknown-duration/non-seekable streams are left to ordinary MPV playback.

## Update an existing working computer

GitHub changes do not update your computer automatically. **Crossfading requires the controller files and a one-time task-action change; replacing Lua alone is insufficient.**

1. Stop the old music tasks and close their MPV players. Back up `C:\MPV\portable_config` outside its `scripts` folder, and export your music tasks.
2. Download and extract the repository ZIP. Copy the **contents of `payload`** into `C:\MPV`, replacing the included files. The payload contains no `mpv.conf` or playback histories, so your speaker and history files are retained. This does replace `script-opts\random-start.conf` with the new active defaults; retain your backup if you customized other options.
3. In each existing music task's **Actions**, remove its two old actions and create the single PowerShell action shown in [manual step 7](MANUAL-SETUP.md#7-create-the-morning-task-manually). Keep your triggers and days. Use your own existing duration in `-DurationSeconds` (3 hours = 10800).
4. Set Task Scheduler's backup stop limit one minute longer than that duration (3 hours + 1 minute for 10800). The controller itself stops at the requested duration; the extra minute is cleanup protection.
5. Run the task, then open **Check Radio.cmd** and verify both PASS reports. Confirm the physical speaker and listen through a transition.

You do not need to reinstall MPV or repeat audio-device setup. Existing tasks that still launch `mpv.exe` directly will sample with the updated Lua, but cannot overlap tracks. Remove/disable old duplicate tasks that could still force-kill all MPV processes.

## Scheduler, safeguards and troubleshooting

Each task uses one PowerShell action to run `Radio.ps1` with its playlist and duration. A new radio session asks the previous controller for the same installation to stop, then starts its own players. Unrelated MPV windows are left alone. If the controller is force-killed, a missing-heartbeat watchdog stops its hidden players after 15 seconds; the latest unsaved history can be lost.

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

See the tests and workflows for reproducible checks. Section tests simulate MPV events and file errors; headless smoke tests use generated local media and verify two advancing streams with overlapping gains. They do not test YouTube or a physical speaker. Windows tests validate installer inputs and that the complete Lua code in the manual matches the shipped file.

Project automation code uses the MIT license. See `THIRD_PARTY.md` for upstream licenses. Sample playlists are suggestions, not music distributed by the project or permission for public/commercial playback. Do not publish personal authentication files or listening logs.

## Alternative: set everything up manually (no installer)

**[Open the complete manual setup guide](MANUAL-SETUP.md).** It includes the folder structure, audio device selection, `mpv.conf`, the **entire current Lua script**, active sampling configuration, controller files, sample playlists, the Task Scheduler action and testing steps. Use this instead of the installer, not as an additional installation that creates duplicate tasks.
