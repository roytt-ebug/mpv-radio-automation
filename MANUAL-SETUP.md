# Manual setup: MPV Radio Automation for Windows

[Back to README](README.md)

This is an **alternative to running the installer**, not an extra installation step. It creates scheduled background music with dedicated audio routing, ten-track history, smarter starting points for long recordings and optional section sampling.

Already configured? Back up `C:\MPV` and export your existing tasks first. Stop MPV before replacing code. Edit existing tasks rather than creating duplicates. Keep only one active radio script; save backups outside `portable_config\scripts`.

## 1. Install MPV and the YouTube helper separately

Start at [mpv's installation page](https://mpv.io/installation/) and follow its Windows-build link. This project has used [Shinchiro](https://github.com/shinchiro/mpv-winbuild-cmake/releases). For Windows x64 choose `mpv-x86_64-...7z`; expand **Show all assets** when necessary. Do not select the `dev`, `i686`, or `aarch64` variant for an x64 installation.

Extract the **complete player archive** to `C:\MPV`, not just the executable. Do not run it inside WinRAR. No file-association registration is required for this project.

Get `yt-dlp.exe` from the [official yt-dlp releases](https://github.com/yt-dlp/yt-dlp/releases/latest) and put it beside `mpv.exe`. Use the appropriate x64 executable. It is a command-line helper; double-clicking it without a URL is not an installation test. Follow [upstream JavaScript-runtime guidance](https://github.com/yt-dlp/yt-dlp/wiki/EJS) as required for YouTube; the runtime is a separate dependency, not bundled here.

Minimum layout:

```text
C:\MPV\
    mpv.exe
    mpv.com
    yt-dlp.exe
    ...other files from the MPV build...
    portable_config\
        mpv.conf
        scripts\
            random-start.lua
        script-opts\
            random-start.conf    (optional sampling settings)
```

Create missing folders in File Explorer. Turn on **View -> File name extensions** (on Windows 11: View -> Show -> File name extensions).

## 2. Find the output device

In File Explorer open `C:\MPV`, click the address bar, type `cmd`, and press Enter. In Command Prompt run:

```bat
mpv.com --no-config --load-scripts=no --audio-device=help
```

Use `mpv.com` for console diagnostics. Copy the **entire ID** for your chosen music speaker, for example `wasapi/{11111111-2222-3333-4444-555555555555}`. That is an example, not a working device ID. Do not copy only the number inside braces or the descriptive speaker name. Leave Windows' default output on your normal headset when keeping music separate.

## 3. Save the player configuration

In Notepad paste:

```ini
audio-device=PASTE_YOUR_COMPLETE_DETECTED_DEVICE_ID_HERE
vid=no
ytdl-format=bestaudio/best
force-window=yes
```

Replace the placeholder with your full detected ID. Use **File -> Save As**, choose **All files**, and save exactly `C:\MPV\portable_config\mpv.conf`, not `mpv.conf.txt`. This makes scheduled music audio-only but retains a visible control window. Space pauses/resumes with the player focused; Q quits.

## 4. Save the radio Lua script

Save the **complete code below** in Notepad as `C:\MPV\portable_config\scripts\random-start.lua`, with **All files** selected. Do not include the Markdown backticks. Alternatively, copy [the source file](payload/portable_config/scripts/random-start.lua) to that location.

Short tracks under 20 minutes are not randomly seeked. Longer seekable recordings favor less-recently-played portions within 0%-75%. Ten accepted starts and ten selected percentages persist. The new section log is separate and starts building after this update; it cannot infer what you heard yesterday from an old starting percentage alone.

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
--   * Tracks 20+ minutes favor less-recently-heard sections within 0%-75%.
--   * Estimated played intervals checkpoint every 15 seconds.
--   * Optional 20-40 minute section sampling with fade-out is OFF by default.
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
    section_mode = false,
    section_min_minutes = 20,
    section_max_minutes = 40,
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
checked_option("section_min_minutes", 20, 0.01, 1440)
checked_option("section_max_minutes", 40, 0.01, 1440)
checked_option("fade_seconds", 5, 0, 60)
checked_option("preference_window_minutes", 20, 0.01, 1440)
checked_option("recency_half_life_days", 14, 0.01, 3650)
checked_option("history_max_age_days", 180, 1, 3650)
checked_option("history_max_intervals", 2000, 10, 10000)
checked_option("history_per_recording", 40, 1, 200)
checked_option("checkpoint_seconds", 15, 1, 300)
if options.section_min_minutes > options.section_max_minutes then
    mp.msg.warn("Section minimum exceeds maximum; using 20-40 minutes.")
    options.section_min_minutes, options.section_max_minutes = 20, 40
end
local SECTION_FILE = "C:\\MPV\\portable_config\\heard-sections.txt"
local SECTION_HEADER = "# MPV heard-sections v1"
local heard, dirty = {}, false
local active_long
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
            table.insert(result, 1, item)
            counts[item.key] = count + 1
        end
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
local function eligible_percentages(history)
    local recent, candidates = {}, {}
    for _, item in ipairs(history) do recent[item.percent] = true end
    local last = history[#history] and history[#history].percent
    for p = 0, MAX_START_PERCENT do
        if not recent[p] and (not last or math.abs(p - last) >= MIN_PERCENT_GAP_FROM_LAST) then
            candidates[#candidates + 1] = p
        end
    end
    if #candidates == 0 then
        for p = 0, MAX_START_PERCENT do if not recent[p] then candidates[#candidates+1] = p end end
    end
    if #candidates == 0 then for p=0,MAX_START_PERCENT do candidates[#candidates+1]=p end end
    return candidates
end
local function select_section(key, duration, history, planned_seconds)
    -- Compare equal-sized look-ahead windows so a late start is not favored just
    -- for having less remaining audio. Every allowed start has this much room.
    local window = math.min(planned_seconds or options.preference_window_minutes * 60,
        duration * (1 - MAX_START_PERCENT / 100))
    local candidates, best, winners = eligible_percentages(history), math.huge, {}
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
mp.add_periodic_timer(0.5, tick_sections)
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
                    "Full-track playback: %s (%d:%02d, under 20 min)",
                    title,
                    math.floor(duration / 60),
                    math.floor(duration % 60)
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

## 5. Optional section sampling (leave off for uninterrupted mixes)

Without extra settings, long mixes continue from the chosen point until they end or you stop playback. To instead rotate through long mixes, create `C:\MPV\portable_config\script-opts\random-start.conf` with:

```ini
section_mode=yes
section_min_minutes=20
section_max_minutes=40
fade_seconds=5
```

Restart MPV. Sampling selects a fresh 20-40-minute listening allowance for each qualifying mix, capped by remaining content. Pauses, detected seeks, buffering and muted time do not use that allowance. Normal songs under 20 minutes are not truncated. Fade-out is a volume ramp, not a crossfade; there may be a network gap before the next item. Set `section_mode=no` to disable sampling.

These are **three different controls**: recording eligibility (20 minutes), optional per-mix sampling allowance (20-40 minutes), and the overall task runtime (for example three hours). Do not substitute one for another.

A complete optional template is at [random-start.conf.example](payload/portable_config/script-opts/random-start.conf.example). It is not loaded or installed automatically. Advanced options cover the selection look-ahead, recency decay, bounded history and checkpoint interval. For sampling on one task only, add `--script-opts-append=random-start-section_mode=yes` to that task's arguments instead of enabling it globally.

## 6. Test audio and history before scheduling

In Command Prompt at `C:\MPV`:

```bat
yt-dlp.exe --version
mpv.com --shuffle --loop-playlist=inf "https://www.youtube.com/playlist?list=PLZAsCc2NQgn0"
```

This Morning sample is optional; substitute your own playlist. Confirm the expected speaker and player controls. Long mixes should display a fresh-section starting message; short songs should not jump randomly. Listen long enough to create a checkpoint (normally 15 seconds). Test a pause and a manual seek, then close MPV normally and inspect:

```text
C:\MPV\portable_config\recent-track-history.txt
C:\MPV\portable_config\random-start-history.txt
C:\MPV\portable_config\heard-sections.txt
```

The last file's final column is the recording range, such as `42:37-68:10`. It contains estimated forward-played intervals, not buffered audio or proof someone was listening. Pauses, seeks and sleep gaps are not joined into a false continuous listen. The first two histories retain their established formats.

Section state is bounded (40 intervals per recording, 2,000 overall, 180 days by default), and only one MPV process should write it. A forced termination can lose the unsaved tail; `.bak` stores a previous complete checkpoint. Existing track history cannot reconstruct previously heard intervals. Unknown-duration/non-seekable media are left alone. See README for selection limitations and configurable settings.

## 7. Create the Morning task manually

Open **Task Scheduler -> Create Task**, not Create Basic Task. Name it **Music - Morning**. On **General**, select your normal Windows user and **Run only when user is logged on**. Do not enable highest privileges. A locked screen still leaves you logged in; signing out does not.

On **Triggers -> New**, choose **On a schedule -> Weekly -> Every 1 week**, select **Monday-Saturday**, leave Sunday unchecked, choose **06:45 AM**, and enable it. These are suggestions; use your preferred local time/days.

On **Actions**, create these two **Start a program** actions in this order.

**Action 1: stop accessible older MPV playback**

Program/script:

```text
C:\Windows\System32\cmd.exe
```

Add arguments:

```text
/c "taskkill /F /IM mpv.exe >nul 2>&1 & exit /b 0"
```

Leave **Start in** blank. If Windows is installed elsewhere, use its actual `System32\cmd.exe` path. This action closes accessible MPV instances, including manual videos; it is not limited to the morning player. Force-closing cannot guarantee a final history flush or fade.

**Action 2: start the Morning playlist**

Program/script:

```text
C:\MPV\mpv.exe
```

Add arguments:

```text
--shuffle --loop-playlist=inf "https://www.youtube.com/playlist?list=PLZAsCc2NQgn0"
```

Start in (no quotes needed):

```text
C:\MPV
```

Keep both actions in the same task. Do not use `--load-scripts=no` here; that bypasses all radio behavior.

On **Conditions**, leave the idle requirement off and enable **Wake the computer to run this task**. Leave the network-condition requirement off. AC-power restrictions are retained by the installer; use the same choices here or deliberately review battery behavior on a laptop.

On **Settings**, allow on-demand execution, leave missed-start catch-up off, retry failures every **5 minutes** up to **3** times, stop after **3 hours**, allow forced stopping, and choose **Do not start a new instance**. Do not enable automatic task deletion.

**Maximum runtime is a DURATION, not the time of day to stop.** Three hours after 06:45 is approximately 09:45 for an uninterrupted on-time run. Retry/delay/interruption can change actual timing. The scheduler limit is not a reliable fade-out timer.

## 8. Create the Day Finisher task

Repeat the same task-creation process, changing these values:

- Name: **Music - Day Finisher**.
- Trigger suggestion: **15:45 / 3:45 PM, Monday-Friday**.
- Maximum runtime suggestion: **3 hours** (editable).
- Second action's **Add arguments**:

```text
--shuffle --loop-playlist=inf "https://www.youtube.com/playlist?list=PLBejJIaDgbyQ"
```

Keep the first action, executable path, working directory, speaker and radio script the same. These external sample playlists are optional and can change; they are not login credentials or music bundled with the project. See [playlist instructions](EXAMPLE-PLAYLISTS.md) to replace links in existing tasks without reinstalling.

The tasks share local histories. Avoid overlapping schedules unless replacing current playback is intentional. The same-task duplicate setting does not prevent two differently named tasks from starting together.

## 9. Test the scheduled task

Close manually launched MPV first. Save the task, right-click it and choose **Run**. Verify playback on the selected speaker. A task may report that it is running while music continues; wait for completion to interpret its final result.

For a real schedule test, temporarily choose a start a few minutes ahead, lock Windows, and verify it starts. Test waking separately with the speaker connected. Restore your desired time afterward. Task Scheduler cannot start a fully powered-off PC; wake support and Windows wake timers matter. Speakers that power off or disconnect must be made available separately.

Do not create new copies of these tasks each time you change a playlist. Edit the existing action or disable the older task first.

## 10. Optional clipboard launchers and updates

Without running the installer, copy these files from `payload` to `C:\MPV`:

- `Play YouTube on MPV Audio.cmd`
- `Play YouTube Video - 720p Best Audio Always On Top.cmd`
- `Update yt-dlp.cmd`
- `README-LOCAL.txt`

Create desktop shortcuts to the first two. Copy a YouTube link, then open the desired launcher. The audio launcher keeps the configured output; the video launcher overrides audio-only mode, selects at most 720p video plus best available audio, and keeps a resizable window on top. These launchers close accessible existing MPV instances and use `--load-scripts=no`, so they do **not** randomize or contribute to radio history.

If YouTube fails, update yt-dlp and follow its current upstream runtime guidance. For diagnostics use `mpv.com`, not only `mpv.exe`, so errors stay visible in Command Prompt. Verify the full speaker ID, the three exact config filenames, and only one active radio script. Keep backups and history files private.

## Reference and upgrade notes

The supported MPV mechanisms are documented in the [official manual](https://mpv.io/manual/stable/): Lua events/timers, script options, audio routing, seek and playlist commands. This guide supplies automation code, not third-party binaries or content rights; see [THIRD_PARTY.md](THIRD_PARTY.md).

For code-only updates, close MPV, back up and replace `random-start.lua`, keep configuration/history files, then restart. The optional sampling `.conf` is separate and need not be recreated. Changes to this GitHub repository do not automatically update an installed computer.
