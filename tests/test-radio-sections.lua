-- Deterministic tests against the real Lua script; no Windows, network or audio.
local script = arg[1] or 'payload/portable_config/scripts/random-start.lua'
local root = 'C:\\MPV\\portable_config\\'
local SECTIONS, TRACK, PERCENT = root..'heard-sections.txt', root..'recent-track-history.txt', root..'random-start-history.txt'
local checks = 0
local function eq(a,b,label) checks=checks+1; assert(a==b,(label or '')..': '..tostring(a)..' ~= '..tostring(b)) end
local function near(a,b,label) checks=checks+1; assert(math.abs(a-b)<1.1,(label or '')..': '..a..' vs '..b) end
local function url(n) return 'https://www.youtube.com/watch?v=test'..string.format('%07d',n) end
local function playlist(n) local t={}; for i=1,n do t[i]={filename=url(i),title='Mix '..i} end; return t end
local function rows(text) local t={}; for row in (text or ''):gmatch('[^\r\n]+') do t[#t+1]=row end; return t end
local function ranges(text)
    local t={}
    for _,row in ipairs(rows(text)) do
        if row:sub(1,1)~='#' then
            local key,a,b,epoch,duration,title,display=row:match('^[^|]+|([^|]+)|([^|]+)|([^|]+)|([^|]+)|([^|]+)|([^|]*)|(.*)$')
            if key then t[#t+1]={key=key,a=tonumber(a),b=tonumber(b),epoch=tonumber(epoch),duration=tonumber(duration),title=title,display=display} end
        end
    end
    return t
end
local function boot(config,files)
    local s={files=files or {}, now=0, epoch=1788918000, events={}, observers={}, timers={}, ticks={}, commands={}, props={volume=80,speed=1,seekable=true}, warnings={}}
    local env=setmetatable({}, {__index=_G})
    env.require=function(name)
        assert(name=='mp.options'); return {read_options=function(o) for k,v in pairs(config or {}) do o[k]=v end end}
    end
    env.os={
        time=function() return s.epoch+math.floor(s.now) end,
        date=function(format,epoch) return os.date(format,epoch or s.epoch+math.floor(s.now)) end,
        remove=function(path) s.files[path]=nil; return true end,
        rename=function(a,b)
            if s.fail_rename_to==b then return nil,'simulated rename failure' end
            if s.files[a]==nil or s.files[b]~=nil then return nil end
            s.files[b]=s.files[a]; s.files[a]=nil; return true
        end
    }
    env.io={open=function(path,mode)
        if s.fail_open==path then return nil,'simulated permission error' end
        if mode=='r' and s.files[path]==nil then return nil end
        if mode=='w' then s.files[path]='' end
        return {
            lines=function() local r=rows(s.files[path]); local i=0; return function() i=i+1; return r[i] end end,
            write=function(self,...)
                for i=1,select('#',...) do s.files[path]=s.files[path]..tostring(select(i,...)) end
                return self
            end,
            close=function() return true end
        }
    end}
    function s:emit(event) for _,fn in ipairs(self.events[event] or {}) do fn() end end
    function s:set(name,value) self.props[name]=value; for _,fn in ipairs(self.observers[name] or {}) do fn(name,value) end end
    env.mp={
        get_time=function() return s.now end,
        get_property=function(k,default) local v=s.props[k]; if v==nil then return default end; return v end,
        get_property_number=function(k,default) local v=s.props[k]; if v==nil then return default end; return v end,
        get_property_native=function(k,default) local v=s.props[k]; if v==nil then return default end; return v end,
        set_property_number=function(k,v) s:set(k,v) end,
        register_event=function(k,fn) s.events[k]=s.events[k] or {}; table.insert(s.events[k],fn) end,
        observe_property=function(k,kind,fn) s.observers[k]=s.observers[k] or {}; table.insert(s.observers[k],fn) end,
        add_timeout=function(dt,fn) s.timers[#s.timers+1]=fn; return {kill=function() end} end,
        add_periodic_timer=function(dt,fn) s.ticks[#s.ticks+1]=fn; return {kill=function() end} end,
        osd_message=function() end,
        msg={info=function() end,warn=function(m) s.warnings[#s.warnings+1]=m end},
        commandv=function(k,a)
            s.commands[#s.commands+1]={k,a}
            if k=='seek' then
                if s.fail_seek then return nil,'simulated seek error' end
                s:emit('seek'); s.props['time-pos']=tonumber(a); s:emit('playback-restart')
            end
            if k=='playlist-play-index' then s.jump=tonumber(a) end
            return true
        end
    }
    local chunk
    if _VERSION=='Lua 5.1' then chunk=assert(loadfile(script)); setfenv(chunk,env)
    else chunk=assert(loadfile(script,'t',env)) end
    chunk()
    function s:drain() local timers=self.timers; self.timers={}; for _,fn in ipairs(timers) do fn() end end
    function s:load(list,index,duration,defer)
        self:emit('end-file'); self.jump=nil
        self.props.playlist=list; self.props['playlist-pos']=index; self.props['playlist-count']=#list
        self.props.path=list[index+1].filename; self.props['media-title']=list[index+1].title
        self.props.duration=duration; self.props['time-pos']=0
        self:emit('start-file'); self:emit('file-loaded'); if not defer then self:drain() end
    end
    function s:accept(list,index,duration)
        for i=1,#list+1 do
            self:load(list,index,duration)
            if self.jump==nil then return self.props.path end
            index=self.jump
        end
        error('unbounded repeat-filter loop')
    end
    function s:tick(dt,advance)
        self.now=self.now+dt
        if advance then self.props['time-pos']=self.props['time-pos']+advance end
        for _,fn in ipairs(self.ticks) do fn() end
    end
    function s:play(seconds)
        for i=1,math.floor(seconds*2) do self:tick(0.5,0.5*self.props.speed) end
    end
    function s:seek(pos) self:emit('seek'); self.props['time-pos']=pos; self:emit('playback-restart') end
    function s:count(command) local n=0; for _,c in ipairs(self.commands) do if c[1]==command then n=n+1 end end; return n end
    return s
end
if ... == 'harness' then return {boot=boot, rows=rows, playlist=playlist, url=url} end
-- Long-mix history records progression, not the entire remaining recording.
local one=playlist(1); local s=boot(); s:load(one,0,7200)
local start=s.props['time-pos']; s:play(60); s:emit('end-file')
local r=ranges(s.files[SECTIONS]); eq(#r,1,'one continuous interval'); near(r[1].a,start+0.5,'range start'); near(r[1].b,start+60,'range end')
eq(r[1].b<7200,true,'not pretending rest was heard'); eq(s:count('playlist-next'),0,'sampling disabled by default')
-- Short tracks still log accepted starts but never receive a random seek or section timer.
s=boot({section_mode=true,section_min_minutes=0.1,section_max_minutes=0.1}); s:load(one,0,1199); s:play(30); s:emit('end-file')
eq(s:count('seek'),0,'short no seek'); eq(s.files[SECTIONS],nil,'short no section history'); eq(#rows(s.files[TRACK]),1,'short track retained'); eq(s:count('playlist-next'),0,'short not sampled')
-- Pause, buffering, seeking, muting and a suspended process do not bridge gaps.
s=boot(); s:load(one,0,7200); s:play(10)
s:set('pause',true); s:tick(60,0); s:set('pause',false); s:play(10)
s:set('paused-for-cache',true); s:tick(30,0); s:set('paused-for-cache',false); s:play(10)
s:set('mute',true); s:play(20); s:set('mute',false); s:play(10)
s:seek(6000); s:play(10); s:tick(100,100); s:play(10); s:emit('end-file')
r=ranges(s.files[SECTIONS]); eq(#r>=6,true,'discontinuities split intervals')
local total=0; for _,row in ipairs(r) do total=total+row.b-row.a; eq(row.b-row.a<11,true,'no large seek or sleep range') end
near(total,57,'only forward active playback counted')
-- A checkpoint survives an abrupt process loss, and keeps a backup of a complete file.
s=boot(); s:load(one,0,7200); s:play(35)
eq(s.files[SECTIONS]~=nil,true,'checkpoint written during playback'); eq(s.files[SECTIONS..'.bak']~=nil,true,'previous complete checkpoint')
local checkpoint=ranges(s.files[SECTIONS])[1].b; eq(s.props['time-pos']-checkpoint<=15,true,'bounded uncheckpointed tail')
local storage=s.files; s=boot(nil,storage); s:load(one,0,7200); s:play(5); s:emit('end-file'); eq(#ranges(s.files[SECTIONS])>=2,true,'restart preserves prior ranges')
-- Bad primary header recovers from backup. Interrupted rename recovers from backup too.
local good=storage[SECTIONS]; local broken={[SECTIONS]='corrupt',[SECTIONS..'.bak']=good}
s=boot(nil,broken); s:load(one,0,7200); s:play(3); s:emit('end-file'); eq(#ranges(s.files[SECTIONS])>=3,true,'backup recovery')
s=boot(nil,{[SECTIONS]=good}); s:load(one,0,7200); s.fail_rename_to=SECTIONS; s:play(20)
eq(s.files[SECTIONS..'.bak']~=nil,true,'rename failure leaves complete backup')
s=boot(nil,{[SECTIONS..'.bak']=good}); s:load(one,0,7200); s:play(3); s:emit('end-file'); eq(#ranges(s.files[SECTIONS])>=3,true,'missing-primary recovery')
-- Disk failure warns but does not interrupt music or falsely claim a persisted history.
s=boot(); s.fail_open=SECTIONS..'.tmp'; s:load(one,0,7200); s:play(20); eq(#s.warnings>0,true,'checkpoint failure warned'); eq(s.files[SECTIONS],nil,'failed write not created')
-- Fresh audio is preferred over a recently heard first half, separately for each video.
local function row(key,a,b,age,duration)
 return string.format('2026-09-08 00:00:00|%s|%s|%s|%s|%s|Example|range\n',key,a,b,1788918000-age,duration)
end
local header='# MPV heard-sections v1\n'
for i=1,50 do
 s=boot(nil,{[SECTIONS]=header..row('youtube:test0000001',0,3600,0,7200)})
 s:load(one,0,7200); eq(s.props['time-pos']>=3600,true,'prefer unheard half')
end
-- If all audio has been covered, prefer older sections; same start fractions on other videos do not matter.
s=boot(nil,{[SECTIONS]=header..row('youtube:test0000001',0,3600,28*86400,7200)..row('youtube:test0000001',3600,7200,0,7200)})
s:load(one,0,7200); eq(s.props['time-pos']<=2400,true,'prefer older first-half window')
-- Duration mismatch, unknown lengths and non-seekable streams are handled conservatively.
s=boot(nil,{[SECTIONS]=header..row('youtube:test0000001',0,3600,0,3600)})
s:load(one,0,7200); eq(s:count('seek'),1,'edited duration remains usable')
s=boot(); s.props.seekable=false; s:load(one,0,7200); s:play(5); eq(s:count('seek'),0,'nonseekable untouched'); eq(s.files[SECTIONS],nil,'nonseekable not treated as fixed timeline')
s=boot(); s:load(one,0,nil); eq(s:count('seek'),0,'unknown duration untouched')
s=boot(); s.fail_seek=true; s:load(one,0,7200); s:play(5); eq(s.files[PERCENT],nil,'failed seek does not consume percentage'); eq(s.files[SECTIONS],nil,'failed seek no false section')
-- Sample countdown follows actual forward playback, not paused time, and restores gain.
s=boot({section_mode=true,section_min_minutes=0.2,section_max_minutes=0.2,fade_seconds=4})
s:load(playlist(3),0,7200); s:play(8); s:set('pause',true); s:tick(60,0); eq(s:count('playlist-next'),0,'paused sample never advances')
s:set('pause',false); s:play(2); eq(s.props.volume<80,true,'fade started'); s:play(4)
eq(s:count('playlist-next'),1,'one automatic advance'); eq(s.props.volume,80,'gain restored for next song'); eq(s.files[SECTIONS]~=nil,true,'history saved before next')
-- Manual skip restores an unfinished fade; changing volume by hand wins.
s=boot({section_mode=true,section_min_minutes=0.2,section_max_minutes=0.2,fade_seconds=5}); s:load(one,0,7200); s:play(10); eq(s.props.volume<80,true,'fade before skip'); s:emit('end-file'); eq(s.props.volume,80,'skip restores gain')
s=boot({section_mode=true,section_min_minutes=0.2,section_max_minutes=0.2,fade_seconds=5}); s:load(one,0,7200); s:play(10); s.props.volume=33; s:play(1); s:emit('end-file'); eq(s.props.volume,33,'human volume change preserved')
-- Infinite playlists wrap explicitly after the final sample and reshuffle when requested.
s=boot({section_mode=true,section_min_minutes=0.1,section_max_minutes=0.1}); s.props['loop-playlist']='inf'; s.props.shuffle=true; s:load(playlist(3),2,7200); s:play(8)
eq(s:count('playlist-shuffle'),1,'reshuffle on sample wrap'); eq(s.jump,0,'wrap to first entry'); eq(s:count('playlist-next'),0,'do not terminate loop')
-- Closed/stale timer from the previous file cannot seek or fade a new file.
s=boot(); s:load(one,0,7200); s:play(3); s:emit('end-file'); local n=s:count('seek'); s:play(30); eq(s:count('seek'),n,'no stale seek')
-- Actual listening time budget compensates for speed, while ranges stay in recording seconds.
s=boot({section_mode=true,section_min_minutes=0.1,section_max_minutes=0.1}); s.props.speed=2; s:load(playlist(3),0,7200); s:play(8); eq(s:count('playlist-next'),1,'six listening seconds at double speed')
-- Limits and sanitization: many starts stay bounded, unsafe titles cannot add history rows.
s=boot({history_per_recording=3}); one[1].title='Jazz | Cafe\nnew row'; s:load(one,0,7200)
for i=1,8 do s:seek(i*300); s:play(3) end; s:emit('end-file'); r=ranges(s.files[SECTIONS]); eq(#r,3,'per-recording cap'); eq(r[3].title,'Jazz   Cafe new row','safe title fields')
-- Retained tracks and percentage history remain ten entries.
s=boot(); one=playlist(1)
for i=1,15 do s:load(one,0,1200) end
eq(#rows(s.files[TRACK]),10,'ten track starts kept'); eq(#rows(s.files[PERCENT]),10,'ten percentages kept')
local seen={}; for _,p in ipairs(rows(s.files[PERCENT])) do local n=tonumber(p:match('|(%d+)$')); eq(seen[n],nil,'percentage exclusion kept'); seen[n]=true end
print('PASS: '..checks..' section-selection, tracking, persistence, sampling and regression checks (mocked MPV).')
