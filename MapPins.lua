-- Campfire - a dot per Campfire player on the world map and the battlefield (zone) map.
-- Blizzard's map is built for this: data providers are called through secureexecuterange, and pins
-- come from the map's own pool, so our dots never touch the group-member pins or any secret data.
-- Everything here comes from the positions guildies and faction players already send us.
local ADDON, CF = ...
local LIB = LibStub("LibForever-1.0")

local TEMPLATE = "CampfireMapPinTemplate"
local REFRESH = 2   -- seconds between refreshes while a map is open
local MAX_PINS = 40 -- stop drawing after this many; the tooltip says how many are left out
local SIZE, SIZE_HOVER = 10, 12

function CF.MapPinsEnabled()
    return CF.db and CF.db.mapPins
end

--- A peer's position on the map being shown: the same map, or converted through world coordinates
--- (a zone position shown on its continent, say). Returns nil when it isn't on this map.
local function PositionOnMap(p, mapID)
    if not (p.map and p.x and p.y and mapID) then return nil end
    if p.map == mapID then return p.x, p.y end
    if not (C_Map.GetWorldPosFromMapPos and C_Map.GetMapPosFromWorldPos and CreateVector2D) then return nil end
    local ok, continent, world = pcall(C_Map.GetWorldPosFromMapPos, p.map, CreateVector2D(p.x, p.y))
    if not (ok and continent and world) then return nil end
    local ok2, _, pos = pcall(C_Map.GetMapPosFromWorldPos, continent, world, mapID)
    if not (ok2 and pos) then return nil end
    local x, y = pos:GetXY()
    if not x or x < 0 or x > 1 or y < 0 or y > 1 then return nil end
    return x, y
end

-- ---------------------------------------------------------------------------
-- The pin
-- ---------------------------------------------------------------------------
-- Blizzard's map mixins; without them (a client that lays the map out differently) we simply draw no dots.
CampfireMapPinMixin = MapCanvasPinMixin and CreateFromMixins(MapCanvasPinMixin) or {}

-- Campfire players outside the guild: a bright green that no class uses.
local OUTSIDE = { r = 0.15, g = 1, b = 0.4 }

-- Blizzard's pins let right clicks fall through to the map (to zoom out) through
-- Frame:SetPassThroughButtons, which is protected for addons in Forever: AcquirePin calls
-- CheckMouseButtonPassthrough on every pin, and that raised ADDON_ACTION_BLOCKED every time the map
-- opened. It is our pin's own method, so we simply do nothing: our dot is small, and a right click on
-- it just does nothing instead of zooming the map out.
function CampfireMapPinMixin:CheckMouseButtonPassthrough()
end

function CampfireMapPinMixin:OnLoad()
    -- Sit at the same level as the group-member dots; fall back quietly on a map without that level.
    pcall(self.UseFrameLevelType, self, "PIN_FRAME_LEVEL_GROUP_MEMBER")
    -- The same size on screen at every zoom: a dot that grows as you zoom in just looks blurry.
    self.ignoreGlobalPinScale = true
    if self.SetScalingLimits then pcall(self.SetScalingLimits, self, 1, 1, 1) end
end

--- Full class colours, not the dimmed ones the chat uses; green when we don't know the class.
local function DotColor(full, peer)
    local r = LIB.roster[full]
    local class = (r and r.class) or peer.class
    local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    return c or OUTSIDE
end

function CampfireMapPinMixin:SetHighlighted(on)
    local size = on and SIZE_HOVER or SIZE
    self:SetSize(size, size)
    local lift = on and 1.3 or 1
    self.Dot:SetVertexColor(math.min(1, self.r * lift), math.min(1, self.g * lift), math.min(1, self.b * lift))
end

function CampfireMapPinMixin:Setup(full, peer)
    self.full, self.peer = full, peer
    local c = DotColor(full, peer)
    self.r, self.g, self.b = c.r, c.g, c.b
    self:SetHighlighted(false)
end

function CampfireMapPinMixin:OnMouseEnter()
    if not self.full then return end
    self:SetHighlighted(true)
    local p = self.peer
    local r = LIB.roster[self.full]
    local class = (r and r.class) or p.class
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine(LIB.ColorName(self.full, class))
    local level = (r and r.level) or p.level
    local className = class and ((LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[class]) or class)
    local who = (level and tostring(level) or "") .. ((level and className) and " " or "") .. (className or "")
    if who ~= "" then GameTooltip:AddLine(who, 1, 1, 1) end
    GameTooltip:AddLine(p.sub or LIB.MapName(p.map), 1, 1, 1)
    local myMap, myX, myY = LIB.MyPosition()
    local yards = myMap and LIB.Distance(myMap, myX, myY, p.map, p.x, p.y)
    if yards then GameTooltip:AddLine(("%d yards away"):format(math.floor(yards + 0.5)), 0.8, 0.8, 0.8) end
    if p.open then GameTooltip:AddLine("Not in your guild", 0.15, 1, 0.4) end
    if CF.mapHidden and CF.mapHidden > 0 then
        GameTooltip:AddLine((" %d more not shown here"):format(CF.mapHidden), 0.8, 0.8, 0.8)
    end
    GameTooltip:AddLine("Click to whisper", 0.8, 0.8, 0.8)
    GameTooltip:Show()
