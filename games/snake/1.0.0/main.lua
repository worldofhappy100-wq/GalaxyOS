local _, load = ...
local Game = { logic=load("logic.lua")(), width=50, height=30,
    controls={ left="left",right="right",up="up",down="down",a="left",d="right",w="up",s="down" },
    help={ "arcadeMove", "snakeHelp" },
    options={
        { id="difficulty",label="difficulty",default=2,values={{"easy","easy"},{"normal","normal"},{"hard","hard"}} },
        { id="wrap",label="snakeWrap",values={{false,"off"},{true,"on"}} },
    } }

function Game.hud(s,t) return t("arcadeScore",s.score) end

function Game.draw(c,s)
    local p = c.p
    c:rect(0,0,50,30,p.background)
    local edge = s.wrap and p.logo or p.border
    c:rect(0,0,50,1,edge); c:rect(0,29,50,1,edge)
    c:rect(0,0,1,30,edge); c:rect(49,0,1,30,edge)
    for i, part in ipairs(s.body) do
        c:rect(part.x*2,part.y*2,2,2,i==1 and p.good or p.accentSoft)
    end
    if s.food then c:rect(s.food.x*2,s.food.y*2,2,2,p.danger) end
end

return Game
