local _, load = ...
local rules=load("logic.lua")()
local Game={ logic=rules,width=38,height=40,
    controls={left="left",a="left",right="right",d="right",down="soft",s="soft",up="rotate",
        w="rotate",x="rotate",z="reverse",space="drop",c="hold"},
    repeatKeys={left=true,right=true}, help={"blocksMove","blocksHelp","blocksTarget","blocksPreview"} }

function Game.hud(s,t) return t("blocksHud",s.score,s.lines,s.level) end

function Game.draw(c,s)
    local p=c.p
    local colors={p.logo,p.accent,p.warning,p.gold,p.good,p.accentSoft,p.danger}
    c:rect(1,2,22,36,p.border)
    c:rect(3,4,18,32,p.background)
    local function tile(x,y,color)
        if y>=1 then c:rect(3+(x-1)*2,4+(y-1)*2,2,2,color) end
    end
    local ghost=rules.ghost(s)
    for _,xy in ipairs(rules.cells(s.id,s.rotation)) do tile(s.x+xy[1],ghost+xy[2],p.raised) end
    for y,row in ipairs(s.board) do for x,id in pairs(row) do tile(x,y,colors[id]) end end
    for _,xy in ipairs(rules.cells(s.id,s.rotation)) do tile(s.x+xy[1],s.y+xy[2],colors[s.id]) end
    local function preview(id, y, active, dots)
        c:rect(26,y,11,12,active and p.raised or p.panel)
        for i=1,dots do c:rect(27+(i-1)*2,y+1,1,1,p.accent) end
        if id then for _,xy in ipairs(rules.cells(id)) do
            c:rect(27+xy[1]*2,y+3+xy[2]*2,2,2,colors[id])
        end end
    end
    preview(s.next,3,true,1)
    preview(s.hold,19,not s.holdUsed,2)
    c:rect(26,35,11,2,p.raised)
    if s.lines>0 then c:rect(26,35,11*s.lines/rules.target,2,p.good) end
end
return Game
