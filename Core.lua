-- Campfire - find guildies and other Campfire players on your faction out in the world.
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
local RIGHT_HERE = 40   -- closer than this reads "right here"

CF.PROTO = PROTO
CF.STALE = STALE

-- hidden: share nothing at all (the one switch in the window).
-- openShare: besides the guild, also share with Campfire players on our faction over a hidden
--   channel (Open.lua). Custom channels are per faction, so the other faction never sees it.
-- zoneOnly: list only players in our zone (the window's "Show all zones" is its opposite).
local defaults = { hidden = false, zoneOnly = true, openShare = true }
local migrations = {
    -- 2: openShare became opt-out (it was off by default in the first test builds).
    [2] = function(db) db.openShare = true end,
    -- 3: "Share my position with my guild" became "Hide my position": whoever had turned
    -- sharing off stays hidden.
    [3] = function(db)
        if db.share == false then db.hidden = true end
        db.share = nil
    end,
}

CF.peers = {}           -- ["Name-Realm"] = { map, x, y, seen, open, sub, level, class } or { seen, hidden = true }
-- Messages: P = position, H = no position (indoors/instance), X = stopped sharing, Q = where is everyone?
-- P;proto;map;x;y;subzone;level;class - the last three were added later, so older clients ignore them.

function CF.Sharing()
    return CF.db and not CF.db.hidden
end

-- ---------------------------------------------------------------------------
-- Who we are, for the message
-- ---------------------------------------------------------------------------
--- Text that came from another player: no separators, no escape codes, and not too long.
function CF.CleanText(s)
    if type(s) ~= "string" then return nil end
    s = s:gsub("[;|\r\n]", ""):sub(1, 40)
    return s ~= "" and s or nil
end

--- Where we are within the zone: "Goldshire", "Fargodeep Mine"; nil in the open.
function CF.MySubZone()
    return CF.CleanText(GetSubZoneText()) or CF.CleanText(GetMinimapZoneText())
end

function CF.AboutMe()
    local _, class = UnitClass("player")
    return CF.MySubZone() or "", UnitLevel("player") or 0, class or ""
end

--- A received class token, only if it's a real one.
function CF.ValidClass(class)
    return class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class] and class or nil
end

function CF.ValidLevel(level)
    level = tonumber(level)
    return level and level >= 1 and level <= 100 and math.floor(level) or nil
end

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

--- Our position as a message: "P" with map, coordinates and who/where we are, or "H" when we have none.
local function PositionText()
    local map, x, y = LIB.MyPosition()
    if not map then return ("H;%d"):format(PROTO) end
    local sub, level, class = CF.AboutMe()
    return ("P;%d;%d;%.4f;%.4f;%s;%d;%s"):format(PROTO, map, x, y, sub, level, class), map, x, y
end

--- reason: "tick" (regular check, only sends when moved or due) or anything else (sends unless we just did).
function CF.SendPosition(reason)
    if not (CF.Sharing() and IsInGuild()) then return end
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
    if not CF.Sharing() then return end
    Send((PositionText()), target)
end

-- ---------------------------------------------------------------------------
-- Receiving
-- ---------------------------------------------------------------------------
local function OnMessage(_, text, dist, sender)
    -- LibForever only passes on guild messages and whispers from guildies.
    local kind, proto, a, b, c, sub, level, class = strsplit(";", text)
    if tonumber(proto) ~= PROTO then return end
    if kind == "P" then
        local map, x, y = tonumber(a), tonumber(b), tonumber(c)
        if not (map and x and y) then return end
        CF.peers[sender] = { map = map, x = x, y = y, seen = GetTime(),
            sub = CF.CleanText(sub), level = CF.ValidLevel(level), class = CF.ValidClass(class) }
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
local DIRS = { "E", "NE", "N", "NW", "W", "SW", "S", "SE" }

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

--- The zone a map belongs to: walks up from sub-zone, cave and floor maps to the zone map, so
--- two players in the same zone compare equal even on different floors. Continents stay themselves.
local zoneOf = {}
function CF.ZoneOf(mapId)
    if not mapId then return nil end
    if zoneOf[mapId] ~= nil then return zoneOf[mapId] end
    local ZONE = Enum and Enum.UIMapType and Enum.UIMapType.Zone or 3
    local id, info = mapId, C_Map.GetMapInfo(mapId)
    while info and info.mapType and info.mapType > ZONE and info.parentMapID and info.parentMapID ~= 0 do
        id = info.parentMapID
        info = C_Map.GetMapInfo(id)
    end
    local zone = (info and info.mapType == ZONE) and id or mapId
    zoneOf[mapId] = zone
    return zone
