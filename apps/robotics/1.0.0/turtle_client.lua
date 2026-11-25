-- Run from CraftOS with protocol.lua and sha256.lua in the same directory.
local controller=tonumber((...))
if not turtle or not controller or controller<0 or controller%1~=0 then
    print("Usage on a Turtle: turtle_client <controller ID>")
    return
end
local base=fs.getDir(shell.getRunningProgram())
local sha=assert(loadfile(fs.combine(base,"sha256.lua")))()
local P=assert(loadfile(fs.combine(base,"protocol.lua")))(sha)
write("Pairing phrase (8-64 characters): ")
local secret=read("*")
assert(#secret>=8 and #secret<=64,"Invalid phrase")
local key=P.key(secret)
secret=nil
for _, name in ipairs(peripheral.getNames()) do
    if peripheral.getType(name)=="modem" then rednet.open(name) end
end
assert(rednet.isOpen(),"Attach a modem")
print("Listening for controller #"..controller)
local id=os.getComputerID()
local session, last, hello, announced
local commands = {
    forward=turtle.forward,back=turtle.back,up=turtle.up,down=turtle.down,left=turtle.turnLeft,right=turtle.turnRight,
    fuel=function() return true, "Fuel: "..tostring(turtle.getFuelLevel()) end,
    inventory=function()
        local rows={}
        for slot=1,16 do
            local item=turtle.getItemDetail(slot)
            if item then rows[#rows+1]=("%d x%d %s"):format(slot,item.count,item.name:sub(1,72)) end
        end
        return true,#rows>0 and table.concat(rows,"\n") or "Inventory is empty"
    end,
    run=function(name)
        assert(type(name)=="string" and #name<=48 and name:match("^[%w_%-]+%.lua$"),"Invalid program name")
        local program="/robotics-programs/"..name
        assert(fs.exists(program) and not fs.isDir(program),"Program not found")
        return shell.run(program),"Program returned to the client"
    end,
}

while true do
    local sender, packet=rednet.receive(P.name)
    if sender==controller then
        local data=P.unpack(key,sender,id,packet)
        if data and packet.kind=="hello" and packet.seq==0 and packet.to==-1 then
            if hello~=packet.session or not announced or os.clock()-announced>3 then
                session,last,hello,announced=P.token(),0,packet.session,os.clock()
                rednet.send(sender,P.pack(key,id,sender,session,0,"found",
                    { discovery=hello,name=(os.getComputerLabel() or ("Turtle "..id)):sub(1,32) }),P.name)
            end
        elseif data and packet.to==id and packet.kind=="command" and session==packet.session and packet.seq>last then
            last=packet.seq
            local operation=commands[data.action]
            local ok,value,message=false,false,"Unknown command"
            if operation then ok,value,message=pcall(operation,data.argument) end
            if not ok and operation then message=value end
            rednet.send(sender,P.pack(key,id,sender,session,last,"result",
                { ok=ok and not not value,text=tostring(message or (value and "OK" or "Blocked")):sub(1,1536) }),P.name)
        end
    end
end
