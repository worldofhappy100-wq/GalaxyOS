local require, load = ...
local Arcade = load("arcade.lua")(require)
local View = require("gui.view")
local App = { title = "games", single = true, w = 45, h = 17 }
App.__index = App
local breakoutSounds = { "wall", "paddle", "brick", "bonus", "miss", "level", "gameover" }
local mineSounds = { "mineReveal", "mineFlag", "mineUnflag", "mineBlast", "mineWin" }
local gameIds = { "2048", "mines", "breakout", "snake", "blockfall", "pong", "tanks", "airhockey" }
local function direction(code)
    if code == keys.up then return "up"
    elseif code == keys.left then return "left"
    elseif code == keys.down then return "down"
    elseif code == keys.right then return "right" end
end

function App.new(d, window, args)
    return setmetatable({ d = d, window = window, initial = args, level = 1, difficulty = "normal", offset = 0, cursor = 1 }, App)
end

function App:start()
    self.d.game, self.d.net.activeGame = self, self
    self:activate(self.initial)
end

function App:activate(args)
    if not args.game then return end
    if not self.d:hasGame(args.game) then self.d:notify(self.d:t("packageUnavailable")); return end
    local engine = self.d.packages:load(self.d.gamePackages[args.game])
    if self.arcade then self.arcade:keepBest() end
    if self.room and self.room ~= args.room then self.d.net:leave() end
    self.arcade = engine.logic and Arcade.new(self, engine, args.game) or nil
    self.game, self.room, self.engine = args.game, not self.arcade and args.room or nil, engine
    if self.arcade then
        self.state, self.animating, self.background = nil, false, false
    else self:reset() end
end

function App:stop()
    if self.arcade then self.arcade:keepBest() end
    if self.room and self.room == self.d.net.room then self.d.net:leave() end
    self.d.game = nil
    if self.d.net.activeGame == self then self.d.net.activeGame = nil end
end

function App:reset()
    self.paused, self.flags, self.cursor, self.boardTop, self.boardLeft = false, false, 1, 1, 1
    self.lastFrame, self.lastSync, self.remoteState = self.d.now, -1, nil
    self.animating, self.changed, self.guestSounds = false, true, {}
    if self.room and self.room.host ~= self.d.net.id then return end
    if self.game == "2048" then
        local seed = math.random(1, 2147483000)
        self.state = self.engine.new(seed)
        self.opponent = self.room and self.engine.new(seed) or nil
    elseif self.game == "mines" then self.state = self.engine.new(self.level)
    elseif self.game == "breakout" then self.state = self.engine.new(self.difficulty) end
end

function App:home()
    if self.arcade then self.arcade:keepBest() end
    self.arcade = nil
    if self.room then self.d.net:leave() end
    self.game, self.room, self.state, self.remoteState, self.animating = nil, nil, nil, nil, false
end

function App:abandon(room)
    if self.room == room then
        self.room, self.animating = nil, false
        if room.host ~= self.d.net.id then
            self.game, self.state, self.remoteState = nil, nil, nil
        end
    end
end

function App:guest()
    return self.room and self.room.host ~= self.d.net.id
end

function App:record(key, score, fastest)
    local new, saved, reason = self.d.prefs:score(key, score, fastest)
    if new then
        if key == "2048" then self:sound("tilesRecord") end
        if not saved then self.d:error(reason)
        elseif self.d.now - (self.recordNotice or -5) >= 4 then
            self.recordNotice = self.d.now
            self.d:notify(self.d:t("newRecord", score))
        end
    end
end

function App:sound(effect, shared)
    self.d.audio:play(effect)
    if shared and self.room and self.room.guest then self.guestSounds[effect] = true end
end

function App:tileSound(before, after)
    self:sound(after.score > before.score and "tilesMerge" or "tilesMove")
    if not before.won and after.won then self:sound("tilesWin") end
    if not before.over and after.over and not after.won then self:sound("tilesLoss") end
end

function App:move(action, value, remote)
    if not self.game or self.paused then return end
    local d = self.d
    if self:guest() then d.net:command(action, value); return end
    local s, changed = self.state
    if self.game == "2048" then
        local target = remote and self.opponent or s
        if target then
            local before = not remote and { score = target.score, won = target.won, over = target.over }
            changed = self.engine.move(target, action)
            if changed and before then
                self:tileSound(before, target)
                self:record("2048", s.score)
            end
        end
    elseif self.game == "mines" then
        local wasFlag = s.visible[value] == "F"
        changed = self.engine.move(s, action, value)
        if changed then
            if action == "flag" then self:sound(wasFlag and "mineUnflag" or "mineFlag", true)
            else
                self:sound(s.over and not s.won and "mineBlast" or "mineReveal", true)
                if s.won then
                    self:sound("mineWin", true)
                    self:record("mines" .. s.level, math.max(1, math.floor(s.elapsed)), true)
                end
            end
        end
    else
        changed = self.engine.move(s, action, value, remote and 2 or 1, self.room and self.room.guest)
        self.animating = s.playing
    end
    if changed then self.changed = true; d.hooks.invalidate() end
