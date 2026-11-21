# Windows app and installer review

Review date: 19 November 2026 (Belize).

## Decision

The existing one-player engine is a useful foundation for a small Windows
application. A public installer should follow a native setup/settings window,
automatic component setup, safe updates, and a real desktop acceptance test.
Wrapping the current console installer in an EXE alone would leave the main
installation difficulties in place.

The proposed product name is **Automatic Music**. This is a working name, not a
published release or a completed desktop application.

## Tested versus proposed

The baseline is commit `518e74e0b6f81d083341f9b9f5a07a64167bccb0`.
The first review commit adds a test plan only and triggers the existing tests
without changing application code:

- [Fresh baseline Windows run](https://github.com/roytt-ebug/mpv-radio-automation/actions/runs/44675827895)
- [Fresh baseline Linux/Lua run](https://github.com/roytt-ebug/mpv-radio-automation/actions/runs/44675827817)

Final results and the checks for the proposed changes are recorded in the draft
pull request. A green hosted Windows run verifies the named automated cases; it
does not certify a fresh Windows 11 desktop installation or audible playback.

The existing automated tests cover Windows PowerShell 5.1, input validation,
limited interactive task registration, hidden helper compilation, actual MPV
process control, local generated audio, history and sampling. Dependency tests
use offline fixtures for downloads. MPV integration uses null audio/video outputs.

Still requiring real desktop testing: YouTube access, a physical speaker,
Bluetooth reconnection, sleep/wake, standard-user setup and upgrades, and the
future graphical interface and uninstaller.

## Changes prepared in this review

1. **Preserve customization during setup.** Retain an existing sampling settings
   file. Update the selected global audio output while keeping unrelated MPV
   settings, comments and profiles. Keep the current defaults on a fresh install.
2. **One owned player for manual and scheduled playback.** Route clipboard
   playback through the same supervisor and Stop command. Manual playback still
   disables radio sampling and listening-history updates. Keep other applications'
   MPV instances untouched.
3. **Locate the updater beside its launcher.** Avoid a hard-coded `C:\MPV` in the
   yt-dlp update shortcut and report failures.
4. **Add regression coverage** for upgrade preservation and manual/scheduled
   player replacement.

These changes are proposed in a draft pull request. They do not provide a
packaged installer or a finished graphical application.

## Remaining priorities

| Priority | Finding | Intended improvement |
| --- | --- | --- |
| Before public beta | MPV and Deno require manual downloads; setup assumes `C:\MPV`. | Download verified components automatically into an application-owned folder. |
| Before public beta | Any existing `yt-dlp.exe` is accepted by the installer without a version/process check. | Bounded version checks, clear failure status, and a Repair/Update action. |
| Before public beta | Setup elevates before detecting devices or running existing components. | Default to per-user installation and ordinary privileges. Isolate migration operations that need elevation. |
| Before public beta | A failure after some setup steps leaves partial changes. | Stage downloads/builds first, record a transaction, and restore replaced files/tasks when applying fails. |
| Before public beta | Task replacement/removal relies on generic task names. | Use an application-specific task folder/ownership marker; verify ownership before modifying legacy tasks. |
| Before public beta | Only URL syntax is checked; the playlist can still be inaccessible. | Check playlist accessibility/title, then play a test through the chosen speaker. |
| Before public beta | There is no app settings window or complete uninstaller. | Add a native control panel and normal Windows uninstall entry. Preserve listening data unless removal is explicitly selected. |
| Reliability | A Task Scheduler retry receives the full original duration. | Use the scheduled occurrence's deadline so retries cannot extend the session unintentionally. |
| Reliability | MPV errors are collapsed into a generic message. | Add a bounded diagnostic log and understandable last-error status. |
| Polish | A smart seek is scheduled one second after media loads. | Listen for an audible initial snippet; if needed, hold playback until a bounded smart-start decision is ready. |

The retry and audible-snippet observations follow from the code and need targeted
runtime reproduction before choosing a fix.

## Proposed first version

### Installation

1. Download `Automatic-Music-Setup.exe` from a versioned GitHub Release.
2. Run setup for the current Windows user.
3. Setup obtains the playback components and verifies them before use.
4. Open **Automatic Music** from the Start menu.
5. Paste a YouTube playlist, choose a speaker and click **Save and Test**.

The filename above describes a proposed release asset; it is not available yet.
Most users should never need to install Git, edit scripts or configuration files,
choose between unfamiliar archive assets, or open Task Scheduler themselves.

### Main window

- Playlist box with a clear validation result.
- Speaker dropdown and **Test sound**.
- **Play**, **Pause**, **Next** and **Stop**.
- Morning and Day Finisher schedules with an enable switch, day checkboxes,
  a normal time picker, and duration in separate hours/minutes fields.
- **Advanced** for sampling and history options.
- A concise component/status area with **Repair / Update** and useful errors.

Keep the existing defaults: sampling on, 15-minute eligibility cutoff,
10–30-minute sample length, five-second fade-out, ten-track history and a
three-hour session. Keep one player and sequential track transitions.

## Windows integration and registry scope

The reviewed code does not edit the registry, Windows default audio output,
system PATH, or persistent PowerShell execution policy. Its per-process
`-ExecutionPolicy Bypass` does not persist a policy change.

Recommended layout:

- App and private components: `%LOCALAPPDATA%\Programs\Automatic Music`.
- Settings/history: a separate app-owned data directory under `%LOCALAPPDATA%`.
- Start menu shortcut for the current user.
- Current-user Task Scheduler tasks with limited privileges and an interactive
  logon, using the supported scheduler API.
- Ordinary installer-managed uninstall registration where needed.

Microsoft supports registering ordinary-privilege tasks from an unelevated
process. Existing tasks created by an administrator can have different access
rules, so legacy migration requires its own tests.

Music requires the listener's Windows account to remain signed in. Locking the
screen is compatible with this design. Wake-from-sleep depends on PC/device
settings; a powered-off PC cannot be started by this app. Avoid automatic logon
or storing Windows passwords as a workaround.

There is no need for registry tuning, changing security settings, or taking over
file associations. Registry entries limited to the app's own uninstall information
are routine and should be removed by the uninstaller.

## Components and packaging

Keep MPV, yt-dlp and Deno local to the app. yt-dlp's official Windows executable
already includes its EJS challenge-solver scripts. Current yt-dlp guidance
recommends Deno, supports it beside `yt-dlp.exe` on Windows, and specifies a
minimum Deno version of 2.3.0. Automatically obtaining and checking it is a more
dependable novice setup than leaving it as a manual troubleshooting step. This
does not mean every YouTube item necessarily fails without it.

Use versions and hashes that were validated together. Download to staging, verify
checksums before execution, extract the full required package and run a bounded
health check before activating it. Keep the working version until its replacement
passes. Network failure must leave the old installation intact.

MPV's installation page lists Shinchiro's Windows builds; they are third-party
builds recommended through the MPV project, not binaries built by MPV itself.
Continue obtaining upstream binaries directly unless the exact redistribution
license and source/notice obligations are handled for an offline bundle.

**Practical installer:** Inno Setup with `PrivilegesRequired=lowest`, paired with
a small native Windows front end. It supports shortcuts, uninstall, downloads,
verification and archive extraction. Its authors request commercial users to buy
a license; their current purchase page says this is not strictly required and
describes perpetual licenses. NSIS is an alternative if keeping the installer
toolchain entirely free is preferred. No tool purchase is part of this review.

Compile the app/helper during the release build rather than on each customer's
machine. Sign release executables with a consistent trusted publisher identity
when preparing public distribution. Signing improves publisher verification but
does not guarantee a new download avoids SmartScreen warnings. Do not disable
Windows protection to accommodate the installer.

## GitHub presentation

GitHub can host source for developers and an ordinary Windows download for users.
Use a prominent **Download for Windows** link pointing to the latest stable
Release, with the installer attached as an asset. Put developer instructions
below the user quick start. Keep an optional portable ZIP for people who prefer it.

For each release include a version, concise changes, known limitations,
installation/upgrade notes, hashes, notices and links to its successful tests.
Start with a clearly labelled beta; retain previous releases for recovery.
Do not publish every successful CI run automatically as a stable release.

## Primary references

- [yt-dlp JavaScript runtime and EJS setup](https://github.com/yt-dlp/yt-dlp/wiki/EJS)
- [MPV Windows builds](https://mpv.io/installation/)
- [Task Scheduler security contexts](https://learn.microsoft.com/en-us/windows/win32/taskschd/security-contexts-for-running-tasks)
- [Windows installation context](https://learn.microsoft.com/en-us/windows/win32/msi/installation-context)
- [PowerShell execution-policy scopes](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_execution_policies)
- [Inno Setup privileges](https://jrsoftware.org/inno-setup/documentation/topic_setup_privilegesrequired.htm)
- [Inno Setup features](https://jrsoftware.org/inno-setup/documentation/topic_whatisinnosetup.htm)
- [Inno Setup commercial licensing explanation](https://jrsoftware.org/inno-setup/purchase)
- [Windows signing and SmartScreen reputation](https://learn.microsoft.com/en-us/windows/apps/package-and-deploy/smartscreen-reputation)
- [GitHub releases](https://docs.github.com/en/repositories/releasing-projects-on-github/about-releases)
- [Linking to release downloads](https://docs.github.com/en/repositories/releasing-projects-on-github/linking-to-releases)
