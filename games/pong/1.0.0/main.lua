local _, load = ...
local logic=load("logic.lua")()
local Game={ logic=logic,width=logic.width,height=logic.height,
    controls={up="up",w="up",down="down",s="down"},
    help={"pongMove","pongTips"},
    options={
        {id="difficulty",label="difficulty",default=2,values={{"easy","easy"},{"normal","normal"},{"hard","hard"}}},
        {id="limit",label="arcadeTarget",default=2,values={{5,"5"},{7,"7"},{10,"10"},{15,"15"}}},
    }}

function Game.hud(s,t) return t("arcadeMatch",s.p,s.b,s.target) end
function Game.draw(c,s)
    local p,w,h=c.p,c.w,c.h
    c:rect(0,0,w,h,p.background)
    c:rect(0,0,w,1,p.border); c:rect(0,h-1,w,1,p.border)
    for y=3,h-3,4 do c:rect(w/2-0.5,y,1,2,p.accentSoft) end
    c:rect(3,s.player-logic.paddle/2,2,logic.paddle,p.good)
    c:rect(w-5,s.bot-logic.paddle/2,2,logic.paddle,p.logo)
    c:circle(s.x,s.y,logic.radius,p.ink)
end
return Game
