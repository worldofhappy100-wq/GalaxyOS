local Mines = { counts = { 8, 13, 20 }, size = 8 }

function Mines.new(level)
    return { level = level, cells = {}, visible = {}, flags = 0, count = Mines.counts[level],
        over = false, won = false, elapsed = 0 }
end

local function neighbors(index, callback)
    local x, y = (index - 1) % 8 + 1, math.floor((index - 1) / 8) + 1
    for ny = math.max(1, y - 1), math.min(8, y + 1) do
        for nx = math.max(1, x - 1), math.min(8, x + 1) do
            local n = (ny - 1) * 8 + nx
            if n ~= index then callback(n) end
        end
    end
end

local function populate(s, first)
    local safe, choices = { [first] = true }, {}
    neighbors(first, function(n) safe[n] = true end)
    for i = 1, 64 do
        if not safe[i] then choices[#choices + 1] = i end
        s.cells[i] = 0
    end
    for i = 1, s.count do
        local slot = math.random(i, #choices)
        choices[i], choices[slot] = choices[slot], choices[i]
        s.cells[choices[i]] = -1
    end
    for i = 1, 64 do
        if s.cells[i] == -1 then
            neighbors(i, function(n) if s.cells[n] >= 0 then s.cells[n] = s.cells[n] + 1 end end)
        end
    end
end

function Mines.move(s, action, index)
    if s.over or type(index) ~= "number" or index < 1 or index > 64 or index % 1 ~= 0 then return false end
    local cell = s.visible[index]
    if action == "flag" then
        if cell == "F" then s.visible[index], s.flags = nil, s.flags - 1
        elseif not cell and s.flags < s.count then s.visible[index], s.flags = "F", s.flags + 1
        else return false end
        return true
    end
    if action ~= "reveal" or cell then return false end
    if #s.cells == 0 then populate(s, index) end
    local todo, nextIndex = { index }, 1
    while nextIndex <= #todo do
        local node = todo[nextIndex]
        nextIndex = nextIndex + 1
        if not s.visible[node] then
            local value = s.cells[node]
            if value == -1 then s.over = true; break end
            s.visible[node] = tostring(value)
            if value == 0 then neighbors(node, function(n)
                if not s.visible[n] then todo[#todo + 1] = n end
            end) end
        end
    end
    if not s.over then
        local remaining = 0
        for i = 1, 64 do if s.cells[i] >= 0 and (not s.visible[i] or s.visible[i] == "F") then remaining = remaining + 1 end end
        s.won, s.over = remaining == 0, remaining == 0
    end
    return true
end

function Mines.public(s)
    local cells = {}
    for i = 1, 64 do cells[i] = s.over and s.cells[i] == -1 and "*" or s.visible[i] or "." end
    return { cells = table.concat(cells), elapsed = math.floor(s.elapsed), count = s.count,
        flags = s.flags, over = s.over, won = s.won, level = s.level }
end

function Mines.valid(s)
    return type(s) == "table" and type(s.cells) == "string" and #s.cells == 64
        and not s.cells:find("[^%.F%*0-8]") and type(s.elapsed) == "number" and s.elapsed >= 0
        and s.elapsed <= 86400 and s.elapsed % 1 == 0 and type(s.level) == "number"
        and Mines.counts[s.level] ~= nil and s.count == Mines.counts[s.level] and type(s.flags) == "number"
        and s.flags >= 0 and s.flags <= s.count and s.flags % 1 == 0 and type(s.over) == "boolean"
        and type(s.won) == "boolean"
end

return Mines
