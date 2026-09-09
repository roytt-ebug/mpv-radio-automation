# MPV Radio Automation for Windows

A small Windows toolkit that turns MPV + yt-dlp into an automated YouTube background-music / radio system.

Looking for music to try? See the [optional Day Finisher playlist recommendation](EXAMPLE-PLAYLISTS.md). It is not selected automatically; users still choose their own playlist URLs.

## What it does

- Plays a shuffled YouTube playlist on a schedule, using a selected audio output.
- Can request waking a sleeping PC and play while the selected user is logged in but the screen is locked.
- Stops an older accessible mpv.exe before a scheduled session starts.
- Remembers recently played tracks across sessions.
- Tracks under 20 minutes are not randomly seeked; tracks 20 minutes or longer get a random 0%-75% starting point.
- Remembers the last 10 random-start percentages and avoids exact recent repeats.
- Includes clipboard launchers for audio-only playback and an always-on-top, resizable video window with video limited to 720p and best available audio.

**Status:** early test build. Windows installer-input tests are provided in `tests/Test-InstallerInput.ps1`. Passing them does not establish that a particular speaker, YouTube playlist or sleep/wake setup works. Always test playback on your computer.

## Requirements

Windows 10/11 x64, Windows PowerShell 5.1, internet access, and MPV installed manually in `C:\MPV`. The setup helper can download yt-dlp when missing, after you approve the setup summary. MPV and yt-dlp binaries are not bundled; see `THIRD_PARTY.md`.

## Quick install

1. Install MPV yourself first. The Windows build used during development is available from https://github.com/shinchiro/mpv-winbuild-cmake/releases . Use the normal x86_64 build, not dev, i686 or aarch64, on a normal x64 PC.
2. Extract the **whole MPV archive** into `C:\MPV`. Verify `C:\MPV\mpv.exe` and `C:\MPV\mpv.com` exist.
3. On this repository choose **Code -> Download ZIP**. Extract the whole project ZIP into a separate folder. Keep `Install.ps1`, `INSTALL.cmd` and the `payload` folder together.
4. Double-click `INSTALL.cmd` in that extracted project folder. Do not run it from inside the ZIP. Start it as the Windows user who will listen; setup will request elevation and carry that user's identity forward.
5. Select an audio output by **number**. Then supply playlists, start times, days and maximum runtimes using the examples below.
6. Review the summary, including speaker name, Windows account, times and approximate stops. Type **YES** to apply. Nothing is saved merely by answering the input questions.
7. In Task Scheduler, right-click a configured music task and choose **Run** to test it.

The updated installer identifies itself as **guided setup (revision 2)**. It re-prompts on invalid input instead of crashing later. MPV is never installed or replaced by this helper.

## Exactly what to type at each prompt

**Type only the answer and then press Enter.** Do not copy prompt labels or square brackets. A displayed `[Enter = ...]` is a default: press Enter without typing to accept it. Type `Q` at an input prompt to cancel.

### 1. Audio output

The installer displays a numbered list of **your detected devices**. For example:

```text
1. Autoselect device [follows Windows default; NOT a dedicated output]
2. Speakers (Example USB speaker)
3. Headset (Example headset)
Audio output number (no default):
```

To choose the USB speaker in this example, type just `2` and press Enter. Use the number shown beside the desired device on YOUR computer; device order is not fixed.

No GUID needs copying. For compatibility, the revised installer also accepts a complete detected `wasapi/{GUID}` ID or a bare GUID, but it only accepts one that matches a device in the detected list. Autoselect follows the Windows default rather than pinning playback to a separate speaker. A monitor-named HDMI output and Realtek Speakers are different outputs.

### 2. Morning task, and then 3. Day-finisher task

Both tasks ask the same four questions. The task name does not restrict the chosen clock time; you can use an evening test time for the Morning task.

| Prompt | What to enter | Meaning / default |
| --- | --- | --- |
| YouTube playlist URL | Paste the complete link from your browser, without extra text | Must contain `list=`. Enter on an empty line skips this task and all its later questions. |
| Start time | `06:45`, `0645`, or `6:45 AM` | All mean 6:45 in the morning. Morning default is `06:45`. |
| Start time, evening example | `18:35`, `1835`, or `6:35 PM` | All mean 6:35 in the evening. Day-finisher default is `15:45` (3:45 PM). |
| Days | `1` | Monday-Friday; day-finisher default. |
| Days | `2` | Monday-Saturday; morning default. Sunday excluded. |
| Days | `3` | Every day, including Sunday. |
| Days | `4` | Saturday and Sunday only. |
| Custom days | `MON,WED,FRI` | Just those days. Full names and lowercase are accepted too. |
| Maximum runtime | `3` | Three hours of playback; default for both tasks. |
| Maximum runtime | `1.5` or `1:30` | One hour thirty minutes. |
| Maximum runtime | `45 min` | Forty-five minutes. |
| Final confirmation | `YES` | Back up and apply the displayed settings. Enter defaults to NO. |

**Start time is a clock time; maximum runtime is a duration, NOT an end time.** For example, a start of `18:35` and runtime of `1.5` means an approximate stop at `20:05` (8:05 PM), assuming an on-time uninterrupted run. The allowed runtime is 1 minute to 24 hours.

This URL is a **format example only**; replace it with your actual playlist:

```text
https://www.youtube.com/playlist?list=YOUR_PLAYLIST_ID
```

