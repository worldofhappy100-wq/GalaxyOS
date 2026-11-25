local require = ...
local View = require("gui.view")
local Files = require("core.files")
local App = { title = "navigation", single = true, w = 47, h = 16 }
App.__index = App
local path = "/galaxy/users/navigation.json"

local function vector(x,y,z)
    for _, n in ipairs({x,y,z}) do if type(n) ~= "number" or math.abs(n) > 30000000 or n ~= n then return end end
    if x and y and z then return {x=x,y=y,z=z} end
end

function App.new(d)
    local self = setmetatable({d=d, points={}, offset=0, zoom=4, page="map"}, App)
    local ok, saved = pcall(function() return textutils.unserializeJSON(Files.read(path, 20000)) end)
    if ok and type(saved) == "table" then
        if type(saved.origin) == "table" then self.origin = vector(saved.origin.x,saved.origin.y,saved.origin.z) end
        for _, point in ipairs(type(saved.points)=="table" and saved.points or {}) do
            if type(point) == "table" and type(point.name) == "string" then
                local xyz = vector(point.x,point.y,point.z)
                if xyz then xyz.name = point.name:gsub("[%c]"," "):sub(1,28); self.points[#self.points+1] = xyz end
            end
        end
    end
    return self
end

function App:save()
    Files.replace(path, textutils.serializeJSON({ origin=self.origin, points=self.points }))
end

function App:coordinates(name, initial, callback)
    self.d:prompt(name, initial and ("%g %g %g"):format(initial.x,initial.y,initial.z) or "", function(s)
        local a,b,c = s:match("^%s*(%S+)[ ,]+(%S+)[ ,]+(%S+)%s*$")
        local xyz = vector(tonumber(a),tonumber(b),tonumber(c))
        assert(xyz, self.d:t("enterXYZ"))
        callback(xyz)
    end)
end

function App:gps()
    local d=self.d
    if self.locating then return end
    self.locating = true
    d.scheduler:spawn("GPS", function()
        local ok,x,y,z
        if gps and gps.locate then ok,x,y,z = pcall(gps.locate, 3, false) end
        self.locating = false
        local xyz = ok and vector(x,y,z)
        if xyz then self.origin=xyz; self:save() else d:notify(self.d:t("gpsUnavailable")) end
        d.hooks.invalidate()
    end)
end

function App:add()
    local d=self.d
    d:prompt(self.d:t("waypointName"), "", function(name)
        assert(name:match("%S") and #name <= 28 and #self.points < 48, self.d:t("waypointInvalid"))
        self:coordinates(self.d:t("waypointXYZ"), self.origin, function(xyz)
            xyz.name=name
            self.points[#self.points+1]=xyz
            self.selected=#self.points
            self:save()
        end)
    end)
end

function App:pointMenu(index, v)
    local d, point = self.d, self.points[index]
    self.selected = index
    d:menu(v.x,v.y+1,{
        { self.d:t("showOnMap"), function() self.page="map" end },
        { self.d:t("rename"), function() d:prompt(self.d:t("waypointName"), point.name, function(name)
            assert(name:match("%S") and #name<=28)
            point.name=name
            self:save()
        end) end },
        { self.d:t("removeWaypoint"), function() d:confirm("Remove " .. point.name .. "?",function()
            table.remove(self.points,index); self.selected=nil; self:save()
        end) end },
    })
end

local function direction(dx,dz)
    if dx==0 and dz==0 then return "-" end
    local degrees=math.deg(math.atan2(dx,-dz))
    return ({"N","NE","E","SE","S","SW","W","NW"})[math.floor((degrees+22.5)/45)%8+1]
end

function App:draw(v)
    local p, origin, target = v.p, self.origin, self.points[self.selected]
    v:bar(1, {
        { self.d:t("navMap"), function() self.page="map" end, self.page=="map" },
        { self.d:t("navWaypoints"), function() self.page="points" end, self.page=="points" },
        { self.d:t("navPosition"), function() self:coordinates(self.d:t("positionXYZ"),origin,function(xyz) self.origin=xyz; self:save() end) end },
        { self.locating and "GPS..." or "GPS", not self.locating and function() self:gps() end },
    })
    if self.page=="points" then
        local rows={}
        for i,point in ipairs(self.points) do rows[i]=("%s   %g %g %g"):format(point.name,point.x,point.y,point.z) end
        v:page(2,rows,self,function(i) self:pointMenu(i,v) end,{ self.d:t("navAdd"),function() self:add() end })
        return
    end
    if origin and target then
        local x,y,z=target.x-origin.x,target.y-origin.y,target.z-origin.z
        v:label(1,2,("%s %.1f m %s"):format(target.name,math.sqrt(x*x+y*y+z*z),direction(x,z)):sub(1,v.w),p.ink)
    elseif origin then v:label(1,2,("X%g Y%g Z%g"):format(origin.x,origin.y,origin.z):sub(1,v.w),p.ink)
    else v:label(1,2,self.d:t("setPosition"),p.quiet) end
    if v.h >= 5 then
        local width,height=v.w*2,(v.h-3)*3
        local cx,cy=math.floor(width/2),math.floor(height/2)
        v:fill(1,3,v.w,v.h-3,p.background)
        v:pixel(cx,7,width-cx,1,p.border)
        v:pixel(1,cy+6,width,1,p.border)
        v:pixel(cx,7,1,height,p.border)
        local center=origin or target or {x=0,z=0}
        for i,point in ipairs(self.points) do
            local x=cx+math.floor((point.x-center.x)/self.zoom+0.5)
            local y=cy+math.floor((point.z-center.z)/self.zoom+0.5)
            if x>=2 and x<width and y>=2 and y<height then
                v:pixel(x,y+6,1,1,target==point and p.good or p.logo)
                v:hit(math.ceil(x/2), math.ceil(y/3)+2, 1, 1, function() self.selected=i end)
            end
        end
        if origin then v:pixel(cx,cy+6,1,1,p.accent) end
    end
    v:bar(v.h,{
        { "-",function() self.zoom=math.min(512,self.zoom*2) end },
        { ("%g m/px"):format(self.zoom) },
        { "+",function() self.zoom=math.max(0.25,self.zoom/2) end },
        { self.d:t("navAdd"),function() self:add() end },
    })
end

function App:input(input) if self.page=="points" then View.scroll(self,input) end end
return App
