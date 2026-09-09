# Optional playlist recommendation

The installer does not prefill personal playlist URLs. Users can choose their own music, or deliberately copy an example below. Leaving a playlist prompt blank skips that task; it does not select an example automatically.

## Day Finisher

A project contributor has suggested this playlist for end-of-day listening:

[Open the suggested Day Finisher playlist](https://www.youtube.com/playlist?list=PLUAbAiT-jXUo)

Paste this at the **Day-finisher YouTube playlist URL** prompt:

```text
https://www.youtube.com/playlist?list=PLUAbAiT-jXUo
```

This is an external YouTube playlist, not music supplied with the project. Its contents and availability can change. This recommendation is contributor-provided; the project does not guarantee that every entry will play in every region or with every client.

The optional schedule is still yours to choose. The setup helper suggests 15:45 (3:45 PM), Monday-Friday, with a maximum runtime of three hours; those values are editable and are not requirements for this playlist.

## Privacy and account access

Publishing a playlist link can associate this project with the playlist owner's publicly visible YouTube channel/profile. It is not an anonymous publishing method.

A normal playlist URL is not a Google sign-in credential or authorization token. This project's setup helper does not ask for Google credentials, authenticate as the playlist owner, or request access to their Gmail, private playlists, or account management. No browser cookies or Google tokens are distributed with this project.

YouTube says that public playlists can be viewed/shared by anyone, and unlisted playlists can be viewed/shared by anyone with the link. Publishing an unlisted link in a public repository makes it available to repository visitors. See [YouTube's playlist privacy documentation](https://support.google.com/youtube/answer/3127309?hl=en).

The example URL retains the playlist ID only; the supplied `si=` sharing parameter is omitted. That does not anonymize the playlist or its owner. Do not publish private account details or authentication files in this repository.

Using a dedicated project channel for future example playlists is an option for separating personal and project identity. Playlist links can be changed in the documentation later, but old public commits may retain earlier links.

## Your own playlists

Copy your playlist's link from YouTube and paste it into the installer. The helper accepts a regular YouTube link containing `list=` and normalizes it to a playlist URL. This validates the input format, not account access or playback availability.

See [README.md](README.md) for installation and all prompt examples. Links are listening suggestions, not a grant of rights for public or commercial playback; see [THIRD_PARTY.md](THIRD_PARTY.md).
