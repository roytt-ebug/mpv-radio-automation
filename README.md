# MPV Radio Automation for Windows

**Scheduled YouTube background music, using one MPV player.**

Choose a playlist, speaker and schedule. Ordinary songs play normally; long mixes start in a less recently heard section and rotate after a limited listening period. The project adds a small Windows launcher and a Lua script to separately installed **mpv + yt-dlp**.

## What it does

- Starts morning/day-finisher playlists using Windows Task Scheduler and your selected audio output.
- Uses MPV's playlist shuffle, with an adaptive recent-track filter that keeps small playlists playable.
- Retains the last **10 accepted track starts** with their original timestamps and titles.
- Remembers estimated played sections separately for each long recording and favors less recent overlap.
- Provides clipboard shortcuts for audio or video capped at 720p. These play normally and bypass radio histories.

| Setting | Default | Meaning |
| --- | --- | --- |
| Eligibility cutoff | **15 minutes** | Only seekable recordings at least this long receive smart seeking and sampling. |
| Sampling | **On** | Rotate between sections of long recordings. |
| Sample length | **10-30 minutes** | Choose a new allowance per recording, capped to its duration. |
| Sample fade-out | **5 seconds** | Fade the current sample, then load the next track. Set to zero to disable. |
| Session duration | **3 hours** | Maximum runtime of the whole session, including loading and pauses. |

**Crossfade has been removed.** There is one MPV window, with no second decoder, preloading controller, or shared-history coordination. The existing simple sample fade-out remains; tracks never overlap. YouTube loading can leave a gap.

A 15-minute recording cannot supply a 30-minute sample. Its allowance is capped at 15 minutes and its start is chosen early enough to fit it. Short songs receive no automatic seek or sampling cutoff.

**Status: test build.** Automated checks use generated local audio and simulated inputs. Test your own YouTube connection, speaker and Windows schedule before relying on unattended playback.

## Quick start: guided setup

