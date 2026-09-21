-- Campfire - find your guildies out in the world.
-- Each player running Campfire shares their own map position with the guild over the addon channel
-- (the client only lets an addon read its own position and its party's), and everyone works out
-- the distance in yards from the map sizes in LibForever's Maps.lua.
local ADDON, CF = ...
local LIB = LibStub("LibForever-1.0")

CF.version = C_AddOns.GetAddOnMetadata(ADDON, "Version") or "?"
CF.TAG = "|cffff9933Campfire|r"
local TAG = CF.TAG

local PREFIX = "Campfire"
local PROTO = 1
local STALE = 240       -- forget a guildie after this many seconds without news
local HEARTBEAT = 90    -- resend at least this often while standing still
local MIN_GAP = 15      -- never send more often than this while moving
local MOVE_YARDS = 40   -- ...and only once we've moved this far

local defaults = { share = true }

CF.peers = {}           -- ["Name-Realm"] = { map, x, y, seen } or { seen, hidden = true }
-- Messages: P = position, H = no position (indoors/instance), X = stopped sharing, Q = where is everyone?

-- ---------------------------------------------------------------------------
-- Sending our position
-- ---------------------------------------------------------------------------
local last = { at = -math.huge }

--- The name to whisper: on our own realm the client wants "Name", not "Name-Realm".
--- Stored names and comparisons keep the full form. LIB.Send normalises its own targets.
function CF.WhisperName(full)
    if LIB.WhisperName then return LIB.WhisperName(full) end
    if not full then return nil end
    local name, realm = full:match("^(.-)%-(.+)$")
    if not name then return full end
    return realm == LIB.Realm() and name or full
end

--- To the guild, or whispered to one guildie when target is given.
local function Send(text, target)
    LIB.Send(PREFIX, text, target and "WHISPER" or "GUILD", target, "BULK")
end

--- Our position as a message: "P" with map and coordinates, or "H" when we have none.
local function PositionText()
    local map, x, y = LIB.MyPosition()
    if not map then return ("H;%d"):format(PROTO) end
    return ("P;%d;%d;%.4f;%.4f"):format(PROTO, map, x, y), map, x, y
end

--- reason: "tick" (regular check, only sends when moved or due) or anything else (sends unless we just did).
function CF.SendPosition(reason)
    if not (CF.db and CF.db.share and IsInGuild()) then return end
    -- Chat lockdown does not touch addon messages (SendAddonMessage has no lockdown clause), so
    -- positions keep flowing through it.
    local now = GetTime()
    local text, map, x, y = PositionText()
    local elapsed = now - last.at
    if not map then
        -- Indoors or in an instance: say so when it happens, then again on every heartbeat so
        -- guildies keep us listed instead of dropping us as gone.
        if reason == "tick" and not last.map and elapsed < HEARTBEAT then return end
        Send(text)
        last = { at = now }
        return
    end
    if reason == "tick" then
        if elapsed < MIN_GAP then return end
        local moved = LIB.Distance(map, x, y, last.map, last.x, last.y)
        if elapsed < HEARTBEAT and moved and moved < MOVE_YARDS then return end
    elseif elapsed < 5 and last.map then
        return
    end
    Send(text)
    last = { at = now, map = map, x = x, y = y }
end

--- Answer one guildie's "where is everyone": whispered, so a login doesn't set off a guild-wide burst.
local function ReplyPosition(target)
    if not (CF.db and CF.db.share) then return end
    Send((PositionText()), target)
end

-- ---------------------------------------------------------------------------
-- Receiving
-- ---------------------------------------------------------------------------
local function OnMessage(_, text, dist, sender)
    -- LibForever only passes on guild messages and whispers from guildies.
    local kind, proto, a, b, c = strsplit(";", text)
    if tonumber(proto) ~= PROTO then return end
    if kind == "P" then
        local map, x, y = tonumber(a), tonumber(b), tonumber(c)
        if not (map and x and y) then return end
        CF.peers[sender] = { map = map, x = x, y = y, seen = GetTime() }
    elseif kind == "H" then
        CF.peers[sender] = { seen = GetTime(), hidden = true }
    elseif kind == "X" then
        -- They stopped sharing: forget them now.
        CF.peers[sender] = nil
    elseif kind == "Q" and dist == "GUILD" then
        -- A guildie just logged in and asks where everyone is; spread the answers out.
        C_Timer.After(1 + math.random() * 5, function() ReplyPosition(sender) end)
        return
    else
        return
    end
    LIB.Fire("CAMPFIRE_PEERS")
end

-- ---------------------------------------------------------------------------
-- Who is where
-- ---------------------------------------------------------------------------
local DIRS = { "east", "northeast", "north", "northwest", "west", "southwest", "south", "southeast" }

--- Compass direction from us to them, only when we're on the same map.
local function Direction(map, x, y, p)
    local size = LIB.Maps and LIB.Maps[map]
    if not size or p.map ~= map then return nil end
    local dx, dy = (p.x - x) * size[1], (p.y - y) * size[2]
    if dx == 0 and dy == 0 then return nil end
    local angle = math.atan2(-dy, dx)   -- map y grows southwards
    local i = math.floor(angle / (2 * math.pi) * 8 + 0.5) % 8
    return DIRS[i + 1]
end

--- Guildies running Campfire, nearest first: { full, peer, yards, dir }.
function CF.Nearby()
    local map, x, y = LIB.MyPosition()
    local now = GetTime()
    local list = {}
    for full, p in pairs(CF.peers) do
        if now - p.seen > STALE or (LIB.rosterReady and not LIB.IsOnline(full)) then
            CF.peers[full] = nil
        else
            local yards = (map and not p.hidden) and LIB.Distance(map, x, y, p.map, p.x, p.y) or nil
            list[#list + 1] = { full = full, peer = p, yards = yards, dir = yards and Direction(map, x, y, p) }
        end
    end
    table.sort(list, function(l, r)
        if l.yards and r.yards then return l.yards < r.yards end
        if l.yards or r.yards then return l.yards ~= nil end
        return l.full < r.full
    end)
    return list
end

local function Describe(e)
    local r = LIB.roster[e.full]
    local name = LIB.ColorName(e.full, r and r.class)
    local p = e.peer
    if p.hidden then
        return name .. " - |cff999999indoors or in an instance|r"
    end
    local zone = LIB.MapName(p.map)
    if e.yards then
        return ("%s - |cffffffff%d yd|r%s, %s"):format(name, math.floor(e.yards + 0.5),
            e.dir and (" " .. e.dir) or "", zone)
    end
    return ("%s - %s |cff999999(too far to measure)|r"):format(name, zone)
end

function CF.PrintList()
    if not IsInGuild() then print(TAG .. ": you're not in a guild.") return end
    local list = CF.Nearby()
    if #list == 0 then
        print(TAG .. ": no guildies with Campfire online yet.")
        return
    end
    print(("%s: %d guildie%s with Campfire online:"):format(TAG, #list, #list == 1 and "" or "s"))
    for _, e in ipairs(list) do print("  " .. Describe(e)) end
    if not CF.db.share then print("  |cff999999You aren't sharing your own position (/campfire share).|r") end
end

-- ---------------------------------------------------------------------------
-- Launcher, compartment, slash
-- ---------------------------------------------------------------------------
local function OnLauncherClick(button)
    if button == "RightButton" then CF.OpenOptions() else CF.TogglePanel() end
end

function CF.SetShare(on)
    if CF.db.share == on then return end
    CF.db.share = on
    -- Turning it off tells guildies at once, so they drop us now instead of after STALE.
    if on then CF.SendPosition("share") else Send(("X;%d"):format(PROTO)) end
end

local function StatusText()
    local list = CF.Nearby()
    local near = 0
    for _, e in ipairs(list) do if e.yards and e.yards <= 1000 then near = near + 1 end end
    if #list == 0 then return "No guildies with Campfire online." end
    return ("%d online, %d within 1000 yards"):format(#list, near)
end
CF.StatusText = StatusText

function Campfire_OnAddonCompartmentClick(_, button) OnLauncherClick(button) end
function Campfire_OnAddonCompartmentEnter(_, menuButton)
    GameTooltip:SetOwner(menuButton, "ANCHOR_LEFT")
    GameTooltip:AddLine(TAG)
    GameTooltip:AddLine(StatusText(), 1, 1, 1)
    GameTooltip:AddLine("Left-click: open Campfire", 0.8, 0.8, 0.8)
    GameTooltip:AddLine("Right-click: settings", 0.8, 0.8, 0.8)
    GameTooltip:Show()
end
function Campfire_OnAddonCompartmentLeave() GameTooltip:Hide() end

local function RegisterLauncher()
    if not LIB.RegisterLauncher then return end
    LIB.RegisterLauncher({
        id = "Campfire", label = "Campfire", order = 30,
        icon = "Interface\\AddOns\\Campfire\\Media\\notch",
        onClick = OnLauncherClick,
        status = StatusText,
        tooltip = { "Left-click: open Campfire", "Right-click: settings" },
    }, CF.db)
end

local function RegisterMinimap()
    if not LIB.RegisterMinimapButton then return end
    LIB.RegisterMinimapButton("Campfire", {
        icon = "Interface\\AddOns\\Campfire\\Media\\minimap",
        label = "Campfire",
        OnClick = function(_, button) OnLauncherClick(button) end,
        OnTooltipShow = function(tt)
            tt:AddLine(TAG)
            tt:AddLine(StatusText(), 1, 1, 1)
            tt:AddLine("Left-click: open Campfire", 0.8, 0.8, 0.8)
            tt:AddLine("Right-click: settings", 0.8, 0.8, 0.8)
        end,
    }, CF.db)
end

SLASH_CAMPFIRE1 = "/campfire"
SLASH_CAMPFIRE2 = "/cfire"
SlashCmdList.CAMPFIRE = function(msg)
    local cmd = strtrim((msg or ""):lower())
    if cmd == "" then
        CF.TogglePanel()
    elseif cmd == "list" then
        CF.PrintList()
    elseif cmd == "share" then
        CF.SetShare(not CF.db.share)
        print(TAG .. ": " .. (CF.db.share and "sharing your position with the guild." or "no longer sharing your position."))
    elseif cmd == "options" or cmd == "settings" then
        CF.OpenOptions()
    elseif cmd == "debug" then
        local map, x, y = LIB.MyPosition()
        print(("%s debug: map %s (%s) at %s, %s; size known: %s; lockdown: %s"):format(TAG, tostring(map),
            LIB.MapName(map), x and ("%.4f"):format(x) or "-", y and ("%.4f"):format(y) or "-",
            tostring(map and LIB.Maps and LIB.Maps[map] ~= nil), tostring(LIB.InChatLockdown())))
        if LIB.CommStats then
            local sent, received = LIB.CommStats(PREFIX)
            print(("  messages: %s sent, %s received"):format(tostring(sent), tostring(received)))
        end
        for full, p in pairs(CF.peers) do
            print(("  %s: %s, seen %ds ago"):format(full, p.hidden and "hidden" or
                ("map %d %.4f %.4f"):format(p.map, p.x, p.y), GetTime() - p.seen))
        end
    else
        print(TAG .. " v" .. CF.version .. " commands:")
        print("  /campfire  - open the window: guildies with Campfire and how far away they are")
        print("  /campfire list  - the same list in chat")
        print("  /campfire share  - start / stop sharing your position (now " .. (CF.db.share and "on" or "off") .. ")")
        print("  /campfire options  - open the settings")
    end
end

-- ---------------------------------------------------------------------------
-- Startup
-- ---------------------------------------------------------------------------
LIB.On("PLAYER_LOGIN", function()
    CF.db = LIB.PrepareDB(CampfireDB, defaults, nil, 1)
    CampfireDB = CF.db
    LIB.RegisterComm(PREFIX, OnMessage)
    RegisterLauncher()
    RegisterMinimap()
    CF.RegisterOptions()
    CF.RegisterIntro()
    C_Timer.After(5, function()
        Send(("Q;%d"):format(PROTO))
        CF.SendPosition("login")
    end)
    C_Timer.NewTicker(5, function() CF.SendPosition("tick") end)
end)