The installer normalizes a YouTube URL containing a playlist ID to its playlist URL, removing `si=`, `t=`, and other share/watch parameters. URL-format validation is not a check that the playlist exists or is playable. No personal playlists are included as defaults.

Leaving a task's playlist blank **does not delete or disable an existing task** with that name. It leaves that task unchanged. To stop an old task, use Task Scheduler to disable it.

All times use the computer's local clock. If today's selected start time has already passed, the task waits until the next selected day; use **Run** in Task Scheduler for an immediate test. Retries, delays and interruptions can alter the actual stop time.

## Failed setup / installing again

Close the old failed installer before retrying. Download the current repository ZIP and extract it again. Alternatively, replace only `Install.ps1` in your previously extracted project folder with the updated file; keep it beside the original `INSTALL.cmd` and `payload` folder. Do not put the setup helper in `C:\MPV` unless the matching payload is there too.

An earlier failed installer may already have written an incomplete audio ID into `mpv.conf`. Revision 2 ignores that config while listing devices, then writes the correctly selected ID when you approve.

Before replacing files, revision 2 makes a timestamped backup in:

```text
C:\MPV\setup-backups\YYYYMMDD-HHMMSS-fff\
```

It backs up the existing `mpv.conf`, project files it will replace, matching scheduled tasks as XML, and existing matching desktop shortcuts. It does not overwrite playback-history files. A warning identifies other root-level tasks that launch `C:\MPV\mpv.exe`; those tasks are left unchanged, so check for duplicate schedules.

The installer keeps unexpected error messages visible and writes details to a timestamped `MPV-Radio-Setup-error-*.txt` in your Windows temporary folder. The exact path is displayed. It does not perform an automatic rollback after a partial installation; the error screen identifies tasks already saved and the backup location. Keep backups and error logs private.

## Scheduled-task behavior

The helper creates or updates `Music - Morning` and/or `Music - Day Finisher`, only after approval. It builds two actions: first close accessible mpv.exe processes, then run:

```text
C:\MPV\mpv.exe --shuffle --loop-playlist=inf "YOUR_PLAYLIST_URL"
```

The working directory is `C:\MPV`. Tasks use the launching user's interactive session with limited privileges: a locked screen is okay, signing out is not. Settings request wake-to-run, retries every 5 minutes up to 3 times for task failures, no duplicate instance of the same task, and the selected maximum runtime. Missed-start catch-up is off. AC-power restrictions are retained; review them on a laptop. A wake request still depends on Windows/hardware support and enabled wake timers. Task Scheduler cannot start a fully shut-down PC.

**Starting either scheduled task closes accessible MPV windows, including manually opened MPV videos.** This is current behavior, not single-instance IPC control. Morning/evening schedules should not overlap unless taking over playback is intended.

## MPV configuration and radio behavior

The helper writes `C:\MPV\portable_config\mpv.conf`:

```text
audio-device=YOUR_SELECTED_DEVICE
vid=no
ytdl-format=bestaudio/best
force-window=yes
```

The script at `C:\MPV\portable_config\scripts\random-start.lua` keeps persistent recent-track history (up to five tracks, reduced for small playlists), leaves tracks under 20 minutes unseeked, and chooses a 0%-75% random start for longer tracks. It avoids the last ten exact random percentages and tries to stay at least six percentage points from the previous percentage. This is a recent-track filter plus MPV shuffle, not yet a complete persistent shuffle-bag implementation.

History files:

```text
C:\MPV\portable_config\random-start-history.txt
C:\MPV\portable_config\recent-track-history.txt
```

The revised installer does not redesign that Lua algorithm or its history format.

## Manual launchers

**Play YouTube on MPV Audio.cmd:** copy a YouTube URL, then double-click the launcher in `C:\MPV` or its desktop shortcut. Existing MPV playback stops and audio uses the configured device. The radio/random-start script is disabled for this manual playback.

**Play YouTube Video - 720p Best Audio Always On Top.cmd:** copy a link and open the video launcher. It opens a resizable always-on-top window, limits video to 720p or lower, and selects best available audio independently. MPV and yt-dlp handle separate audio/video streams. Radio scripts are disabled here too.

## Updating and troubleshooting

For YouTube failures, check `C:\MPV\yt-dlp.exe --version`, then use `C:\MPV\Update yt-dlp.cmd` to update from upstream. If extraction still fails, follow yt-dlp's current upstream guidance, including its JavaScript-runtime requirements; this installer does not install a JavaScript runtime.

To update MPV, replace its program files with a newer appropriate build while retaining `portable_config` and the custom launchers. To inspect output IDs independently of configuration:

```text
C:\MPV\mpv.com --no-config --audio-device=help
```

If output IDs change, rerun guided setup or correct the `audio-device=` line. For ignored files, enable File Explorer's **File name extensions** option: use `mpv.conf`, not `mpv.conf.txt`; use `random-start.lua`, not `random-start.lua.txt`.

For scheduler problems, verify the correct user is logged in, the selected speaker is powered/connected, wake timers permit waking, the task is enabled, and there is no duplicate older task. Test the selected output and a real playlist rather than relying only on successful installation.

## Third-party software and disclaimer

MPV and yt-dlp remain separate upstream projects and are not bundled here. See `THIRD_PARTY.md`. This project does not provide or redistribute music/video content. Users are responsible for permissions, licenses and service terms applicable to their listening or public playback.
