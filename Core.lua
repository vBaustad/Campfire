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
-- Neighbour mode: while a Campfire player shares our zone, someone may well be watching our dot on
-- the map, so we send more often - but only while actually moving.
local NEAR_GAP = 5
local NEAR_YARDS = 15
local CROWD_ON = 10     -- more than this many in the zone (a city): back to the slow rate
local CROWD_OFF = 8     -- ...and only back to the fast rate below this, so it doesn't flip about
local RIGHT_HERE = 40   -- closer than this reads "right here"

CF.PROTO = PROTO

-- hidden: share nothing at all (the one switch in the window).
-- openShare: besides the guild, also share with Campfire players on our faction over a hidden
--   channel (Open.lua). Custom channels are per faction, so the other faction never sees it.
-- zoneOnly: list only players in our zone (the window's "Show all zones" is its opposite).
-- mapPins: a dot per player on the world map and the zone map (MapPins.lua).
-- mapGuildOnly: only guildies get a dot. With strangers left out there is no crowd to fear, so...
-- mapZoneOnly: ...this starts off, and the whole continent can be shown at once.
local defaults = { hidden = false, zoneOnly = true, openShare = true, mapPins = true,
    mapGuildOnly = true, mapZoneOnly = false }
local migrations = {
    -- 2: openShare became opt-out (it was off by default in the first test builds).
    [2] = function(db) db.openShare = true end,
    -- 3: "Share my position with my guild" became "Hide my position": whoever had turned
    -- sharing off stays hidden.
    [3] = function(db)
        if db.share == false then db.hidden = true end
        db.share = nil
    end,
    -- 4: map dots became guild-only by default, which removes the crowd the zone limit guarded
    -- against, so the zone limit comes off with it - but only for players who never chose. The zone
    -- limit shipped in beta4, so someone may well have ticked it; mapZoneOnlyChosen marks that.
    [4] = function(db)
        if db.mapGuildOnly == nil then db.mapGuildOnly = true end
        if not db.mapZoneOnlyChosen then db.mapZoneOnly = false end
    end,
}

CF.peers = {}           -- ["Name-Realm"] = { map, x, y, seen, open, sub, level, class } or { seen, hidden = true }
local MAX_PEERS = 300   -- hard cap on everyone we track, whatever the channel
local SENDER_GAP = 3    -- ignore a sender that talks faster than the protocol allows
-- Messages: P = position, H = no position (indoors/instance), X = stopped sharing, Q = where is everyone?
-- P;proto;map;x;y;subzone;level;class - the last three were added later, so older clients ignore them.

function CF.Sharing()
    return CF.db and not CF.db.hidden
end

-- ---------------------------------------------------------------------------
-- Who we are, for the message
-- ---------------------------------------------------------------------------
--- Text that came from another player. Anything we show must be stripped first: a pipe would let a
--- sender inject |H item links, |T textures or |c colour codes into our window, tooltips and chat,
--- and control characters break lines apart. Also capped, so nobody sends a wall of text.
function CF.CleanText(s)
    if type(s) ~= "string" then return nil end
    s = s:gsub("|", "/"):gsub("%c", ""):gsub(";", ""):sub(1, 40)
    s = s:gsub("^%s+", ""):gsub("%s+$", "")
    return s ~= "" and s or nil
end

--- A position from the wire: a real map we know, and coordinates inside it.
function CF.ValidPosition(map, x, y)
    map, x, y = tonumber(map), tonumber(x), tonumber(y)
    if not (map and x and y) then return nil end
    if map < 1 or map ~= math.floor(map) then return nil end
    if x < 0 or x > 1 or y < 0 or y > 1 then return nil end
    if not ((LIB.Maps and LIB.Maps[map]) or C_Map.GetMapInfo(map)) then return nil end
    return map, x, y
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
    -- A name comes from the client, not from a message body, but it ends up in a chat line, so it is
    -- cleaned like anything else before use.
    full = CF.CleanText(full)
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

--- Is anyone with Campfire in our zone, without it being a crowd? Hysteretic: it takes more than
--- CROWD_ON to fall back, and fewer than CROWD_OFF to speed up again.
local crowded = false
local function Neighbours()
    local myZone = CF.ZoneOf(LIB.MapId())
    if not myZone then return false end
    local n = 0
    for _, p in pairs(CF.peers) do
        if not p.hidden and CF.ZoneOf(p.map) == myZone then n = n + 1 end
    end
    if n > CROWD_ON then crowded = true elseif n < CROWD_OFF then crowded = false end
    return n > 0 and not crowded, n
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
        local gap, yards = MIN_GAP, MOVE_YARDS
        local moved = LIB.Distance(map, x, y, last.map, last.x, last.y)
        -- Moving, with a neighbour to see it: keep the dot alive. Standing still stays on the heartbeat.
        if moved and moved > 0 and Neighbours() then gap, yards = NEAR_GAP, NEAR_YARDS end
        if elapsed < gap then return end
        if elapsed < HEARTBEAT and moved and moved < yards then return end
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
--- Room for one more? Beyond the cap we drop the stalest entry we track rather than grow forever.
function CF.MakeRoom(sender)
    if CF.peers[sender] then return true end
    local n, oldest, oldestAt = 0, nil, math.huge
    for full, p in pairs(CF.peers) do
        n = n + 1
        -- Players outside the guild go first, then whoever we heard from longest ago.
        local age = p.seen - (p.open and 0 or 1e6)
        if age < oldestAt then oldest, oldestAt = full, age end
    end
    if n < MAX_PEERS then return true end
    if not oldest then return false end
    CF.peers[oldest] = nil
    return true
end

--- Senders that talk faster than the protocol allows are ignored, so nobody can spam us.
local heardAt = {}
function CF.TooSoon(sender, gap)
    local now = GetTime()
    local last = heardAt[sender]
    if last and now - last < (gap or SENDER_GAP) then return true end
    heardAt[sender] = now
    return false
end

local function OnMessage(_, text, dist, sender)
    cached = nil    -- peers changed; the next Nearby() rebuilds
    -- LibForever only passes on guild messages and whispers from guildies.
    local kind, proto, a, b, c, sub, level, class = strsplit(";", text)
    if tonumber(proto) ~= PROTO then return end
    if kind == "P" then
        local map, x, y = CF.ValidPosition(a, b, c)
        if not map then return end
        if CF.TooSoon(sender) or not CF.MakeRoom(sender) then return end
        CF.peers[sender] = { map = map, x = x, y = y, seen = GetTime(),
            sub = CF.CleanText(sub), level = CF.ValidLevel(level), class = CF.ValidClass(class) }
    elseif kind == "H" then
        if CF.TooSoon(sender) or not CF.MakeRoom(sender) then return end
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
--- The window, the status line, the tooltips and the map all ask for this, several times a second,
--- so the answer is kept for a moment instead of walking every peer each time.
local cached, cachedAt, cachedElsewhere = nil, -1, 0
function CF.Nearby()
    local now = GetTime()
    if cached and now - cachedAt < 0.25 then return cached, cachedElsewhere end
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
    cached, cachedAt, cachedElsewhere = list, now, elsewhere
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
    -- Everyone gets their class colour; a green dot marks the ones outside the guild, like their
    -- green halo on the map.
    local name = (p.open and ("|cff26ff66" .. [[•]] .. "|r ") or "") .. LIB.ColorName(e.full, class)

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
    if className then className = "|c" .. LIB.ClassColor(class) .. className .. "|r" end
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
--- print(), unless a self-test is running: a test that passes should say nothing but its own line.
function CF.Say(text)
    if not CF.silent then print(text) end
end

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

function CF.SetMapPins(on)
    CF.db.mapPins = on and true or false
    if CF.RefreshMapPins then CF.RefreshMapPins() end
end

--- Ticking either map setting counts as choosing: from here on nothing overwrites it.
function CF.SetMapZoneOnly(on)
    CF.db.mapZoneOnly = on and true or false
    CF.db.mapZoneOnlyChosen = true
    if CF.RefreshMapPins then CF.RefreshMapPins() end
end

--- Guild-only and zone-only answer the same worry (a crowded map) in two ways, so they move
--- together instead of fighting: leaving the guild in means keeping the zone limit.
function CF.SetMapGuildOnly(on)
    CF.db.mapGuildOnly = on and true or false
    CF.db.mapZoneOnly = not CF.db.mapGuildOnly
    CF.db.mapZoneOnlyChosen = true
    if CF.RefreshMapPins then CF.RefreshMapPins() end
end

--- Map dots are GuildMap's speciality, so leave them off when it is installed - once, so the
--- player's own choice sticks afterwards.
local function DefaultMapPins()
    if CF.db.mapPinsDefaulted then return end
    CF.db.mapPinsDefaulted = true
    local guildMap = C_AddOns and ((C_AddOns.DoesAddOnExist and C_AddOns.DoesAddOnExist("GuildMap"))
        or (C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("GuildMap")))
    if guildMap then CF.db.mapPins = false end
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

--- The one short line under the window's toggles: "2 nearby - 3 elsewhere".
function CF.ShortStatus()
    local list, elsewhere = CF.Nearby()
    if #list == 0 and elsewhere == 0 then return "No one nearby" end
    local text = ("%d nearby"):format(#list)
    if CF.db.zoneOnly and elsewhere > 0 then text = text .. (" - %d elsewhere"):format(elsewhere) end
    return text
end

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
    elseif cmd == "selftest" then
        -- Also run by /yippyapp test across the family; not in the help text.
        if CF.SelfTest then CF.SelfTest(false) end
    elseif cmd:sub(1, 10) == "debug camp" then
        -- The camp research probe (Probe.lua) is not in the shipped build; add its line back to
        -- Campfire.toc to use it. Deliberately absent from the help text either way.
        if not (CF.ProbeCamp and CF.ProbeWatch) then
            CF.Say(TAG .. ": the camp probe isn't part of this build.")
        elseif cmd == "debug camp watch" then
            CF.ProbeWatch(180)
        else
            CF.ProbeCamp(cmd == "debug camp all")
        end
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
        local fast, inZone = Neighbours()
        print(("  neighbours in zone: %s, fast sending: %s"):format(tostring(inZone), tostring(fast)))
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
    CF.db = LIB.PrepareDB(CampfireDB, defaults, migrations, 4)
    CampfireDB = CF.db
    LIB.RegisterComm(PREFIX, OnMessage)
    RegisterLauncher()
    RegisterMinimap()
    DefaultMapPins()
    CF.RegisterOptions()
    CF.RegisterIntro()
    if CF.StartMapPins then CF.StartMapPins() end
    C_Timer.After(5, function()
        Send(("Q;%d"):format(PROTO))
        CF.SendPosition("login")
    end)
    C_Timer.NewTicker(5, function() CF.SendPosition("tick") end)
    if CF.StartOpen then CF.StartOpen() end
end)
