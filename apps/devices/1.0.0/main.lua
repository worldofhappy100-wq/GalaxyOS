local require = ...
local View = require("gui.view")
local Machines = require("drivers.machines")
local Icons = require("assets.icons.devices")
local App = { title = "devicesTitle", single = true, w = 49, h = 17 }
App.__index = App
local kinds = { "door", "lamp", "piston", "redstone" }
local generic = { "monitor", "modem", "chest", "drive", "printer", "speaker" }

local function deviceIcon(types)
    for _, name in ipairs(generic) do if types:find(name, 1, true) then return name end end
    if types:find("inventory", 1, true) then return "chest" end
    return "chip"
end

function App.new(d)
    local config = d.prefs.devices
    if type(config.names) ~= "table" then config.names = {} end
    if type(config.sides) ~= "table" then config.sides = {} end
    return setmetatable({ d = d, config = config, page = 1, faults = {}, nodes = {} }, App)
end

function App:sync()
    local names, nodes, found = Machines.devices(peripheral), {}, {}
    for _, name in ipairs(names) do
        local types = ({ peripheral.getType(name) })
        if types[1] then
            local id = "device:" .. name
            nodes[#nodes + 1] = { id = id, name = name, icon = deviceIcon(table.concat(types, " "):lower()) }
            found[id] = true
        end
    end
    if redstone then
        for _, side in ipairs(redstone.getSides()) do
            local kind = self.config.sides[side]
            if Icons[kind] then
                local id = "rs:" .. side
                nodes[#nodes + 1] = { id = id, name = side, side = side, icon = kind }
                found[id] = true
            end
        end
    end
    if not found[self.selected] then self.selected = nil end
    for id in pairs(self.faults) do if not found[id] then self.faults[id] = nil end end
    self.nodes = nodes
end

function App:start() self:sync() end

function App:frame(now)
    if self.version ~= self.d.deviceVersion or not self.refreshAt or now >= self.refreshAt then
        self.version, self.refreshAt = self.d.deviceVersion, now + 1
        self:sync()
    end
end

function App:save()
    local ok, problem = self.d.prefs:saveDevices()
    if not ok then self.d:error(problem) end
    self:sync()
end

function App:name(node)
    local custom = self.config.names[node.id]
    if type(custom) == "string" and #custom > 0 then return custom:gsub("[%c]", " "):sub(1, 24) end
    return node.name
end

function App:rename(node)
    self.d:prompt(self.d:t("rename"), self:name(node), function(value)
        self.config.names[node.id] = value:match("%S") and value:sub(1, 24) or nil
        self:save()
    end)
end

function App:pinMenu(side, x, y)
    local d = self.d
    local items = {}
    for _, kind in ipairs(kinds) do
        items[#items + 1] = { d:t(kind), function() self.config.sides[side] = kind; self:save() end }
    end
    if self.config.sides[side] then
        items[#items + 1] = { d:t("removeNode"), function() self.config.sides[side] = nil; self:save() end }
    end
    d:menu(x, y, items)
    d.modal.message = side
end

function App:output(node, x, y)
    local d, rs, side = self.d, redstone, node.side
    local set = rs.setAnalogOutput or rs.setAnalogueOutput
    local get = rs.getAnalogOutput or rs.getAnalogueOutput
    local input = rs.getAnalogInput or rs.getAnalogueInput
    d:menu(x, y, {
        { d:t("toggle"), function() rs.setOutput(side, not rs.getOutput(side)) end },
        { d:t("level"), function()
            d:prompt(d:t("level"), tostring(get(side)), function(value)
                local n = tonumber(value)
                assert(n and n >= 0 and n <= 15 and n % 1 == 0, d:t("invalidValue"))
                set(side, n)
            end)
        end },
        { d:t("pulse"), function()
            self.pulses = self.pulses or {}
            if self.pulses[side] then return end
            local before = get(side)
            rs.setOutput(side, true)
            self.pulses[side] = { before = before, task = d.scheduler:spawn("redstone:" .. side, function()
                os.sleep(0.25)
                if get(side) == 15 then set(side, before) end
                self.pulses[side] = nil
                d.hooks.invalidate()
            end) }
        end },
        { d:t("rename"), function() self:rename(node) end },
        { d:t("redstoneKind"), function() self:pinMenu(side, x, y) end },
    })
    d.modal.message = self:name(node) .. (" / %s %d>%d"):format(side, input(side), get(side))
end

function App:controls(node, x, y)
    self.selected = node.id
    if node.side then self:output(node, x, y); return end
    local d = self.d
    local api = setmetatable({}, { __index = peripheral })
    function api.call(name, method, ...)
        local result = table.pack(pcall(peripheral.call, name, method, ...))
        self.faults[node.id] = not result[1] or nil
        if not result[1] then error(result[2], 0) end
        return (table.unpack or unpack)(result, 2, result.n)
    end
    local ok, items = pcall(Machines.actions, api, node.name, d)
    if not ok then self.faults[node.id] = true; d:error(items); return end
    items[#items + 1] = { d:t("rename"), function() self:rename(node) end }
    d:menu(x, y, items)
    d.modal.message = self:name(node)
end

function App:computer(x, y)
    local d, items = self.d, {}
    if redstone then
        for _, side in ipairs(redstone.getSides()) do
            local node = { id = "rs:" .. side, name = side, side = side }
            items[#items + 1] = { self:name(node), function() self:controls(node, x, y) end }
        end
    else items[1] = { d:t("unavailable") } end
    d:menu(x, y, items)
    d.modal.message = "Redstone"
end

function App:stop()
    if not self.pulses then return end
    local get = redstone.getAnalogOutput or redstone.getAnalogueOutput
    local set = redstone.setAnalogOutput or redstone.setAnalogueOutput
    for side, pulse in pairs(self.pulses) do
        self.d.scheduler:stop(pulse.task)
        if get(side) == 15 then set(side, pulse.before) end
    end
end

local function dotted(v, x, y, toX, toY, color)
    local dx, dy = toX - x, toY - y
    local steps = math.max(math.abs(dx), math.abs(dy))
    for i = 0, steps, 3 do
        v:pixel(math.floor(x + dx * i / math.max(1, steps) + 0.5),
            math.floor(y + dy * i / math.max(1, steps) + 0.5), 1, 1, color)
    end
end

local function circle(v, x, y, radius, color)
    for dy = -radius, radius do
        local dx = math.floor(math.sqrt(radius * radius - dy * dy))
        v:pixel(x - dx, y + dy, 2 * dx + 1, 1, color)
    end
end

function App:draw(v)
    local p, d = v.p, self.d
    local large = v.w >= 26 and v.h >= 10
    local size = large and 4 or v.h >= 6 and 2 or 1
    local pages = math.max(1, math.ceil(#self.nodes / size))
    self.pages, self.page = pages, math.min(self.page, pages)
    local middle, height = math.floor(v.w / 2), math.floor((v.h + 1) / 2)
    local cx, cy = middle * 2, height * 3 - 1
    local visible = {}
    local count = math.min(size, #self.nodes - (self.page - 1) * size)
    for i = 1, size do
        local node = self.nodes[(self.page - 1) * size + i]
        if not node then break end
        local right = i % 2 == 0 or count == 1
        local x = right and math.floor(v.w * 0.79) or math.floor(v.w * 0.21)
        local y = large and count >= 3 and (i < 3 and 3 or v.h - 3) or height
        local color = self.faults[node.id] and p.danger or self.selected == node.id and p.good or p.logo
        visible[#visible + 1] = { x = x, y = y, color = color, node = node }
    end
    if v.h >= 6 then
        for _, spot in ipairs(visible) do
            if spot.node.id ~= self.selected then dotted(v, cx, cy, spot.x * 2, spot.y * 3 - 1, self.faults[spot.node.id] and p.danger or p.logo) end
        end
        for _, spot in ipairs(visible) do
            if spot.node.id == self.selected then dotted(v, cx, cy, spot.x * 2, spot.y * 3 - 1, spot.color) end
        end
    end
    local function drawNode(x, y, icon, color, label, callback, central)
        if v.h < 6 then
            local width = math.floor(v.w / 2)
            v:button(central and 1 or v.w - width + 1, 2, label, callback, width)
            return
        end
        local radius = central and large and 6 or 4
        local px, py = x * 2, y * 3 - 1
        circle(v, px, py, radius, color)
        v:sprite(px - 3, py - 2, Icons[icon], { ["1"] = p.accentInk })
        local limit = central and 10 or math.max(4, math.floor(v.w / 3))
        label = label:sub(1, limit)
        local row = y + (radius + 2) / 3
        row = math.ceil(row)
        v:label(x - math.floor(#label / 2), row, label, color)
        v:hit(x - 2, y - 1, 5, row - y + 2, callback)
        v:hit(x - math.floor(#label / 2), row, #label, 1, callback)
    end

    drawNode(middle, height, "computer", p.accent, "Galaxy", function() self:computer(v.x, v.y + 1) end, true)
    for _, spot in ipairs(visible) do
        local node = spot.node
        drawNode(spot.x, spot.y, node.icon, spot.color, self:name(node), function()
            self:controls(node, spot.x < middle and v.x + math.floor(v.w / 2) or v.x, v.y + 1)
        end)
    end
    if #self.nodes == 0 then v:label(1, 1, d:t("noDevices"), p.quiet) end
    v:bar(v.h, {
        { "<", self.page > 1 and function() self.page = self.page - 1 end },
        { ("%d/%d"):format(self.page, pages) },
        { ">", self.page < pages and function() self.page = self.page + 1 end },
    })
end

function App:input(input)
    if input.kind ~= "scroll" then return end
    self.page = math.max(1, math.min(self.pages or 1, self.page + input.direction))
end

return App
