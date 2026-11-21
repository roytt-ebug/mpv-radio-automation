# Windows installer readiness review

Review started: 2026-11-19 (America/Belize).

## Baseline

Application source: `518e74e0b6f81d083341f9b9f5a07a64167bccb0`.

The first commit on this review branch adds this test plan only. Its pull-request
checks exercise the existing application without changing playback or setup.

## Automated coverage

- Windows PowerShell 5.1 input validation and task definitions.
- Offline dependency version/checksum fixtures.
- Registration and cleanup of a disabled, uniquely named Windows task.
- Hidden-launcher compilation, argument handling and a real child process.
- Real Windows MPV with generated local audio and null output: diagnostics,
  stop, session replacement and duration enforcement.
- Lua history and section tests, plus real headless MPV on Linux.

A Windows hosted runner is not a physical Windows 11 listening test.
The tests above do not establish YouTube connectivity, audible speaker output,
Bluetooth reconnect, sleep/wake, or a standard-user desktop installation.

## Release acceptance checks

Before publishing an installer, verify:

1. Fresh Windows 11 x64 standard-user installation.
2. Complete dependency setup without manual archive extraction.
3. Playlist validation and real YouTube playback on the selected speaker.
4. Optional schedules, local time, locked-screen behavior and wake from sleep.
5. Upgrade preserving sampling settings, unrelated player settings and history.
6. Failed download or setup leaves the prior working installation usable.
7. Uninstall removes only application-owned tasks, files and shortcuts.
8. Paths with spaces and non-ASCII characters.
9. No system-wide security, audio-default, execution-policy or PATH changes.
10. A release build with versioned assets, checksums, notices and an honest
    description of signing status.

## Proposed user experience

One Windows download; open Automatic Music; paste a playlist; choose a speaker;
choose days, start time and duration; click Save and Test.

Keep advanced sampling settings behind an Advanced section. Preserve the
single-player design, recent-track and heard-section history, and simple fade-out.
