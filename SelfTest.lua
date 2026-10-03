-- Campfire - the self-test behind /yippyapp test.
-- After a cleanup round the usual bug is something deleted but still called, so this walks the paths
-- that only run on a click or a command: the list and its rows, the status lines, the empty-window
-- text, the map provider, and the debug commands (including the camp probe, which is no longer in
-- the TOC). Nothing here sends a message, joins a channel or changes a setting. It does add a
-- player to CF.peers and take them out again, firing CAMPFIRE_PEERS both times, which is the
-- only way to prove from inside that the list notices a change.
local ADDON, CF = ...
local LIB = LibStub("LibForever-1.0")

-- Every name another file reaches for. A missing one is the "deleted but still called" bug.
local NEEDED = {
    "Sharing", "CleanText", "MySubZone", "AboutMe", "ValidClass", "ValidLevel", "ValidPosition",
    "WhisperName", "Whisper", "SendPosition", "IsSelf", "NoteSent", "MakeRoom", "TooSoon", "ZoneOf", "Nearby", "RowText", "PrintList",
    "SetHidden", "SetShowAllZones", "SetMapPins", "SetMapZoneOnly", "SetMapGuildOnly", "StatusText", "ShortStatus",
    "TogglePanel", "OpenPanel", "EmptyText", "OpenOptions", "RegisterOptions",
    "GroupMembers", "GroupKey", "LivePeers", "MapPinsEnabled", "RefreshMapPins", "StartMapPins", "OpenActive", "SetOpenShare",
    "OpenHiddenChanged", "OpenDebug", "Say",
}

local SETTINGS = { "hidden", "zoneOnly", "openShare", "mapPins", "mapGuildOnly", "mapZoneOnly" }

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

    -- The group key must come out in the same shape as the keys in CF.peers, which arrive from
    -- addon messages with the realm normalised. A raw realm with a space is the case that broke.
    local raw = CF.GroupKey("Testdummy", "Bleeding Hollow")
    if raw ~= "Testdummy-BleedingHollow" then
        return false, "GroupKey() gives " .. tostring(raw) .. ", not Testdummy-BleedingHollow"
    end
    if CF.GroupKey("Testdummy", "Zul'jin") ~= "Testdummy-Zuljin" then
        return false, "GroupKey() keeps the apostrophe in a realm name"
    end
    if CF.GroupKey("Testdummy", "") ~= LIB.FullName("Testdummy") then
        return false, "GroupKey() disagrees with FullName() on your own realm"
    end
    checked = checked + 3

    -- The group filter compares keys built from group units against keys built from addon messages.
    -- On Forever the second value from UnitName is a SURNAME, not a realm, so a hand-built key was
    -- always wrong ("Duplo-Bonk" instead of "Duplo Bonk-OurRealm") and the filter never matched.
    if not LIB.UnitKey then
        return false, "LibForever has no UnitKey: the group filter would read surnames as realms"
    end
    local mine = LIB.UnitKey("player")
    if type(mine) ~= "string" or not mine:find("-", 1, true) then
        return false, "UnitKey(\"player\") gives " .. tostring(mine) .. ", not Name-Realm"
    end
    local realmPart = mine:match("%-([^%-]+)$")
    if realmPart ~= LIB.Realm() then
        return false, "UnitKey ends in " .. tostring(realmPart) .. ", not our realm " .. tostring(LIB.Realm())
    end
    -- A full name with a space must survive as one name, not be split into name and realm.
    if CF.GroupKey("Duplo Bonk", "") ~= "Duplo Bonk-" .. LIB.Realm() then
        return false, "GroupKey() mangles a name that has a surname in it"
    end
    checked = checked + 4

    -- Our own messages must never become a peer, whatever the server calls us. This is the check
    -- that would have caught Campfire showing you yourself on the map and in the list.
    if not CF.IsSelf(LIB.Me(), "P;1;1426;0.5000;0.5000;Test;10;MAGE") then
        return false, "IsSelf() does not recognise our own name"
    end
    local echo = "P;1;1426;0.1234;0.5678;SelfTest;10;MAGE"
    CF.NoteSent(echo)
    if not CF.IsSelf("Someone Else-" .. (LIB.Realm() or "Realm"), echo) then
        return false, "IsSelf() does not recognise a payload we just sent coming back"
    end
    if CF.IsSelf("Someone Else-" .. (LIB.Realm() or "Realm"), "P;1;1426;0.9000;0.9000;Other;20;PRIEST") then
        return false, "IsSelf() mistakes another player's message for our own"
    end
    checked = checked + 3

    -- Whispering: the name must reach the chat box as a target, never inside a "/w ..." line,
    -- because every Forever name has a space in it. We check the API is there rather than open a box.
    if not (ChatFrame_SendTellWithMessage or ChatFrame_SendTell) then
        return false, "no ChatFrame_SendTell on this client: a whisper would fall back to /w and break two-word names"
    end
    checked = checked + 1

    -- Reading from the wire: the guards that keep a stranger's text out of the UI.
    if CF.CleanText("a|cffff0000b|r\nc") ~= "a/cffff0000b/rc" then return false, "CleanText() no longer strips pipes" end
    local here = LIB.MapId() or 1426
    if CF.ValidPosition(here, 1.5, 0.5) then return false, "ValidPosition() accepts coordinates off the map" end
    if not CF.ValidPosition(here, 0.5, 0.5) then return false, "ValidPosition() rejects a real position" end
    checked = checked + 3

    -- Someone we stopped hearing from must disappear everywhere, not just from the window: the map
    -- used to read CF.peers raw, which is how guildies who had logged out stayed on it.
    local ghost = "Selftest Ghost-" .. (LIB.Realm() or "Realm")
    CF.peers[ghost] = { map = here, x = 0.5, y = 0.5, seen = GetTime() - 99999, open = true }
    CF.LivePeers()
    if CF.peers[ghost] then
        CF.peers[ghost] = nil
        return false, "LivePeers() keeps a peer we stopped hearing from"
    end
    checked = checked + 1

    -- ...and a peer we HAVE just heard from must reach the list straight away. CF.Nearby() keeps
    -- its answer for a quarter second, and the line that dropped that cache when a message arrived
    -- sat above the cache's own declaration, so it wrote a global and the cache stayed put.
    local fresh = "Selftest Fresh-" .. (LIB.Realm() or "Realm")
    local list0, else0 = CF.Nearby()
    local before = #list0 + else0
    CF.peers[fresh] = { map = here, x = 0.5, y = 0.5, seen = GetTime(), open = true }
    LIB.Fire("CAMPFIRE_PEERS")
    local list1, else1 = CF.Nearby()
    CF.peers[fresh] = nil
    LIB.Fire("CAMPFIRE_PEERS")
    if #list1 + else1 ~= before + 1 then
        return false, "a peer we just heard from did not reach Nearby(): its cache was not dropped"
    end
    checked = checked + 1

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