end

local function Expired(full, p, now)
    if p.open then return now - p.seen > (CF.OPEN_STALE or STALE) end
    return now - p.seen > STALE or (LIB.rosterReady and not LIB.IsOnline(full))
end

--- Players running Campfire, nearest first: { full, peer, yards, dir, sameZone }.
--- With zoneOnly on, only players in our zone are listed; the second return counts the rest.
function CF.Nearby()
    local map, x, y = LIB.MyPosition()
    local myZone = CF.ZoneOf(map)
    local zoneOnly = CF.db and CF.db.zoneOnly
    local now = GetTime()
    local list, elsewhere = {}, 0
    for full, p in pairs(CF.peers) do
        if Expired(full, p, now) then
            CF.peers[full] = nil
        else
            local same = not p.hidden and myZone ~= nil and CF.ZoneOf(p.map) == myZone
            if zoneOnly and not same then
                elsewhere = elsewhere + 1
            else
                local yards = (map and not p.hidden) and LIB.Distance(map, x, y, p.map, p.x, p.y) or nil
                list[#list + 1] = { full = full, peer = p, yards = yards, sameZone = same,
                    dir = yards and Direction(map, x, y, p) }
            end
        end
    end
    table.sort(list, function(l, r)
        if l.yards and r.yards then return l.yards < r.yards end
        if l.yards or r.yards then return l.yards ~= nil end
        return l.full < r.full
    end)
    return list, elsewhere
end

--- A rough distance: close ones to 10 yards, then 50, then 100.
local function Rough(yards)
    local step = yards < 200 and 10 or yards < 1000 and 50 or 100
    return math.floor(yards / step + 0.5) * step
end

--- The four parts of a row:
---   name (class colour)          where (sub-zone, or zone)
---   who ("20 Priest")            how ("1300 yd SW", "right here", "far away", "indoors")
function CF.RowText(e)
    local p = e.peer
    local r = LIB.roster[e.full]
    local class = (r and r.class) or p.class
    local level = (r and r.level) or p.level
    -- Players outside the guild (open channel) are grey.
    local name = p.open and ("|cff999999" .. LIB.ShortName(e.full) .. "|r") or LIB.ColorName(e.full, class)

    local where
    if p.hidden then
        where = ""
    elseif e.sameZone then
        where = p.sub or LIB.MapName(p.map)
    else
        -- Another zone (only listed with "Show all zones"): the zone says more than the sub-zone.
        where = LIB.MapName(CF.ZoneOf(p.map) or p.map)
    end

    local className = class and ((LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[class]) or class)
    if className then
        className = p.open and className or ("|c" .. LIB.ClassColor(class) .. className .. "|r")
    end
    local who = (level and tostring(level) or "") .. ((level and className) and " " or "") .. (className or "")

    local how
    if p.hidden then
        how = "indoors"
    elseif e.yards and e.yards < RIGHT_HERE then
        how = "right here"
    elseif e.yards then
        how = Rough(e.yards) .. " yd" .. (e.dir and (" " .. e.dir) or "")
    else
        how = "far away"
    end
    return name, where, who, how
end

function CF.PrintList()
    local list = CF.Nearby()
    print(TAG .. ": " .. CF.StatusText())
    for _, e in ipairs(list) do
        local name, where, who, how = CF.RowText(e)
        print(("  %s %s - %s%s"):format(name, who, where ~= "" and (where .. ", ") or "", how))
    end
end

-- ---------------------------------------------------------------------------
-- Hiding, launcher, compartment, slash
-- ---------------------------------------------------------------------------
local function OnLauncherClick(button)
    if button == "RightButton" then CF.OpenOptions() else CF.TogglePanel() end
end

--- Hide our position from everyone, or share it again as set in the settings.
function CF.SetHidden(hidden)
    hidden = hidden and true or false
    if CF.db.hidden == hidden then return end
    CF.db.hidden = hidden
    -- Hiding tells guildies at once, so they drop us now instead of after STALE.
    if hidden then Send(("X;%d"):format(PROTO)) else CF.SendPosition("share") end
    if CF.OpenHiddenChanged then CF.OpenHiddenChanged() end
    LIB.Fire("CAMPFIRE_PEERS")
