local require = ...
local View = require("gui.view")
local Drawings = require("core.drawings")
local Wallpapers = require("gui.wallpapers")
local App = { title="gallery", single=true, w=45, h=16 }
App.__index=App

function App.new(d) return setmetatable({d=d,offset=0},App) end

function App:select(name)
    self.name,self.image=name,Drawings.read(Drawings.path(name))
end

function App:actions(v)
    local d,name,image=self.d,self.name,self.image
    local path=Drawings.path(name)
    d:menu(v.x,v.y+1,{
        {self.d:t("galleryWallpaper"),function()
            Drawings.save(Drawings.active,image)
            Wallpapers.reloadDrawing()
            d:preference("wallpaper",9)
        end},
        {self.d:t("galleryPaint"),d.registry.paint and function() d:open("paint",{path=path}) end},
        {self.d:t("rename"),function() d:prompt(self.d:t("drawingFilename"),name,function(value)
            local dest=Drawings.path(value)
            if dest==path then return end
            assert(not fs.exists(dest),"Drawing already exists")
            fs.move(path,dest); self.name=fs.getName(dest)
        end) end},
        {self.d:t("delete"),function() d:confirm("Delete "..name.."?",function()
            fs.delete(path); self.name,self.image=nil,nil
        end) end},
    })
end

function App:draw(v)
    if self.image then
        v:label(1,1,self.name:sub(1,v.w),v.p.accent)
        local view=View.new(v.b,v.x,v.y+1,v.w,math.max(1,v.h-2),v.p)
        v.b:withClip(view.x,view.y,view.w,view.h,function() Drawings.preview(view,self.image) end)
        v:bar(v.h,{
            {self.d:t("gallery"),function() self.image=nil end},
            {self.d:t("actions"),function() self:actions(v) end},
        })
    else
        local names=Drawings.list()
        if #names==0 then v:label(1,1,"No drawings",v.p.quiet) end
        v:page(1,names,self,function(i) self:select(names[i]) end)
    end
end

function App:input(input) View.scroll(self,input) end
return App
