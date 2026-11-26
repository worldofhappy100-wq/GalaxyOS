local Hockey={width=40,height=50,mallet=3.1,puck=1.15,gate=16}
local W,H=Hockey.width,Hockey.height
local R,P=Hockey.mallet,Hockey.puck
local difficulty={
    easy={speed=16,delay=0.32,error=3.5},
    normal={speed=22,delay=0.22,error=2.1},
    hard={speed=27,delay=0.14,error=0.9},
}
local function clamp(x, lo, hi) return math.max(lo,math.min(hi,x)) end
local function unit(x,y)
    local length=math.sqrt(x*x+y*y)
    if length==0 then return 0,0,0 end
    return x/length,y/length,length
end

local function place(s,towardsPlayer)
    s.player={x=W/2,y=H-10,vx=0,vy=0}
    s.bot={x=W/2,y=10,vx=0,vy=0}
    s.p={x=W/2,y=H/2,vx=(s.random()-.5)*9,vy=towardsPlayer and 7 or -7}
    s.think,s.delay=0,0.65
end

function Hockey.new(options, random)
    local s={score=0,enemy=0,target=options.limit or 7,ai=difficulty[options.difficulty] or difficulty.normal,
        random=random or math.random,cues={}}
    place(s,true)
    return s
end

function Hockey.action(s, action)
    if action=="left" or action=="right" or action=="up" or action=="down" then s.pointer=nil end
end

function Hockey.pointer(s,x,y)
    s.pointer={ x=clamp(x,R,W-R), y=clamp(y,H/2+R,H-R) }
end

local function move(m, x, y, speed, dt, low, high)
    local ux,uy,distance=unit(x-m.x,y-m.y)
    local stride=math.min(distance,speed*dt)
    local nx,ny=clamp(m.x+ux*stride,R,W-R),clamp(m.y+uy*stride,low,high)
    m.vx,m.vy=(nx-m.x)/dt,(ny-m.y)/dt
    m.x,m.y=nx,ny
end

function Hockey.botTarget(s)
    local p=s.p
    if p.y>H/2+2 and p.vy>=0 then
        return W/2+(p.x-W/2)*0.45,8
    end
    local error=(s.random()*2-1)*s.ai.error
    local lead=p.vy<0 and math.min(0.30,math.max(0,(p.y-11)/-p.vy)) or 0
    local x=clamp(p.x+p.vx*lead+error,R,W-R)
    if p.y>H/2-2 then return x, H/2-8 end
    return x,clamp(p.y-4,R,H/2-R)
end

local function cap(p)
    local x,y,speed=unit(p.vx,p.vy)
    if speed>45 then p.vx,p.vy=x*45,y*45 end
end

local function impact(s,mallet, direction)
    local p=s.p
    local x,y,distance=unit(p.x-mallet.x,p.y-mallet.y)
    if distance>=R+P then return end
    if distance==0 then x,y=0,direction end
    local normalSpeed=(p.vx-mallet.vx)*x+(p.vy-mallet.vy)*y
    p.x,p.y=mallet.x+x*(R+P+0.015),mallet.y+y*(R+P+0.015)
    if normalSpeed < -0.03 then
        local impulse=-1.76*normalSpeed
        p.vx,p.vy=p.vx+impulse*x,p.vy+impulse*y
        cap(p)
        s.cues.hit=true
    end
end

local function inGate(x)
    return math.abs(x-W/2)<=Hockey.gate/2-P
end

local function walls(s)
    local p=s.p
    if p.x<P then p.x,p.vx,s.cues.wall=P+P-p.x,math.abs(p.vx),true
    elseif p.x>W-P then p.x,p.vx,s.cues.wall=(W-P)*2-p.x,-math.abs(p.vx),true end
    if not inGate(p.x) then
        if p.y<P then p.y,p.vy,s.cues.wall=P,math.abs(p.vy),true
        elseif p.y>H-P then p.y,p.vy,s.cues.wall=H-P,-math.abs(p.vy),true end
        return
    end
    if p.y<=-P then
        s.score,s.cues.goal=s.score+1,true
        if s.score>=s.target then s.result="win" else place(s,true) end
    elseif p.y>=H+P then
        s.enemy,s.cues.lostPoint=s.enemy+1,true
        if s.enemy>=s.target then s.result="loss" else place(s,false) end
    end
end

function Hockey.step(s, held, dt)
    if s.result then return end
    local m=s.player
    local x=(held.right and 1 or 0)-(held.left and 1 or 0)
    local y=(held.down and 1 or 0)-(held.up and 1 or 0)
    local ux,uy=unit(x,y)
    local target=s.pointer
    move(m,target and target.x or m.x+ux*30*dt,target and target.y or m.y+uy*30*dt,30,dt,H/2+R,H-R)
    s.think=s.think-dt
    if s.think<=0 then s.think=s.ai.delay; s.aimX,s.aimY=Hockey.botTarget(s) end
    move(s.bot,s.aimX,s.aimY,s.ai.speed,dt,R,H/2-R)
    if s.delay>0 then s.delay=s.delay-dt; return end
    local p=s.p
    p.x,p.y=p.x+p.vx*dt,p.y+p.vy*dt
    local drag=math.max(0,1-dt*0.47)
    p.vx,p.vy=p.vx*drag,p.vy*drag
    impact(s,s.player,-1)
    impact(s,s.bot,1)
    walls(s)
end

return Hockey
