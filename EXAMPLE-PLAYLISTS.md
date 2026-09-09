# Sample music playlists

These contributor-approved samples are now shown **inside guided setup (revision 4)**. At either task's playlist prompt, type **S** and press Enter to use the sample shown for that task. You may instead paste your own URL, or press Enter without typing to skip. A blank answer never automatically selects music and leaves an existing task unchanged.

## Morning Music

[Open the Morning Music sample](https://www.youtube.com/playlist?list=PLZAsCc2NQgn0)

At the Morning task's playlist prompt, type **S** or paste:

```text
https://www.youtube.com/playlist?list=PLZAsCc2NQgn0
```

The installer suggests **06:45 (6:45 AM), Monday-Saturday, for three hours**. These are editable schedule suggestions, not requirements for this playlist.

## Day Finisher

[Open the Day Finisher sample](https://www.youtube.com/playlist?list=PLBejJIaDgbyQ)

At the Day-finisher task's playlist prompt, type **S** or paste:

```text
https://www.youtube.com/playlist?list=PLBejJIaDgbyQ
```

The installer suggests **15:45 (3:45 PM), Monday-Friday, for three hours**. Choose a different time, set of days, or runtime when needed.

**Maximum runtime is a DURATION, not the time of day to stop.** For example, `3` means three hours after launch, not 3 PM. `1.5` or `1:30` means ninety minutes; `45 min` means forty-five minutes.

## Using these links on an already configured computer

Updating this repository does **not** change tasks already saved on your PC. There is no need to reinstall MPV or replace the Lua script just to change playlists.

1. Open the existing task's **Properties -> Actions** and edit its PowerShell controller action.
2. Change only the URL after `-Playlist`. Keep the `-DurationSeconds` value, triggers, and days.
3. If the task still has the old taskkill + direct-MPV actions, first follow [the controller upgrade instructions](README.md#update-an-existing-working-computer).

**Morning Music - Add arguments (three hours):**

```text
-NoProfile -ExecutionPolicy Bypass -File "C:\MPV\Radio.ps1" -Playlist "https://www.youtube.com/playlist?list=PLZAsCc2NQgn0" -DurationSeconds 10800
```

**Day Finisher - Add arguments (three hours):**

```text
-NoProfile -ExecutionPolicy Bypass -File "C:\MPV\Radio.ps1" -Playlist "https://www.youtube.com/playlist?list=PLBejJIaDgbyQ" -DurationSeconds 10800
```

The executable is `C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe`, with `C:\MPV` as **Start in**. In the installer enter **S** or only the URL; it supplies the command automatically. **S is an installer choice, not a player command.**

## Availability and privacy

These are external YouTube playlists, not music distributed with this project. Their contents and availability can change. The project does not guarantee playback of every entry in every region or client. URL-format validation in the installer does not check that a playlist exists or is playable.

The sample URLs retain the supplied playlist IDs and omit `si=` sharing parameters. This does not anonymize a playlist or its publicly visible owner/channel. Public playlists can be viewed/shared by anyone; unlisted playlists can be viewed/shared by anyone with the link. Publishing an unlisted link here makes it available to repository visitors. See [YouTube's playlist privacy documentation](https://support.google.com/youtube/answer/3127309?hl=en).

A playlist link is not a Google sign-in credential. This setup does not authenticate as the playlist owner or distribute Google credentials, browser cookies or account tokens. Keep authentication files and private account details out of this repository.

Replacing a link in the current documentation does not remove earlier versions from Git history or copies already downloaded. These instructions change only the URLs used for future setup or task launches; they do not erase old history.

See [README.md](README.md) for the guided installer, or [MANUAL-SETUP.md](MANUAL-SETUP.md) to configure everything yourself with the complete Lua code. Recommendations are not a grant of rights for public or commercial playback; see [THIRD_PARTY.md](THIRD_PARTY.md).
