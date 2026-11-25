local require = ...
local Drawings = require("core.drawings")
local App = { title="paint", single=true, w=46, h=17 }
App.__index=App

local function copy(rows)
    return { (table.unpack or unpack)(rows) }
end

function App.new(d,w,args)
    local self=setmetatable({d=d,image=Drawings.new(32,24),undo={},redo={},x=1,y=1,color="0",zoom=2,tool="pen"},App)
    if args.path then self:load(args.path) end
    return self
end

function App:load(path)
    self.image,self.path=Drawings.read(path),path
    self.undo,self.redo,self.dirty,self.x,self.y={}, {},false,1,1
    self.stroke = nil
end

function App:activate(args)
    if not args.path or args.path==self.path then return end
    if self.dirty then self.d:confirm(self.d:t("discard"),function() self:load(args.path) end)
    else self:load(args.path) end
end

function App:remember()
    self.undo[#self.undo+1]=copy(self.image.rows)
    if #self.undo>16 then table.remove(self.undo,1) end
    self.redo={}
    self.dirty=true
end

function App:history(reverse)
    self.stroke = nil
    local from,to=self.undo,self.redo
    if reverse then from,to=to,from end
    if #from==0 then return end
    to[#to+1]=copy(self.image.rows)
    self.image.rows=table.remove(from)
    self.dirty=true
end

local function pixel(rows,x,y) return rows[y]:sub(x,x) end
local function put(rows,x,y,color)
    local row=rows[y]
    rows[y]=row:sub(1,x-1)..color..row:sub(x+1)
end

function App:drawAt(x,y,alternate,stroke)
    local im, rows=self.image,self.image.rows
    if x<1 or y<1 or x>im.w or y>im.h then return end
    local color=(alternate or self.tool=="erase") and "." or self.color
    if pixel(rows,x,y)==color then return end
    if not stroke or not stroke.changed then
        self:remember()
        if stroke then stroke.changed = true end
    end
    if self.tool~="fill" or alternate then put(rows,x,y,color); return end
    local original=pixel(rows,x,y)
    local queue={{x,y}}
    put(rows,x,y,color)
    local i=1
    while i<=#queue do
        local item=queue[i]
        for _, nextCell in ipairs({{item[1]-1,item[2]},{item[1]+1,item[2]},{item[1],item[2]-1},{item[1],item[2]+1}}) do
            local nx,ny=nextCell[1],nextCell[2]
            if nx>=1 and ny>=1 and nx<=im.w and ny<=im.h and pixel(rows,nx,ny)==original then
                put(rows,nx,ny,color)
                queue[#queue+1]=nextCell
            end
        end
        i=i+1
    end
end

function App:save()
    local d=self.d
    d:prompt(self.d:t("saveDrawing"), self.path and fs.getName(self.path) or "Drawing.gxr", function(name)
        local path=Drawings.path(name)
        local function write() Drawings.save(path,self.image); self.path,self.dirty=path,false end
        if fs.exists(path) and path~=self.path then d:confirm("Overwrite "..name.."?",write) else write() end
    end)
end

function App:menu(v)
    local d=self.d
    local tools = {
        {self.d:t("paintPen"),function() self.tool="pen" end},{self.d:t("paintErase"),function() self.tool="erase" end},{self.d:t("paintFill"),function() self.tool="fill" end},
        {"Zoom "..self.zoom.."x",function() self.zoom=self.zoom==8 and 2 or self.zoom*2 end},
        {self.d:t("panLeft"),function() self.x=math.max(1,self.x-2) end},
        {self.d:t("panRight"),function() self.x=math.min(self.image.w,self.x+2) end},
        {self.d:t("panUp"),function() self.y=math.max(1,self.y-2) end},
        {self.d:t("panDown"),function() self.y=math.min(self.image.h,self.y+2) end},
        {self.d:t("openDrawing"),function() d:prompt(self.d:t("drawingFilename"), "", function(name) self:activate({path=Drawings.path(name)}) end) end},
    }
    if v.w < #Drawings.digits then
        tools[#tools + 1] = { d:t("paintMoreColors"), function()
            self.paletteOffset = (self.paletteOffset or 0) > 0 and 0 or #Drawings.digits - v.w
        end }
    end
    d:menu(v.x, v.y + 1, tools)
end

function App:draw(v)
    local p,z=v.p,self.zoom
    local colors=Drawings.digits
    local offset=math.max(0, math.min(#colors - v.w, self.paletteOffset or 0))
    for i=1,math.min(16,v.w) do
        local color=colors:sub(i+offset,i+offset)
        if color~="" then
            v:fill(i,1,1,1,color)
            if color==self.color then v:label(i,1,"+",p.ink,color) end
            v:hit(i,1,1,1,function() self.color=color end)
        end
    end
    if v.w>=23 then v:label(18,1,("%s %dx%s"):format(self.tool,self.zoom,self.dirty and " *" or ""),p.quiet) end
    -- At 2x one drawing pixel occupies one CraftOS character (2x3 screen pixels).
    local cell = z / 2
    local columns = math.floor(v.w / cell)
    local rows = math.floor((v.h - 2) / cell)
    v.b:withClip(v.x,v.y+1,v.w,v.h-2,function()
        v:fill(1,2,v.w,v.h-2,p.background)
        for y=0,math.min(rows-1,self.image.h-self.y) do
            for x=0,math.min(columns-1,self.image.w-self.x) do
                local c=pixel(self.image.rows,x+self.x,y+self.y)
                if c~="." then
                    v:fill(x * cell + 1, y * cell + 2, cell, cell, c)
                end
            end
        end
    end)
    self.canvas = { width = columns, height = rows, cell = cell, viewWidth = v.w }
    v:bar(v.h,{
        {self.d:t("paintTools"),function() self:menu(v) end},
        {self.d:t("paintUndo"),#self.undo>0 and function() self:history(false) end},
        {self.d:t("paintRedo"),#self.redo>0 and function() self:history(true) end},
        {self.d:t("save"),function() self:save() end},
    })
end

function App:input(input)
    local canvas = self.canvas
    if not canvas then return end
    if input.kind == "release" then self.stroke = nil; return end
    if input.kind == "scroll" then
        self.stroke = nil
        if input.localY == 1 then
            local limit = #Drawings.digits - canvas.viewWidth
            self.paletteOffset = math.max(0, math.min(limit, (self.paletteOffset or 0) + input.direction))
        else
            self.y = math.max(1, math.min(self.image.h, self.y + input.direction))
        end
        return
    end
    if input.kind ~= "click" and input.kind ~= "drag" then return end
    if input.kind == "click" then self.stroke = nil end
    if input.button ~= 1 and input.button ~= 2 then return end
    if not input.localX or not input.localY then return end
    local col = math.floor((input.localX - 1) / canvas.cell)
    local row = math.floor((input.localY - 2) / canvas.cell)
    local x, y = self.x + col, self.y + row
    if col < 0 or row < 0 or col >= canvas.width or row >= canvas.height
        or x > self.image.w or y > self.image.h then
        self.stroke = nil
        return
    end
    local alternate = input.button == 2
    if self.tool == "fill" and not alternate then self:drawAt(x, y); return end
    if input.source then self:drawAt(x, y, alternate); return end
    local stroke = self.stroke
    if not stroke or stroke.button ~= input.button then
        stroke = { x = x, y = y, button = input.button }
        self.stroke = stroke
    end
    local sx, sy = stroke.x, stroke.y
    local dx, dy = math.abs(x - sx), -math.abs(y - sy)
    local stepX, stepY = sx < x and 1 or -1, sy < y and 1 or -1
    local err = dx + dy
    while true do
        self:drawAt(sx, sy, alternate, stroke)
        if sx == x and sy == y then break end
        local twice = 2 * err
        if twice >= dy then err, sx = err + dy, sx + stepX end
        if twice <= dx then err, sy = err + dx, sy + stepY end
    end
    stroke.x, stroke.y = x, y
end

return App