1. Install MPV yourself from the [official installation page](https://mpv.io/installation/). This project has used [Shinchiro Windows builds](https://github.com/shinchiro/mpv-winbuild-cmake/releases). For an x64 PC choose `mpv-x86_64-...7z`, not developer, 32-bit or ARM packages. Extract the **whole build** into `C:\MPV`, including `mpv.exe` and `mpv.com`.
2. On this repository choose **Code -> Download ZIP**. Extract the whole project to a separate folder. Keep `INSTALL.cmd`, `Install.ps1`, and `payload` together.
3. Run `INSTALL.cmd` as the Windows user who will listen. Setup requests elevation while carrying that user's identity forward. It does not install or replace MPV.
4. Select a detected speaker by **number**. At each playlist question, type **S** for the displayed sample, paste your own URL, or press **Enter to skip** that task.
5. Enter schedules using the examples below, review the summary, and type **YES** to save. Existing matching files/tasks are backed up first; playback histories are retained. Missing yt-dlp is downloaded from upstream only after approval.
6. In Task Scheduler, right-click a configured task and choose **Run**. Check the speaker, playlist, and repeat behavior before waiting for the next scheduled start.

The guided installer is **revision 6**. It builds the small `Radio-Hidden.exe` starter from included source using Windows' existing .NET Framework, then creates one starter action per radio task. No extra download or developer tools are needed. PowerShell still supervises the same single MPV player, without a console window. See [sample playlists and existing-task instructions](EXAMPLE-PLAYLISTS.md).

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
| Maximum runtime | `1.5` | One hour thirty minutes. |
| Maximum runtime | `0.75` | Forty-five minutes. |
| Maximum runtime | `11.5` | Eleven hours thirty minutes. |
| Maximum runtime | `24` | Twenty-four hours; the maximum. |
| Confirmation | `YES` | Apply the reviewed changes; Enter defaults to NO. |

**Maximum runtime is a DURATION, not the time of day to stop.** Enter a number of hours only, using a decimal point for fractions. `45` and `96` exceed the 24-hour maximum; `45 min`, `1:30` and unit words are rejected. A start of 18:35 plus 1.5 hours has an approximate stop of 20:05, assuming an on-time uninterrupted run. Defaults remain Morning **06:45, Mon-Sat, 3 hours** and Day Finisher **15:45, Mon-Fri, 3 hours**. All clock times use the computer's local time.

The installer validates URL structure, not playlist existence or playback rights. Share/index/time parameters are removed from scheduled playlist URLs. Skipping a task does not disable or remove an existing task; use Task Scheduler for that.

## Playback and settings

Edit `C:\MPV\portable_config\script-opts\random-start.conf`, then restart MPV:

```ini
section_mode=yes
min_duration_minutes=15
section_min_minutes=10
section_max_minutes=30
fade_seconds=5
```

`section_mode=no` plays long mixes without a sampling limit, while retaining smart starting points. `fade_seconds=0` disables the sample fade-out. There is no crossfade setting.

MPV supplies [shuffle, seeking, script options, audio routing and playback controls](https://mpv.io/manual/stable/). Lua supplies our history and section-selection rules. `Radio.ps1` only starts/stops one MPV and enforces the whole-session duration. The launcher explicitly loads this Lua script once and disables automatic loading of other scripts for scheduled playback.

Use MPV's normal controls in its window: **Space** pauses, **>** selects the next playlist entry, **9/0** adjusts volume, and **Q** quits. **Stop Radio.cmd** stops this installation's radio. Other MPV windows are left alone. Sampling counts forward, unmuted playback; the whole-session runtime also counts pauses and loading.

### Verify that MPV is listening

Press **F8 in the MPV window** to display the loaded Lua version and settings. During a scheduled radio session, **Check Radio.cmd** additionally connects to that actual MPV through a local Windows named pipe and waits for a fresh Lua acknowledgement. One PASS should show cutoff `15`, sampling enabled and range `10` to `30`. Check the physical speaker by listening. Directly launched MPV instances use F8; they do not necessarily have the launcher's diagnostic pipe.

Use an MPV build with Lua and `user-data` support (tested from 0.37). No Python or extra PowerShell modules are required to play music.

## History and selection

Histories stay in `C:\MPV\portable_config` and are never uploaded by this project:

| File | Contents |
| --- | --- |
| `recent-track-history.txt` | Last 10 accepted starts: original timestamp, video ID and title. |
| `random-start-history.txt` | Last 10 selected starting percentages. |
| `heard-sections.txt` | Estimated played intervals per recording, including readable ranges such as `42:37-68:10`. |
| `heard-sections.txt.bak` | Previous complete section checkpoint for recovery. |

Repeat blocking is separate from history retention: at most five recent starts, reduced according to the number of unique videos to leave choices in small playlists. MPV shuffles playlist entries; duplicate entries are not removed. The shuffled queue is rebuilt on restart, while history persists.

Smart starts stay within 0%-75% and favor less recently played overlap in that recording. Sampling narrows this range to leave room for the selected allowance; percentage exclusions relax if necessary. With sampling off, scoring looks ahead up to 20 minutes. This is a preference for variety, not a guarantee of never repeating audio.

Section tracking excludes pauses, buffering, muted playback and detected seeks. It estimates player activity, not whether someone heard the physical speaker. It saves about every 15 seconds and on normal file transitions/shutdown. Abrupt termination or write failures can lose the unsaved portion. History is bounded to 40 intervals per recording, 2,000 overall and 180 days by default; recent overlap has a 14-day half-life. Unknown-duration and nonseekable sources play normally.

Only one radio script should write these history files at a time. Scheduled launchers coordinate starts for the same installation. Avoid running the script separately alongside the scheduled player; clipboard launchers already disable it.

## Update an existing working computer

GitHub changes do not automatically update your PC. **This update adds only the hidden-start helper; `Radio.ps1`, Lua, sampling settings and all three histories are unchanged.**

### Hidden-start-only upgrade (already using Radio.ps1)

No reinstall or replacement of `portable_config` is needed.

1. Stop the music using **Stop Radio.cmd**. Export your music tasks as a backup.
2. Download a fresh repository ZIP. Copy only `payload/Radio-Hidden.cs` and `payload/Build-HiddenStarter.ps1` into `C:\MPV`. Keep your existing `Radio.ps1`, Lua, settings and histories.
3. In PowerShell or Command Prompt run this once:

   ```text
   powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\MPV\Build-HiddenStarter.ps1"
   ```

   It builds `C:\MPV\Radio-Hidden.exe` locally. It will not overwrite an existing helper: for a future rebuild, stop the radio and move the old executable into your backup first. If Windows/security policy blocks compilation or execution, stop and report it; do not disable protection.
4. In each music task's **Properties -> Actions -> Edit**, change **Program/script** to `C:\MPV\Radio-Hidden.exe`. Remove the PowerShell options through `-File "C:\MPV\Radio.ps1"` from **Add arguments**. Keep the `-Playlist` and `-DurationSeconds` values exactly as they were. Keep **Start in** as `C:\MPV` and leave triggers, conditions and runtime settings alone. For example, a two-hour Day Finisher uses:

   ```text
   -Playlist "https://www.youtube.com/playlist?list=PLBejJIaDgbyQ" -DurationSeconds 7200
   ```

5. Run the task. Check the MPV controls, F8 and **Check Radio.cmd**, then **Stop Radio.cmd**. Scheduled starts should no longer create a PowerShell terminal. Manually opened diagnostic/CMD windows are intentionally unchanged.

To undo just this update, restore the exported task actions; no playback or history files need changing. On failure, check Task Scheduler's **Last Run Result** and `C:\MPV\Radio-Hidden-error.log`. The log contains the latest helper/PowerShell failure, is bounded, and is not erased on success: check its timestamp. If that folder is unwritable, the nonzero task result is still returned but the log may be unavailable.

### Older installations (including the former crossfade build)

1. Stop the music task and close its MPV windows. Back up `portable_config` outside its `scripts` folder and export the music tasks.
2. Download and extract a fresh repository ZIP. Copy the **contents of `payload` into `C:\MPV`**, replacing included files. Copy all files, including `Play-YouTube.ps1`; do not replace just the Lua script. The payload contains no `mpv.conf` or history files, so your speaker and histories are retained. Its `random-start.conf` supplies the defaults above; keep your backup if you customized settings.
3. Build `Radio-Hidden.exe` using the command above, then use the new helper action. Keep your existing playlist, duration and triggers. MPV's normal player window remains available.
4. **If your older task runs taskkill followed by `mpv.exe`,** replace those two actions with the single action in [manual step 7](MANUAL-SETUP.md#7-create-the-morning-task-manually). Preserve your triggers, days and intended duration. Disable duplicate legacy tasks that still kill all MPV windows.
5. Run a music task. Confirm one MPV window, press F8, and run **Check Radio.cmd**. Listen through a sample transition.

The old crossfade version may leave `radio-session.json` behind. The new code does not read it; it can be deleted after stopping playback. No MPV reinstall or speaker reconfiguration is needed for the payload update.

## Scheduler and installation safeguards

Each task runs one `Radio-Hidden.exe` action. This launch-only helper starts the adjacent, unchanged `Radio.ps1` with Windows' **CreateNoWindow** setting, waits for it and returns its exit code to Task Scheduler. It does not choose tracks, change volume, manage history or replace the supervisor's stop logic. MPV starts with its terminal disabled; its normal playback window stays available. A new session asks the previous radio launcher for the same installation to stop and waits before opening one MPV. Normal shutdown asks MPV to quit and save history; forced cleanup is restricted to the exact process started by that launcher.

The launcher and Lua independently enforce the requested runtime. If the launcher is forcibly terminated, MPV can remain open until its Lua session limit; close its visible window or use Stop Radio. Task Scheduler's backup stop limit is one minute longer than the intended duration to allow cleanup.

Tasks require the chosen Windows user to remain logged in; a locked session is okay. Wake-to-run is requested, missed-start catch-up is off, and failures can retry every five minutes up to three times. Duplicate starts of the same task are ignored. Wake timers, power conditions, sleep and the speaker still depend on Windows/hardware; a powered-off PC is not started by these tasks.

Setup validates inputs, shows a review before saving, and backs up replaced configuration, matching tasks and shortcuts under `C:\MPV\setup-backups`. It stops its radio before updating and asks you to close other MPV windows from that installation. Unexpected failures show a stage and error-log path. Partial installation has **no automatic rollback**; use the backup and inspect tasks before retrying. Skipping an existing task leaves it unchanged.

Clipboard shortcuts accept one YouTube URL and pass it directly to MPV without placing pasted text in a Command Prompt command. They stop only this installation's radio before opening manual playback.

Windows Terminal has a [documented issue with `-WindowStyle Hidden`](https://github.com/microsoft/terminal/issues/12464). The helper avoids creating a PowerShell console in the first place, using [Windows' documented no-window process setting](https://learn.microsoft.com/en-us/dotnet/api/system.diagnostics.processstartinfo.createnowindow). It does not change the default terminal application or security policies. It is built locally from reviewable source, not supplied as an opaque downloaded executable. Managed computers may restrict local compilation or unsigned executables; report such restrictions rather than bypassing them.

## Troubleshooting and checks

```bat
C:\MPV\mpv.com --no-config --load-scripts=no --audio-device=help
C:\MPV\yt-dlp.exe --version
C:\MPV\yt-dlp.exe -U
```

Use the entire detected `wasapi/{GUID}` device ID. Enable File Explorer's **File name extensions** to avoid `.lua.txt` or `.conf.txt`. Keep script backups outside `scripts` so MPV cannot load them twice.

For YouTube extraction failures, follow [yt-dlp's current JavaScript-runtime guidance](https://github.com/yt-dlp/yt-dlp/wiki/EJS). This installer downloads a missing yt-dlp from upstream but does not install the separate JavaScript runtime. Network, upstream or regional restrictions can still prevent playback.

Tests cover input validation, Windows task definitions, history, seeking, sample transitions, bounded runtime, scoped shutdown and a live Lua acknowledgement. Local media tests do not verify YouTube or a physical speaker. The manual's full Lua block is checked against the shipped script.

GitHub Actions checks run on pull requests and pushes to `main`, not again on every development-branch push. Superseded runs are cancelled. A failed-run email concerns repository tests, not a fault reported by your installed player. Account notification preferences remain under your control in [GitHub notification settings](https://github.com/settings/notifications).

Project code uses the MIT license. See [THIRD_PARTY.md](THIRD_PARTY.md) for upstream dependencies. Sample playlists are contributor-approved suggestions; no music, credentials or third-party executables are distributed here.

## Alternative: set everything up manually (no installer)

**[Open the complete manual setup guide](MANUAL-SETUP.md).** It includes folder layout, speaker selection, `mpv.conf`, the entire current Lua script, sampling settings, launcher files, sample playlists and exact Task Scheduler actions. Follow it instead of the installer to avoid duplicate tasks.