end

function App:remote(action, value) self:move(action, value, true) end

function App:public()
    local s = self.state
    if self.game == "2048" then return self.engine.public(s)
    elseif self.game == "mines" then return self.engine.public(s)
    else return self.engine.public(s, self.room and self.room.guest) end
end

function App:receive(packet)
    if not self:guest() or type(packet) ~= "table" or packet.game ~= self.game or type(packet.paused) ~= "boolean" then return false end
    local s = packet.state
    if self.game == "2048" then
        if not self.engine.valid(s) or type(packet.other) ~= "number" or packet.other < 0 or packet.other > 1e9
            or packet.other % 1 ~= 0 then return false end
        self.other = packet.other
        s = self.engine.public(s)
        local before = self.remoteState
        if before then
            for i = 1, 16 do
                if before.cells[i] ~= s.cells[i] then self:tileSound(before, s); break end
            end
        end
        self:record("2048", s.score)
    elseif self.game == "mines" then
        if not self.engine.valid(s) then return false end
        if s.won then self:record("mines" .. s.level, math.max(1, s.elapsed), true) end
    elseif not self.engine.valid(s) then return false
    else self:record("breakout", s.score) end
    if type(packet.sounds) == "table" and self.game ~= "2048" then
        for _, effect in ipairs(self.game == "mines" and mineSounds or breakoutSounds) do
            if packet.sounds[effect] == true then self:sound(effect) end
        end
    end
    self.remoteState, self.paused = s, packet.paused
    return true
end

function App:frame(now)
    if self.arcade then
        self.animating = self.arcade:frame(now)
        return
    end
    if not self.game or self:guest() then return end
    local s, d = self.state, self.d
    local elapsed = math.max(0, now - self.lastFrame)
    self.lastFrame = now
    if self.game == "mines" and #s.cells > 0 and not s.over and not self.paused then
        s.elapsed = math.min(86400, s.elapsed + elapsed)
    end
    if self.game == "breakout" then
        self.animating = s.playing and not self.paused
        if self.animating and elapsed > 0 then
            local effect, sounds = self.engine.tick(s, elapsed, self.room and self.room.guest)
            if sounds then
                for _, cue in ipairs(breakoutSounds) do if sounds[cue] then self:sound(cue, true) end end
            end
            if effect then self:record("breakout", s.score) end
            self.changed = true
        end
    end
    self.background = self.room ~= nil
    if self.room and self.room.guest and (now - self.lastSync > 0.9 or self.changed and now - self.lastSync >= 0.1) then
        local state = self.game == "2048" and self.engine.public(self.opponent) or self:public()
        d.net:publish({ game = self.game, state = state, paused = self.paused,
            other = self.game == "2048" and s.score or nil, sounds = self.guestSounds })
        self.guestSounds = {}
        self.lastSync, self.changed = now, false
    end
end

