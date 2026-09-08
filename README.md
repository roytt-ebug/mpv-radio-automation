# MPV Radio Automation for Windows

A small Windows toolkit that turns MPV + yt-dlp into an automated YouTube background-music / radio system.

## What it does

- Plays a shuffled YouTube playlist on a schedule.
- Can wake a sleeping Windows PC for scheduled playback.
- Runs while Windows is locked, as long as the user is still logged in.
- Sends MPV to one selected Windows audio output while other Windows apps can use another output.
- Stops an older MPV instance before a scheduled session starts.
- Avoids recently played tracks.
- Remembers recent tracks across MPV restarts.
- Tracks under 30 minutes play from 0:00.
- Tracks 30 minutes or longer start at a random position from 0% to 75%.
- Remembers the last 10 random start percentages and avoids immediate/recent repeats.
- Includes clipboard launchers for audio-only YouTube playback and always-on-top 720p video with best available audio.

## Requirements

- Windows 10 or Windows 11, 64-bit
- Internet access
- MPV Windows x86_64 build installed manually by the user
- yt-dlp (the setup helper can download yt-dlp automatically)

This project intentionally does **not** bundle MPV or yt-dlp binaries. See `THIRD_PARTY.md`.

## Quick install

1. Install MPV yourself first. The Windows build used during development is available from the Shinchiro release page: https://github.com/shinchiro/mpv-winbuild-cmake/releases
2. Download the normal **x86_64** MPV build (not `dev`, `i686`, or `aarch64`) and extract the complete build into `C:\MPV`.
3. Download this repository with **Code -> Download ZIP** and extract it.
4. Double-click `INSTALL.cmd`.
5. The setup helper downloads `yt-dlp.exe` directly from the official yt-dlp release if it is missing.
6. The setup helper displays MPV's detected audio devices. Copy/paste the desired device identifier, for example `wasapi/{xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx}`.
7. Enter a morning playlist URL and/or a day-finisher playlist URL.
8. Enter the schedule, days, and maximum runtime for each task.
9. The setup helper creates the Windows Scheduled Tasks and desktop shortcuts.

The default MPV folder is `C:\MPV`.

## Scheduled-task behavior

The setup helper creates up to two tasks:

- `Music - Morning`
- `Music - Day Finisher`

Each task runs in the current user's interactive session, so a locked screen is okay but signing out is not. It kills any existing `mpv.exe`, starts MPV with `--shuffle --loop-playlist=inf`, wakes the PC from sleep when Windows wake timers permit it, retries failures every 5 minutes up to 3 times, ignores a second concurrent instance, and stops after the runtime you specify. It does not automatically run late just because a scheduled start was missed.

Task Scheduler cannot start a fully powered-off PC.

## MPV configuration

The setup helper generates:

`C:\MPV\portable_config\mpv.conf`

with:

```text
audio-device=YOUR_SELECTED_DEVICE
vid=no
ytdl-format=bestaudio/best
force-window=yes
```

## Radio-style Lua script

Installed here:

`C:\MPV\portable_config\scripts\random-start.lua`

Current behavior:

- Persistent recent-track history; protects up to the last 5 tracks.
- Persistent last-10 random-start percentages.
- Tracks shorter than 30 minutes start at 0:00.
- Tracks 30 minutes or longer start randomly from 0% to 75%.
- Exact recent percentages are not reused.
- The new random percentage tries to stay at least 6 percentage points away from the previous value.

History files are created automatically:

`C:\MPV\portable_config\random-start-history.txt`

`C:\MPV\portable_config\recent-track-history.txt`

## Manual launchers

### Play YouTube on MPV Audio

Copy a YouTube URL, then double-click `C:\MPV\Play YouTube on MPV Audio.cmd`. Existing MPV playback stops and the copied URL starts audio-only on the configured MPV output. The radio/random-start Lua script is disabled for manually selected items.

### Play YouTube Video - 720p Best Audio Always On Top

Copy a YouTube URL, then double-click the video launcher. It opens a resizable always-on-top MPV window, limits video to 720p or lower, and selects the best available audio stream independently. MPV + yt-dlp automatically handle separate YouTube audio/video streams.

## Updating

Run `C:\MPV\Update yt-dlp.cmd` if YouTube playback suddenly breaks. YouTube changes frequently, so updating yt-dlp is usually the first troubleshooting step.

To update MPV, download a newer normal x86_64 Windows build and replace the MPV program files while keeping `C:\MPV\portable_config\` and the custom `.cmd` files.

## Troubleshooting

List audio devices:

```text
C:\MPV\mpv.com --audio-device=help
```

If Windows changes the device identifier, update `audio-device=` in `C:\MPV\portable_config\mpv.conf`.

If the config or Lua script seems ignored, enable `File Explorer -> View -> File name extensions` and confirm the files are really named `mpv.conf` and `random-start.lua`, not `.txt` files.

Check yt-dlp:

```text
C:\MPV\yt-dlp.exe --version
```

For scheduled playback, confirm the user is still logged in, the speaker/output is powered and connected, and `Wake the computer to run this task` remains enabled.

## Third-party software

MPV and yt-dlp are separate open-source projects and are not included in this repository. See `THIRD_PARTY.md` for licensing and upstream links.

## Disclaimer

This project does not provide or redistribute music/video content. Users are responsible for ensuring that their use of third-party services and content complies with applicable rights, licenses, and service terms.
