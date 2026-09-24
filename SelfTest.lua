-- Campfire - the self-test behind /yippyapp test.
-- After a cleanup round the usual bug is something deleted but still called, so this walks the paths
-- that only run on a click or a command: the list and its rows, the status lines, the empty-window
-- text, the map provider, and the debug commands (including the camp probe, which is no longer in
-- the TOC). It only reads: nothing here sends a message, joins a channel or changes a setting.
local ADDON, CF = ...
local LIB = LibStub("LibForever-1.0")

-- Every name another file reaches for. A missing one is the "deleted but still called" bug.
local NEEDED = {
    "Sharing", "CleanText", "MySubZone", "AboutMe", "ValidClass", "ValidLevel", "ValidPosition",
    "WhisperName", "SendPosition", "MakeRoom", "TooSoon", "ZoneOf", "Nearby", "RowText", "PrintList",
    "SetHidden", "SetShowAllZones", "SetMapPins", "SetMapZoneOnly", "StatusText", "ShortStatus",
    "TogglePanel", "OpenPanel", "EmptyText", "OpenOptions", "RegisterOptions", "RegisterIntro",
    "MapPinsEnabled", "RefreshMapPins", "StartMapPins", "OpenActive", "SetOpenShare",
    "OpenHiddenChanged", "OpenDebug", "Say",
}

local SETTINGS = { "hidden", "zoneOnly", "openShare", "mapPins", "mapZoneOnly" }

--- A row that isn't in CF.peers, so the row builder is exercised even with nobody around.
local function FakeEntry()
    local map = LIB.MapId() or 1426
    return {
        full = "Testdummy-" .. (LIB.Realm() or "Realm"),
        peer = { map = map, x = 0.5, y = 0.5, seen = GetTime(), sub = "Test", level = 10, class = "MAGE" },
        yards = 120, dir = "NE", sameZone = true,
    }
end

--- The checks themselves. The debug commands below are always silenced: the point is that they run
--- without error, not what they print.
local function Run()
    local checked = 0

    for _, name in ipairs(NEEDED) do
        if type(CF[name]) ~= "function" then
            return false, "CF." .. name .. " is missing (deleted but still called?)"
        end
        checked = checked + 1
    end

    if type(CF.db) ~= "table" then return false, "no saved variables" end
    for _, key in ipairs(SETTINGS) do
        if CF.db[key] == nil then return false, "setting '" .. key .. "' is missing from the saved variables" end
        checked = checked + 1
    end

    -- The list, its rows and the status lines, with however many players are around (often none).
    local list, elsewhere = CF.Nearby()
    if type(list) ~= "table" or type(elsewhere) ~= "number" then return false, "Nearby() returned nothing usable" end
    for _, e in ipairs(list) do
        local name, where, who, how = CF.RowText(e)
        if type(name) ~= "string" or type(where) ~= "string" or type(who) ~= "string" or type(how) ~= "string" then
            return false, "RowText() is incomplete for " .. tostring(e.full)
        end
        checked = checked + 1
    end
    local name, where, who, how = CF.RowText(FakeEntry())
    if not (name and where and who and how) then return false, "RowText() failed on a made-up row" end
    checked = checked + 1

    for _, text in ipairs({ CF.StatusText(), CF.ShortStatus(), CF.EmptyText(0), CF.EmptyText(3) }) do
        if type(text) ~= "string" or text == "" then return false, "a status line came out empty" end
        checked = checked + 1
    end

    -- Reading from the wire: the guards that keep a stranger's text out of the UI.
    if CF.CleanText("a|cffff0000b|r\nc") ~= "a/cffff0000b/rc" then return false, "CleanText() no longer strips pipes" end
    local here = LIB.MapId() or 1426
    if CF.ValidPosition(here, 1.5, 0.5) then return false, "ValidPosition() accepts coordinates off the map" end
    if not CF.ValidPosition(here, 0.5, 0.5) then return false, "ValidPosition() rejects a real position" end
    checked = checked + 3

    -- The map provider, against whichever maps are open (usually none, which is also a case).
    CF.RefreshMapPins()
    checked = checked + 1

    -- The commands. The camp probe is no longer in the TOC, so this is the path that must answer
    -- politely instead of calling something that isn't there.
    CF.silent = true
    local ok = pcall(function()
        for _, cmd in ipairs({ "debug camp", "debug camp all", "debug camp watch" }) do
            SlashCmdList.CAMPFIRE(cmd)
            checked = checked + 1
        end
    end)
    CF.silent = nil
    if not ok then return false, "a /campfire debug command errored (deleted but still called?)" end
    if CF.ProbeCamp or CF.ProbeWatch then
        return true, ("%d checks; the camp probe IS loaded (Probe.lua is in the TOC)"):format(checked)
    end
    return true, ("%d checks, %d listed, %d elsewhere"):format(checked, #list, elsewhere)
end

--- quiet: say nothing, just return (ok, message) - that is how /yippyapp test runs every addon.
function CF.SelfTest(quiet)
    local ok, message = Run()
    if not quiet then
        print(CF.TAG .. ": selftest " .. (ok and "|cff60d060passed|r - " or "|cffff6060failed|r - ")
            .. tostring(message))
    end
    return ok, message
end

if LIB.RegisterSelfTest then
    LIB.RegisterSelfTest("Campfire", function() return CF.SelfTest(true) end)
end
