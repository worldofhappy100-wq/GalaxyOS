local require = ...
local Files = require("core.files")
local View = require("gui.view")
local App = { title = "network", single = true, w = 43, h = 14 }
App.__index = App

function App.new(d, window, args)
    return setmetatable({ d = d, page = "peers", offset = 0, file = args.file }, App)
end

function App:activate(args)
    if args.file then self.file, self.page, self.offset = args.file, "peers", 0 end
end

function App:peer(id, v)
    local d, net = self.d, self.d.net
    local function send(path)
        assert(fs.exists(path) and not fs.isDir(path), d:t("invalidTarget"))
        net:offer(id, path)
        self.file = nil
    end
    if self.file then send(self.file); return end
    d:menu(v.x, v.y + 1, {
        { d:t("sendFile"), function()
            d:prompt(d:t("sendPath"), "/", function(value) send(Files.path("/", value)) end)
        end },
    })
end

function App:draw(v)
    local d, net = self.d, self.d.net
    v:bar(1, {
        { d:t("peers"), function() self.page, self.offset = "peers", 0 end, self.page == "peers" },
        { d:t("rooms"), function() self.page, self.offset = "rooms", 0 end, self.page == "rooms" },
        { d:t("inbox"), function() self.d:open("files", { path = fs.exists("/inbox") and "/inbox" or "/" }) end },
    })
    if not net.online then
        v:label(1, 2, d:t(net.enabled and "noModem" or "networkOffline"), v.p.quiet)
        v:button(1, v.h, d:t(net.enabled and "refresh" or "connect"), not d.hooks.state.safe and function()
            net:setEnabled(true)
        end, v.w)
        return
    end
    local ids, labels = {}, {}
    for id, peer in pairs(net.peers) do if self.page == "peers" or peer.room then ids[#ids + 1] = id end end
    table.sort(ids)
    for i, id in ipairs(ids) do
        local peer = net.peers[id]
        local label = ("%s #%d"):format(peer.name, id)
        if self.page == "rooms" then label = d:t(peer.game) .. " / " .. label end
        labels[i] = label
    end
    if #labels == 0 then labels[1] = d:t(self.page == "peers" and "noPeers" or "noRooms") end
    if self.file and self.page == "peers" and v.h >= 5 then v:label(1, 2, d:t("selectRecipient"), v.p.accent) end
    v:page(v.h >= 5 and self.file and self.page == "peers" and 3 or 2, labels, self, function(i)
        local id = ids[i]
        if not id then return end
        if self.page == "rooms" then
            local peer = net.peers[id]
            if peer then net:join(id, peer.room, peer.game) end
        else
            self:peer(id, v)
        end
    end, { d:t("actions"), function()
        d:menu(v.x, v.y + 1, {
            { d:t("refresh"), function() net:discover() end },
            { d:t("hostRoom"), function()
                d:menu(v.x, v.y + 1, {
                    { "2048", function() net:host("2048") end },
                    { d:t("mines"), function() net:host("mines") end },
                    { d:t("breakout"), function() net:host("breakout") end },
                })
            end },
            { d:t("disconnect"), function() net:setEnabled(false) end },
        })
    end })
end

function App:input(input) View.scroll(self, input) end
return App
