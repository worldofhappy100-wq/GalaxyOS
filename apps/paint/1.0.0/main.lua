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

function App:drawAt(x,y,alternate)
    local im, rows=self.image,self.image.rows
    if x<1 or y<1 or x>im.w or y>im.h then return end
    local color=(alternate or self.tool=="erase") and "." or self.color
    if pixel(rows,x,y)==color then return end
    self:remember()
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
    local columns,rows=math.max(1,math.ceil(v.w*2/z)),math.max(1,math.ceil((v.h-2)*3/z))
    v.b:withClip(v.x,v.y+1,v.w,math.max(1,v.h-2),function()
        v:fill(1,2,v.w,v.h-2,p.background)
        for y=0,math.min(rows-1,self.image.h-self.y) do
            for x=0,math.min(columns-1,self.image.w-self.x) do
                local c=pixel(self.image.rows,x+self.x,y+self.y)
                if c~="." then v:pixel(x*z+1,y*z+4,z,z,c) end
            end
        end
    end)
    self.canvas=v
    v:bar(v.h,{
        {self.d:t("paintTools"),function() self:menu(v) end},
        {self.d:t("paintUndo"),#self.undo>0 and function() self:history(false) end},
        {self.d:t("paintRedo"),#self.redo>0 and function() self:history(true) end},
        {self.d:t("save"),function() self:save() end},
    })
end

function App:input(input)
    local v=self.canvas
    if input.kind=="scroll" then
        if input.localY==1 then self.paletteOffset=math.max(0,math.min(16-v.w,(self.paletteOffset or 0)+input.direction))
        else self.y=math.max(1,math.min(self.image.h,self.y+input.direction)) end
        return
    end
    if not v or (input.kind~="click" and input.kind~="drag") or not input.localY or input.localY<2 or input.localY>=v.h then return end
    local x=self.x+math.floor((input.localX-1)*2/self.zoom)
    local y=self.y+math.floor((input.localY-2)*3/self.zoom)
    self:drawAt(x,y,input.button==2)
end
return App
