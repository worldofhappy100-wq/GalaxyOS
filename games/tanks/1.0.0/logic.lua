local Tanks={ w=23,h=15 }
local vectors={ up={0,-1},right={1,0},down={0,1},left={-1,0} }
local directions={"down","left","right","up"}
local classes={
    {kind="scout",hp=1,pace=0.31,fire=1.1,points=100},
    {kind="gunner",hp=1,pace=0.43,fire=0.65,points=160},
    {kind="armor",hp=2,pace=0.56,fire=1.25,points=220},
}
local waves={ 6,8,11 }
local rewards={"shield","speed","weapon","life"}
local W,H=Tanks.w,Tanks.h
local bx,by=12,H
local function key(x,y) return (y-1)*W+x end
local function inside(x,y) return x>=1 and x<=W and y>=1 and y<=H end

local function map(level)
    local grid={}
    local function row(y,first,last,tile)
        for x=first,last do grid[key(x,y)]=tile end
    end
    local kind=(level-1)%3+1
    for y=4,11,2 do
        if kind==1 then
            row(y,3,7,"brick"); row(y,17,21,"brick")
            if y%4==0 then row(y,10,14,"steel") end
        elseif kind==2 then
            row(y,3,9,y==6 and "steel" or "brick"); row(y,15,21,y==8 and "steel" or "brick")
            if y%4==2 then grid[key(12,y)]="steel" end
        else
            row(y,5,8,"steel"); row(y,16,19,"brick")
            row(y+1,10,14,"brick")
        end
    end
    grid[key(bx,by-1)],grid[key(bx-1,by)],grid[key(bx+1,by)]="brick","brick","brick"
    return grid
end

local function begin(s)
    s.grid,s.enemies,s.shots,s.effects=map(s.level),{},{},{}
    s.drop,s.spawnClock = nil, 0.5
    s.remaining=s.survival and math.min(22,5+s.level*2) or waves[s.level]
    s.player.x,s.player.y,s.player.dir,s.player.move=bx-3,by-1,"up",0
    s.player.invuln=1.2
end

function Tanks.new(options)
    local s={ survival=options.mode=="survival", level=1, player={}, lives=3, base=3,
        score=0,kills=0,fire=0,shield=0,speed=0,weapon=false,cues={} }
    begin(s)
    return s
end

local function tankAt(s,x,y,enemy)
    if s.player.x==x and s.player.y==y then return s.player end
    for _,tank in ipairs(s.enemies) do
        if tank~=enemy and tank.x==x and tank.y==y and tank.hp>0 then return tank end
    end
end

local function clear(s,x,y,tank)
    return inside(x,y) and (x~=bx or y~=by) and not s.grid[key(x,y)] and not tankAt(s,x,y,tank)
end

local function move(s,tank,dir)
    if not dir then return end
    local delta=vectors[dir]
    tank.dir=dir
    local x,y=tank.x+delta[1],tank.y+delta[2]
    if clear(s,x,y,tank) then tank.x,tank.y=x,y end
end