end

function CampfireMapPinMixin:OnMouseLeave()
    self:SetHighlighted(false)
    GameTooltip:Hide()
end

local function Whisper(full)
    local target = full and CF.WhisperName(full)
    if not target then return end
    if ChatFrameUtil and ChatFrameUtil.OpenChat then ChatFrameUtil.OpenChat("/w " .. target .. " ")
    elseif ChatFrame_OpenChat then ChatFrame_OpenChat("/w " .. target .. " ") end
end

-- The map calls one of these depending on the client's pin code; both do the same.
function CampfireMapPinMixin:OnMouseClickAction(button)
    if button == "LeftButton" then Whisper(self.full) end
end

function CampfireMapPinMixin:OnClick(button)
    if button == "LeftButton" then Whisper(self.full) end
end

-- ---------------------------------------------------------------------------
-- The data provider, one per map
-- ---------------------------------------------------------------------------
local providers = {}

local function NewProvider()
    local provider = CreateFromMixins(MapCanvasDataProviderMixin)

    function provider:RemoveAllData()
        self:GetMap():RemoveAllPinsByTemplate(TEMPLATE)
    end

    function provider:RefreshAllData()
        self:RemoveAllData()
        CF.mapHidden = 0
        if not CF.MapPinsEnabled() or not next(CF.peers) then return end
        local map = self:GetMap()
        local mapID = map:GetMapID()
        if not mapID then return end
        -- "Only in my zone": only draw on a zone map, and only players in that zone. That keeps the
        -- continent and world maps clean, which is where a crowd would pile up.
        local zoneOnly = CF.db.mapZoneOnly
        local guildOnly = CF.db.mapGuildOnly
        local shownZone = CF.ZoneOf(mapID)
        if zoneOnly and shownZone ~= mapID then return end

        local myMap, myX, myY = LIB.MyPosition()
        local draw = {}
        for full, p in pairs(CF.peers) do
            -- No dot for anyone indoors or in an instance: they have no position to show.
            if not p.hidden and not (guildOnly and p.open) and not (zoneOnly and CF.ZoneOf(p.map) ~= shownZone) then
                local x, y = PositionOnMap(p, mapID)
                if x then
                    draw[#draw + 1] = { full = full, p = p, x = x, y = y,
                        yards = myMap and LIB.Distance(myMap, myX, myY, p.map, p.x, p.y) or math.huge }
                end
            end
        end
        -- Nearest first, so the cap drops the far-away ones.
        table.sort(draw, function(l, r) return l.yards < r.yards end)
        for i, d in ipairs(draw) do
            if i > MAX_PINS then
                CF.mapHidden = #draw - MAX_PINS
                break
            end
            local pin = map:AcquirePin(TEMPLATE)
            pin:Setup(d.full, d.p)
            pin:SetPosition(d.x, d.y)
        end
    end

    function provider:OnMapChanged()
        MapCanvasDataProviderMixin.OnMapChanged(self)
        self:RefreshAllData()
    end

    return provider
end


--- Redraw every open map.
function CF.RefreshMapPins()
    for canvas, provider in pairs(providers) do
        if canvas:IsShown() then pcall(provider.RefreshAllData, provider) end
    end
end

-- The ticker only runs while one of our maps is actually open: a closed map costs nothing.
local ticker

local function AnyMapShown()
    for canvas in pairs(providers) do
        if canvas:IsShown() then return true end
    end
    return false
end

local function StartTicker()
    if ticker or not AnyMapShown() then return end
    ticker = C_Timer.NewTicker(REFRESH, function()
        if not AnyMapShown() then
            ticker:Cancel()
            ticker = nil
            return
        end
        CF.RefreshMapPins()
    end)
end
local function AddTo(canvas)
    if not (canvas and canvas.AddDataProvider) or providers[canvas] then return end
    local provider = NewProvider()
    providers[canvas] = provider
    canvas:AddDataProvider(provider)
    -- HookScript, never SetScript: the map has its own OnShow/OnHide.
    canvas:HookScript("OnShow", function() StartTicker() end)
end

function CF.StartMapPins()
    if not (MapCanvasPinMixin and MapCanvasDataProviderMixin) then return end
    AddTo(WorldMapFrame)
    AddTo(BattlefieldMapFrame)
    if not BattlefieldMapFrame then
        -- The zone map is load-on-demand.
        LIB.On("ADDON_LOADED", function(name)
            if name == "Blizzard_BattlefieldMap" then AddTo(BattlefieldMapFrame) end
        end)
    end
    -- A busy guild sends several positions a second. Coalesce them: one redraw shortly after the
    -- last one, and the 2s ticker keeps the map fresh if they never stop coming.
    LIB.Listen("CAMPFIRE_PEERS", function()
        LIB.Debounce("CampfirePins", 0.4, function()
            CF.RefreshMapPins()
            StartTicker()
        end)
    end)
    StartTicker()
end
