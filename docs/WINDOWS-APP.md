# Automatic Music for Windows — desktop beta

Automatic Music is a small Windows application for scheduling YouTube playlists,
choosing an output speaker, and adjusting sampling of long recordings. Version
**0.2.0-beta.2** introduces the native app and a per-user installer.

## Supported Windows versions

- Windows **10 version 2004 or later** (build 19041+), **x64**; this includes Windows 10 Pro 22H2 (build 19045).
- Windows **11**, **x64**.
- Windows on ARM and 32-bit Windows are not supported by this build.

Windows 10 has reached the end of standard security support. A supported Windows 11 installation is preferable for an internet-connected music player. The beta is built and smoke-tested on hosted Windows Server runners; an actual Windows 10 22H2 desktop installation and audible YouTube playback still require end-user testing.

## First-time setup

1. Run **Automatic-Music-Setup-0.2.0-beta.2.exe** on Windows 10 version 2004 or later, or Windows 11, on an x64 (Intel/AMD) PC.
2. Open **Automatic Music** from the Start menu. No account or activation key is needed.
3. On **Setup**, install the playback components. Keep the internet connection
   available while MPV, yt-dlp and Deno download and are verified.
4. On **Music & schedule**, paste a YouTube playlist link, choose your speaker,
   and test the sound. A speaker test replaces the app's current playback.
5. Choose Morning or Day Finisher, select the days and start time, and set a
   duration. Enable the schedule when you want it to run automatically.
6. Save the settings and test playback. Confirm that you hear music from the
   selected speaker before relying on an unattended schedule.

The application can be closed after saving. Windows Task Scheduler starts the
saved sessions. Keep the listening Windows account signed in; the screen may be
locked. Wake-from-sleep is optional and depends on the PC's power settings.
The app cannot turn on a powered-off PC. Times use the Windows local clock.
Missed starts are not replayed automatically, and failed tasks do not restart
with a fresh full-length session.

## Controls and settings

- Separate Morning and Day Finisher playlists, enabled switches, weekdays,
  local start times, and durations.
- Speaker selection, a local test tone, volume, Play, Pause, Next, and Stop.
- Advanced sampling: eligibility cutoff, minimum/maximum sample lengths and
  fade-out duration. Defaults remain 15 minutes, 10–30 minutes and five seconds.
- One MPV player belongs to this installation. Starting a session or a speaker
  test replaces that player; unrelated MPV instances are left alone.
- Listening histories are retained across sessions. The existing ten-entry
  history behavior is unchanged.

An enabled schedule requires a playlist and at least one day. Blank disabled
sessions are allowed. A playlist URL passing the format check does not guarantee
that YouTube will allow access; use the playlist check and playback test.
Saved changes apply to the next playback session.

## Installation, data and updates

The installer runs for the current user, creates a Start-menu shortcut and adds
the normal Windows uninstall entry. It does not change the system PATH, default
speaker, firewall, Windows logon settings or persistent PowerShell policy.

| Item | Default location |
| --- | --- |
| Application | `%LOCALAPPDATA%\Programs\Automatic Music` |
| Preferences | `%LOCALAPPDATA%\Automatic Music\settings.json` |
| Playback config and history | `%LOCALAPPDATA%\Automatic Music\Player` |
| Downloaded playback components | `%LOCALAPPDATA%\Automatic Music\Components` |
| App diagnostics | `%LOCALAPPDATA%\Automatic Music\app.log` |

The app automatically downloads its pinned components directly from their
upstream release providers. Each download must match the SHA-256 recorded in
`components.lock.json` before extraction or execution. The install then runs
bounded version checks. MPV's complete archive is extracted using Windows'
`tar.exe` when its codec is supported. Older Windows builds that lack LZMA
support automatically download and SHA-256-verify a pinned, standalone official
7-Zip `7zr.exe` (approximately 600 KB) to extract MPV. No separate archiver
installation or manual steps are required.

Repair prepares a separate component bundle and activates it only after all
checks pass. A failed repair preserves the previous active bundle. Working
versions are retained for recovery. A future app update can ship a new reviewed
component lock file; the beta does not silently trust arbitrary latest binaries.

The optional portable ZIP contains the same app. Extract the entire folder and
run `AutomaticMusic.exe`. Settings still use the per-user data folder. If you
save schedules, keep that extracted folder in its permanent location. The
installer is recommended for ordinary use.

The beta uses unsigned project executables. Windows may show an unknown-publisher
or reputation prompt. Publisher signing is a distribution follow-up; the app
does not change or turn off Windows protections.

## Existing C:\MPV installations

The desktop beta uses a separate data folder and its own identified tasks.
It does not silently import, overwrite or disable the older toolkit's tasks.
If the older `Music - Morning` or `Music - Day Finisher` task is still enabled,
disable it after verifying the new app to prevent duplicate music sessions.
Keep the old installation until the new one has been tested with your speaker.

## Uninstall

Use **Settings → Apps → Installed apps → Automatic Music → Uninstall**.
Close the settings window first. The uninstaller stops this app's player and
removes only tasks that pass the app's ownership check. If cleanup cannot be
completed safely, it aborts and retains the program files.
Your separate preferences and listening-history folder is retained for
reinstallation. Removing that folder manually after uninstall is optional.

## Building and testing

The app uses Windows Forms and .NET Framework 4.8, included with supported Windows 10 and Windows 11.
It has no NuGet dependencies and does not require a separately installed .NET
runtime. Its source is in `app/`; the original PowerShell/Lua engine is retained.

On a Windows build machine with Inno Setup 6:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\installer\Build-App.ps1
```

The output is under `dist`: the installer EXE, an optional portable ZIP and
`SHA256SUMS.txt`. `-SkipInstaller` builds the portable app without Inno Setup.
Build into a fresh output directory to avoid mixing old and new files.

The **Build Windows app** GitHub Actions workflow compiles the native app,
runs backend and component tests, exercises actual upstream downloads on
Windows, captures the app interface, and checks installation/uninstallation.
Successful runs publish downloadable build artifacts. Public releases remain
a separate deliberate step.

### Desktop acceptance before a stable release

- Clean Windows 10 22H2 and Windows 11 standard-user installs with no existing MPV/Deno/yt-dlp.
- Real playlist access and audible playback on built-in, USB and Bluetooth audio.
- Changing settings, relaunching, and an actual clock-triggered task.
- Locked-screen playback, sleep/wake and a disconnected output device.
- Interrupted download, failed update, settings preservation, upgrade and uninstall.
- Check scaling at 100%, 150% and 200% and keyboard-only operation.

Hosted Windows tests use generated local media and null outputs for playback
integration. Their success does not establish live YouTube access or audible
speaker behavior on a personal Windows 10 or Windows 11 PC.

## Upstream references

- [yt-dlp JavaScript runtime setup](https://github.com/yt-dlp/yt-dlp/wiki/EJS)
- [MPV Windows builds](https://mpv.io/installation/)
- [Windows tar and supported archives](https://learn.microsoft.com/en-us/windows/tar/)
- [.NET Framework on Windows](https://learn.microsoft.com/en-us/dotnet/framework/install/on-windows-11)
- [Task Scheduler security contexts](https://learn.microsoft.com/en-us/windows/win32/taskschd/security-contexts-for-running-tasks)
- [Inno Setup per-user mode](https://jrsoftware.org/ishelp/topic_setup_privilegesrequired.htm)

See `THIRD_PARTY.md` for component source and licensing information.
