local Breakout = { width = 36, height = 25, brickColumns = 6, brickRows = 4 }

Breakout.speeds = { easy = 0.45, normal = 0.65, hard = 1 }
local wallLeft, wallRight, paddleY = 1, 36, 23
local function clamp(n, low, high) return math.max(low, math.min(high, n)) end

function Breakout.paddleEdges(center, width)
    return center - width / 2, center + width / 2
end

local function position(target, width, player, duo)
    local half = width / 2
    local left = player == 2 and duo and 18.5 or 0.5
    local right = player == 1 and duo and 18.5 or Breakout.width + 0.5
    return clamp(target, left + half, right - half)
end

local function resetBall(s)
    s.x, s.y, s.dx, s.dy, s.playing = s.p1, 21, 13 * s.speed, -17 * s.speed, false
    s.bonus = nil
end

local function level(s)
    s.bricks = {}
    for i = 1, 24 do s.bricks[i] = s.level == 3 and (i % 3 + 1) or 1 + (s.level == 2 and i % 2 or 0) end
    resetBall(s)
end

function Breakout.new(difficulty)
    difficulty = Breakout.speeds[difficulty] and difficulty or "normal"
    local s = { difficulty = difficulty, speed = Breakout.speeds[difficulty], lives = 3, score = 0, level = 1, p1 = 18, p2 = 28, over = false, won = false, width = 7 }
    level(s)
    return s
end

function Breakout.move(s, action, target, player, duo)
    if s.over then return false end
    if action == "launch" and not s.playing then s.playing = true; return true end
    if action ~= "paddle" or type(target) ~= "number" or target ~= target or target < -10 or target > 46 then return false end
    if player == 2 and duo then s.p2 = position(target, s.width, 2, true)
    elseif player == 1 then s.p1 = position(target, s.width, 1, duo) end
    if not s.playing then s.x = s.p1 end
    return true
end

local function hitPaddle(s, x, center)
    local left, right = Breakout.paddleEdges(center, s.width)
    if x < left or x > right then return false end
    local off = (x - center) / (s.width / 2)
    s.dx = off * 25 * s.speed
    s.dy = -math.min(34 * s.speed, math.abs(s.dy) + 0.6 * s.speed)
    return true
end

local function horizontal(x, dx, elapsed)
    local nextX = x + dx * elapsed
    if nextX < wallLeft then return 2 * wallLeft - nextX, -dx end
    if nextX > wallRight then return 2 * wallRight - nextX, -dx end
    return nextX, dx
end

function Breakout.tick(s, dt, duo)
    if not s.playing or s.over or dt <= 0 then return end
    dt = math.min(0.2, dt)
    local steps = math.ceil(dt / 0.0125)
    local step = dt / steps
    local effect, sounds
    local function mark(name)
        if not sounds then sounds = {} end
        sounds[name] = true
    end
    s.p1 = position(s.p1, s.width, 1, duo)
    s.p2 = position(s.p2, s.width, 2, duo)
    for _ = 1, steps do
        local x, vx = horizontal(s.x, s.dx, step)
        if vx ~= s.dx then mark("wall") end
        local y = s.y + s.dy * step
        if s.dy > 0 and s.y <= paddleY and y >= paddleY then
            local contact = (paddleY - s.y) / s.dy
            local hitX = horizontal(s.x, s.dx, contact)
            if hitPaddle(s, hitX, s.p1) or (duo and hitPaddle(s, hitX, s.p2)) then
                local remaining = step - contact
                x, vx = horizontal(hitX, s.dx, remaining)
                y, effect = paddleY + s.dy * remaining, "paddle"
                mark("paddle")
            end
        end
        s.dx = vx
        if y < 1 then s.dy = -s.dy; y = 1; mark("wall") end
        if y >= 3 and y < 11 then
            local col, row = math.floor((x - 1) / 6) + 1, math.floor((y - 3) / 2) + 1
            local id = (row - 1) * 6 + col
            if s.bricks[id] > 0 and (x - 1) % 6 < 5 and (y - 3) % 2 < 1.25 then
                s.bricks[id], s.dy, y = s.bricks[id] - 1, -s.dy, s.y
                s.score, effect = s.score + 10, "brick"
                mark("brick")
                if s.score % 50 == 0 and not s.bonus then s.bonus = { x = x, y = y } end
                local alive = false
                for _, strength in ipairs(s.bricks) do if strength > 0 then alive = true; break end end
                if not alive then
                    if s.level == 3 then s.over, s.won, s.playing = true, true, false
                    else s.level = s.level + 1; level(s) end
                    mark("level")
                    if s.over then mark("gameover") end
                    return "level", sounds
                end
            end
        end
        if y > 25 then
            s.lives = s.lives - 1
            if s.lives == 0 then s.over, s.playing = true, false
            else resetBall(s) end
            mark("miss")
            if s.over then mark("gameover") end
            return "miss", sounds
        end
        s.x, s.y = x, y
        if s.bonus then
            local bonus = s.bonus
            bonus.y = bonus.y + step * 8
            if bonus.y >= 23 then
                if math.abs(bonus.x - s.p1) <= s.width / 2 or (duo and math.abs(bonus.x - s.p2) <= s.width / 2) then
                    s.width, s.score, effect = math.min(11, s.width + 2), s.score + 15, "bonus"
                    mark("bonus")
                    s.p1 = position(s.p1, s.width, 1, duo)
                    s.p2 = position(s.p2, s.width, 2, duo)
                end
                s.bonus = nil
            end
        end
    end
    return effect, sounds
end

function Breakout.public(s, duo)
    local bricks = {}
    for i, value in ipairs(s.bricks) do bricks[i] = tostring(value) end
    return { bricks = table.concat(bricks), x = s.x, y = s.y, p1 = s.p1, p2 = s.p2,
        width = s.width, lives = s.lives, score = s.score, level = s.level, over = s.over, won = s.won,
        playing = s.playing, difficulty = s.difficulty, duo = not not duo, bx = s.bonus and s.bonus.x, by = s.bonus and s.bonus.y }
end

function Breakout.valid(s)
    local function between(value, lo, hi)
        return type(value) == "number" and value >= lo and value <= hi
    end
    return type(s) == "table" and type(s.bricks) == "string" and #s.bricks == 24
        and not s.bricks:find("[^0-3]") and between(s.x, 1, 36) and between(s.y, 1, 25) and between(s.p1, 1, 36)
        and between(s.p2, 1, 36) and between(s.width, 7, 11) and between(s.score, 0, 10000) and s.score % 1 == 0
        and between(s.lives, 0, 3) and s.lives % 1 == 0 and between(s.level, 1, 3) and s.level % 1 == 0
        and (s.difficulty == nil or Breakout.speeds[s.difficulty] ~= nil) and type(s.playing) == "boolean" and type(s.duo) == "boolean" and type(s.over) == "boolean"
        and type(s.won) == "boolean" and (s.bx == nil and s.by == nil or between(s.bx, 1, 36) and between(s.by, 1, 25))
end

return Breakout
