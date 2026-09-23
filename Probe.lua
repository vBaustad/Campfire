-- Campfire - research probe for camps (/campfire debug camp). Not in the help text.
-- The client tells us a camp is within 100 yards (aura 1283391 "Campfire Nearby") but never where.
-- This dumps what the client does expose near a camp, and records what happens when one is placed,
-- into CampfireDB.probe so it can be read after logging out.
local ADDON, CF = ...
local LIB = LibStub("LibForever-1.0")

local NEARBY_AURA = 1283391     -- "Campfire Nearby"
local MAX_ENTRIES = 300

-- Camp-building spells from the datamine. Casts are also caught by name or by the auras they give,
-- in case the real IDs differ from these.
local CAMP_SPELLS = {
    [1307227] = "Basic Campfire", [1307252] = "Journeyman Campfire", [1307237] = "Expert Campfire",
    [1307229] = "Camp Chair", [1307230] = "Camp Tent",
    [1229737] = "Basic Campfire (old)", [1229432] = "Camp Tent (old)", [1229517] = "Camp Chair (old)",
    [465447] = "Create Campsite", [465626] = "Create Campsite Accessories",
}

--- Secret values must never be printed or saved; show what we can and mark the rest.
local function Safe(v)
    if issecretvalue and issecretvalue(v) then return "<secret>" end
    if type(v) == "table" then return "<table>" end
    return v
end

local function Log(entry)
    if not CF.db then return end
    CF.db.probe = CF.db.probe or {}
    entry.t = date("%Y-%m-%d %H:%M:%S")
    local map, x, y = LIB.MyPosition()
    entry.map, entry.x, entry.y = map, x and ("%.4f"):format(x), y and ("%.4f"):format(y)
    entry.sub = CF.MySubZone()
    table.insert(CF.db.probe, entry)
    while #CF.db.probe > MAX_ENTRIES do table.remove(CF.db.probe, 1) end
end

-- ---------------------------------------------------------------------------
-- What the player has on right now
-- ---------------------------------------------------------------------------
--- Reading a secret aura is an error, not a secret value, so we ask first. In combat every aura is
--- secret (measured), so we don't touch them at all then.
local function AurasBlocked()
    if InCombatLockdown() or UnitAffectingCombat("player") then return true end
    if C_Secrets and C_Secrets.ShouldAurasBeSecret and C_Secrets.ShouldAurasBeSecret() then return true end
    return false
end
CF.ProbeAurasBlocked = AurasBlocked

local function IndexSecret(i)
    return C_Secrets and C_Secrets.ShouldUnitAuraIndexBeSecret
        and C_Secrets.ShouldUnitAuraIndexBeSecret("player", i, "HELPFUL") or false
end

local function ReadAura(i)
    if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
        local data = C_UnitAuras.GetAuraDataByIndex("player", i, "HELPFUL")
        if not data then return nil end
        return data.spellId, data.name, data.duration, data.sourceUnit
    end
    local name, _, _, _, duration, _, source, _, _, spellId = UnitAura("player", i, "HELPFUL")
    if not name then return nil end
    return spellId, name, duration, source
end

--- Returns false when auras can't be read at all; a secret index is skipped, never counted as missing.
local function EachAura(fn)
    if AurasBlocked() then return false end
    for i = 1, 60 do
        if not IndexSecret(i) then
            local ok, spellId, name, duration, source = pcall(ReadAura, i)
            if not ok then return false end
            if spellId == nil and name == nil then break end
            fn(spellId, name, duration, source)
        end
    end
    return true
end

--- The set of auras we can see, or nil when they're secret right now.
local function AuraSnapshot()
    local set = {}
    local ok = EachAura(function(spellId, name) if spellId then set[spellId] = name or "?" end end)
    return ok and set or nil
end

local function DumpAuras(print_)
    local found = {}
    local ok = EachAura(function(spellId, name, duration, source)
        local mark = ""
        if spellId == NEARBY_AURA then mark = "  <-- Campfire Nearby"
        elseif type(name) == "string" and name:lower():find("camp") then mark = "  <-- camp?" end
        if mark ~= "" or print_ == "all" then
            found[#found + 1] = ("    %s (%s) duration %s from %s%s"):format(tostring(Safe(name)),
                tostring(Safe(spellId)), tostring(Safe(duration)), tostring(Safe(source)), mark)
        end
    end)
    if not ok then return { "    auras are secret right now (in combat?) - nothing read" } end
    return found
end

-- ---------------------------------------------------------------------------
-- Vignettes and area POIs: do camps show up at all?
-- ---------------------------------------------------------------------------
local function DumpVignettes()
    local out = {}
    if not (C_VignetteInfo and C_VignetteInfo.GetVignettes) then return { "    C_VignetteInfo missing" } end
    local ok, guids = pcall(C_VignetteInfo.GetVignettes)
    if not ok or not guids then return { "    GetVignettes failed" } end
    for _, guid in ipairs(guids) do
        local info = C_VignetteInfo.GetVignetteInfo and C_VignetteInfo.GetVignetteInfo(guid)
        local pos = C_VignetteInfo.GetVignettePosition and LIB.MapId()
            and C_VignetteInfo.GetVignettePosition(guid, LIB.MapId())
        local x, y = pos and pos.GetXY and pos:GetXY()
        out[#out + 1] = ("    %s (%s) at %s, %s"):format(tostring(Safe(info and info.name)),
            tostring(Safe(info and info.vignetteID)), x and ("%.3f"):format(x) or "-",
            y and ("%.3f"):format(y) or "-")
    end
    if #out == 0 then out[1] = "    none" end
    return out
