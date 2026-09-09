# MPV Radio Automation for Windows

**Scheduled YouTube music, with variety across songs and long mixes.**

Choose your playlists, speaker, and schedule. The player shuffles ordinary songs and plays them normally. For long recordings, it remembers which sections played, chooses a less recently heard starting area, and optionally moves to another recording after a sample.

The project uses **one MPV player**, yt-dlp for YouTube playback, and Windows Task Scheduler. MPV's playback controls stay visible while its PowerShell supervisor runs without a terminal window.

**Status: early test build for Windows x64.** Automated checks pass, but test your own scheduled playback and speaker before relying on it unattended.

## Defaults and adjustable limits

| Setting | Default | Allowed range or choice | Meaning |
| --- | --- | --- | --- |
| Eligibility cutoff | **15 minutes** | 0.01–1,440 minutes | Only recordings at least this long receive smart starting points and optional sampling. They must have a known duration and allow seeking. |
| Sampling | **On** | On or Off | On rotates between samples of long recordings. Off lets them continue from their smart starting point. |
| Minimum sample length | **10 minutes** | 0.01–1,440 minutes; no greater than the maximum | Shortest playback allowance to choose for each eligible recording. |
| Maximum sample length | **30 minutes** | 0.01–1,440 minutes; no less than the minimum | Longest playback allowance to choose. Shorter recordings finish sooner. |
| Sample fade-out | **5 seconds** | 0–60 seconds | Fade the sample, then load the next track. Zero turns the fade off. |
| Session duration | **3 hours** | 1 minute–24 hours, entered as hours | Maximum runtime of the entire scheduled session, including pauses and loading. |

The ranges show what the current settings accept, not suggested listening lengths: **1,440 minutes = 24 hours**. Sample allowances use whole seconds, with a minimum of one second. Keep the sample minimum at or below the maximum; an invalid pair falls back to 10–30 minutes.

For example, an eligible 15-minute mix cannot supply a 30-minute sample. Its allowance is shortened to fit, and the starting point leaves room for it. Tracks play one after another; YouTube loading can leave a gap.

