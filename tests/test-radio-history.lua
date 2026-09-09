-- Run: lua tests/test-radio-history.lua [path/to/random-start.lua]
-- Tests the actual script with fake MPV properties/events and in-memory files.
-- No audio, network, Windows task registration or real history writes.
local script = arg[1] or 'payload/portable_config/scripts/random-start.lua'
local TRACK = 'C:\\MPV\\portable_config\\recent-track-history.txt'
local PERCENT = 'C:\\MPV\\portable_config\\random-start-history.txt'
local checks = 0
local function equal(actual, expected, message)
    checks = checks + 1
    assert(actual == expected, (message or '') .. ': expected ' .. tostring(expected) .. ', got ' .. tostring(actual))
end
local function rows(text)
    local result = {}
    for line in (text or ''):gmatch('[^\r\n]+') do result[#result+1] = line end
    return result
end
local function url(i) return 'https://www.youtube.com/watch?v=test' .. string.format('%07d', i) end
local function entries(count)
    local result = {}
    for i=1,count do result[i] = { filename=url(i), title='Song ' .. i } end
    return result
end
local function boot(storage)
    local s = { files=storage or {}, events={}, timers={}, seeks={}, messages={}, jumps={}, props={}, stamp='2026-09-08 07:00:00' }
    local env = setmetatable({}, {__index=_G})
    env.os = { time=os.time, date=function() return s.stamp end }
    env.io = { open=function(path, mode)
        if mode == 'r' and s.files[path] == nil then return nil end
        if mode == 'w' then s.files[path] = '' end
        return {
            lines=function()
                local data = rows(s.files[path]); local i=0
                return function() i=i+1; return data[i] end
            end,
            write=function(self, ...)
                for i=1,select('#', ...) do s.files[path] = s.files[path] .. tostring(select(i, ...)) end
                return self
            end,
            close=function() return true end
        }
    end }
    env.mp = {
        get_property=function(name) return s.props[name] end,
        get_property_number=function(name, default) local v=s.props[name]; if v == nil then return default end; return v end,
        get_property_native=function(name, default) return s.props[name] or default end,
        register_event=function(name, callback) s.events[name]=callback end,
        add_timeout=function(_, callback) s.timers[#s.timers+1]=callback; return {kill=function() end} end,
        osd_message=function(text) s.messages[#s.messages+1]=text end,
        msg={info=function() end, warn=function() end},
        commandv=function(name, a)
            if name == 'seek' then s.seeks[#s.seeks+1]=tonumber(a) end
            if name == 'playlist-play-index' then s.jumps[#s.jumps+1]=tonumber(a); s.next_index=tonumber(a) end
        end
    }
    local chunk
    if _VERSION == 'Lua 5.1' then chunk=assert(loadfile(script)); setfenv(chunk, env)
    else chunk=assert(loadfile(script, 't', env)) end
    chunk()
    function s:drain()
        local timers=self.timers; self.timers={}
        for _, callback in ipairs(timers) do callback() end
    end
    function s:load(playlist, index, duration)
        if self.events['end-file'] then self.events['end-file']() end
        self.props['playlist']=playlist; self.props['playlist-pos']=index
        self.props['playlist-count']=#playlist; self.props['duration']=duration
        self.props['path']=playlist[index+1].filename; self.props['media-title']=playlist[index+1].title
        self.next_index=nil
        if self.events['start-file'] then self.events['start-file']() end
        self.events['file-loaded']()
    end
    function s:accept(playlist, index, duration)
        for _=1,#playlist+1 do
            self:load(playlist,index,duration)
            if self.next_index == nil then self:drain(); return self.props.path end
            index=self.next_index
        end
        error('unbounded skip loop')
    end
    return s
end
-- Retention: not reduced to playlist-count minus one; applies even to one song.
local s = boot(); local one=entries(1)
for i=1,12 do s.stamp=string.format('2026-09-08 07:%02d:00',i); s:accept(one,0,240) end
local history=rows(s.files[TRACK])
equal(#history,10,'one-song playlist retains ten starts')
equal(history[1],'2026-09-08 07:03:00|youtube:test0000001|Song 1','oldest surviving timestamp')
equal(history[10],'2026-09-08 07:12:00|youtube:test0000001|Song 1','newest timestamp')
equal(#s.seeks,0,'short tracks not seeked'); equal(s.files[PERCENT],nil,'short tracks consume no percentages')
equal(#s.jumps,0,'one song is never blocked')
-- Restart retains history. Legacy two-column records migrate without erasing timestamps.
local old = { [TRACK]='2026-09-01 07:00:00|youtube:test0000042\n2026-09-02 07:00:00|youtube:test0000043\n' }
s=boot(old); s:accept(one,0,240); history=rows(s.files[TRACK])
equal(history[1],'2026-09-01 07:00:00|youtube:test0000042|','legacy timestamp retained')
s=boot(old); s:accept(one,0,240)
equal(#rows(s.files[TRACK]),4,'restart loads existing records')
-- More than ten unique tracks retain the last ten events, not the repeat window.
s=boot(); local list=entries(15)
for i=1,15 do s:accept(list,i-1,180) end
history=rows(s.files[TRACK]); equal(#history,10,'15 unique songs -> 10 retained')
equal(history[1]:match('|([^|]+)|'),'youtube:test0000006','oldest ID is song six')
equal(history[10]:match('|([^|]+)|'),'youtube:test0000015','newest ID is song fifteen')
-- Two-track playlist blocks only the previous track, not the entire ten-entry history.
s=boot(); list=entries(2)
for i=1,12 do equal(s:accept(list,0,200),url(((i-1)%2)+1),'two-track alternation') end
equal(#rows(s.files[TRACK]),10,'two-track retention independent from cooldown')
-- Four tracks: protect last two, allowing choices rather than a forced four-cycle.
s=boot(); list=entries(4)
for i=1,3 do s:accept(list,i-1,200) end
local jumps=#s.jumps
s:accept(list,0,200); equal(#s.jumps,jumps,'first of four allowed after two intervening starts')
-- Duplicate rows are one unique track, so cannot blacklist every choice.
s=boot(); list={{filename=url(1),title='A'},{filename=url(1)..'&list=OTHER',title='A duplicate'}}
for i=1,12 do s:accept(list,(i-1)%2,200) end
equal(#s.jumps,0,'all duplicate rows remain playable'); equal(#rows(s.files[TRACK]),10,'duplicate starts recorded')
-- A recent final entry wraps to an eligible entry, and filtered candidates are not logged.
s=boot(); list=entries(4); s:accept(list,3,200)
s:load(list,3,200); equal(s.next_index,0,'repeat at final index wraps')
equal(#rows(s.files[TRACK]),1,'automatically filtered repeat not recorded')
-- Long tracks retain percentage behavior and a separate last-ten percentage history.
s=boot(); one=entries(1)
for i=1,15 do
    s:accept(one,0,1200)
    local percentages=rows(s.files[PERCENT]); local seen={}
    for _,row in ipairs(percentages) do
        local p=tonumber(row:match('|(%d+)$'))
        equal(p>=0 and p<=75,true,'percent range')
        equal(seen[p],nil,'no exact recent percentage repeat'); seen[p]=true
    end
end
equal(#rows(s.files[PERCENT]),10,'ten percentage values retained')
equal(#rows(s.files[TRACK]),10,'ten long track starts retained')
equal(#s.seeks,15,'twenty-minute threshold inclusive')
s:accept(one,0,1199); equal(#s.seeks,15,'under twenty minutes not seeked')
-- Titles are readable but cannot inject extra records/columns.
s=boot(); list={{filename=url(1),title='Jazz | Café\nNew line'}}; s:accept(list,0,240)
equal(#rows(s.files[TRACK]),1,'title newline sanitized')
equal(rows(s.files[TRACK])[1]:match('|[^|]+|(.+)$'),'Jazz   Café New line','title kept safely')
-- A stale one-second timer must not seek a newly loaded/reloaded song.
s=boot(); one=entries(1); s:load(one,0,3600); s:load(one,0,3600); s:drain()
equal(#s.seeks,1,'same-URL reload cancels old seek')
s:load(one,0,3600); s.events['end-file'](); s:drain()
equal(#s.seeks,1,'stopped file cancels delayed seek')
-- Legacy history may contain every track. Small-playlist cooldown must still unblock choices.
local store={ [TRACK]='' }; for i=1,10 do store[TRACK]=store[TRACK]..'2026-09-01 01:00:00|youtube:test'..string.format('%07d',((i-1)%3)+1)..'\n' end
s=boot(store); list=entries(3); s:accept(list,0,180)
equal(#rows(s.files[TRACK]),10,'full legacy history neither deadlocks nor shrinks')
print('PASS: '..checks..' history, cooldown, migration and seek checks; mocked MPV only.')
