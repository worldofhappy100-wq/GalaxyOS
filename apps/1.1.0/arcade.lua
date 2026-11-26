local require = ...
local Files = require("core.files")
local Arcade = {}
Arcade.__index = Arcade
local dataPath = "/galaxy/config/arcade.settings"
local cues = { eat="bonus", turn="tilesMove", land="wall", clear="tilesMerge", hold="mineFlag",
    hit="paddle", wall="wall", goal="level", lostPoint="miss", shot="mineReveal",
    blast="mineBlast", pickup="bonus", level="level", win="tilesWin", loss="gameover" }
local step = 1 / 60
local maxSteps = 12

local function loadData()
    for _, path in ipairs({ dataPath, dataPath .. ".galaxy-bak" }) do
        local ok, data = pcall(function() return textutils.unserialize(Files.read(path, 8192)) end)
        if ok and type(data) == "table" then return data end
    end
    return {}
end

local function count(value)
    return type(value) == "number" and value >= 0 and math.min(1e9, math.floor(value)) or 0
end

function Arcade.new(host, engine, id)
    local d = host.d
    d.arcadeData = d.arcadeData or loadData()
    local saved = d.arcadeData[id]
    saved = type(saved) == "table" and saved or {}
    local stats = { best=count(saved.best), played=count(saved.played), won=count(saved.won), total=count(saved.total) }
    stats.won = math.min(stats.won, stats.played)
    local choices = {}
    for _, entry in ipairs(engine.options or {}) do
        local index = type(saved.choices) == "table" and saved.choices[entry.id]
        choices[entry.id] = type(index) == "number" and entry.values[index] and index or entry.default or 1
    end
    stats.choices = choices
    d.arcadeData[id] = stats
    return setmetatable({ host=host, d=d, engine=engine, id=id, stats=stats, mode="menu", held={} }, Arcade)
end

function Arcade:save()
    local ok, problem = self.d.prefs:store("arcade.settings", self.d.arcadeData)
    if not ok then self.d:error(problem) end
end

function Arcade:settingValues()
    local values = {}
    for _, entry in ipairs(self.engine.options or {}) do
        values[entry.id] = entry.values[self.stats.choices[entry.id]][1]
    end
    return values
end

function Arcade:keepBest()
    local score = self.state and count(self.state.score) or 0
    if score > self.stats.best then self.stats.best = score; self:save() end
end

function Arcade:play()
    self:keepBest()
    self.state = self.engine.logic.new(self:settingValues())
    self.mode, self.clock, self.held, self.last = "play", 0, {}, os.clock()
end

function Arcade:pause()
    if self.mode == "play" then self.mode = "pause"
    elseif self.mode == "pause" then self.mode = "play" end
    self.last, self.held, self.clock = os.clock(), {}, 0
end

function Arcade:fullscreen()
    local w = self.host.window
    if w then self.d.wm:fullscreen(w) end
end

function Arcade:frame(now)
    if self.mode ~= "play" then return false end
    local elapsed = math.max(0, now - self.last)
    self.last = now
    self.clock = math.min(step * maxSteps, self.clock + elapsed)
    for action, untilTime in pairs(self.held) do
        if now > untilTime then self.held[action] = nil end
    end
    local state = self.state
    while self.clock + 1e-8 >= step and not state.result do
        self.engine.logic.step(state, self.held, step)
        self.clock = math.max(0, self.clock - step)
    end
    if state.result then
        local stats, score = self.stats, count(state.score)
        stats.best, stats.played = math.max(stats.best, score), stats.played + 1
        if state.result == "win" then stats.won = stats.won + 1 end
        stats.total = stats.total + score
        state.cues = state.cues or {}
        state.cues[state.result] = true
        self.mode = "result"
        self:save()
    end
    for name in pairs(state.cues or {}) do
        if cues[name] then self.d.audio:play(cues[name]) end
    end
    state.cues = {}
    return self.mode == "play"
end

local Court = {}
Court.__index = Court

function Court:rect(x, y, w, h, color)
    local left = self.x + math.floor(x * self.scale)
    local top = self.y + math.floor(y * self.scale)
    local right = self.x + math.floor((x+w) * self.scale)
    local bottom = self.y + math.floor((y+h) * self.scale)
    self.view:pixel(left, top, math.max(1,right-left), math.max(1,bottom-top), color)
end

function Court:circle(x, y, radius, color)
    local screenRadius = math.max(1, math.floor(radius * self.scale + 0.5))
    local px, py = self.x + math.floor(x * self.scale), self.y + math.floor(y * self.scale)
    for dy = -screenRadius, screenRadius do
        local dx = math.floor(math.sqrt(screenRadius ^ 2 - dy ^ 2))
        self.view:pixel(px - dx, py + dy, 2 * dx + 1, 1, color)
    end
end

function Arcade:options(v)
    local choices, items = self.stats.choices, {}
    for _, entry in ipairs(self.engine.options or {}) do
        local selected = entry.values[choices[entry.id]]
        items[#items+1] = { self.d:t(entry.label) .. "  " .. self.d:t(selected[2]), function()
            choices[entry.id] = choices[entry.id] % #entry.values + 1
            self:save()
            self:options(v)
        end }
    end
    self.d:menu(v.x, v.y + 1, items)
