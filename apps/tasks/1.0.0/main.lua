local require = ...
local View = require("gui.view")
local App = { title = "tasks", single = true, w = 38, h = 13 }
App.__index = App

function App.new(d) return setmetatable({ d = d, offset = 0 }, App) end

function App:draw(v)
    local d, items, chosen = self.d, {}
    local all = {}
    local monitors = d.hooks.monitors
    for _, desktop in ipairs(monitors and monitors:allDesktops() or { d }) do
        for _, window in ipairs(desktop.wm.order) do
            all[#all + 1] = { window = window, desktop = desktop }
        end
    end
    table.sort(all, function(a, b) return a.window.task < b.window.task end)
    for index, item in ipairs(all) do
        local window = item.window
        items[index] = ("%d %s%s%s"):format(window.task, window.title, window.minimized and " [-]" or "",
            item.desktop.monitorName and (" @" .. item.desktop.monitorName) or "")
        if window.task == self.id then self.selected, chosen = index, item end
    end
    if not chosen then self.selected = nil end
    if v.h >= 4 then
        v:label(1, 1, d:t("running"), v.p.quiet)
    end
    v:page(v.h >= 4 and 2 or 1, items, self, function(index) self.id = all[index].window.task end,
        { d:t("actions"), chosen and function()
            local owner, window = chosen.desktop, chosen.window
            d:menu(v.x, v.y + 1, {
                { d:t("focus"), function() owner.wm:focus(window) end },
                { d:t("restart"), function() owner.wm:close(window, true, d) end },
                { d:t("endTask"), function() owner.wm:close(window, false, d) end },
            })
        end })
end

function App:input(input) View.scroll(self, input) end
return App
