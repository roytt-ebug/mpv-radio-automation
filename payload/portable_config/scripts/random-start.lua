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
--   * 10-30 minute section sampling is ON by default.
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
    managed = false,
    min_duration_minutes = 15,
    crossfade_seconds = 5,
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
checked_option("crossfade_seconds", 5, 0, 60)
checked_option("min_duration_minutes", 15, 0.01, 1440)
MIN_RANDOM_START_DURATION = options.min_duration_minutes * 60
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
local SECTION_FILE = CONFIG_DIR .. "heard-sections.txt"
local SECTION_HEADER = "# MPV heard-sections v1"
local heard, dirty = {}, false
local active_long
local prepared, managed_playing = nil, false
local managed_pending = {}
local command_sequence = 0
local last_controller_seen = mp.get_time()
local VERSION = "2026.09-radio-crossfade-1"
local json = require("mp.utils").format_json
local function publish_status()
    local pos = mp.get_property_number("time-pos", 0)
    local duration = mp.get_property_number("duration", 0)
    local speed = math.max(0.01, mp.get_property_number("speed", 1))
    local remaining = duration > 0 and math.max(0, (duration - pos) / speed) or -1
    if active_long and active_long.limit then remaining = math.min(remaining, math.max(0, active_long.limit-active_long.elapsed)) end
    local status = {
        version=VERSION, managed=options.managed, ready=prepared ~= nil,
        playing=managed_playing, sequence=command_sequence,
        section_mode=options.section_mode, min_duration_minutes=options.min_duration_minutes,
        section_min_minutes=options.section_min_minutes, section_max_minutes=options.section_max_minutes,
        fade_seconds=options.fade_seconds, crossfade_seconds=options.crossfade_seconds,
        checkpoint_seconds=options.checkpoint_seconds, path=mp.get_property("path", ""),
        title=mp.get_property("media-title", ""), remaining=remaining, position=pos,
        sample_limit=active_long and active_long.limit or 0,
        paused=mp.get_property_native("pause", false),
        buffering=mp.get_property_native("paused-for-cache", false),
        seeking=mp.get_property_native("seeking", false),
        eof=mp.get_property_native("eof-reached", false),
        audio_device=mp.get_property("audio-device", "auto")
    }
    mp.set_property("user-data/radio-status", json(status))
end
local function show_status()
    local text = string.format("Radio %s | %s | cutoff %.0f min | samples %s %.0f-%.0f min | %s",
        VERSION, options.managed and "controller connected" or "standalone script loaded",
        options.min_duration_minutes, options.section_mode and "ON" or "OFF",
        options.section_min_minutes, options.section_max_minutes,
        options.managed and ("crossfade " .. options.crossfade_seconds .. " s") or "sequential fade (no overlap)")
    mp.msg.info(text)
    mp.osd_message(text, 8)
    publish_status()
end
mp.add_key_binding("F8", "radio-status", show_status)
mp.register_script_message("radio-status", show_status)
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
    if options.managed then
        local current = read_sections(SECTION_FILE) or read_sections(SECTION_FILE .. ".bak") or {}
        for _, item in ipairs(managed_pending) do
            if item.saved then
                for i = #current, 1, -1 do
                    local old = current[i]
                    if old.key == item.key and old.first == item.saved.first
                        and old.last == item.saved.last and old.heard_at == item.saved.heard_at then
                        table.remove(current, i)
                        break
                    end
                end
            end
            current[#current+1] = item
        end
        table.sort(current, function(a,b) return a.heard_at < b.heard_at end)
        heard = current
    end
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
    if options.managed then
        for _, item in ipairs(managed_pending) do
            item.saved = {first=tonumber(string.format("%.3f",item.first)),
                last=tonumber(string.format("%.3f",item.last)), heard_at=item.heard_at}
        end
        -- Only the open interval can change again; older entries are now on disk.
        managed_pending = active_long and active_long.open and {active_long.open} or {}
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
    if not options.managed then save_sections() end
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
        if options.managed then managed_pending[#managed_pending+1] = item end
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
    if not c or (options.managed and not managed_playing) then return end
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
        if c.limit and not options.managed then
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
    if not options.managed and dirty and now - last_checkpoint >= options.checkpoint_seconds then save_sections() end
end
mp.add_periodic_timer(0.5, function()
    if options.managed and mp.get_time() - last_controller_seen > 15 then
        mp.msg.warn("Radio controller disconnected; stopping this managed player.")
        mp.commandv("quit")
        return
    end
    tick_sections(); publish_status()
end)
mp.register_script_message("radio-heartbeat", function() last_controller_seen = mp.get_time() end)
mp.register_event("seek", function() restore_fade(active_long); break_interval(); if not options.managed then save_sections() end end)
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
    prepared, managed_playing = nil, false
    finish_long()
    publish_status()
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

    if not options.managed and key and blocked[key] then
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
    if not options.managed then remember_track(key, title) end

    mp.add_timeout(1, function()
        if generation ~= expected_generation then return end

        local duration = mp.get_property_number("duration")
        prepared = {key=key, title=title}
        if not duration or duration <= 0 then publish_status(); return end

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
        if options.managed then
            heard = read_sections(SECTION_FILE) or read_sections(SECTION_FILE .. ".bak") or {}
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
        if options.managed then prepared.percent = percent
        else save_percent_history(percent_history, percent) end
        begin_long(key, title, duration, start, planned)
        local label = string.format("Fresh-section start: %d%% (%s)", percent, clock(start))
        if planned then label = label .. " | sample up to " .. clock(active_long.limit) end
        mp.osd_message(label, 4)
        mp.msg.info(string.format("%s: %s; weighted recent overlap %.3f", title, label, exposure))
    end)
end)

-- The controller sends these commands one deck at a time and waits for sequence
-- acknowledgement. Preloading alone never counts as an accepted/heard track.
mp.register_script_message("radio-activate", function()
    if not options.managed or not prepared or managed_playing then return end
    recent_tracks = {}
    load_persistent_track_history()
    remember_track(prepared.key, prepared.title)
    if prepared.percent then save_percent_history(read_percent_history(), prepared.percent) end
    managed_playing = true
    break_interval()
    command_sequence = command_sequence + 1
    publish_status()
end)
mp.register_script_message("radio-checkpoint", function()
    if not options.managed then return end
    save_sections()
    command_sequence = command_sequence + 1
    publish_status()
end)
mp.register_script_message("radio-finish", function()
    if not options.managed then return end
    tick_sections()
    finish_long()
    save_sections()
    prepared, managed_playing = nil, false
    command_sequence = command_sequence + 1
    publish_status()
end)

mp.register_script_message("radio-ping", function()
    command_sequence = command_sequence + 1
    publish_status()
end)
