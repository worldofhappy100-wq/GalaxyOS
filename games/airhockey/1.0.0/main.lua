local _, load=...
local logic=load("logic.lua")()
local Game={logic=logic,width=logic.width+2,height=logic.height+4,
    controls={ up="up",down="down",left="left",right="right",w="up",a="left",s="down",d="right" },
    help={"arcadeMove","hockeyPointer","hockeyTips"},
    options={
        {id="difficulty",label="difficulty",default=2,values={{"easy","easy"},{"normal","normal"},{"hard","hard"}}},
        {id="limit",label="arcadeTarget",default=2,values={{5,"5"},{7,"7"},{10,"10"}}},
    }}

function Game.pointer(s,x,y) logic.pointer(s,x-1,y-2) end

function Game.hud(s,t) return t("arcadeMatch",s.score,s.enemy,s.target) end

function Game.draw(c,s)
    local p,w,h=c.p,logic.width,logic.height
    c:rect(0,0,c.w,c.h,p.panel)
    c:rect(1,2,w,h,p.background)
    local gate=(w-logic.gate)/2
    for _, y in ipairs({1,h+2}) do
        c:rect(1,y,gate,1,p.border); c:rect(w-gate+1,y,gate,1,p.border)
        c:rect(gate+1,y,logic.gate,1,y==1 and p.logo or p.good)
    end
    c:rect(0,2,1,h,p.border); c:rect(w+1,2,1,h,p.border)
    for x=3,w-1,4 do c:rect(x,h/2+2,2,1,p.accentSoft) end
    c:circle(w/2+1,h/2+2,4,p.panel)
    c:circle(w/2+1,h/2+2,1,p.logo)
    c:circle(s.player.x+1,s.player.y+2,logic.mallet,p.good)
    c:circle(s.player.x+1,s.player.y+2,1,p.background)
    c:circle(s.bot.x+1,s.bot.y+2,logic.mallet,p.logo)
    c:circle(s.bot.x+1,s.bot.y+2,1,p.background)
    c:circle(s.p.x+1,s.p.y+2,logic.puck,p.ink)
end

return Game