end

function CF.SetShowAllZones(all)
    CF.db.zoneOnly = not all
    LIB.Fire("CAMPFIRE_PEERS")
end

--- "2 in your zone (1 guildie), 3 more elsewhere." The guildie count only shows when the list also
--- has players from outside the guild.
local function StatusText()
    local list, elsewhere = CF.Nearby()
    local guildies = 0
    for _, e in ipairs(list) do if not e.peer.open then guildies = guildies + 1 end end
    local text
    if #list == 0 then
        text = CF.db.zoneOnly and "No one in your zone" or "No one with Campfire online"
    else
        text = ("%d %s"):format(#list, CF.db.zoneOnly and "in your zone" or "with Campfire online")
        if guildies < #list then
            text = text .. (" (%d guildie%s)"):format(guildies, guildies == 1 and "" or "s")
        end
    end
    if CF.db.zoneOnly and elsewhere > 0 then text = text .. (", %d more elsewhere"):format(elsewhere) end
    return text .. "."
end
CF.StatusText = StatusText

local function TooltipLines(add)
    add(TAG)
    add(StatusText(), 1, 1, 1)
    if CF.db.hidden then add("Your position is hidden.", 1, 0.6, 0.2) end
    add("Left-click: open Campfire", 0.8, 0.8, 0.8)
    add("Right-click: settings", 0.8, 0.8, 0.8)
end

function Campfire_OnAddonCompartmentClick(_, button) OnLauncherClick(button) end
function Campfire_OnAddonCompartmentEnter(_, menuButton)
    GameTooltip:SetOwner(menuButton, "ANCHOR_LEFT")
    TooltipLines(function(...) GameTooltip:AddLine(...) end)
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
        OnTooltipShow = function(tt) TooltipLines(function(...) tt:AddLine(...) end) end,
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
    elseif cmd == "hide" or cmd == "share" then
        CF.SetHidden(not CF.db.hidden)
        print(TAG .. ": " .. (CF.db.hidden and "your position is hidden." or "sharing your position again."))
    elseif cmd == "options" or cmd == "settings" then
        CF.OpenOptions()
    elseif cmd == "debug" then
        local map, x, y = LIB.MyPosition()
        print(("%s debug: map %s (%s) at %s, %s; size known: %s; lockdown: %s; hidden: %s"):format(TAG,
            tostring(map), LIB.MapName(map), x and ("%.4f"):format(x) or "-", y and ("%.4f"):format(y) or "-",
            tostring(map and LIB.Maps and LIB.Maps[map] ~= nil), tostring(LIB.InChatLockdown()),
            tostring(CF.db.hidden)))
        local sub, level, class = CF.AboutMe()
        print(("  about me: %s, level %s, %s"):format(sub ~= "" and sub or "-", tostring(level), tostring(class)))
        if LIB.CommStats then
            local sent, received = LIB.CommStats(PREFIX)
            print(("  messages: %s sent, %s received"):format(tostring(sent), tostring(received)))
        end
        if CF.OpenDebug then CF.OpenDebug() end
        for full, p in pairs(CF.peers) do
            print(("  %s%s: %s, seen %ds ago"):format(full, p.open and " (open)" or "", p.hidden and "hidden" or
                ("map %d (zone %s) %.4f %.4f %s"):format(p.map, tostring(CF.ZoneOf(p.map)), p.x, p.y,
                    tostring(p.sub)), GetTime() - p.seen))
        end
    else
        print(TAG .. " v" .. CF.version .. " commands:")
        print("  /campfire  - open the window: players with Campfire near you")
        print("  /campfire list  - the same list in chat")
        print("  /campfire hide  - hide your position / share it again (now " .. (CF.db.hidden and "hidden" or "shared") .. ")")
        print("  /campfire options  - open the settings")
    end
end

-- ---------------------------------------------------------------------------
-- Startup
-- ---------------------------------------------------------------------------
LIB.On("PLAYER_LOGIN", function()
    CF.db = LIB.PrepareDB(CampfireDB, defaults, migrations, 3)
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
    if CF.StartOpen then CF.StartOpen() end
end)
