local Game = { width=9, height=16, target=36 }
local shapes = {
    { "....", "####", "....", "...." },
    { "#..", "###", "..." }, { "..#", "###", "..." },
    { "##", "##" }, { ".##", "##.", "..." }, { ".#.", "###", "..." }, { "##.", ".##", "..." },
}
local rotations = {}
for id, shape in ipairs(shapes) do
    local len, tiles = #shape, {}
    for y,row in ipairs(shape) do for x=1,len do
        if row:sub(x,x) == "#" then tiles[#tiles+1]={x-1,y-1} end
    end end
    rotations[id]={}
    for r=1,4 do
        rotations[id][r]=tiles
        if id~=4 then
            local rotated={}
            for i,p in ipairs(tiles) do rotated[i]={len-p[2]-1,p[1]} end
            tiles=rotated
        end
    end
end

function Game.cells(id, rotation) return rotations[id][rotation or 1] end

local function fits(s,id,rotation,x,y)
    for _, p in ipairs(Game.cells(id,rotation)) do
        local px,py=x+p[1],y+p[2]
        if px<1 or px>Game.width or py>Game.height or (py>0 and s.board[py][px]) then return false end
    end
    return true
end

local function empty() return {} end

local function pick(s)
    if #s.bag==0 then
        for i=1,#shapes do s.bag[i]=i end
        for i=#s.bag,2,-1 do
            local j=s.random(i)
            s.bag[i],s.bag[j]=s.bag[j],s.bag[i]
        end
    end
    return table.remove(s.bag)
end

local function spawn(s,id)
    s.id,s.x,s.y,s.rotation,s.fall,s.grounded=id,4,-1,1,0,0
    if not fits(s,id,1,s.x,s.y) then s.result="loss" end
end

local function advance(s)
    local id=s.next
    s.next=pick(s)
    spawn(s,id)
end

function Game.new(_, random)
    local s={ board={},bag={},random=random or math.random,score=0,lines=0,level=1,combo=0,
        cues={}, holdUsed=false }
    for y=1,Game.height do s.board[y]=empty() end
    s.next=pick(s)
    advance(s)
    return s
end

local function place(s)
    local cells=Game.cells(s.id,s.rotation)
    for _,p in ipairs(cells) do
        if s.y+p[2]<1 then s.result="loss"; return end
    end
    for _,p in ipairs(cells) do s.board[s.y+p[2]][s.x+p[1]]=s.id end
    local count=0
    for y=Game.height,1,-1 do
        local row=s.board[y]
        local full=true
        for x=1,Game.width do if not row[x] then full=false; break end end
        if full then
            table.remove(s.board,y)
            count=count+1
        end
    end
    for _=1,count do table.insert(s.board,1,empty()) end
    if count>0 then
        s.combo=s.combo+1
        s.score=s.score+count*count*90*s.level+25*(s.combo-1)
        s.lines=s.lines+count
        s.level=1+math.floor(s.lines/6)
        s.cues.clear=true
    else
        s.combo=0
        s.cues.land=true
    end
    if s.lines>=Game.target then s.result="win"; return end
    s.holdUsed=false
    advance(s)
end

function Game.ghost(s)
    local y=s.y
    while fits(s,s.id,s.rotation,s.x,y+1) do y=y+1 end
    return y
end

local function shift(s,dx,dy)
    if fits(s,s.id,s.rotation,s.x+dx,s.y+dy) then
        s.x,s.y=s.x+dx,s.y+dy
        return true
    end
end

function Game.action(s,action)
    if s.result then return end
    if action=="left" or action=="right" then
        if shift(s,action=="left" and -1 or 1,0) then s.cues.turn=true end
    elseif action=="rotate" or action=="reverse" then
        local r=(s.rotation-1+(action=="rotate" and 1 or -1))%4+1
        for _,kick in ipairs({{0,0},{-1,0},{1,0},{-2,0},{2,0},{0,-1},{0,-2}}) do
            if fits(s,s.id,r,s.x+kick[1],s.y+kick[2]) then
                s.rotation,s.x,s.y=r,s.x+kick[1],s.y+kick[2]
                s.cues.turn=true
                break
            end
        end
    elseif action=="drop" then
        local y=Game.ghost(s)
        s.score=s.score+2*(y-s.y)
        s.y=y
        place(s)
    elseif action=="hold" and not s.holdUsed then
        local previous=s.hold
        s.hold,s.holdUsed=s.id,true
        if previous then spawn(s,previous) else advance(s) end
        s.cues.hold=true
    elseif action=="soft" and shift(s,0,1) then
        s.score,s.fall=s.score+1,0
    end
end

function Game.step(s, held, dt)
    if s.result then return end
    local interval=held.soft and 0.055 or math.max(0.12,0.86-0.10*(s.level-1))
    if fits(s,s.id,s.rotation,s.x,s.y+1) then
        s.fall,s.grounded=s.fall+dt,0
        if s.fall>=interval then
            s.fall=s.fall-interval
            shift(s,0,1)
            if held.soft then s.score=s.score+1 end
        end
    else
        s.grounded=s.grounded+dt
        if s.grounded>=0.36 then place(s) end
    end
end

return Game