end

function Arcade:help()
    local lines = {}
    for _, id in ipairs(self.engine.help) do lines[#lines+1] = self.d:t(id) end
    lines[#lines+1] = self.d:t("arcadeKeys")
    self.d:info(self.d:t(self.id), lines)
end

function Arcade:draw(v)
    local d, p = self.d, v.p
    local function t(...) return d:t(...) end
    local state = self.state
    local label = self.mode == "pause" and t("paused") or self.mode == "result"
        and t(state.result == "win" and "won" or "lost") or t(self.id)
    v:fill(1, 1, v.w, 1, p.raised)
    v:label(1, 1, label:sub(1, v.w), p.accent, p.raised)
    local buttons
    if self.mode == "play" then
        local status = self.engine.hud(state, t)
        local width = math.min(v.w, 102 / 2) * 2
        local height = math.min((v.h - 2) * 3, 51)
        if height < 12 or width < 22 then
            v:label(1, 2, t("largerScreen"):sub(1, v.w), p.quiet)
            self.court = nil
        else
            local bw, bh = self.engine.width, self.engine.height
            local scale = math.min(width / bw, height / bh)
            local court = setmetatable({ view=v, scale=scale,
                x=math.floor((v.w * 2 - bw*scale)/2)+1,
                y=math.floor((height-bh*scale)/2)+4, w=bw, h=bh, p=p }, Court)
            self.court = court
            v.b:withClip(v.x, v.y+1, v.w, v.h-2, function() self.engine.draw(court, state) end)
        end
        if #status + #label + 1 <= v.w then v:label(v.w - #status + 1, 1, status, p.ink, p.raised)
        else v:label(1, 1, status:sub(1, v.w), p.ink, p.raised) end
        buttons = {
            { t("pause"), function() self:pause() end },
            { t("arcadeFull"), function() self:fullscreen() end },
        }
    else
        self.court = nil
        if self.mode == "menu" then
            if v.h >= 3 then v:label(1, 2, t("best", self.stats.best):sub(1,v.w), p.ink) end
            if v.h >= 4 then
                v:label(1, 3, t("arcadeStats", self.stats.played, self.stats.won):sub(1,v.w), p.quiet)
            end
            if v.h >= 5 then v:label(1, 4, t("arcadeTotal", self.stats.total):sub(1,v.w), p.quiet) end
            buttons = {
                { t("arcadePlay"), function() self:play() end, true },
                { t("arcadeHelp"), function() self:help() end },
                { t("games"), function() self.host:home() end },
            }
            if self.engine.options and #self.engine.options > 0 then
                table.insert(buttons, 2, { t("arcadeOptions"), function() self:options(v) end })
            end
        else
            if v.h >= 3 then v:label(1, 2, self.engine.hud(state,t):sub(1,v.w), p.ink) end
            if v.h >= 4 then v:label(1, 3, t("best", self.stats.best):sub(1,v.w), p.quiet) end
            buttons = {
                { t("restart"), function() self:play() end },
                { t("arcadeMenu"), function() self:keepBest(); self.state, self.mode, self.held = nil, "menu", {} end },
                { t("games"), function() self.host:home() end },
            }
            if self.mode == "pause" then table.insert(buttons, 1, { t("resume"), function() self:pause() end, true }) end
        end
    end
    if v.w < 25 and #buttons > 2 then
        local all = buttons
        buttons = { buttons[1], { t("more"), function() d:menu(v.x, v.y+1, all) end } }
    end
    v:bar(v.h, buttons)
end

function Arcade:input(input)
    local kind = input.kind
    if kind == "key" or kind == "key_up" then
        local key = keys.getName(input.code)
        if kind == "key" and not input.repeating then
            if key == "f" then self:fullscreen(); return end
            if key == "p" or key == "escape" then
                if self.mode == "play" or self.mode == "pause" then self:pause()
                else self.host:home() end
                return
            end
            if key == "enter" and self.mode ~= "play" then
                if self.mode == "pause" then self:pause() else self:play() end
                return
            end
        end
        if self.mode ~= "play" then return end
        local action = self.engine.controls[key]
        if action then
            self.held[action] = kind == "key" and os.clock() + 0.9 or nil
            if kind == "key" and (not input.repeating or self.engine.repeatKeys and self.engine.repeatKeys[action]) then
                self.engine.logic.action(self.state, action)
            end
        end
    elseif self.mode == "play" and self.court
        and (kind == "click" or kind == "drag") and input.button == 1 and input.localX and input.localY then
        local c = self.court
        local x, y = (input.localX * 2 - 0.5 - c.x) / c.scale, (input.localY * 3 - 1 - c.y) / c.scale
        local steer = self.engine.pointer or self.engine.logic.pointer
        if steer and x >= -1 and y >= -1 and x <= c.w + 1 and y <= c.h + 1 then
            steer(self.state, x, y)
        end
    end
end

return Arcade
