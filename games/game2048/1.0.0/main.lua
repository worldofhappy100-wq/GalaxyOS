local Tiles = {}
local directions = { left = true, right = true, up = true, down = true }

local function spawn(s)
    local empty = {}
    for i, tile in ipairs(s.cells) do if tile == 0 then empty[#empty + 1] = i end end
    if #empty == 0 then return end
    s.seed = (s.seed * 48271) % 2147483647
    local place = empty[s.seed % #empty + 1]
    s.seed = (s.seed * 48271) % 2147483647
    s.cells[place] = s.seed % 10 == 0 and 4 or 2
end

function Tiles.new(seed)
    local s = { cells = {}, seed = seed, score = 0, over = false, won = false }
    for i = 1, 16 do s.cells[i] = 0 end
    spawn(s)
    spawn(s)
    return s
end

local function index(direction, line, cell)
    if direction == "left" then return (line - 1) * 4 + cell end
    if direction == "right" then return line * 4 - cell + 1 end
    if direction == "up" then return (cell - 1) * 4 + line end
    return (4 - cell) * 4 + line
end

function Tiles.move(s, direction)
    if not directions[direction] or s.over then return false end
    local changed = false
    for line = 1, 4 do
        local values, merged = {}, {}
        for i = 1, 4 do
            local value = s.cells[index(direction, line, i)]
            if value > 0 then values[#values + 1] = value end
        end
        local i = 1
        while i <= #values do
            local value = values[i]
            if values[i + 1] == value then
                value, i = value * 2, i + 1
                s.score = s.score + value
                if value >= 2048 then s.won = true end
            end
            merged[#merged + 1] = value
            i = i + 1
        end
        for j = 1, 4 do
            local at, value = index(direction, line, j), merged[j] or 0
            if s.cells[at] ~= value then
                s.cells[at] = value
                changed = true
            end
        end
    end
    if not changed then return false end
    spawn(s)
    for i, value in ipairs(s.cells) do
        if value == 0 or (i % 4 > 0 and s.cells[i + 1] == value) or s.cells[i + 4] == value then
            return true
        end
    end
    s.over = true
    return true
end

function Tiles.public(s)
    local cells = {}
    for i = 1, 16 do cells[i] = s.cells[i] end
    return { cells = cells, score = s.score, over = s.over, won = s.won }
end

function Tiles.valid(s)
    if type(s) ~= "table" or type(s.cells) ~= "table" or type(s.score) ~= "number" or s.score < 0
        or s.score > 1e9 or s.score % 1 ~= 0 or type(s.over) ~= "boolean" or type(s.won) ~= "boolean" then return false end
    for i = 1, 16 do
        local n = s.cells[i]
        if type(n) ~= "number" or n < 0 or n > 131072 or n % 1 ~= 0 then return false end
        local p = n
        while p > 1 and p % 2 == 0 do p = p / 2 end
        if n ~= 0 and (n < 2 or p ~= 1) then return false end
    end
    return true
end

return Tiles
