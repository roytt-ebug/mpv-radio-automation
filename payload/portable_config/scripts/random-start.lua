-- random-start.lua
-- Radio-style playlist helper for MPV
--
-- Designed to be used with:
--   --shuffle --loop-playlist=inf
--
-- Behavior:
--   * MPV handles playlist shuffle.
--   * Recently played tracks are remembered persistently and skipped.
--   * Tracks shorter than 20 minutes always start at 0:00.
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

    local id =
        path:match("[?&]v=([%w_-]+)") or
        path:match("youtu%.be/([%w_-]+)")

    if id then
        return "youtube:" .. id
    end

    return path
end

local function load_persistent_track_history()
    if not PERSIST_TRACK_HISTORY then
        return
    end

    local file = io.open(TRACK_HISTORY_FILE, "r")
    if not file then
        return
    end

    for line in file:lines() do
        local key = line:match("^[^|]*|(.+)$")
        if key and key ~= "" then
            table.insert(recent_tracks, key)
        end
    end

    file:close()

    while #recent_tracks > MAX_RECENT_TRACKS do
        table.remove(recent_tracks, 1)
    end
end

local function save_persistent_track_history()
    if not PERSIST_TRACK_HISTORY then
        return
    end

    local file = io.open(TRACK_HISTORY_FILE, "w")
    if not file then
        mp.msg.warn("Could not write recent-track history file.")
        return
    end

    for _, key in ipairs(recent_tracks) do
        file:write(
            os.date("%Y-%m-%d %H:%M:%S"),
            "|",
            key,
            "\n"
        )
    end

    file:close()
end

local function recent_track_limit()
    local count = mp.get_property_number("playlist-count", 1) or 1
    local safe_limit = math.max(0, count - 1)
    return math.min(MAX_RECENT_TRACKS, safe_limit)
end

local function trim_recent_tracks()
    local limit = recent_track_limit()

    while #recent_tracks > limit do
        table.remove(recent_tracks, 1)
    end
end

local function track_is_recent(key)
    if not key then
        return false
    end

    for _, recent_key in ipairs(recent_tracks) do
        if recent_key == key then
            return true
        end
    end

    return false
end

local function remember_track(key)
    if not key then
        return
    end

    trim_recent_tracks()

    local limit = recent_track_limit()
    if limit <= 0 then
        return
    end

    table.insert(recent_tracks, key)

    while #recent_tracks > limit do
        table.remove(recent_tracks, 1)
    end

    save_persistent_track_history()
end

load_persistent_track_history()

-- =========================
-- MAIN RADIO LOGIC
-- =========================

mp.register_event("file-loaded", function()
    local path = mp.get_property("path")
    local key = track_key(path)
    local title = mp.get_property("media-title") or "track"

    trim_recent_tracks()

    if recent_track_limit() > 0 and track_is_recent(key) then
        mp.msg.info("Skipping recently played track: " .. title)
        mp.osd_message("Skipping recent track: " .. title, 2)

        mp.add_timeout(0.05, function()
            mp.commandv("playlist-next", "weak")
        end)

        return
    end

    -- Track history is recorded for ALL tracks, short or long.
    remember_track(key)

    local expected_key = key

    mp.add_timeout(1, function()
        local current_key = track_key(mp.get_property("path"))

        if expected_key and current_key ~= expected_key then
            return
        end

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
            mp.osd_message("Playing full track from 0:00", 2)
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