local function effect(s,x,y,blast)
    s.effects[#s.effects+1]={x=x,y=y,life=blast and 0.22 or 0.11,blast=blast}
end

local function fire(s,tank,enemy)
    if #s.shots>=25 then return end
    s.shots[#s.shots+1]={x=tank.x,y=tank.y,dir=tank.dir,enemy=enemy,clock=0,
        power=not enemy and s.weapon and 2 or 1}
    effect(s,tank.x,tank.y,false)
    if not enemy then s.cues.shot=true end
end

function Tanks.action(s,action)
    if s.result then return end
    if vectors[action] then
        s.player.dir,s.player.queued,s.player.move=action,action,0
    elseif action=="fire" and s.fire<=0 then
        fire(s,s.player,false); s.fire=s.weapon and 0.22 or 0.39
    end
end

local function damage(s,shot,x,y)
    local k=key(x,y)
    local tile=s.grid[k]
    if tile then
        if tile=="brick" then s.grid[k]=nil end
        effect(s,x,y,true)
        if not shot.enemy then s.cues.blast=true end
        return true
    end
    if x==bx and y==by then
        if shot.enemy then
            s.base,s.cues.blast=s.base-1,true
            effect(s,x,y,true)
            if s.base<=0 then s.result="loss" end
        end
        return true
    end
    if shot.enemy then
        local p=s.player
        if p.x==x and p.y==y then
            if s.shield<=0 and p.invuln<=0 then
                s.lives,s.cues.blast=s.lives-1,true
                effect(s,x,y,true)
                if s.lives<=0 then s.result="loss"
                else
                    p.invuln,p.move=1.25,0
                    for _, spawnX in ipairs({bx-3,bx+3,bx-6,bx+6}) do
                        if clear(s,spawnX,by-1) then p.x,p.y=spawnX,by-1; break end
                    end
                end
            end
            return true
        end
    else
        local tank=tankAt(s,x,y)
        if tank and tank~=s.player then
            tank.hp=tank.hp-shot.power
            s.cues.blast=true
            effect(s,x,y,true)
            if tank.hp<=0 then
                s.score,s.kills=s.score+tank.model.points,s.kills+1
                if s.kills%2==0 and not s.drop then
                    local reward=rewards[(math.floor(s.kills/2)-1)%#rewards+1]
                    s.drop={x=x,y=y,kind=reward,life=16}
                end
            end
            return true
        end
    end
end

local function direct(s,tank,tx,ty)
    if tank.x~=tx and tank.y~=ty then return end
    local dir=tank.x==tx and (tank.y<ty and "down" or "up") or (tank.x<tx and "right" or "left")
    local v=vectors[dir]
    local x,y=tank.x+v[1],tank.y+v[2]
    while x~=tx or y~=ty do
        if s.grid[key(x,y)]=="steel" then return end
        x,y=x+v[1],y+v[2]
    end
    return dir
end

local function route(s,tank,tx,ty)
    local here=key(tank.x,tank.y)
    local nodes,visited,head={{x=tank.x,y=tank.y}},{[here]=true},1
    local best,closest=nil,math.abs(tx-tank.x)+math.abs(ty-tank.y)
    while head<=#nodes do
        local node=nodes[head]
        head=head+1
        for _,dir in ipairs(directions) do
            local v=vectors[dir]
            local x,y=node.x+v[1],node.y+v[2]
            local k=key(x,y)
            if inside(x,y) and not visited[k] and clear(s,x,y,tank) then
                local nextNode={x=x,y=y,first=node.first or dir}
                visited[k]=true
                nodes[#nodes+1]=nextNode
                local distance=math.abs(tx-x)+math.abs(ty-y)
                if distance<closest then
                    closest,best=distance,nextNode.first
                    if distance<=1 then return best end
                end
            end
        end
    end
    return best
end

local function spawn(s)
    for i=1,3 do
        local x=({2,12,22})[(i+s.level+s.remaining)%3+1]
        if clear(s,x,2) then
            local model=classes[(s.remaining+s.level)%#classes+1]
            s.enemies[#s.enemies+1]={x=x,y=2,dir="down",hp=model.hp,model=model,move=0.25,fire=1}
            s.remaining=s.remaining-1
            return
        end
    end
end

function Tanks.step(s,held,dt)
    if s.result then return end
    local p=s.player
    s.fire,s.shield,s.speed,p.invuln=s.fire-dt,s.shield-dt,s.speed-dt,p.invuln-dt
    p.move=p.move-dt
    if p.move<=0 then
        local nextDir=p.queued or held[p.dir] and p.dir
        if not nextDir then for _,dir in ipairs(directions) do if held[dir] then nextDir=dir; break end end end
        move(s,p,nextDir)
        p.queued=nil
        p.move=nextDir and (s.speed>0 and 0.085 or 0.13) or 0
    end
    if held.fire then Tanks.action(s,"fire") end
    s.spawnClock=s.spawnClock-dt
    if s.spawnClock<=0 and s.remaining>0 and #s.enemies<math.min(5,2+s.level) then
        spawn(s)
        s.spawnClock=math.max(0.52,1.25-s.level*0.1)
    end
    for _,tank in ipairs(s.enemies) do
        tank.fire,tank.move=tank.fire-dt,tank.move-dt
        local tx,ty=bx,by
        local distance=math.abs(p.x-tank.x)+math.abs(p.y-tank.y)
        if distance<=8 or tank.model.kind=="scout" then tx,ty=p.x,p.y end
        local aim=direct(s,tank,tx,ty)
        if aim and tank.fire<=0 then
            tank.dir,tank.fire,tank.move=aim,tank.model.fire,math.max(0.10,tank.move)
            fire(s,tank,true)
        elseif tank.move<=0 then
            tank.move=math.max(0.20,tank.model.pace-0.015*(s.level-1))
            local dir=route(s,tank,tx,ty)
            if not dir then
                for _,d in ipairs(directions) do
                    local v=vectors[d]
                    local x,y=tank.x+v[1],tank.y+v[2]
                    if clear(s,x,y,tank) then dir=d; break end
                end
            end
            move(s,tank,dir)
        end
    end
    for i=#s.shots,1,-1 do
        local shot=s.shots[i]
        shot.clock=shot.clock+dt
        local period=shot.power>1 and 0.049 or 0.075
        if shot.clock>=period then
            shot.clock=shot.clock-period
            local v=vectors[shot.dir]
            local x,y=shot.x+v[1],shot.y+v[2]
            if not inside(x,y) or damage(s,shot,x,y) then table.remove(s.shots,i)
            else shot.x,shot.y=x,y end
        end
        if s.result then break end
    end
    for i=#s.enemies,1,-1 do if s.enemies[i].hp<=0 then table.remove(s.enemies,i) end end
    for i=#s.effects,1,-1 do
        local fx=s.effects[i]
        fx.life=fx.life-dt
        if fx.life<=0 then table.remove(s.effects,i) end
    end
    local drop=s.drop
    if drop then
        drop.life=drop.life-dt
        if drop.x==p.x and drop.y==p.y then
            if drop.kind=="life" then s.lives=s.lives+1
            elseif drop.kind=="shield" then s.shield=7
            elseif drop.kind=="speed" then s.speed=9
            else s.weapon=true end
            s.drop,s.cues.pickup=nil,true
        elseif drop.life<=0 then s.drop=nil end
    end
    if not s.result and s.remaining==0 and #s.enemies==0 then
        if not s.survival and s.level>=#waves then s.result="win"
        else s.level,s.cues.level=s.level+1,true; begin(s) end
    end
end

return Tanks
