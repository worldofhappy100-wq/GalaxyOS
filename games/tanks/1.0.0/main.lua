local _, load=...
local logic=load("logic.lua")()
local Game={ logic=logic,width=71,height=47,
    controls={up="up",down="down",left="left",right="right",w="up",a="left",s="down",d="right",space="fire"},
    help={"arcadeMove","tanksFire","tanksBonuses"},
    options={{id="mode",label="tanksMode",values={{"campaign","tanksCampaign"},{"survival","tanksSurvival"}}}} }
local barrel={up={1,0},left={0,1},right={2,1},down={1,2}}

function Game.hud(s,t) return t("tanksHud",s.score,s.lives,s.base,s.level) end

function Game.draw(c,s)
    local p=c.p
    c:rect(0,0,c.w,c.h,p.background)
    c:rect(0,0,c.w,1,p.border); c:rect(0,c.h-1,c.w,1,p.border)
    c:rect(0,0,1,c.h,p.border); c:rect(c.w-1,0,1,c.h,p.border)
    local function at(x,y) return (x-1)*3+1,(y-1)*3+1 end
    for k,tile in pairs(s.grid) do
        local x,y=at((k-1)%logic.w+1,math.floor((k-1)/logic.w)+1)
        local color=tile=="steel" and p.quiet or p.accentSoft
        c:rect(x,y,3,3,color)
        c:rect(x+(tile=="steel" and 1 or 0),y+1,tile=="steel" and 1 or 2,1,p.background)
    end
    local baseX,baseY=at(12,logic.h)
    c:rect(baseX,baseY,3,3,s.base<=1 and p.danger or p.gold)
    c:rect(baseX+1,baseY+1,1,1,p.background)
    local function tank(t,color)
        local x,y=at(t.x,t.y)
        c:rect(x,y,3,3,color)
        c:rect(x+1,y+1,1,1,p.background)
        local endPoint=barrel[t.dir]
        c:rect(x+endPoint[1],y+endPoint[2],1,1,p.ink)
    end
    for _,t in ipairs(s.enemies) do
        tank(t,t.model.kind=="armor" and p.danger or t.model.kind=="scout" and p.logo or p.warning)
    end
    tank(s.player,s.shield>0 and p.logo or p.good)
    if s.drop then
        local x,y=at(s.drop.x,s.drop.y)
        local colors={shield=p.logo,speed=p.accent,weapon=p.warning,life=p.good}
        c:rect(x+1,y,1,3,colors[s.drop.kind]); c:rect(x,y+1,3,1,colors[s.drop.kind])
    end
    for _,shot in ipairs(s.shots) do
        local x,y=at(shot.x,shot.y)
        local tip=barrel[shot.dir]
        c:rect(x+tip[1],y+tip[2],1,1,shot.enemy and p.danger or p.ink)
    end
    for _,fx in ipairs(s.effects) do
        local x,y=at(fx.x,fx.y)
        if fx.blast then
            c:rect(x+1,y,1,3,p.warning); c:rect(x,y+1,3,1,p.warning)
        end
        c:rect(x+1,y+1,1,1,p.gold)
    end
end
return Game