function App:gameMenu(v)
    local d = self.d
    local options = { { d:t("games"), function() self:home() end } }
    if not self:guest() then
        options[#options + 1] = { d:t(self.paused and "resume" or "pause"), function()
            self.paused, self.changed, self.lastFrame = not self.paused, true, d.now
        end }
        options[#options + 1] = { d:t("restart"), function() self:reset() end }
    end
    if not self.room and d.net.online then
        options[#options + 1] = { d:t("hostRoom"), function() d.net:host(self.game) end }
    end
    if self.room then options[#options + 1] = { d:t("leaveRoom"), function() self:home() end } end
    if self.game == "mines" and not self:guest() then
        options[#options + 1] = { d:t("difficulty"), function()
            d:menu(v.x, v.y + 1, {
                { d:t("easy"), function() self.level = 1; self:reset() end },
                { d:t("normal"), function() self.level = 2; self:reset() end },
                { d:t("hard"), function() self.level = 3; self:reset() end },
            })
        end }
    end
    if self.game == "breakout" and not self:guest() then
        options[#options + 1] = { d:t("difficulty"), function()
            local items = {}
            for _, key in ipairs({ "easy", "normal", "hard" }) do
                items[#items + 1] = { ("%s  %d%%"):format(d:t(key), self.engine.speeds[key] * 100), function()
                    self.difficulty = key
                    self:reset()
                end }
            end
            d:menu(v.x, v.y + 1, items)
        end }
    end
    local key = self.game == "mines" and "mines" .. self.level or self.game
    options[#options + 1] = { d:t("best", d.prefs:record(key)) }
    d:menu(v.x, v.y + 1, options)
end

function App:homepage(v)
    local d, items, ids = self.d, {}, {}
    for _, game in ipairs(gameIds) do
        if d:hasGame(game) then
            ids[#ids + 1], items[#items + 1] = game, d:t(game)
        end
    end
    if #items == 0 then items[1] = d:t("noGamesInstalled") end
    v:label(1, 1, d:t("selectGame"), v.p.accent)
    v:page(2, items, self, function(index) if ids[index] then self:activate({ game = ids[index] }) end end,
        { d:t("rooms"), function()
            local w = d:open("network")
            if w then w.app.page = "rooms" end
        end })
end

function App:drawTiles(v, s)
    local p, d = v.p, self.d
    local size = math.min(8, math.floor((v.w - (v.w >= 24 and 8 or 0)) / 4))
    local spacing = v.h >= 13 and 2 or 1
    local palette = { p.raised, p.border, p.accentSoft, p.logo, p.good, p.accent, p.warning, p.danger }
    for i, value in ipairs(s.cells) do
        local x, y = (i - 1) % 4 * size + 1, math.floor((i - 1) / 4) * spacing + 2
        local color = value == 0 and palette[1] or palette[math.min(8, math.floor(math.log(value, 2)) + 1)]
        local label = value == 0 and "" or tostring(value)
        v:fill(x, y, size - 1, 1, color)
        v:label(x + math.max(0, math.floor((size - 1 - #label) / 2)), y, label:sub(1, size - 1),
            value >= 16 and p.shadow or p.ink, color)
    end
    if v.w >= 24 then
        v:label(size * 4 + 2, 3, tostring(s.score):sub(1, v.w - size * 4 - 1), p.accent)
        local rival = self:guest() and self.other or self.opponent and self.room and self.room.guest and self.opponent.score
        if rival then v:label(size * 4 + 2, 5, tostring(rival):sub(1, v.w - size * 4 - 1), p.quiet) end
    end
    v:bar(v.h, {
        { "<", function() self:move("left") end },
        { "^", function() self:move("up") end },
        { "v", function() self:move("down") end },
        { ">", function() self:move("right") end },
        { d:t("more"), function() self:gameMenu(v) end },
    })
end

function App:drawMines(v, s)
    local p, d = v.p, self.d
    local width = v.w >= 17 and 2 or 1
    local rows = math.min(8, v.h - 2)
    self.boardRows = rows
    self.boardTop = math.max(1, math.min(9 - rows, self.boardTop))
    for row = self.boardTop, self.boardTop + rows - 1 do
        for col = 1, 8 do
            local i = (row - 1) * 8 + col
            local x, y = (col - 1) * width + 1, row - self.boardTop + 2
            local symbol = s.cells:sub(i, i)
            local color = symbol == "." and p.raised or symbol == "F" and p.accentSoft or p.background
            if i == self.cursor then color = p.border end
            v:fill(x, y, width, 1, color)
            v:label(x, y, symbol == "0" and " " or symbol, symbol == "*" and p.danger or p.ink, color)
            v:hit(x, y, width, 1, function()
                self.cursor = i
                self:move(self.flags and "flag" or "reveal", i)
            end, function() self.cursor = i; self:move("flag", i) end)
        end
    end
    if v.w - width * 8 >= 6 then
        v:label(width * 8 + 2, 2, ("%d/%d"):format(s.count - s.flags, s.count), p.quiet)
        v:label(width * 8 + 2, 3, ("%ds"):format(s.elapsed), p.accent)
    end
    local buttons = { { d:t("flag"), function() self.flags = not self.flags end, self.flags } }
    if rows < 8 then
        buttons[#buttons + 1] = { "^", function() self.boardTop = self.boardTop - 1 end }
        buttons[#buttons + 1] = { "v", function() self.boardTop = self.boardTop + 1 end }
    end
    buttons[#buttons + 1] = { d:t("more"), function() self:gameMenu(v) end }
    v:bar(v.h, buttons)
end

function App:drawBreakout(v, s)
    local p, d = v.p, self.d
    local screenWidth, screenHeight = math.min(v.w * 2, 62), (v.h - 2) * 3
    self.courtWidth = screenWidth
    local function line(x, y, w, h, color)
        local ox = math.floor((x - 0.5) * screenWidth / self.engine.width)
        local oy = math.floor((y - 0.5) * screenHeight / self.engine.height)
        local right = math.floor((x - 0.5 + w) * screenWidth / self.engine.width)
        local bottom = math.floor((y - 0.5 + h) * screenHeight / self.engine.height)
        if ox < screenWidth and oy < screenHeight then
            v:pixel(ox + 1, oy + 4, math.max(1, right - ox), math.max(1, bottom - oy), color)
        end
    end
    v:pixel(1, 4, screenWidth, screenHeight, p.background)
    for i = 1, 24 do
        local strength = tonumber(s.bricks:sub(i, i))
        if strength > 0 then line((i - 1) % 6 * 6 + 1, math.floor((i - 1) / 6) * 2 + 3, 5, 1.25,
            strength == 3 and p.danger or strength == 2 and p.logo or p.accent) end
    end
    line(s.x - 0.5, s.y - 0.5, 1, 1, p.ink)
    local left, right = self.engine.paddleEdges(s.p1, s.width)
    line(left, 23, right - left, 1, p.good)
    if s.duo then
        left, right = self.engine.paddleEdges(s.p2, s.width)
        line(left, 23, right - left, 1, p.logo)
    end
    if s.bx then line(s.bx - 0.5, s.by - 0.5, 1, 1, p.warning) end
    if v.w >= 36 then v:label(math.ceil(screenWidth / 2) + 2, 3, d:t("lives", s.lives), p.quiet) end
    self.courtX, self.courtRows = v.x, v.h - 2
    v:hit(1, 2, math.ceil(screenWidth / 2), v.h - 2, function(input) self:steer(input.x) end)
    local pos = self:guest() and s.p2 or s.p1
    v:bar(v.h, {
        { "<", function() self:move("paddle", pos - 4) end },
        { d:t("launch"), not s.playing and function() self:move("launch") end },
        { ">", function() self:move("paddle", pos + 4) end },
        { d:t("more"), function() self:gameMenu(v) end },
    })
end

function App:draw(v)
    if self.arcade then self.arcade:draw(v); return end
    if not self.game then self:homepage(v); return end
    local d = self.d
    local s = self:guest() and self.remoteState or not self:guest() and self:public()
    if not s or v.h < 7 then
        v:label(1, 1, d:t(s and "largerScreen" or "waiting"), v.p.quiet)
        v:button(1, v.h, d:t("more"), function() self:gameMenu(v) end, v.w)
        return
    end
    local status = self.paused and d:t("paused") or s.over and d:t(s.won and "won" or "lost") or d:t(self.game)
    if self.game == "breakout" then
        status = ("%s %d/L%d %s"):format(status, s.score, s.level, d:t(s.difficulty or "normal"))
    end
    if self.game == "2048" and v.w < 24 then status = status .. " " .. tostring(s.score) end
    if self.room and v.w >= 28 then
        status = status .. "  " .. d:t(self:guest() and "guest" or self.room.guest and "roomLive" or "waiting")
    end
    v:label(1, 1, status:sub(1, v.w), v.p.accent)
    if self.game == "2048" then self:drawTiles(v, s)
    elseif self.game == "mines" then self:drawMines(v, s)
    else self:drawBreakout(v, s) end
end

function App:steer(x)
    local px = (x - self.courtX + 0.5) * 2
    local target = math.max(1, math.min(self.engine.width, 0.5 + px / self.courtWidth * self.engine.width))
    self:move("paddle", target)
end

function App:input(input)
    if self.arcade then self.arcade:input(input); return end
    if not self.game then View.scroll(self, input); return end
    if self.game == "mines" and input.kind == "scroll" then self.boardTop = self.boardTop + input.direction end
    if self.game == "breakout" and input.kind == "drag" and input.button == 1 and self.courtX
        and input.localY and input.localY >= 2 and input.localY <= self.courtRows + 1 then
        self:steer(input.x)
        return
    end
    if input.kind ~= "key" then return end
    if not self:guest() and input.code == keys.p and not input.repeating then
        self.paused, self.changed, self.lastFrame = not self.paused, true, self.d.now
    end
    if self.game == "2048" then
        local dir = direction(input.code)
        if dir then self:move(dir) end
    elseif self.game == "mines" then
        local dir = direction(input.code)
        local deltas = { left = -1, right = 1, up = -8, down = 8 }
        if dir then
            self.cursor = math.max(1, math.min(64, self.cursor + deltas[dir]))
            local row = math.floor((self.cursor - 1) / 8) + 1
            if row < self.boardTop then self.boardTop = row end
            if row >= self.boardTop + (self.boardRows or 1) then self.boardTop = row - (self.boardRows or 1) + 1 end
        elseif input.code == keys.space or input.code == keys.enter then
            self:move("reveal", self.cursor)
        elseif input.code == keys.f then self:move("flag", self.cursor) end
    elseif self.game == "breakout" then
        local s = self:guest() and self.remoteState or self.state
        if not s then return end
        local center = self:guest() and s.p2 or s.p1
        if input.code == keys.left then self:move("paddle", center - 3)
        elseif input.code == keys.right then self:move("paddle", center + 3)
        elseif input.code == keys.space or input.code == keys.enter then self:move("launch") end
    end
end

return App
