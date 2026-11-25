local require, module = ...
local View=require("gui.view")
local P=module("protocol.lua")(require("core.sha256"))
local App={title="robotics",single=true,w=46,h=16}
App.__index=App

function App.new(d)
    return setmetatable({d=d,turtles={},offset=0, status=d:t("pairTurtle")},App)
end

function App:pair()
    self.d:prompt(self.d:t("pairPhrase"), "", function(secret)
        assert(#secret>=8 and #secret<=64,self.d:t("invalidPairPhrase"))
        self.key,self.turtles,self.selected=P.key(secret),{},nil
        self:scan()
    end,true)
end

function App:scan()
    if not self.key then self:pair(); return end
    if self.pending or not self.d.net.online then self.status=self.d:t("robotBusy"); return end
    self.discovery=P.token()
    self.discoveredAt=os.clock()
    self.turtles,self.selected={},nil
    self.status=self.d:t("robotScan")
    rednet.broadcast(P.pack(self.key,os.getComputerID(),-1,self.discovery,0,"hello",{}),P.name)
end

function App:command(action, argument)
    local peer=self.turtles[self.selected]
    if not peer or not self.d.net.online or self.pending then return end
    peer.seq=peer.seq+1
    local packet=P.pack(self.key,os.getComputerID(),self.selected,peer.session,peer.seq,"command",{action=action,argument=argument})
    if not rednet.send(self.selected,packet,P.name) then self.status=self.d:t("robotUnreachable"); return end
    self.pending={id=self.selected,seq=peer.seq,at=os.clock()}
    self.status="Awaiting Turtle #" .. self.selected
end

function App:message(event)
    if not self.key then return end
    local sender,packet=event[1],event[2]
    local data=P.unpack(self.key,sender,os.getComputerID(),packet)
    if not data or packet.to~=os.getComputerID() then return end
    if packet.kind=="found" and packet.seq==0 and self.discovery and data.discovery==self.discovery
        and os.clock()-self.discoveredAt<=6 and type(data.name)=="string" and #data.name<=32 then
        self.turtles[sender]={name=data.name:gsub("[%c]"," "),session=packet.session,seq=0}
        self.status="Turtle #" .. sender .. " found"
    elseif packet.kind=="result" and self.pending and self.pending.id==sender and self.pending.seq==packet.seq
        and self.turtles[sender] and self.turtles[sender].session==packet.session
        and type(data.ok)=="boolean" and type(data.text)=="string" and #data.text<=1536 then
        self.pending=nil
        self.status=data.ok and self.d:t("robotConnected") or self.d:t("robotCommandFailed")
        local rows={}
        for line in data.text:gmatch("[^\n]+") do rows[#rows+1]=line:gsub("[%c]"," "):sub(1,100) end
        if #rows>1 then self.d:info(self.status,rows) elseif rows[1] then self.status=rows[1] end
    end
    self.d.hooks.invalidate()
end

function App:frame(now)
    if self.pending and now-self.pending.at>8 then self.pending=nil; self.status=self.d:t("robotTimeout") end
    if self.discovery and now-self.discoveredAt>6 then
        self.discovery=nil
        if not next(self.turtles) then self.status=self.d:t("robotNoResults") end
    end
end

function App:controls(v)
    local d=self.d
    local menu={}
    for _, action in ipairs({"forward","back","left","right","up","down","fuel","inventory"}) do
        menu[#menu+1]={action,function() self:command(action) end}
    end
    menu[#menu+1]={self.d:t("robotRun"),function()
        d:prompt(self.d:t("robotProgramPath"), "", function(name)
            assert(name:match("^[%w_%-]+%.lua$") and #name<=48,self.d:t("robotInvalidProgram"))
            d:confirm("Run "..name.." on the selected Turtle?",function() self:command("run",name) end)
        end)
    end}
    d:menu(v.x,v.y+1,menu)
end

function App:draw(v)
    local ids,names={},{}
    for id in pairs(self.turtles) do ids[#ids+1]=id end
    table.sort(ids)
    for _,id in ipairs(ids) do names[#names+1]=("%s #%d %s"):format(self.turtles[id].name,id,self.selected==id and "*" or "") end
    v:label(1,1,self.status:sub(1,v.w),v.p.quiet)
    local rows=math.max(1,v.h-2)
    self.offset,self.maximum=v:rows(2,rows,names,self.offset,nil,function(i) self.selected=ids[i]; self:controls(v) end)
    v:bar(v.h,{
        {self.d:t("robotPair"),function() self:pair() end},
        {self.d:t("robotScanButton"),not self.pending and function() self:scan() end},
        {self.d:t("robotControls"),self.selected and not self.pending and function() self:controls(v) end},
    })
end

function App:input(input) View.scroll(self,input) end
return App
