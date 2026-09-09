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