end

local function DumpAreaPOIs()
    local out = {}
    local mapID = LIB.MapId()
    if not (mapID and C_AreaPoiInfo and C_AreaPoiInfo.GetAreaPOIForMap) then return { "    C_AreaPoiInfo missing" } end
    local ok, ids = pcall(C_AreaPoiInfo.GetAreaPOIForMap, mapID)
    if not ok or not ids then return { "    GetAreaPOIForMap failed" } end
    for _, id in ipairs(ids) do
        local info = C_AreaPoiInfo.GetAreaPOIInfo and C_AreaPoiInfo.GetAreaPOIInfo(mapID, id)
        local x, y = info and info.position and info.position.GetXY and info.position:GetXY()
        out[#out + 1] = ("    %s (%s) at %s, %s"):format(tostring(Safe(info and info.name)), tostring(Safe(id)),
            x and ("%.3f"):format(x) or "-", y and ("%.3f"):format(y) or "-")
    end
    if #out == 0 then out[1] = "    none" end
    return out
end

-- ---------------------------------------------------------------------------
-- Watching a camp being placed
-- ---------------------------------------------------------------------------
local function SpellName(spellID)
    local info = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(spellID)
    return (info and info.name) or CAMP_SPELLS[spellID] or "?"
end

--- Camp-ish means: a known camp spell, a name with "camp" or "fire" in it, or a spell that gave us
--- an aura with "camp" in the name. Everything else is ordinary play and isn't logged.
local function CampIsh(spellID, name, gained)
    if CAMP_SPELLS[spellID] then return true end
    if type(name) == "string" and (name:lower():find("camp") or name:lower():find("fire")) then return true end
    for _, text in ipairs(gained) do
        if text:lower():find("camp") then return true end
    end
    return false
end

-- "Watch" mode logs every single cast for a while, for when the camp spell isn't one we guessed.
local watchUntil = 0

local function AfterCast(spellID, before, watching)
    local after = AuraSnapshot()
    local gained = {}
    if before and after then
        for id, name in pairs(after) do
            if not before[id] then gained[#gained + 1] = id .. " " .. tostring(name) end
        end
    else
        gained[1] = "<auras secret, not read>"
    end
    local name = SpellName(spellID)
    if not (watching or CampIsh(spellID, name, gained)) then return end
    Log({ what = watching and "cast-watch" or "cast", spell = spellID, spellName = name,
        gained = table.concat(gained, ", ") })
    print(CF.TAG .. (" probe: cast %s (%s), auras gained: %s"):format(tostring(spellID), tostring(Safe(name)),
        #gained > 0 and table.concat(gained, ", ") or "none"))
end

LIB.On("UNIT_SPELLCAST_SUCCEEDED", function(unit, _, spellID)
    if unit ~= "player" or not CF.db then return end
    local before = AuraSnapshot()
    local watching = GetTime() < watchUntil
    -- Two seconds later we compare auras, and (outside watch mode) only keep camp-related casts.
    C_Timer.After(2, function() AfterCast(spellID, before, watching) end)
end)

--- Log every cast for the next few minutes: place the camp while this is running.
function CF.ProbeWatch(seconds)
    seconds = seconds or 180
    watchUntil = GetTime() + seconds
    Log({ what = "watch-started", gained = seconds .. "s" })
    print(CF.TAG .. (" probe: logging every spell you cast for %d seconds. Place the camp now."):format(seconds))
end

-- The "Campfire Nearby" aura coming and going is worth a line of its own.
local hadNearby = false
LIB.On("UNIT_AURA", function(unit)
    if unit ~= "player" or not CF.db then return end
    local has = false
    -- Secret (in combat): leave hadNearby as it was rather than guessing it is gone.
    if not EachAura(function(spellId) if spellId == NEARBY_AURA then has = true end end) then return end
    if has ~= hadNearby then
        hadNearby = has
        Log({ what = has and "nearby-aura-gained" or "nearby-aura-lost" })
    end
end)

-- ---------------------------------------------------------------------------
-- /campfire debug camp
-- ---------------------------------------------------------------------------
function CF.ProbeCamp(all)
    local map, x, y = LIB.MyPosition()
    print(CF.TAG .. " camp probe:")
    print(("  position: map %s (%s) %s, %s, sub-zone %s"):format(tostring(map), LIB.MapName(map),
        x and ("%.4f"):format(x) or "-", y and ("%.4f"):format(y) or "-", tostring(CF.MySubZone())))
    print(all and "  all helpful auras:" or "  camp-ish auras:")
    local auras = DumpAuras(all and "all" or nil)
    if #auras == 0 then print("    none") else for _, line in ipairs(auras) do print(line) end end
    print("  vignettes:")
    for _, line in ipairs(DumpVignettes()) do print(line) end
    print("  area POIs on this map:")
    for _, line in ipairs(DumpAreaPOIs()) do print(line) end
    print(("  recorded entries: %d (CampfireDB.probe)"):format(CF.db.probe and #CF.db.probe or 0))
    Log({ what = "probe", auras = table.concat(auras, " | ") })
end
