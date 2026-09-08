# Third-party software and licensing

This repository intentionally does **not** bundle third-party MPV or yt-dlp binaries.

## MPV

Project: https://mpv.io/

Source: https://github.com/mpv-player/mpv

Windows builds used during development:
https://github.com/shinchiro/mpv-winbuild-cmake/releases

MPV is GPLv2-or-later by default. MPV can also be built under LGPLv2.1-or-later when GPL-only code is excluded, but linked libraries can affect the license of a particular binary.

If you redistribute an MPV binary yourself, you are responsible for satisfying the license obligations that apply to that exact binary and its bundled/linked components, including applicable license notices and corresponding-source requirements.

For this reason this project recommends downloading MPV directly from the upstream Windows build provider instead of repackaging the binary.

## yt-dlp

Project/source:
https://github.com/yt-dlp/yt-dlp

The yt-dlp source repository is released under the Unlicense. However, the project documents that its PyInstaller-bundled release executables include third-party GPLv3+ code and the combined executable is therefore GPLv3+.

If you redistribute the Windows executable yourself, you are responsible for the applicable GPLv3+ and third-party license obligations.

This project instead downloads/references yt-dlp from its official upstream release.

## Project code

The automation scripts written for this repository are licensed under the MIT License in `LICENSE`.

This file is informational and is not legal advice.
