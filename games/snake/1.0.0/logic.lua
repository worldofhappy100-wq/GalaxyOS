local Snake = {}
local vectors = { up={0,-1}, down={0,1}, left={-1,0}, right={1,0} }
local intervals = { easy=0.30, normal=0.23, hard=0.17 }
local function key(s,x,y) return (y - 1) * s.w + x end

local function food(s)
    local space = s.w*s.h - #s.body
    if space == 0 then s.food, s.result = nil, "win"; return end
    local choice = s.random(space)
    for y = 1, s.h do
        for x = 1, s.w do
            if not s.occupied[key(s,x,y)] then
                choice = choice - 1
                if choice == 0 then s.food = { x=x, y=y }; return end
            end
        end
    end
end

function Snake.new(options, random)
    local s = { w=23,h=13,body={{x=9,y=7},{x=8,y=7},{x=7,y=7}}, occupied={}, direction="right",
        random=random or math.random, wrap=options.wrap, interval=intervals[options.difficulty] or intervals.normal,
        elapsed=0, score=0, eaten=0, cues={} }
    for _, part in ipairs(s.body) do s.occupied[key(s,part.x,part.y)] = true end
    food(s)
    return s
end

function Snake.action(s, dir)
    local target, current = vectors[dir], vectors[s.direction]
    if not s.next and target and (target[1]*current[1] + target[2]*current[2] == 0) then s.next = dir end
end

function Snake.step(s, _, dt)
    local interval = math.max(0.10, s.interval - s.eaten * 0.006)
    s.elapsed = s.elapsed + dt
    if s.result or s.elapsed < interval then return end
    s.elapsed = s.elapsed - interval
    if s.next then s.direction, s.next = s.next, nil end
    local delta, head, tail = vectors[s.direction], s.body[1], s.body[#s.body]
    local x,y = head.x + delta[1], head.y + delta[2]
    if s.wrap then x,y = (x-1)%s.w+1, (y-1)%s.h+1 end
    if x < 1 or x > s.w or y < 1 or y > s.h then s.result="loss"; return end
    local grows = s.food.x == x and s.food.y == y
    local target = key(s,x,y)
    if s.occupied[target] and (grows or x ~= tail.x or y ~= tail.y) then s.result="loss"; return end
    if not grows then
        s.occupied[key(s,tail.x,tail.y)] = nil
        table.remove(s.body)
    end
    table.insert(s.body,1,{x=x,y=y})
    s.occupied[target] = true
    if grows then
        s.eaten, s.score, s.cues.eat = s.eaten + 1, s.score + 10, true
        food(s)
    end
end

return Snake
