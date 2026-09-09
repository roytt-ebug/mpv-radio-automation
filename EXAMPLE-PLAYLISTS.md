# Sample music playlists

These contributor-approved samples are now shown **inside guided setup (revision 3)**. At either task's playlist prompt, type **S** and press Enter to use the sample shown for that task. You may instead paste your own URL, or press Enter without typing to skip. A blank answer never automatically selects music and leaves an existing task unchanged.

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

1. Open Windows Task Scheduler and open the existing morning music task's **Properties**.
2. On **Actions**, select the action that starts `C:\MPV\mpv.exe` and click **Edit**. In the standard setup, this is the second action. Leave the first stop-old-MPV action unchanged.
3. Replace **Add arguments** with the Morning Music line below. Keep **Program/script** as `C:\MPV\mpv.exe` and **Start in** as `C:\MPV`.
4. Save, then repeat for the Day Finisher task using its corresponding line. Keep your chosen triggers, days, output device and runtime limits unchanged.
5. The replacement URL is used on the next task start. To test immediately, right-click the task and choose **Run**; the task will stop the currently accessible MPV playback first.

**Morning Music - Add arguments:**

```text
--shuffle --loop-playlist=inf "https://www.youtube.com/playlist?list=PLZAsCc2NQgn0"
```

**Day Finisher - Add arguments:**

```text
--shuffle --loop-playlist=inf "https://www.youtube.com/playlist?list=PLBejJIaDgbyQ"
```

In the installer, use **S** or paste **only the URL**, not the `--shuffle` command. The installer supplies the command-line options automatically. In Task Scheduler's **Add arguments**, use the full line with the options as shown above. **S is an installer choice, not an mpv command or a playlist URL.**

## Availability and privacy

These are external YouTube playlists, not music distributed with this project. Their contents and availability can change. The project does not guarantee playback of every entry in every region or client. URL-format validation in the installer does not check that a playlist exists or is playable.

The sample URLs retain the supplied playlist IDs and omit `si=` sharing parameters. This does not anonymize a playlist or its publicly visible owner/channel. Public playlists can be viewed/shared by anyone; unlisted playlists can be viewed/shared by anyone with the link. Publishing an unlisted link here makes it available to repository visitors. See [YouTube's playlist privacy documentation](https://support.google.com/youtube/answer/3127309?hl=en).

A playlist link is not a Google sign-in credential. This setup does not authenticate as the playlist owner or distribute Google credentials, browser cookies or account tokens. Keep authentication files and private account details out of this repository.

Replacing a link in the current documentation does not remove earlier versions from Git history or copies already downloaded. These instructions change only the URLs used for future setup or task launches; they do not erase old history.

See [README.md](README.md) for the guided installer, or [MANUAL-SETUP.md](MANUAL-SETUP.md) to configure everything yourself with the complete Lua code. Recommendations are not a grant of rights for public or commercial playback; see [THIRD_PARTY.md](THIRD_PARTY.md).
