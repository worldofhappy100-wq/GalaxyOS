local Pong={ width=60,height=34,paddle=8,radius=0.7 }
local settings={
    easy={ speed=12, delay=0.33, error=5.0 },
    normal={ speed=17, delay=0.22, error=3.0 },
    hard={ speed=22, delay=0.15, error=1.4 },
}
local leftFace,rightFace=5+Pong.radius,55-Pong.radius

local function clamp(n,lo,hi) return math.max(lo,math.min(hi,n)) end
local function paddle(y)
    return clamp(y,Pong.paddle/2,Pong.height-Pong.paddle/2)
end
local function reflected(y)
    local low,high=Pong.radius,Pong.height-Pong.radius
    local span=high-low
    local offset=(y-low)%(2*span)
    if offset>span then return high-(offset-span) end
    return low+offset
end

local function advanceY(s, dt)
    local nextY=s.y+s.vy*dt
    if nextY < Pong.radius or nextY > Pong.height-Pong.radius then
        s.y,s.vy,s.cues.wall=reflected(nextY),-s.vy,true
    else s.y=nextY end
end

local function serve(s,direction)
    local angle=(s.random()*0.62+0.14)*(s.random(2)==1 and -1 or 1)
    s.x,s.y,s.speed,s.delay=Pong.width/2,Pong.height/2,21,0.58
    s.vx,s.vy=math.cos(angle)*s.speed*direction,math.sin(angle)*s.speed
end

function Pong.new(options, random)
    local center=Pong.height/2
    local s={ player=center,bot=center,ai=settings[options.difficulty] or settings.normal,
        random=random or math.random, p=0,b=0,score=0,target=options.limit or 7, think=0, cues={} }
    serve(s,-1)
    return s
end

function Pong.action(s,action)
    if action=="up" or action=="down" then s.pointer=nil end
end

function Pong.pointer(s,_,y) s.pointer=paddle(y) end

local function approach(current,target,speed,dt)
    return current+clamp(target-current,-speed*dt,speed*dt)
end

function Pong.botTarget(s)
    if s.vx<=0 or s.x >= rightFace then return Pong.height/2 end
    local time=(rightFace-s.x)/s.vx
    return paddle(reflected(s.y+time*s.vy)+(s.random()*2-1)*s.ai.error)
end

function Pong.step(s, held, dt)
    if s.result then return end
    local motion=(held.down and 1 or 0)-(held.up and 1 or 0)
    local aim=s.pointer or s.player+motion*42*dt
    s.player=paddle(approach(s.player,aim,48,dt))
    s.think=s.think-dt
    if s.think<=0 then s.think=s.ai.delay; s.aim=Pong.botTarget(s) end
    s.bot=paddle(approach(s.bot,s.aim,s.ai.speed,dt))
    if s.delay>0 then s.delay=s.delay-dt; return end
    local nextX=s.x+s.vx*dt
    local right=s.vx>0
    local face=right and rightFace or leftFace
    if (right and s.x<=face and nextX>=face) or (not right and s.x>=face and nextX<=face) then
        local center=right and s.bot or s.player
        local at=(face-s.x)/s.vx
        local y=reflected(s.y+s.vy*at)
        local offset=(y-center)/(Pong.paddle/2)
        if math.abs(offset)<=1+Pong.radius/(Pong.paddle/2) then
            advanceY(s,at)
            local angle=clamp(offset,-1,1)*0.97
            s.speed=math.min(42,s.speed+1.55)
            s.vx=math.cos(angle)*s.speed*(right and -1 or 1)
            s.vy=math.sin(angle)*s.speed
            s.x=face+s.vx*(dt-at)
            advanceY(s,dt-at)
            s.cues.hit=true
            return
        end
    end
    s.x=nextX
    advanceY(s,dt)
    if s.x < -Pong.radius then
        s.b,s.cues.lostPoint=s.b+1,true
        if s.b>=s.target then s.result="loss" else serve(s,1) end
    elseif s.x > Pong.width+Pong.radius then
        s.p,s.cues.goal=s.p+1,true
        s.score=s.p
        if s.p>=s.target then s.result="win" else serve(s,-1) end
    end
end

return Pong