Change session duration during setup. Change the other settings in the [sampling settings file](#change-sampling-settings).

## Install and try it

1. **Install MPV separately.** Start at [MPV's installation page](https://mpv.io/installation/). This project uses [Shinchiro Windows builds](https://github.com/shinchiro/mpv-winbuild-cmake/releases). For Windows x64, choose `mpv-x86_64-...7z` and extract the **whole archive** into `C:\MPV`, including `mpv.exe` and `mpv.com`.
2. **Download this project:** choose **Code → Download ZIP**, then extract it to a separate folder. Keep `INSTALL.cmd`, `Install.ps1`, and `payload` together.
3. **Run `INSTALL.cmd`** from the Windows account that will play the music. Accept the Windows administrator prompt when asked. The installer does not install or replace MPV.
4. **Choose your speaker, playlists, and schedules** using the examples below. Review the summary and type **YES** to save.
5. **Test a task:** open **Task Scheduler**, right-click **Music - Morning** or **Music - Day Finisher**, and choose **Run**. Confirm that MPV opens and music comes from the selected speaker.

The installer is **revision 8**. It downloads yt-dlp only if missing, verifies the download's checksum, and builds the small `Radio-Hidden.exe` helper from included source. Deno is an [optional recommendation](#optional-recommendation-deno).

Setup backs up files and matching tasks it replaces in `C:\MPV\setup-backups`. Running setup again can reset custom playback settings; listening-history files are retained unless you delete them. If setup fails, it shows the failed step and an error-log location; it does not automatically undo completed changes.

### Exactly what to type

Type only your answer, not the prompt or brackets. **Enter accepts a displayed default; Q cancels at an input prompt.** At a playlist question, an empty answer skips that task.

| Question | Example answer | Meaning |
| --- | --- | --- |
| Speaker | `2` | Use speaker number 2 in your detected list. No device code to copy. |
| Playlist | `S` | Use the sample displayed for this task. |
| Playlist | Full `https://www.youtube.com/playlist?list=...` URL | Use your own playlist. Paste the actual link, without quotes or extra commands. |
| Playlist | Press Enter on an empty line | Skip this task and its remaining questions. An existing task is left unchanged. |
| Start time | `06:45`, `0645`, or `6:45 AM` | 6:45 in the morning. |
| Start time | `18:35`, `1835`, or `6:35 PM` | 6:35 in the evening. |
| Days | `1` / `2` / `3` / `4` | Monday–Friday / Monday–Saturday / every day / weekends. |
| Custom days | `MON,WED,FRI` | Only Monday, Wednesday, and Friday. |
| Maximum runtime | `3` | Three hours. |
| Maximum runtime | `1.5` | One hour thirty minutes. |
| Maximum runtime | `0.75` | Forty-five minutes. |
| Maximum runtime | `11.5` | Eleven hours thirty minutes. |
| Maximum runtime | `24` | Twenty-four hours; the maximum. |
| Confirmation | `YES` | Save the reviewed changes. Enter defaults to NO. |

**Maximum runtime is a DURATION, not the time of day to stop.** Enter hours as a number, using a decimal point for fractions. For 45 minutes, enter `0.75`; `45` exceeds the 24-hour limit. Formats such as `45 min` and `1:30` are not accepted for duration.

| Suggested task | Start time | Days | Duration |
| --- | --- | --- | --- |
| Morning Music | 06:45 (6:45 AM) | Monday–Saturday | 3 hours |
| Day Finisher | 15:45 (3:45 PM) | Monday–Friday | 3 hours |

All times use your computer's local clock. You can change these suggestions during setup. [Listen to the sample playlists](EXAMPLE-PLAYLISTS.md).

### Optional recommendation: Deno

**Deno helps yt-dlp handle YouTube's JavaScript checks and find playable audio.** Some playlists work without it. Consider adding it if YouTube playback reports JavaScript/signature errors or missing formats. It does not fix every playback problem. [yt-dlp's runtime guidance](https://github.com/yt-dlp/yt-dlp/wiki/EJS)

The installer recommends Deno but **continues without it**. It does not download Deno automatically.

#### Choose the right download

Open **Settings → System → About → System type**, then choose the matching ZIP from the [official Deno release assets](https://github.com/denoland/deno/releases/latest). Expand **Show all assets** if needed.

| Windows System type | Deno ZIP to choose |
| --- | --- |
| **64-bit operating system, x64-based processor** (Intel or AMD) | **`deno-x86_64-pc-windows-msvc.zip`** |
| **64-bit operating system, ARM-based processor** (ARM64, for example Snapdragon) | `deno-aarch64-pc-windows-msvc.zip` |
| **32-bit operating system** | No current official Windows 32-bit Deno download. Do not choose a 64-bit ZIP. |

Use stable **Deno 2.3.0 or newer** for yt-dlp. Deno requires Windows 10 version 1709 or newer, including Windows 11. The ARM entry above describes Deno; this radio project is tested for **Windows x64**, not ARM or 32-bit Windows. [Deno's installation requirements](https://docs.deno.com/runtime/getting_started/installation/)

| Other asset names | What they mean |
| --- | --- |
| `apple-darwin` / `unknown-linux-gnu` | macOS / Linux downloads. |
| `.from-...bsdiff` | Update patches, not the complete program. |
| `.sha256sum` | Checksum text, not the program. For ZIP verification, use its matching `.zip.sha256sum` from the same release. |
| `denort`, `libdenort`, `.d.ts`, source archives | Developer/runtime files; choose the full **`deno-...zip`** instead. |

#### Where to put it

Extract **`deno.exe` directly into `C:\MPV`**, beside `mpv.exe` and `yt-dlp.exe`. Do not leave it inside the ZIP, a temporary WinRAR folder, or an extra subfolder. You do not need to leave a Deno window open.

To check it, run `C:\MPV\deno.exe --version` in Command Prompt or PowerShell. Restart MPV after adding it.

**Putting Deno in `C:\MPV` is the simplest option.** Windows can otherwise make a program available to one user but not another. This location lets our setup find the intended copy without changing Windows settings. If Deno is already installed and setup finds it, no extra copy is needed. Test your music task afterward to confirm actual playback.

## Change sampling settings

Edit `C:\MPV\portable_config\script-opts\random-start.conf`, then restart MPV:

```ini
section_mode=yes
min_duration_minutes=15
section_min_minutes=10
section_max_minutes=30
fade_seconds=5
```

The [defaults table](#defaults-and-adjustable-limits) explains each value and its limits. `section_mode=no` turns sampling off while keeping smart starting points. `fade_seconds=0` turns the sample fade-out off. Enable File Explorer's **File name extensions** so the file does not accidentally become `random-start.conf.txt`.

## Controls and a quick playback check

| Control | Action |
| --- | --- |
| Space in MPV | Pause or resume. |
| `>` in MPV | Next playlist entry. |
| `9` / `0` in MPV | Lower / raise volume. |
| Q in MPV | Quit playback. |
| F8 in MPV | Show the loaded radio script and its settings. |
| `C:\MPV\Check Radio.cmd` | Check that the scheduled MPV and radio script both respond. |
| `C:\MPV\Stop Radio.cmd` | Stop this installation's radio. |

With default settings, the radio check should show a **15-minute cutoff**, sampling **on**, and a **10–30-minute** range. Listen to confirm the selected speaker. Clipboard audio/video shortcuts play a copied YouTube link normally, without updating the radio histories; video is capped at 720p.

Keep the selected Windows user logged in; locking the screen is fine. The task can request wake from sleep, but it cannot turn on a powered-off computer. Test sleep/wake and speaker availability on your PC. A missed start is not automatically caught up; use **Run** to test immediately.

## Listening history

History is stored locally in `C:\MPV\portable_config`:

| File | What it remembers |
| --- | --- |
| `recent-track-history.txt` | The last 10 accepted track starts, with dates and titles. |
| `random-start-history.txt` | The last 10 selected starting percentages. |
| `heard-sections.txt` | Played sections for each recording, such as `42:37–68:10`. |
| `heard-sections.txt.bak` | A previous section-history save for recovery. |

Remembering ten tracks does not block all ten from playing again: repeat protection adjusts for small playlists. Smart starts favor less recently heard portions, but cannot guarantee no repeated audio. Section history excludes pauses, buffering, muted playback, and detected seeks; it estimates playback rather than whether someone heard the speaker. It saves about every 15 seconds and on normal stops. A forced shutdown can lose the latest unsaved portion.

## Start over with a fresh setup

For an earlier test installation, this is the simplest way to reset everything:

1. Run **Stop Radio.cmd** and close MPV.
2. Open **Task Scheduler → Task Scheduler Library**. Delete only this project's music tasks, normally **Music - Morning** and **Music - Day Finisher**, including any older copies you renamed.
3. In File Explorer, open `C:\MPV` and delete **`portable_config`**. **This removes your speaker/sampling settings and all listening history.** Copy that folder elsewhere first if you want to keep a backup.
4. Download and extract a fresh project ZIP, then run **`INSTALL.cmd`** and choose your speaker, playlists, and schedules again.
5. Run each new task once to check playback.

Keep MPV, yt-dlp, and any optional `deno.exe` in `C:\MPV`. The installer replaces its own helper files. You do not need to reset a working installation just because this documentation changed.

## Troubleshooting

| Problem | What to check |
| --- | --- |
| Task does not start | Confirm its next run time, enabled state, selected Windows user, and that the user is logged in. |
| Wrong speaker or no sound | Check MPV's volume and the chosen output; rerun setup to select a different device. |
| YouTube extraction fails | Run `Update yt-dlp.cmd`; consider [Deno](#optional-recommendation-deno). Also check the link and internet connection. Setup validates the URL format, not whether every playlist entry can play. |
| Radio settings seem ignored | Restart MPV, press F8, and run `Check Radio.cmd`. Keep script backups outside the `scripts` folder. |
| Task starts but no MPV appears | Check Task Scheduler's **Last Run Result** and `C:\MPV\Radio-Hidden-error.log`. Check the log's date; a later success does not erase it. |
| Antivirus examines or blocks the helper | Record the product name and exact message. The helper is built locally and unsigned; do not disable protection to complete setup. |
| yt-dlp download verification fails | Read the setup error and retry the official download later. The installer does not accept a download with a missing or mismatched checksum. |

Checksum verification applies to **newly downloaded yt-dlp**. An existing copy is retained and is not checked again by this installer. A checksum confirms agreement with the upstream file list; it is not a malware-free certification.

Report problems through [GitHub Issues](https://github.com/roytt-ebug/mpv-radio-automation/issues), including the installer revision and exact error. Remove private account details before sharing logs or screenshots.

Project code is [MIT licensed](LICENSE). MPV and yt-dlp are obtained separately; see [third-party software notes](THIRD_PARTY.md). Automated [GitHub checks](https://github.com/roytt-ebug/mpv-radio-automation/actions) cover installer inputs, task definitions, history, sampling, and local-audio playback; they do not test your physical speaker or YouTube connection.

## Alternative: set everything up manually (no installer)

[Open the complete manual setup guide](MANUAL-SETUP.md) for folder layout, speaker selection, configuration, the full Lua script, and exact Task Scheduler entries. Use it as an alternative to guided setup.
