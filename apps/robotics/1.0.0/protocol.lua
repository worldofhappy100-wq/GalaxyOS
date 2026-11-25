local sha = ...
local P = { name = "galaxy.robotics.v1" }

local function rawDigest(data)
    return (sha(data):gsub("..",function(x) return string.char(tonumber(x,16)) end))
end

function P.key(secret)
    if #secret > 64 then secret = rawDigest(secret) end
    secret = secret .. ("\0"):rep(64-#secret)
    local inner, outer = {}, {}
    for i=1,64 do
        inner[i] = string.char(bit32.bxor(secret:byte(i), 0x36))
        outer[i] = string.char(bit32.bxor(secret:byte(i), 0x5c))
    end
    return {table.concat(inner),table.concat(outer)}
end

local function authenticate(key,sender,w)
    local framed = ("%d|%d|%s|%d|%s|%d:%s"):format(sender,w.to,w.session,w.seq,w.kind,#w.body,w.body)
    return sha(key[2]..rawDigest(key[1]..framed))
end

function P.pack(key,sender,to,session,seq,kind,data)
    local w={to=to,session=session,seq=seq,kind=kind,body=textutils.serializeJSON(data)}
    w.tag=authenticate(key,sender,w)
    return w
end

function P.unpack(key,sender,to,w)
    if type(w)~="table" or w.to~=to and w.to~=-1 or type(w.session)~="string" or #w.session>56
        or not w.session:match("^[%w%-]+$") or type(w.seq)~="number" or w.seq<0 or w.seq>1e7 or w.seq%1~=0
        or type(w.kind)~="string" or #w.kind>12 or not w.kind:match("^[a-z]+$")
        or type(w.body)~="string" or #w.body>3072 or type(w.tag)~="string" or #w.tag~=64 then return end
    local expected=authenticate(key,sender,w)
    local comparison=0
    for i=1,#expected do comparison=bit32.bor(comparison,bit32.bxor(expected:byte(i),w.tag:byte(i))) end
    if comparison~=0 then return end
    local ok, data=pcall(textutils.unserializeJSON,w.body)
    if ok and type(data)=="table" then return data end
end

function P.token()
    return ("%d-%d-%d"):format(os.getComputerID(),os.epoch("utc"),math.random(1,1000000000))
end

return P
