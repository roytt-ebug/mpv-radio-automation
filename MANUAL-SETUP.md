# Manual setup: MPV Radio Automation for Windows

[Back to the main README](README.md)

This is an **alternative to the installer**. Follow these steps instead of running `INSTALL.cmd` or `Install.ps1`. It reproduces this project's scheduled background-music setup using File Explorer, Notepad, Command Prompt and Windows Task Scheduler.

**Already installed?** Do not create duplicate tasks or a second radio script. Back up your existing `C:\MPV` folder and export the existing tasks first, then edit only the parts you intend to change. Stop MPV before replacing configuration or Lua files. Backups belong outside `portable_config\scripts`, not beside active `.lua` files.

This guide uses `C:\MPV` because the supplied Lua script and launchers use that path. The scripts are not currently path-independent. MPV, yt-dlp and any JavaScript runtime are installed separately from their upstream projects; no third-party executables or music are included in this repository.

## 1. Install the playback software yourself

For a normal Windows x64 computer, start at the [official mpv installation page](https://mpv.io/installation/) and follow its link to a Windows build. This project has used [Shinchiro Windows builds](https://github.com/shinchiro/mpv-winbuild-cmake/releases).

Download the normal `mpv-x86_64-...7z` player archive. On GitHub, expand **Assets / Show all assets** if needed. Do not choose `mpv-dev` (developer libraries), `i686` (32-bit), or `aarch64` (ARM) for this x64 setup. Extract the **entire archive**, not only `mpv.exe`, into `C:\MPV`. Do not run the player from inside an archive viewer. File associations are optional; you do not need `mpv-register.bat` for this project.

Next, download **`yt-dlp.exe`** from [official yt-dlp releases](https://github.com/yt-dlp/yt-dlp/releases/latest) and put it beside the player:

```text
C:\MPV\mpv.exe
C:\MPV\mpv.com
C:\MPV\yt-dlp.exe
```

Keep all the other files supplied with the MPV build. `yt-dlp.exe` is a command-line helper, not a graphical installer; do not double-click it expecting a setup wizard.

For current YouTube support, follow yt-dlp's [JavaScript-runtime setup instructions](https://github.com/yt-dlp/yt-dlp/wiki/EJS). Deno is its recommended runtime; install a supported version using the [official Deno instructions](https://docs.deno.com/runtime/getting_started/installation/). The official bundled `yt-dlp.exe` already includes the EJS scripts, but the JavaScript runtime is separate. Ensure the runtime is available to the Windows user who will run the music tasks. The guided installer does not install this runtime either.

Open a **new Command Prompt** after installing a runtime and check:

```bat
C:\MPV\yt-dlp.exe --version
deno --version
```

The second command assumes you installed Deno on PATH. Follow yt-dlp's guide for other runtime locations or supported runtimes. A version number confirms the executable runs, not that every YouTube link will play.

## 2. Show file extensions and create the folders

In File Explorer enable **File name extensions**. On Windows 10 this is on the **View** tab; on Windows 11 use **View -> Show -> File name extensions**.

Inside `C:\MPV`, create `portable_config`. Inside it, create `scripts`.

Your simplified layout will become:

```text
C:\MPV\
    mpv.exe
    mpv.com
    yt-dlp.exe
    ...other MPV build files and folders...
    portable_config\
        mpv.conf
        scripts\
            random-start.lua
        random-start-history.txt     [created automatically]
        recent-track-history.txt     [created automatically]
```

Do not manually create empty history files. The script will create them as playback occurs. The Windows account running MPV needs permission to write inside `portable_config`.

## 3. Find the music speaker's complete device ID

Connect and switch on the speaker. In Windows **Settings -> System -> Sound**, keep your headset or other preferred device as the normal Windows output. The MPV configuration below independently selects the music speaker.

Press **Windows + R**, type `cmd`, and press Enter. Run:

```bat
C:\MPV\mpv.com --no-config --load-scripts=no --audio-device=help
```

Use `mpv.com` for diagnostics; it displays console output. `mpv.exe` is used for the scheduled graphical player window.

Find the row with your intended speaker's name. Copy the whole device identifier inside its single quotes, including `wasapi/` and both braces. Do **not** copy only the GUID, the speaker's descriptive name, or the single quotes.

For example, a row might look like this (this is an invented ID, not yours):

```text
'wasapi/{11111111-2222-3333-4444-555555555555}' (Speakers (Example USB))
```

The portion needed would be:

```text
wasapi/{11111111-2222-3333-4444-555555555555}
```

**Use the identifier returned on your own computer.** Selecting `auto` would follow Windows' default output instead of fixing MPV to a separate speaker. Monitor/HDMI outputs and Realtek Speakers are separate devices; choose the one actually connected to your music speakers.

## 4. Create mpv.conf

Open Notepad, paste the following, and replace `PASTE_YOUR_FULL_DEVICE_ID_HERE` with the complete ID from step 3:

```text
audio-device=PASTE_YOUR_FULL_DEVICE_ID_HERE
vid=no
ytdl-format=bestaudio/best
force-window=yes
```

For example, the first line will begin `audio-device=wasapi/{` when using a detected WASAPI output.

Choose **File -> Save As**. Set **Save as type: All files**, **Encoding: UTF-8**, and save exactly as:

```text
C:\MPV\portable_config\mpv.conf
```

Check in File Explorer that the filename is `mpv.conf`, **not `mpv.conf.txt`**.

These settings select the speaker, disable video playback, request an audio stream where available, and keep a visible control window. The format has a `best` fallback if an audio-only format is unavailable. See [mpv's manual](https://mpv.io/manual/stable/) for the options and Windows `portable_config` behavior.

## 5. Create the radio Lua script

Open a new Notepad document. Paste the **entire code** in [Full random-start.lua code](#full-random-startlua-code) at the end of this guide, not just the settings at its top. Use **Save as type: All files**, **Encoding: UTF-8**, and save exactly as:

```text
C:\MPV\portable_config\scripts\random-start.lua
```

Alternatively, copy the repository's [ready-made script](payload/portable_config/scripts/random-start.lua) to that exact path. The full code below is the same script, not a shortened example. Automated checks compare the code block with the source file to help prevent documentation drift.

Keep **only one** active copy. Do not leave `random-start-smart.lua`, `random-start-persistent.lua`, or another older radio `.lua` file in the `scripts` folder. Do not name the new file `random-start.lua.txt`.

The supplied script keeps ten accepted track starts, including short songs, and has a separate recent-track filter adapted for small playlists. Tracks **under 20 minutes** are not randomly seeked. Tracks **20 minutes or longer** get a random start from **0% to 75%**, provided their duration is available. Unknown-duration items are left alone.

The script does not force a short track back to zero if another setting, saved playback position or URL explicitly starts it later. Use ordinary playlist URLs without a timestamp for normal scheduled listening. MPV shuffle plus this filter is not a complete persistent shuffled queue.

## 6. Test the player before scheduling

Choose one of these sample playlists or substitute your own. In **Command Prompt**, test:

**Morning Music:**

```bat
C:\MPV\mpv.com --shuffle --loop-playlist=inf "https://www.youtube.com/playlist?list=PLZAsCc2NQgn0"
```

**Day Finisher:**

```bat
C:\MPV\mpv.com --shuffle --loop-playlist=inf "https://www.youtube.com/playlist?list=PLBejJIaDgbyQ"
```

Run one test at a time. Quit the first player before running the second command, or you will hear two instances. A manual command does not include the scheduled stop-old-MPV action.

Check that the intended speaker plays audio and a control window opens without playing video. A long item should briefly show its random starting percentage. Short items should not jump randomly. Check that the two history files begin appearing in `portable_config`.

With the MPV window focused, **Space** pauses/resumes, **Enter** advances to the next playlist entry, and lowercase **q** quits. Uppercase Q can save a resume point; use lowercase q for these tests. See [mpv's default controls](https://mpv.io/manual/stable/#keyboard-control).

These samples are external playlists. Their contents and availability can change, and not all entries may be accessible in every region/client. See [sample playlist notes](EXAMPLE-PLAYLISTS.md) and [third-party notices](THIRD_PARTY.md).

## 7. Create the Morning task in Windows Task Scheduler

Search the Start menu for **Task Scheduler**. Choose **Create Task...**, not Create Basic Task. If the task already exists, open its **Properties** instead.

### General

Set **Name** to `Music - Morning`. Choose the Windows account that will listen, select **Run only when user is logged on**, and leave **Run with highest privileges** unchecked. Leave **Hidden** unchecked. Use the appropriate Windows version offered in **Configure for**; some Windows 11 systems still label this compatibility choice Windows 10.

An interactive task needs a logged-in session. Locking the screen is not signing out. Do not switch to running as SYSTEM or a different background account to try to get desktop audio. Microsoft's [task security context documentation](https://learn.microsoft.com/en-us/windows/win32/taskschd/security-contexts-for-running-tasks) explains interactive logon behavior.

### Triggers

Choose **New...** and set:

| Field | Morning example |
| --- | --- |
| Begin the task | On a schedule |
| Schedule | Weekly |
| Recur every | 1 week |
| Days | Monday, Tuesday, Wednesday, Thursday, Friday, Saturday |
| Start time | 6:45:00 AM |
| Enabled | Checked |

Leave Sunday unchecked. Use your own time and days if preferred. For an immediate scheduled test, set a time a few minutes in the future; a time already passed today will wait until the next eligible day. Do not enable a repeating interval inside this trigger for ordinary once-per-day playback.

### Actions: add these TWO actions in this order

**Action 1: stop accessible existing MPV instances**

Choose **New... -> Start a program**.

Program/script:

```text
C:\Windows\System32\cmd.exe
```

Add arguments:

```text
/c "taskkill /F /IM mpv.exe >nul 2>&1 & exit /b 0"
```

Leave **Start in** empty. If Windows is installed somewhere other than `C:\Windows`, use the actual `System32\cmd.exe` path.

**Warning:** this intentionally force-closes accessible processes named `mpv.exe`, including manually opened MPV videos. It is not limited to the music task. The final `exit /b 0` allows the next action even when no old player was found. This reproduces the current installer; it is not graceful single-instance control.

**Action 2: start the Morning playlist**

Add another **Start a program** action.

Program/script:

```text
C:\MPV\mpv.exe
```

Add arguments:

```text
--shuffle --loop-playlist=inf "https://www.youtube.com/playlist?list=PLZAsCc2NQgn0"
```

Start in:

```text
C:\MPV
```

Use the arrow buttons to make sure the stop action is first and the MPV action is second. Do not put both commands in the Program field. Keep the quotation marks around the playlist URL; do not put quotation marks around the Start in path. Replace only the URL when using your own playlist.

### Conditions

Leave **Start the task only if the computer is idle** unchecked. Check **Wake the computer to run this task**. Leave the specific network-connection requirement unchecked; internet is still needed for YouTube.

To match the installer, keep **Start the task only if the computer is on AC power** checked and the battery-stop condition enabled. On a laptop, deliberately review these: AC-only will prevent a battery-powered start. Decide whether battery playback is appropriate rather than changing it unknowingly.

The wake option requests waking; it is not a guarantee on every PC. Windows/hardware must support waking and the power plan must permit the wake timer. Where available, review **Control Panel -> Power Options -> Change plan settings -> Change advanced power settings -> Sleep -> Allow wake timers**. The speaker must also be powered and connected. A fully shut-down PC cannot be started by this task. See Microsoft's [WakeToRun documentation](https://learn.microsoft.com/en-us/windows/win32/taskschd/tasksettings-waketorun).

### Settings

| Setting | Value matching the example setup |
| --- | --- |
| Allow task to be run on demand | Checked |
| Run task as soon as possible after a scheduled start is missed | Unchecked |
| If the task fails, restart every | Checked; 5 minutes |
| Attempt to restart up to | 3 times |
| Stop the task if it runs longer than | Checked; 3 hours, or your chosen duration |
| If the running task does not end when requested, force it to stop | Checked |
| Delete the task if it is not scheduled to run again | Unchecked |
| If the task is already running | Do not start a new instance |

**Maximum runtime is a DURATION, not the time of day to stop.** Three hours from a 6:45 AM start is approximately 9:45 AM. Three hours from a 3:45 PM start is approximately 6:45 PM. It is not a separate fixed-time stop trigger; delays or retries can alter the actual stop time. See Microsoft's [execution time limit documentation](https://learn.microsoft.com/en-us/windows/win32/taskschd/tasksettings-executiontimelimit).

The installer accepts inputs such as `3`, `1.5`, `1:30` or `45 min`. Task Scheduler has its own duration field: choose an offered duration such as **3 hours**, rather than pasting the installer syntax into an unrelated field. The retry policy applies to task failures; it does not detect every possible silent-audio or unavailable-speaker problem.

Click **OK** to save the task.

## 8. Create the Day Finisher task

Create a separate task named **Music - Day Finisher** using the same General, Conditions and Settings choices and the same two-action order. Change the weekly schedule and the second action's URL:

| Field | Day Finisher example |
| --- | --- |
| Days | Monday-Friday |
| Start time | 3:45:00 PM |
| Maximum runtime | 3 hours |

Saturday and Sunday are unchecked in this example. The Morning example includes Saturday; the Day Finisher example does not. These are editable choices.

**Action 1:** exactly the same stop-old-MPV action from step 7.

**Action 2 Program/script:**

```text
C:\MPV\mpv.exe
```

**Action 2 Add arguments:**

```text
--shuffle --loop-playlist=inf "https://www.youtube.com/playlist?list=PLBejJIaDgbyQ"
```

**Action 2 Start in:**

```text
C:\MPV
```

Both tasks share the selected speaker, radio script and local histories. Avoid overlapping schedules unless replacing currently playing music is intended. The setting **Do not start a new instance** applies to one task; it does not by itself coordinate these two different tasks.

## 9. Test the saved tasks and locked-session behavior

First close any manual test player. In Task Scheduler, right-click a music task and choose **Run**. Confirm that its new playlist starts through the intended speaker. Repeat with the other task and confirm that the previous accessible MPV instance closes.

Do not treat the task's creation message as a playback test. A running long playlist keeps the task running; it need not immediately show a completed-success result. Inspect the action arguments and **Last Run Result** if nothing starts.

To verify locked-screen operation, temporarily set a trigger a few minutes ahead, save it, then press **Windows + L** while staying logged in. Listen for playback. Restore the intended schedule afterward. Test waking from sleep separately; do not assume a successful unlocked or locked test proves wake support.

If the wrong playlist starts later, check for an older, differently named music task still enabled. Disable the duplicate rather than leaving two independent schedules active.

## 10. Optional clipboard launchers and desktop shortcuts

From the downloaded repository's `payload` folder, copy these files into `C:\MPV` without running the installer:

```text
Play YouTube on MPV Audio.cmd
Play YouTube Video - 720p Best Audio Always On Top.cmd
Update yt-dlp.cmd
README-LOCAL.txt
```

To make desktop shortcuts, right-click a copied `.cmd` file and select **Send to -> Desktop (create shortcut)**. On Windows 11, **Show more options** may reveal that menu.

For manual listening, copy a trusted YouTube URL and double-click the audio shortcut. The video shortcut instead opens an always-on-top, resizable window with video limited to 720p and separately selected best available audio when available. Both use the configured MPV audio output, close accessible existing MPV playback and disable the radio Lua script using `--load-scripts=no`. Their manual playback does not enter radio history.

These launchers use Windows PowerShell internally to read the clipboard, but do not require using the project installer. Advanced users can inspect the exact [audio launcher](payload/Play%20YouTube%20on%20MPV%20Audio.cmd) and [video launcher](payload/Play%20YouTube%20Video%20-%20720p%20Best%20Audio%20Always%20On%20Top.cmd) before running them.

## 11. Maintenance and troubleshooting

**No YouTube audio:** open Command Prompt and use `mpv.com` with a real playlist so you can read the errors. Check the internet connection, playlist availability and selected speaker. Update yt-dlp with:

```bat
C:\MPV\yt-dlp.exe -U
```

Follow the current [yt-dlp runtime guidance](https://github.com/yt-dlp/yt-dlp/wiki/EJS) if extraction still fails. Do not disable Windows security tools simply to silence an error.

**Wrong speaker or no output:** rerun the device-list command from step 3 and replace the `audio-device=` value. A USB device reconnect or changed output configuration may require a new ID.

**Video is playing in the radio task:** inspect `mpv.conf`, its location and its real extension. A blank control window is intentional; a moving YouTube video is not part of this radio configuration.

**No random start or no history:** confirm that exactly one script exists at `C:\MPV\portable_config\scripts\random-start.lua`, the task does not use `--load-scripts=no`, and the Windows user can write the history files. Short tracks should not randomly jump. Unknown-duration items are also left unseeked.

**History size:** the track file retains the last ten accepted starts and the percentage file the last ten random percentages. The newest line is at the bottom. These are local files, not cloud-synchronized history. Automatically filtered tracks are not recorded, and an accepted start is not proof the whole track was heard. Existing older history rows are read without inventing missing titles or times.

**Changing playlists only:** edit the second task action's URL. Do not reinstall MPV, reset history, or create another task just for a different playlist.

**Updating the script only:** close MPV, back up the old Lua file outside the scripts folder, replace it with the latest source, keep both history files, and restart MPV. Do not leave two `.lua` versions active. Updating GitHub does not update your local computer automatically.

**Removing automation:** disable or delete the two music tasks after exporting them if needed. Keep or remove the project Lua/config/launcher files deliberately. Removing a task does not automatically undo the MPV configuration. No MPV uninstall is required merely to stop scheduled playback.

## Full random-start.lua code

Copy everything inside this code block into `C:\MPV\portable_config\scripts\random-start.lua`. Do not copy the surrounding Markdown backticks. It is the complete current repository script, including the 20-minute cutoff and ten-start history. Review the settings near the top before changing behavior.

<!-- BEGIN RADIO LUA -->
```lua
-- random-start.lua
-- Radio-style playlist helper for MPV
--
-- Designed to be used with:
--   --shuffle --loop-playlist=inf
--
-- Behavior:
--   * MPV handles playlist shuffle.
--   * The last 10 accepted track starts are saved across restarts.
--   * Retention is separate from repeat protection, so small playlists still play.
--   * Tracks shorter than 20 minutes are not randomly seeked.
--   * Tracks 20 minutes or longer start at a random point from 0% to 75%.
--   * The last 10 random-start percentages are remembered across MPV restarts.
--   * Exact recent percentages are not reused, and the new percentage
--     tries to stay at least 6 percentage points away from the previous one.
--
-- Manual launchers that use --load-scripts=no are not affected.

math.randomseed(os.time() + (mp.get_property_number("pid") or 0))
math.random()
math.random()
math.random()

-- =========================
-- USER-ADJUSTABLE SETTINGS
-- =========================

local MAX_START_PERCENT = 75

-- Only tracks this long or longer get a random start.
-- 20 minutes = 1200 seconds.
local MIN_RANDOM_START_DURATION = 20 * 60

local PERCENT_HISTORY_SIZE = 10
local MIN_PERCENT_GAP_FROM_LAST = 6
local PERCENT_HISTORY_FILE =
    "C:\\MPV\\portable_config\\random-start-history.txt"

-- History retention is independent of the number of playlist entries.
-- Increase this value to retain more than 10 track starts.
local TRACK_HISTORY_SIZE = 10

-- Repeat protection is separate: at most 5 recent starts are considered.
-- For small playlists it shrinks to leave choices, and for one track it is off.
local MAX_RECENT_TRACKS = 5
local PERSIST_TRACK_HISTORY = true

local TRACK_HISTORY_FILE =
    "C:\\MPV\\portable_config\\recent-track-history.txt"

-- =========================
-- PERCENTAGE HISTORY
-- =========================

local function read_percent_history()
    local history = {}
    local file = io.open(PERCENT_HISTORY_FILE, "r")
    if not file then
        return history
    end

    for line in file:lines() do
        local pct =
            tonumber(line:match("|(%d+)%s*$")) or
            tonumber(line:match("^%s*(%d+)%s*$"))

        if pct and pct >= 0 and pct <= MAX_START_PERCENT then
            table.insert(history, {
                percent = pct,
                line = line
            })
        end
    end

    file:close()

    while #history > PERCENT_HISTORY_SIZE do
        table.remove(history, 1)
    end

    return history
end

local function percent_is_recent(percent, history)
    for _, item in ipairs(history) do
        if item.percent == percent then
            return true
        end
    end
    return false
end

local function choose_percent(history)
    local last =
        history[#history] and
        history[#history].percent or
        nil

    for _ = 1, 500 do
        local candidate = math.random(0, MAX_START_PERCENT)
        local far_enough =
            (not last) or
            (math.abs(candidate - last) >= MIN_PERCENT_GAP_FROM_LAST)

        if not percent_is_recent(candidate, history) and far_enough then
            return candidate
        end
    end

    for _ = 1, 500 do
        local candidate = math.random(0, MAX_START_PERCENT)
        if not percent_is_recent(candidate, history) then
            return candidate
        end
    end

    return math.random(0, MAX_START_PERCENT)
end

local function save_percent_history(history, percent)
    table.insert(history, {
        percent = percent,
        line =
            os.date("%Y-%m-%d %H:%M:%S") ..
            "|" ..
            tostring(percent)
    })

    while #history > PERCENT_HISTORY_SIZE do
        table.remove(history, 1)
    end

    local file = io.open(PERCENT_HISTORY_FILE, "w")
    if not file then
        mp.msg.warn("Could not write percentage history file.")
        return
    end

    for _, item in ipairs(history) do
        file:write(item.line, "\n")
    end

    file:close()
end

-- =========================
-- TRACK HISTORY
-- =========================

local recent_tracks = {}

local function track_key(path)
    if not path or path == "" then
        return nil
    end
    local id = path:match("[?&]v=([%w_-]+)") or
        path:match("youtu%.be/([%w_-]+)")
    if id then
        return "youtube:" .. id
    end
    return path
end

local function history_field(value)
    -- One record per line; prevent titles from inserting fake columns/records.
    return tostring(value or ""):gsub("[\r\n\t|]", " ")
end

local function trim_track_history()
    -- Never trim history to playlist-count: even a one-song playlist keeps 10 starts.
    while #recent_tracks > TRACK_HISTORY_SIZE do
        table.remove(recent_tracks, 1)
    end
end

local function load_persistent_track_history()
    if not PERSIST_TRACK_HISTORY then return end
    local file = io.open(TRACK_HISTORY_FILE, "r")
    if not file then return end
    for line in file:lines() do
        -- New: timestamp|track-key|title
        -- Old: timestamp|track-key (preserved without inventing titles/timestamps).
        local stamp, key, tail = line:match("^([^|]+)|([^|]+)(.*)$")
        if stamp and key and (tail == "" or tail:sub(1, 1) == "|") then
            table.insert(recent_tracks, {
                timestamp = stamp,
                key = key,
                title = tail == "" and "" or tail:sub(2)
            })
        end
    end
    file:close()
    trim_track_history()
end

local function save_persistent_track_history()
    if not PERSIST_TRACK_HISTORY then return end
    local file = io.open(TRACK_HISTORY_FILE, "w")
    if not file then
        mp.msg.warn("Could not write recent-track history file.")
        return
    end
    for _, item in ipairs(recent_tracks) do
        local ok, err = file:write(
            history_field(item.timestamp), "|",
            history_field(item.key), "|",
            history_field(item.title), "\n"
        )
        if not ok then
            mp.msg.warn("Could not finish writing track history: " .. tostring(err))
            break
        end
    end
    file:close()
end

local function blocked_track_keys(playlist)
    local available, unique_count = {}, 0
    for _, entry in ipairs(playlist) do
        local key = track_key(entry.filename)
        if key and not available[key] then
            available[key] = true
            unique_count = unique_count + 1
        end
    end
    -- Count unique tracks, not duplicate playlist rows. Leave at least two
    -- choices when there are 3+ unique tracks. Two tracks can only alternate.
    local safe_limit = math.max(0, unique_count - 2)
    if unique_count == 2 then safe_limit = 1 end
    local limit = math.min(MAX_RECENT_TRACKS, safe_limit)
    local blocked = {}
    for i = math.max(1, #recent_tracks - limit + 1), #recent_tracks do
        local key = recent_tracks[i].key
        if available[key] then blocked[key] = true end
    end
    return blocked
end

local function next_nonrecent_index(playlist, blocked)
    local position = mp.get_property_number("playlist-pos", -1)
    if position < 0 or position >= #playlist then return nil end
    -- Follow the already shuffled order. Wrap explicitly: playlist-next weak
    -- can do nothing at the final entry. Only return an eligible alternative.
    for step = 1, #playlist - 1 do
        local index = (position + step) % #playlist
        local key = track_key(playlist[index + 1].filename)
        if key and not blocked[key] then return index end
    end
    return nil
end

local function remember_track(key, title)
    if not key then return end
    table.insert(recent_tracks, {
        timestamp = os.date("%Y-%m-%d %H:%M:%S"),
        key = key,
        title = title or ""
    })
    trim_track_history()
    save_persistent_track_history()
end

load_persistent_track_history()

-- Invalidate delayed seeks/skips when any file ends, starts or is reloaded.
-- Comparing URL alone is insufficient when the same song is loaded twice.
local generation = 0
local function invalidate_callbacks() generation = generation + 1 end
mp.register_event("start-file", invalidate_callbacks)
mp.register_event("end-file", invalidate_callbacks)

-- =========================
-- MAIN RADIO LOGIC
-- =========================

mp.register_event("file-loaded", function()
    local path = mp.get_property("path")
    local key = track_key(path)
    local title = mp.get_property("media-title") or "track"

    generation = generation + 1
    local expected_generation = generation
    local playlist = mp.get_property_native("playlist", {}) or {}
    local blocked = blocked_track_keys(playlist)

    if key and blocked[key] then
        local target = next_nonrecent_index(playlist, blocked)
        if target ~= nil then
            mp.msg.info("Skipping recently played track: " .. title)
            mp.osd_message("Skipping recent track: " .. title, 2)
            -- Jump now rather than queueing a stale playlist index in a timer.
            mp.commandv("playlist-play-index", tostring(target))
            return
        end
        -- A changing/unavailable playlist must not cause endless skip loops.
        mp.msg.warn("No eligible alternative; allowing playback and recording it.")
    end

    -- Log accepted starts, not completed listens. Automatically filtered
    -- repeats are not logged. Short/long tracks and single-file playback are.
    remember_track(key, title)

    mp.add_timeout(1, function()
        if generation ~= expected_generation then return end

        local duration = mp.get_property_number("duration")
        if not duration or duration <= 0 then
            return
        end

        -- Short tracks play from the beginning.
        -- They still remain in recent-track history, but they do NOT
        -- consume a random percentage-history slot.
        if duration < MIN_RANDOM_START_DURATION then
            mp.msg.info(
                string.format(
                    "Full-track playback: %s (%d:%02d, under 20 min)",
                    title,
                    math.floor(duration / 60),
                    math.floor(duration % 60)
                )
            )
            mp.osd_message("Short track: no random jump", 2)
            return
        end

        -- Long tracks get a random 0%-75% starting point.
        local percent_history = read_percent_history()
        local percent = choose_percent(percent_history)
        local start = duration * percent / 100

        save_percent_history(percent_history, percent)

        mp.commandv("seek", tostring(start), "absolute", "exact")

        local mins = math.floor(start / 60)
        local secs = math.floor(start % 60)

        mp.osd_message(
            string.format(
                "Random start: %d%% (%d:%02d)",
                percent,
                mins,
                secs
            ),
            3
        )

        mp.msg.info(
            string.format(
                "Radio start: %s at %d%% (%d:%02d)",
                title,
                percent,
                mins,
                secs
            )
        )
    end)
end)
```
<!-- END RADIO LUA -->

The script code is covered by this repository's [LICENSE](LICENSE). For MPV, yt-dlp and other upstream dependencies, see [THIRD_PARTY.md](THIRD_PARTY.md). Playlist links do not grant public-performance or other content rights.
