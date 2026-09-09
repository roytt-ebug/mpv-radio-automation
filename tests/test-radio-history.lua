-- Legacy history/cooldown regression suite, using the shared mock player harness.
-- No MPV, sound, network or Windows task registration is required.
local support = assert(loadfile('tests/test-radio-sections.lua'))('harness')
local boot, rows, entries, url = support.boot, support.rows, support.playlist, support.url
local TRACK = 'C:\\MPV\\portable_config\\recent-track-history.txt'
local PERCENT = 'C:\\MPV\\portable_config\\random-start-history.txt'
local checks=0
local function equal(a,b,label) checks=checks+1; assert(a==b,(label or '')..': '..tostring(a)..' ~= '..tostring(b)) end
local function stamp(s) return os.date('%Y-%m-%d %H:%M:%S',s.epoch+math.floor(s.now)) end
-- Retention is independent of playlist size, including a single song.
local s=boot(); local one=entries(1); local stamps={}
for i=1,12 do s.now=i*60; stamps[i]=stamp(s); s:accept(one,0,240) end
local h=rows(s.files[TRACK]); equal(#h,10,'one song keeps ten starts')
equal(h[1],stamps[3]..'|youtube:test0000001|Mix 1','oldest real timestamp')
equal(h[10],stamps[12]..'|youtube:test0000001|Mix 1','newest real timestamp')
equal(s:count('seek'),0,'short songs not seeked'); equal(s.files[PERCENT],nil,'short songs no percentage'); equal(s:count('playlist-play-index'),0,'one song never blocked')
-- Legacy two-column migration and restart preserve timestamps.
local storage={[TRACK]='2026-09-01 07:00:00|youtube:test0000042\n2026-09-02 07:00:00|youtube:test0000043\n'}
s=boot(nil,storage); s:accept(one,0,240); equal(rows(s.files[TRACK])[1],'2026-09-01 07:00:00|youtube:test0000042|','legacy timestamp retained')
s=boot(nil,storage); s:accept(one,0,240); equal(#rows(s.files[TRACK]),4,'history across restart')
-- More than ten unique tracks retain last ten starts.
s=boot(); local list=entries(15)
for i=1,15 do s:accept(list,i-1,180) end
h=rows(s.files[TRACK]); equal(#h,10,'fifteen starts trimmed to ten'); equal(h[1]:match('|([^|]+)|'),'youtube:test0000006','oldest is six'); equal(h[10]:match('|([^|]+)|'),'youtube:test0000015','newest is fifteen')
-- Two tracks can alternate even with ten recorded starts.
s=boot(); list=entries(2)
for i=1,12 do equal(s:accept(list,0,200),url(((i-1)%2)+1),'two-track alternation') end
equal(#rows(s.files[TRACK]),10,'two tracks keep ten events')
-- Four tracks protect only two recent starts, avoiding a forced four-cycle.
s=boot(); list=entries(4); for i=1,3 do s:accept(list,i-1,200) end
local n=s:count('playlist-play-index'); s:accept(list,0,200); equal(s:count('playlist-play-index'),n,'first allowed after two intervening starts')
-- Duplicate rows are not additional unique choices.
s=boot(); list={{filename=url(1),title='A'},{filename=url(1)..'&list=OTHER',title='A duplicate'}}
for i=1,12 do s:accept(list,(i-1)%2,200) end
equal(s:count('playlist-play-index'),0,'all duplicates still playable'); equal(#rows(s.files[TRACK]),10,'duplicate starts recorded')
-- Recently played final entry wraps; filtered candidates are not recorded.
s=boot(); list=entries(4); s:accept(list,3,200); s:load(list,3,200)
equal(s.jump,0,'recent last entry wraps'); equal(#rows(s.files[TRACK]),1,'filtered repeat not logged')
-- Long tracks preserve the threshold and ten-percentage exclusion window.
s=boot({section_mode=false}); one=entries(1)
for i=1,15 do
 s:accept(one,0,900)
 local seen={}
 for _,row in ipairs(rows(s.files[PERCENT])) do
  local p=tonumber(row:match('|(%d+)$'))
  equal(p>=0 and p<=75,true,'percentage range'); equal(seen[p],nil,'no exact recent percentage'); seen[p]=true
 end
end
equal(#rows(s.files[PERCENT]),10,'ten selected percentages'); equal(#rows(s.files[TRACK]),10,'ten long starts'); equal(s:count('seek'),15,'15-minute threshold inclusive')
s:accept(one,0,899); equal(s:count('seek'),15,'under threshold unchanged')
-- Unsafe titles cannot insert records or columns.
s=boot(); list={{filename=url(1),title='Jazz | Café\nNew line'}}; s:accept(list,0,240)
equal(#rows(s.files[TRACK]),1,'safe row count'); equal(rows(s.files[TRACK])[1]:match('|[^|]+|(.+)$'),'Jazz   Café New line','safe title')
-- Deferred callback cannot seek a new instance of the same URL.
s=boot(); one=entries(1); s:load(one,0,3600,true); s:load(one,0,3600,true); s:drain(); equal(s:count('seek'),1,'stale same-URL callback invalidated')
s:load(one,0,3600,true); s:emit('end-file'); s:drain(); equal(s:count('seek'),1,'stopped callback invalidated')
-- An existing history containing every track cannot deadlock a small playlist.
storage={[TRACK]=''}
for i=1,10 do storage[TRACK]=storage[TRACK]..'2026-09-01 01:00:00|youtube:test'..string.format('%07d',((i-1)%3)+1)..'\n' end
s=boot(nil,storage); s:accept(entries(3),0,180); equal(#rows(s.files[TRACK]),10,'full legacy history remains playable')
print('PASS: '..checks..' history, cooldown, migration and seek regression checks (mocked MPV).')
