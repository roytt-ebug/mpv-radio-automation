# Manual setup: MPV Radio Automation for Windows

[Back to README](README.md)

Follow these steps **instead of running `INSTALL.cmd`**. You will create the configuration files, build the small launcher, and enter two schedules yourself. The result is the same single-player YouTube radio described in the README.

This guide is for **Windows x64**. Use the Windows account that will play the music. For an earlier test installation, the [fresh-setup instructions](README.md#start-over-with-a-fresh-setup) explain how to reset it; that reset clears settings and listening history. Avoid creating duplicate music tasks.

## Before you begin: download this project's files

1. Open [the project repository](https://github.com/roytt-ebug/mpv-radio-automation).
2. Choose **Code → Download ZIP**. Save the ZIP in Downloads.
3. In File Explorer, right-click the downloaded ZIP and choose **Extract All**, then **Extract**.
4. Open the extracted folder, normally `mpv-radio-automation-main`. Confirm that it contains `README.md`, `INSTALL.cmd`, and a folder named **`payload`**.

Whenever this guide says **the project's `payload` folder**, it means the folder you just extracted. Leave it available; you will copy files from it in step 5. Do not run files from inside the ZIP.

**Notepad is the Windows text editor.** A configuration file starts as a blank document in Notepad; it becomes `mpv.conf`, `.lua`, or `.conf` when you save it with the specified name. The steps below show the folder and filename separately.

## 1. Prepare the MPV folder and YouTube helper

### Create the destination folders

1. Press **Windows + E** to open File Explorer. Open **This PC → Local Disk (C:)**.
2. Right-click an empty area, choose **New → Folder**, and name it **`MPV`**. If `C:\MPV` already exists, open it instead.
3. Inside `C:\MPV`, create a folder named **`portable_config`**.
4. Inside `portable_config`, create **two separate folders** named **`scripts`** and **`script-opts`**. Neither belongs inside the other. Use any of these folders that already exist.
5. Show complete filenames: on Windows 11 choose **View → Show → File name extensions**; on Windows 10 select **View → File name extensions**.

| Folder that should now exist | What will go there |
| --- | --- |
| `C:\MPV` | MPV, yt-dlp, and this project's launcher files. |
| `C:\MPV\portable_config` | The player configuration you create in step 3; histories appear later automatically. |
| `C:\MPV\portable_config\scripts` | The Lua script you save in step 4. |
| `C:\MPV\portable_config\script-opts` | Sampling settings you save in step 5. |

### Download and extract MPV

Start at [MPV's installation page](https://mpv.io/installation/) and follow its Windows-build link. This project uses [Shinchiro Windows builds](https://github.com/shinchiro/mpv-winbuild-cmake/releases). For Windows x64 choose `mpv-x86_64-...7z`, without `dev`, `i686`, or `aarch64` in its name. Expand **Show all assets** if needed.

Extract the **entire archive** using Windows' extraction option or an archive program that supports `.7z`. Put its contents directly in `C:\MPV`. Keep all accompanying files. If extraction creates an extra folder, move its contents up so File Explorer shows **`C:\MPV\mpv.exe`** and **`C:\MPV\mpv.com`**, not `C:\MPV\another-folder\mpv.exe`. No file-association registration is needed.

### Download and verify yt-dlp

1. Open the [official yt-dlp releases](https://github.com/yt-dlp/yt-dlp/releases/latest).
2. From **the same release**, download **`yt-dlp.exe`** and **`SHA2-256SUMS`**. Move `yt-dlp.exe` into `C:\MPV`; the checksum file can stay in Downloads. If Windows hides some assets, expand the list.
3. Open **Notepad** from the Windows Start menu. Choose **File → Open**, browse to Downloads, select **All files** in the file-type filter, and open `SHA2-256SUMS`.
4. Find the line whose filename is exactly **`yt-dlp.exe`**. The long hexadecimal value on that line is its expected checksum.
5. In File Explorer open `C:\MPV`, click the address bar at the top, type **`cmd`**, and press **Enter**. This opens **Command Prompt** in that folder.
6. Paste this entire command into Command Prompt and press Enter:

```bat
powershell.exe -NoProfile -Command "(Get-FileHash -LiteralPath 'C:\MPV\yt-dlp.exe' -Algorithm SHA256).Hash"
```

Compare all 64 characters displayed with the checksum from step 4 above; uppercase/lowercase does not matter. **Continue only if they match.** If they do not, discard the downloaded `yt-dlp.exe` and obtain it and its checksum again from the same official release. A checksum checks download integrity; it is not a malware scan.

You can close the checksum document without saving it. Do not double-click `yt-dlp.exe` to test installation; it is a helper used by MPV.

**Optional Deno:** follow the [download-selection table](README.md#optional-recommendation-deno) if you want to add it. Extract `deno.exe` directly into `C:\MPV`, beside `mpv.exe` and `yt-dlp.exe`. You can continue without Deno.

**Check before continuing:** `mpv.exe`, `mpv.com`, and the verified `yt-dlp.exe` are directly in `C:\MPV`; the three configuration folders listed above exist. You have not created the configuration files yet.

## 2. Find and copy your speaker's device ID

1. Turn on and connect the speaker you want the music to use.
2. In File Explorer open `C:\MPV`, click the address bar, type **`cmd`**, and press Enter. If your Command Prompt from step 1 is still open there, you can use it.
3. Run:

```bat
mpv.com --no-config --load-scripts=no --audio-device=help
```

Find your speaker in the displayed list. Copy its **complete device ID**. It may look like:

```text
wasapi/{11111111-2222-3333-4444-555555555555}
```

That is only an example. Copy the ID for **your** speaker, including `wasapi/` and the braces. Do not copy the descriptive speaker name or surrounding quotation marks. You can select the ID in the terminal and use **Ctrl+C** to copy it. Keep this window open so you can refer back to the list.

**Check before continuing:** you have your actual device ID ready to paste into the next step. If the speaker is missing from the list, reconnect it and run the command again first.

## 3. Create and save the player configuration

1. Open the Windows **Start** menu, type **Notepad**, and open it.
2. Choose **File → New** (or **New tab**) to get a blank document. You do not need to create a file in File Explorer first.
3. Paste these four lines into the blank document:

```ini
audio-device=PASTE_YOUR_COMPLETE_DETECTED_DEVICE_ID_HERE
vid=no
ytdl-format=bestaudio/best
force-window=yes
```

4. On the first line, replace only `PASTE_YOUR_COMPLETE_DETECTED_DEVICE_ID_HERE` with the device ID from step 2. Keep `audio-device=` at the beginning. Leave the other three lines as shown.
5. Choose **File → Save As**. Click the folder/address bar in the save window, enter **`C:\MPV\portable_config`**, and press Enter to open that folder.
6. Complete the save fields as follows, then click **Save**:

| Save As field | Enter or select |
| --- | --- |
| Folder | `C:\MPV\portable_config` |
| File name | `mpv.conf` |
| Save as type | **All files** (`*.*`) |
| Encoding | **UTF-8** |

**Check before continuing:** open `C:\MPV\portable_config` in File Explorer. The file must be named **`mpv.conf`**, not `mpv.conf.txt`. Reopen it in Notepad and check that the placeholder has been replaced with your device ID. These settings keep MPV's controls visible while playing audio.

## 4. Create and save the radio Lua script

The Lua script supplies the recent-track history, smart starting points, and section sampling. You do not need to understand or edit its code to use it.

1. In Notepad choose **File → New** or **New tab** for a **separate blank document**. Do not paste over `mpv.conf`.
2. Expand **Show the complete Lua script to copy** below. Copy all the code inside the code block and paste it into the blank document. Do not include the three backtick characters used to mark a code block.
3. Choose **File → Save As**, open the folder below through the save window's address bar, and save with these fields:

| Save As field | Enter or select |
| --- | --- |
| Folder | `C:\MPV\portable_config\scripts` |
| File name | `random-start.lua` |
| Save as type | **All files** (`*.*`) |
| Encoding | **UTF-8** |

Alternatively, copy the existing `random-start.lua` from the extracted project's **`payload\portable_config\scripts`** folder into **`C:\MPV\portable_config\scripts`**. Either method supplies the same file; use only one copy.

<details>
<summary>Show the complete Lua script to copy</summary>

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
--   * Tracks shorter than 15 minutes are not randomly seeked.
--   * Tracks 15+ minutes favor less-recently-heard sections within 0%-75%.
--   * Estimated played intervals checkpoint every 15 seconds.
--   * Optional 10-30 minute section sampling with fade-out is ON by default.
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
local CONFIG_DIR = mp.command_native({"expand-path", "~~/"})
if not CONFIG_DIR:match("[/\\]$") then CONFIG_DIR = CONFIG_DIR .. "/" end

-- Only tracks this long or longer get a random start.
-- 15 minutes = 900 seconds.
local MIN_RANDOM_START_DURATION = 15 * 60

local PERCENT_HISTORY_SIZE = 10
local MIN_PERCENT_GAP_FROM_LAST = 6
local PERCENT_HISTORY_FILE =
    CONFIG_DIR .. "random-start-history.txt"

-- History retention is independent of the number of playlist entries.
-- Increase this value to retain more than 10 track starts.
local TRACK_HISTORY_SIZE = 10

-- Repeat protection is separate: at most 5 recent starts are considered.
-- For small playlists it shrinks to leave choices, and for one track it is off.
local MAX_RECENT_TRACKS = 5
local PERSIST_TRACK_HISTORY = true

local TRACK_HISTORY_FILE =
    CONFIG_DIR .. "recent-track-history.txt"

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

-- =========================
-- PER-RECORDING HEARD SECTIONS
-- =========================
-- These are estimated played intervals, not proof that a person heard sound.
-- One active player must own these files. No buffered/downloaded span is counted.
local options = {
    section_mode = true,
    min_duration_minutes = 15,
    session_seconds = 0, -- launcher supplies the total wall-clock duration; 0 = unlimited
    section_min_minutes = 10,
    section_max_minutes = 30,
    fade_seconds = 5,
    preference_window_minutes = 20,
    recency_half_life_days = 14,
    history_max_age_days = 180,
    history_max_intervals = 2000,
    history_per_recording = 40,
    checkpoint_seconds = 15
}
require("mp.options").read_options(options, "random-start")
local function finite(n)
    return type(n) == "number" and n == n and n > -math.huge and n < math.huge
end
local function checked_option(name, default, minimum, maximum)
    local value = options[name]
    if not finite(value) or value < minimum or value > maximum then
        mp.msg.warn("Invalid " .. name .. "; using " .. tostring(default))
        options[name] = default
    end
end
checked_option("section_min_minutes", 10, 0.01, 1440)
checked_option("section_max_minutes", 30, 0.01, 1440)
checked_option("fade_seconds", 5, 0, 60)
checked_option("preference_window_minutes", 20, 0.01, 1440)
checked_option("recency_half_life_days", 14, 0.01, 3650)
checked_option("history_max_age_days", 180, 1, 3650)
checked_option("history_max_intervals", 2000, 10, 10000)
checked_option("history_per_recording", 40, 1, 200)
checked_option("checkpoint_seconds", 15, 1, 300)
if options.section_min_minutes > options.section_max_minutes then
    mp.msg.warn("Section minimum exceeds maximum; using 10-30 minutes.")
    options.section_min_minutes, options.section_max_minutes = 10, 30
end
checked_option("min_duration_minutes", 15, 0.01, 1440)
checked_option("session_seconds", 0, 0, 86400)
MIN_RANDOM_START_DURATION = options.min_duration_minutes * 60
local session_started = mp.get_time()
local session_ended = false

local SECTION_FILE = CONFIG_DIR .. "heard-sections.txt"
local SECTION_HEADER = "# MPV heard-sections v1"
local heard, dirty = {}, false
local active_long
local VERSION = "2026.09-single-player-1"
local command_sequence = 0
local json = require("mp.utils").format_json
local function publish_status()
    mp.set_property("user-data/radio-status", json({
        version=VERSION, sequence=command_sequence,
        section_mode=options.section_mode, min_duration_minutes=options.min_duration_minutes,
        section_min_minutes=options.section_min_minutes, section_max_minutes=options.section_max_minutes,
        fade_seconds=options.fade_seconds, session_seconds=options.session_seconds,
        title=mp.get_property("media-title", ""),
        sample_limit=active_long and active_long.limit or 0,
        audio_device=mp.get_property("audio-device", "auto")
    }))
end
local function show_status()
    local text = string.format("Radio %s | script loaded | cutoff %.0f min | samples %s %.0f-%.0f min",
        VERSION, options.min_duration_minutes, options.section_mode and "ON" or "OFF",
        options.section_min_minutes, options.section_max_minutes)
    mp.msg.info(text)
    mp.osd_message(text, 8)
    publish_status()
end
mp.add_key_binding("F8", "radio-status", show_status)
mp.register_script_message("radio-status", show_status)
mp.register_script_message("radio-ping", function()
    command_sequence = command_sequence + 1
    publish_status()
end)
show_status()
local last_checkpoint = mp.get_time()
local function clock(seconds)
    seconds = math.max(0, math.floor(seconds))
    return string.format("%d:%02d", math.floor(seconds / 60), seconds % 60)
end
local function prune_heard()
    -- Retain the newest intervals per recording and globally. Never keep unbounded state.
    local result, counts = {}, {}
    local oldest = os.time() - options.history_max_age_days * 86400
    for i = #heard, 1, -1 do
        local item = heard[i]
        local count = counts[item.key] or 0
        if item.heard_at >= oldest and count < options.history_per_recording
            and #result < options.history_max_intervals then
            result[#result + 1] = item
            counts[item.key] = count + 1
        end
    end
    -- Reverse once to restore chronological order without shifting every entry.
    for i = 1, math.floor(#result / 2) do
        local j = #result - i + 1
        result[i], result[j] = result[j], result[i]
    end
    heard = result
end
local function read_sections(path)
    local file = io.open(path, "r")
    if not file then return nil end
    local result, valid_header = {}, false
    for line in file:lines() do
        if line == SECTION_HEADER then valid_header = true end
        local stamp, key, first, last, epoch, duration, title = line:match(
            "^([^|]+)|([^|]+)|([^|]+)|([^|]+)|([^|]+)|([^|]+)|([^|]*)|[^|]*$")
        first, last, epoch, duration = tonumber(first), tonumber(last), tonumber(epoch), tonumber(duration)
        if stamp and key and finite(first) and finite(last) and finite(epoch) and finite(duration)
            and first >= 0 and last > first and last <= duration + 1 and duration > 0
            and epoch > 0 and epoch <= os.time() + 86400 then
            result[#result + 1] = {timestamp=stamp, key=key, first=first, last=last,
                heard_at=epoch, duration=duration, title=title}
        end
    end
    file:close()
    if valid_header then return result end
    return nil
end
heard = read_sections(SECTION_FILE) or read_sections(SECTION_FILE .. ".bak") or {}
prune_heard()
local function save_sections()
    if not dirty then return end
    prune_heard()
    local temporary, backup = SECTION_FILE .. ".tmp", SECTION_FILE .. ".bak"
    local file, err = io.open(temporary, "w")
    if not file then mp.msg.warn("Cannot checkpoint heard sections: " .. tostring(err)); return end
    local ok = file:write(SECTION_HEADER, "\n# Last-heard-local|recording-ID|from-seconds|to-seconds|epoch|duration-seconds|title|range\n")
    for _, item in ipairs(heard) do
        if not ok then break end
        ok = file:write(string.format("%s|%s|%.3f|%.3f|%.0f|%.3f|%s|%s-%s\n",
            history_field(item.timestamp), history_field(item.key), item.first, item.last,
            item.heard_at, item.duration, history_field(item.title), clock(item.first), clock(item.last)))
    end
    local closed = file:close()
    if not ok or not closed then
        os.remove(temporary)
        mp.msg.warn("Heard-section checkpoint incomplete; existing history kept.")
        return
    end
    -- Windows rename cannot replace an existing file. Rotate the last complete
    -- copy first. A process killed between renames can recover from .bak.
    local previous = io.open(SECTION_FILE, "r")
    if previous then
        previous:close()
        os.remove(backup)
        local moved = os.rename(SECTION_FILE, backup)
        if not moved then os.remove(temporary); mp.msg.warn("Cannot rotate section history."); return end
    end
    local replaced = os.rename(temporary, SECTION_FILE)
    if not replaced then
        os.rename(backup, SECTION_FILE)
        mp.msg.warn("Cannot replace section history; previous copy retained.")
        return
    end
    dirty = false
    last_checkpoint = mp.get_time()
end
local function eligible_percentages(history, maximum)
    local recent, candidates = {}, {}
    for _, item in ipairs(history) do recent[item.percent] = true end
    local last = history[#history] and history[#history].percent
    for p = 0, maximum do
        if not recent[p] and (not last or math.abs(p - last) >= MIN_PERCENT_GAP_FROM_LAST) then
            candidates[#candidates + 1] = p
        end
    end
    if #candidates == 0 then
        for p = 0, maximum do if not recent[p] then candidates[#candidates+1] = p end end
    end
    if #candidates == 0 then for p=0,maximum do candidates[#candidates+1]=p end end
    return candidates
end
local function select_section(key, duration, history, planned_seconds)
    -- Compare equal-sized look-ahead windows so a late start is not favored just
    -- for having less remaining audio. Every allowed start has this much room.
    local maximum = MAX_START_PERCENT
    if planned_seconds then
        maximum = math.min(maximum, math.max(0, math.floor((duration-math.min(planned_seconds,duration))/duration*100 + 0.000001)))
    end
    local window = planned_seconds and math.min(planned_seconds,duration) or
        math.min(options.preference_window_minutes * 60, duration * (1-MAX_START_PERCENT/100))
    local candidates, best, winners = eligible_percentages(history, maximum), math.huge, {}
    local now = os.time()
    for _, p in ipairs(candidates) do
        local first, score = duration * p / 100, 0
        for _, item in ipairs(heard) do
            -- A substantially edited/replaced timeline must not reuse old offsets.
            if item.key == key and math.abs(item.duration - duration) <= math.max(5, duration * 0.01) then
                local overlap = math.max(0, math.min(first + window, item.last) - math.max(first, item.first))
                local age = math.max(0, now - item.heard_at)
                if age <= options.history_max_age_days * 86400 then
                    score = score + overlap / window * 2 ^ (-age / (options.recency_half_life_days * 86400))
                end
            end
        end
        if score < best - 0.000001 then best, winners = score, {p}
        elseif math.abs(score - best) <= 0.000001 then winners[#winners+1] = p end
    end
    return winners[math.random(1, #winners)], best
end
local function restore_fade(c)
    if not c or not c.fade then return end
    local current = mp.get_property_number("volume", 100)
    -- Do not overwrite a user's volume adjustment made while fading.
    if math.abs(current - c.fade.last) < 0.05 then
        mp.set_property_number("volume", c.fade.base)
    end
    c.fade = nil
end
local function break_interval()
    if active_long then active_long.previous, active_long.open = nil, nil end
end
local function finish_long()
    restore_fade(active_long)
    active_long = nil
    save_sections()
end
local function begin_long(key, title, duration, start, planned_seconds)
    local speed = mp.get_property_number("speed", 1)
    if not finite(speed) or speed <= 0 then speed = 1 end
    active_long = {key=key, title=title, duration=duration, elapsed=0,
        limit=planned_seconds and math.min(planned_seconds, math.max(0, duration-start)/speed) or nil}
end
local function record_interval(c, first, last)
    if not c.key or last <= first then return end
    local item = c.open
    if not item or math.abs(item.last - first) > 0.75 then
        item = {key=c.key, title=c.title, duration=c.duration, first=first, last=last}
        heard[#heard+1] = item
        c.open = item
    end
    item.last = math.min(last, c.duration)
    item.heard_at = os.time()
    item.timestamp = os.date("%Y-%m-%d %H:%M:%S", item.heard_at)
    dirty = true
end
local function advance_section(c)
    if active_long ~= c then return end
    -- Persist before asking MPV to unload; do not leave the next song at zero volume.
    finish_long()
    mp.osd_message("Section finished - next mix", 2)
    local list = mp.get_property_native("playlist", {}) or {}
    local position = mp.get_property_number("playlist-pos", -1)
    if #list > 0 and position == #list - 1 and mp.get_property("loop-playlist") == "inf" then
        if mp.get_property_native("shuffle", false) then mp.commandv("playlist-shuffle") end
        mp.commandv("playlist-play-index", "0")
    else
        mp.commandv("playlist-next", "force")
    end
end
local function tick_sections()
    local c = active_long
    if not c then return end
    local now = mp.get_time()
    local pos = mp.get_property_number("time-pos")
    local speed = mp.get_property_number("speed", 1)
    local volume = mp.get_property_number("volume", 100)
    local paused = mp.get_property_native("pause", false) or mp.get_property_native("paused-for-cache", false)
    local seeking = mp.get_property_native("seeking", false)
    local muted = mp.get_property_native("mute", false)
    if c.fade and math.abs(volume - c.fade.last) >= 0.05 then
        -- A human volume change wins. Still honor the section limit, without further fades.
        c.fade, c.no_fade = nil, true
    end
    if paused or seeking or muted or volume <= 0 or mp.get_property("aid") == "no"
        or not finite(pos) or not finite(speed) or speed <= 0 then
        break_interval()
    else
        local previous = c.previous
        if previous then
            local dt, delta = now - previous.time, pos - previous.pos
            -- Refuse to bridge seeks, sleep, large stalls or speed changes.
            if dt > 0 and dt <= 3 and delta > 0 and delta <= dt * speed + 0.75
                and math.abs(speed - previous.speed) < 0.001 then
                record_interval(c, previous.pos, pos)
                c.elapsed = c.elapsed + delta / speed
            else c.open = nil end
        end
        c.previous = {time=now, pos=pos, speed=speed}
        if c.limit then
            local left = c.limit - c.elapsed
            if left <= 0.05 then advance_section(c); return end
            local fade_length = math.min(options.fade_seconds, c.limit)
            if fade_length > 0 and left < fade_length and not c.no_fade then
                if not c.fade then c.fade = {base=volume, last=volume} end
                local target = c.fade.base * math.max(0.001, left / fade_length)
                mp.set_property_number("volume", target)
                c.fade.last = target
            end
        end
    end
    if dirty and now - last_checkpoint >= options.checkpoint_seconds then save_sections() end
end
mp.add_periodic_timer(0.5, function()
    -- This limit is independent of track changes, seeks, pauses and the launcher.
    if not session_ended and options.session_seconds > 0
        and mp.get_time() - session_started >= options.session_seconds then
        session_ended = true
        finish_long()
        mp.commandv("quit")
        return
    end
    tick_sections()
end)
mp.register_event("seek", function() restore_fade(active_long); break_interval(); save_sections() end)
mp.register_event("playback-restart", break_interval)
for _, property in ipairs({"pause", "paused-for-cache", "mute", "seeking"}) do
    mp.observe_property(property, "bool", function() break_interval() end)
end
mp.register_event("shutdown", finish_long)

load_persistent_track_history()

-- Invalidate delayed seeks/skips when any file ends, starts or is reloaded.
-- Comparing URL alone is insufficient when the same song is loaded twice.
local generation = 0
local function invalidate_callbacks()
    generation = generation + 1
    finish_long()
end
mp.register_event("start-file", invalidate_callbacks)
mp.register_event("end-file", invalidate_callbacks)

-- =========================
-- MAIN RADIO LOGIC
-- =========================

mp.register_event("file-loaded", function()
    finish_long()
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
                    "Full-track playback: %s (%d:%02d, under %.0f min)",
                    title,
                    math.floor(duration / 60),
                    math.floor(duration % 60), options.min_duration_minutes
                )
            )
            mp.osd_message("Short track: no random jump", 2)
            return
        end

        if mp.get_property_native("seekable", true) == false then
            mp.msg.info("Stream is not seekable; section selection and sampling disabled.")
            return
        end
        local planned
        if options.section_mode then
            planned = math.random(math.max(1, math.floor(options.section_min_minutes * 60)),
                math.max(1, math.floor(options.section_max_minutes * 60)))
        end
        local percent_history = read_percent_history()
        local speed = mp.get_property_number("speed", 1)
        if not finite(speed) or speed <= 0 then speed = 1 end
        if planned then planned = math.min(planned, duration / speed) end
        local percent, exposure = select_section(key, duration, percent_history, planned and planned * speed)
        local start = duration * percent / 100
        local ok, err = mp.commandv("seek", tostring(start), "absolute", "exact")
        if ok == nil or ok == false then
            mp.msg.warn("Section seek failed: " .. tostring(err))
            return
        end
        save_percent_history(percent_history, percent)
        begin_long(key, title, duration, start, planned)
        local label = string.format("Fresh-section start: %d%% (%s)", percent, clock(start))
        if planned then label = label .. " | sample up to " .. clock(active_long.limit) end
        mp.osd_message(label, 4)
        mp.msg.info(string.format("%s: %s; weighted recent overlap %.3f", title, label, exposure))
    end)
end)
```
<!-- END RADIO LUA -->

</details>

**Check before continuing:** `C:\MPV\portable_config\scripts\random-start.lua` exists and is not named `random-start.lua.txt`. Its contents should match the complete supplied script. Keep any backup copies outside the `scripts` folder.

## 5. Copy the launcher files and create sampling settings

### Copy the files prepared at the beginning

Open the extracted project's **`payload`** folder in one File Explorer window and **`C:\MPV`** in another. Copy the following files from `payload` directly into `C:\MPV`:

| File to copy | Purpose |
| --- | --- |
| `Radio.ps1` | Starts/stops the radio and enforces the session duration. |
| `Radio-Hidden.cs` | Source code for the helper that prevents the extra terminal window. |
| `Build-HiddenStarter.ps1` | Builds that helper using Windows PowerShell and .NET. |
| `Check-Radio.ps1` | Checks whether MPV and the Lua script respond. |
| `Check Radio.cmd` | Opens the check above when double-clicked. |
| `Stop Radio.cmd` | Stops this installation's radio. |

Copy the **files themselves**, not an extra `payload` folder. In `C:\MPV`, confirm that these six files now appear beside `mpv.exe`.

### Build the hidden-start helper

In File Explorer open `C:\MPV`, click the address bar, type **`cmd`**, and press Enter. Run this command in the resulting **Command Prompt**:

```bat
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\MPV\Build-HiddenStarter.ps1"
```

The command uses **Windows PowerShell 5.1** and Windows' existing .NET Framework. It creates **`C:\MPV\Radio-Hidden.exe`**; you do not need to download an executable or install developer tools.

**Check before continuing:** the command reports `Built hidden starter: C:\MPV\Radio-Hidden.exe`, and that file appears in File Explorer. If the helper already exists, the build refuses to replace it: stop the radio and move that helper into a backup folder before rebuilding. If antivirus or another policy blocks the build or file, record the exact message; do not disable protection.

### Create the sampling-settings file

1. Open **Notepad → File → New** (or **New tab**) to get another blank document.
2. Paste these five lines:

```ini
section_mode=yes
min_duration_minutes=15
section_min_minutes=10
section_max_minutes=30
fade_seconds=5
```

3. Choose **File → Save As**, open the folder below through the save window's address bar, and save:

| Save As field | Enter or select |
| --- | --- |
| Folder | `C:\MPV\portable_config\script-opts` |
| File name | `random-start.conf` |
| Save as type | **All files** (`*.*`) |
| Encoding | **UTF-8** |

**Check before continuing:** `random-start.conf` is in **`script-opts`**, while `random-start.lua` is in **`scripts`**. Neither ends in `.txt`.

These defaults sample 10–30 minutes from eligible recordings at least 15 minutes long, shortened when the recording cannot supply the full allowance. `section_mode=no` turns sampling off while keeping smart starting points. `fade_seconds=0` turns the sample fade-out off. See the [defaults and adjustable limits](README.md#defaults-and-adjustable-limits) before changing values. Restart MPV after any later changes.

### Confirm the required files are in place

| Location | Files that must now be present |
| --- | --- |
| `C:\MPV` | `mpv.exe`, `mpv.com`, `yt-dlp.exe`, the six copied launcher/check files, and the newly built `Radio-Hidden.exe`. |
| `C:\MPV\portable_config` | `mpv.conf` |
| `C:\MPV\portable_config\scripts` | `random-start.lua` |
| `C:\MPV\portable_config\script-opts` | `random-start.conf` |

Keep all other files from the MPV build. `deno.exe` is optional. **Do not create history files yourself**; the Lua script creates them during playback.

## 6. Test playback before creating the schedules

Open **Command Prompt** in `C:\MPV` using File Explorer's address bar as above. Paste the entire command below and press Enter:

```bat
"C:\MPV\Radio-Hidden.exe" -Playlist "https://www.youtube.com/playlist?list=PLZAsCc2NQgn0" -DurationSeconds 180
```

This uses the Morning sample playlist for a **three-minute test**. You may replace the URL inside the quotes with your own complete YouTube playlist URL. Keep the quotes and `-DurationSeconds 180`.

1. Allow time for YouTube to load. Confirm that **one MPV window** opens and music comes from your chosen speaker. The Command Prompt you opened yourself may remain; scheduled starts will not open that window.
2. Click inside MPV and press **F8**. It should show the loaded radio script and the default settings: cutoff **15**, sampling **on**, range **10–30**.
3. While music is playing, use File Explorer to double-click **`C:\MPV\Check Radio.cmd`**. A separate diagnostic window should report **PASS** when the player and script respond. It pauses so you can read the result; press a key to close it.
4. Let the three-minute test finish and confirm MPV closes. To stop early, press **Q in MPV** or double-click **`C:\MPV\Stop Radio.cmd`**.

This short test checks startup, controls, the speaker, and stopping. It does **not** reach the normal 10–30-minute sample transition; test that during a longer session in step 9.

**Check before continuing:** playback, F8, the diagnostic check, and stopping work. If any fails, use [troubleshooting](#10-optional-shortcuts-and-troubleshooting) before adding schedules.

## 7. Create the Morning task manually

### Open Task Scheduler and set the account

1. Open Windows **Start**, search for **Task Scheduler**, and open it.
2. Select **Task Scheduler Library** in the left pane. This is where you will save the task.
3. In the right-hand **Actions** pane, click **Create Task**. Choose this rather than **Create Basic Task**, so all the tabs below are available.
4. On **General**, enter:

| Field | Value |
| --- | --- |
| Name | `Music - Morning` |
| When running the task, use the following user account | The Windows account that successfully played music in step 6. Use **Change User or Group** if a different account is shown. |
| Run only when user is logged on | Selected. |
| Run with highest privileges | Unchecked. |

Keep the Create Task window open as you move through the tabs.

### Add the weekly trigger

On **Triggers**, click **New** and enter:

| Field | Value |
| --- | --- |
| Begin the task | On a schedule. |
| Schedule | Weekly. |
| Start date | Today, or the first date you want this schedule to apply. |
| Start time | `06:45` (6:45 AM); check the AM/PM display if Windows uses it. |
| Recur every | `1` week. |
| Days | Monday, Tuesday, Wednesday, Thursday, Friday, Saturday. |
| Enabled | Checked. |

Leave **Repeat task every** and the trigger's **Stop task if it runs longer than** unchecked. The whole-task limit is configured under Settings below. Click **OK** to save the trigger and return to Create Task.

### Add the launcher action

On **Actions**, click **New**. Select **Start a program**, then fill the three fields **separately**:

**Program/script — paste this path:**

```text
C:\MPV\Radio-Hidden.exe
```

**Add arguments — paste this entire line:**

```text
-Playlist "https://www.youtube.com/playlist?list=PLZAsCc2NQgn0" -DurationSeconds 10800
```

**Start in — paste this folder path:**

```text
C:\MPV
```

These are Task Scheduler fields, not commands to run in a terminal. Keep the quotation marks around the playlist URL, and do not put the arguments into Program/script. Click **OK**. The Actions list should contain exactly **one** action.

**Maximum runtime is a DURATION, not the time of day to stop.** Manual task arguments use **seconds**. Choose a row below and replace only the number after `-DurationSeconds` if you want a different duration:

| Desired session | `-DurationSeconds` value |
| --- | --- |
| 45 minutes | `2700` |
| 1 hour | `3600` |
| 1 hour 30 minutes | `5400` |
| 3 hours (the example) | `10800` |
| 24 hours (maximum) | `86400` |

For other durations, multiply hours by **3600**. Pauses and loading count toward the session. The guided installer asks for hours instead; do not paste its `1.5` example into a manual seconds field.

### Conditions and Settings

On **Conditions**, check **Wake the computer to run this task**. Leave **Start the task only if the computer is idle** unchecked. Leave the normal AC-power conditions enabled unless you want the task to run on battery too.

On **Settings**, use:

| Setting | Value |
| --- | --- |
| Allow task to be run on demand | Checked. |
| Run task as soon as possible after a scheduled start is missed | Unchecked. |
| If the task fails, restart every | Checked; `5 minutes`. |
| Attempt to restart up to | `3` times. |
| Stop the task if it runs longer than | **3 hours 1 minute** (181 minutes) for the three-hour example. Set this to your selected session duration plus one minute. |
| If the running task does not end when requested, force it to stop | Checked. |
| If the task is already running, then the following rule applies | **Do not start a new instance**. |

The extra minute allows shutdown and history saving; it does not extend music playback. The launcher and Lua enforce `-DurationSeconds`.

Click **OK** at the bottom of Create Task to save it. If the chosen start time already passed today, the next automatic start will be on the next selected day.

**Check before continuing:** **Music - Morning** appears in Task Scheduler Library, has one weekly trigger and one launcher action, and shows the expected **Next Run Time**. Use F5 to refresh the task list if necessary.

## 8. Create the Day Finisher task

In **Task Scheduler Library**, choose **Create Task** again. Follow the same General, Triggers, Actions, Conditions, and Settings instructions from step 7, with these changes:

| Item | Day Finisher value |
| --- | --- |
| Task name | `Music - Day Finisher` |
| Start time | `15:45` (3:45 PM). |
| Days | Monday, Tuesday, Wednesday, Thursday, Friday. |
| Playlist URL in Add arguments | `https://www.youtube.com/playlist?list=PLBejJIaDgbyQ` |

For the same three-hour duration, **Add arguments** must contain this complete line:

```text
-Playlist "https://www.youtube.com/playlist?list=PLBejJIaDgbyQ" -DurationSeconds 10800
```

Keep **Program/script** as `C:\MPV\Radio-Hidden.exe` and **Start in** as `C:\MPV`. Click **OK** to save the task.

**Check before continuing:** both music tasks appear in Task Scheduler Library with their own playlist and intended schedule. A new radio session stops the previous radio session for this installation. The two schedules share listening history.

## 9. Test the saved tasks

1. In **Task Scheduler Library**, right-click **Music - Morning** and choose **Run**.
2. Confirm that MPV opens with the intended playlist and speaker, without an extra scheduled-start terminal. Press **F8** and run **Check Radio.cmd** as in step 6.
3. Double-click **Stop Radio.cmd**, then repeat the test for **Music - Day Finisher**.
4. For a real scheduled-start test, open one task's **Properties → Triggers**, select the trigger, and click **Edit**. Note its original values. Temporarily include today's weekday and set the time a few minutes ahead. Click **OK** in both windows and confirm **Next Run Time** reflects that test.
5. Leave Windows logged in and wait for the scheduled start. You can lock the screen with **Windows + L** to check locked-session playback. Afterward, restore the original trigger's date, time, and days and check Next Run Time again.
6. During a longer session, listen through one 10–30-minute sample transition, then stop normally. Open `C:\MPV\portable_config` and confirm the history files have appeared. Short songs do not receive sampling cutoffs.

For a sleep/wake test, repeat the temporary-trigger procedure, put the PC to sleep, and confirm whether it wakes and plays through the intended speaker. Wake behavior depends on Windows, power settings, and hardware. Restore the normal trigger afterward. A powered-off computer cannot be started by these tasks.

History files are created automatically: `recent-track-history.txt` remembers ten accepted starts, `random-start-history.txt` remembers ten selected percentages, and `heard-sections.txt` records played ranges. A normal stop saves sections; forced shutdowns can lose the latest unsaved portion. Avoid running another radio script against the same files at the same time.

## 10. Optional shortcuts and troubleshooting

### Clipboard playback shortcuts

The project's extracted `payload` folder also contains:

| File to copy into `C:\MPV` | Purpose |
| --- | --- |
| `Play-YouTube.ps1` | Required helper for both clipboard shortcuts below. |
| `Play YouTube on MPV Audio.cmd` | Play the copied YouTube link as audio. |
| `Play YouTube Video - 720p Best Audio Always On Top.cmd` | Play the copied link as video, capped at 720p. |
| `Update yt-dlp.cmd` | Update the YouTube helper when needed. |

After copying the files, right-click each desired `.cmd` in `C:\MPV` and choose **Send to → Desktop (create shortcut)**. On Windows 11, choose **Show more options** first if Send to is not visible. Keep the original files in `C:\MPV`.

To use a playback shortcut, copy one complete YouTube URL from your browser, then double-click the audio or video shortcut. It stops this installation's radio and opens normal manual playback without updating radio histories. Video stays on top. Command windows opened by manual shortcuts or diagnostics are separate from the hidden scheduled-start helper.

### If a step fails

| Problem | Check |
| --- | --- |
| Save As cannot find the folder | Return to step 1 and create the folders exactly as listed. |
| A file ends in `.txt` | Reopen it in Notepad and use the matching Save As table with **All files** selected. Confirm the final name in File Explorer. |
| A launcher file is missing | Return to step 5 and copy the six named files from the extracted project's `payload`, then build the helper. |
| No music or wrong speaker | Recheck the actual device ID from step 2, MPV's volume, and the speaker connection. Restart MPV after editing `mpv.conf`. |
| YouTube error | Check the URL/internet, run the optional `Update yt-dlp.cmd` copied above, and consider [Deno](README.md#optional-recommendation-deno). |
| Task runs but no MPV appears | Check its **Last Run Result** and open `C:\MPV\Radio-Hidden-error.log` in Notepad if it exists. Check its timestamp; later success does not erase an earlier error. |
| Antivirus message | Record the product name and full message; do not disable protection to complete a step. |

If MPV remains after a forced task termination, close its window with **Q** or double-click **Stop Radio.cmd**. For a complete reset of an earlier test, use the [start-over instructions](README.md#start-over-with-a-fresh-setup), which explain the loss of settings/history.

MPV supplies playback controls, seeking, shuffle, audio routing, and [JSON IPC](https://mpv.io/manual/stable/#json-ipc). This project adds schedules, history, and section selection. See [third-party software notes](THIRD_PARTY.md) for the separately obtained dependencies.

<details>
<summary>Technical notes: selection, history, and task behavior</summary>

MPV shuffles playlist entries; duplicate entries are not removed. The shuffled queue starts fresh after a restart, while listening history persists. Repeat protection considers at most five recent starts and reduces that number for small playlists so they still have choices.

Smart starts stay within 0%–75% of a recording and favor less recently heard overlap. Sampling narrows this range to leave room for the chosen allowance; percentage exclusions relax when necessary. With sampling off, selection scores up to 20 minutes ahead. Unknown-duration and nonseekable sources play normally.

Default section history retains at most 40 intervals per recording, 2,000 overall, and 180 days; the influence of recent listening halves every 14 days. Pauses, buffering, muted playback, and detected seeks are excluded. Saves occur about every 15 seconds and on normal file transitions or shutdown. Avoid running a separate copy of the radio script against the same histories at the same time.

The helper starts `Radio.ps1` without a console, waits, and returns its exit code. The supervisor coordinates starts for this installation, explicitly loads the Lua script once, and asks MPV to quit normally so history can be saved. Forced cleanup is limited to its own player. The supervisor and Lua both enforce session duration; Task Scheduler provides an extra minute for cleanup. Other user scripts are not automatically loaded during scheduled playback.

</details>
