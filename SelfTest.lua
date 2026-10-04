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
    "CampState", "RefreshCamp", "StartCamp", "SetCampIcon", "SetCampList", "SetCampLocked",
    "SetCampAlways", "CampLines", "CampStats", "StatColor", "CampFraction", "CampTooltipLines",
}

local SETTINGS = { "hidden", "zoneOnly", "openShare", "mapPins", "mapGuildOnly", "mapZoneOnly",
    "camp", "campList", "campLocked", "campAlways" }

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

    -- The camp HUD reads our own auras, which is a different kind of risk from everything above:
    -- in combat they are all secret, and the whole point is that "could not look" is not the same
    -- answer as "you have not got it". So the state must survive a read that cannot happen.
    CF.RefreshCamp()
    local camp, campStale = CF.CampState()
    if type(camp) ~= "table" or type(camp.buffs) ~= "table" then
        return false, "CampState() returned nothing usable"
    end
    if camp.nearby == nil or camp.benefits == nil or camp.carrying == nil then
        return false, "CampState() left nearby/benefits/carrying nil, which the HUD reads as false"
    end
    -- An hour-long camp buff must keep the HUD up after you have walked away from the fire; only
    -- 1283391 means "in range", and every other camp aura is one you carry off with you.
    if camp.carrying and #camp.buffs == 0 then
        return false, "CampState() says we are carrying camp buffs but lists none"
    end
    if type(campStale) ~= "boolean" then
        return false, "CampState() does not say whether its answer is current"
    end
    -- Out of combat the reading must actually have worked; in combat it must say so instead.
    if not campStale and InCombatLockdown() then
        return false, "the camp state calls itself current while auras are secret"
    end
    for _, b in ipairs(camp.buffs) do
        if not b.id then return false, "a camp buff came back without a spell id" end
        checked = checked + 1
    end

    -- One line, and only when there is something to do about it. Each of these was a state the
    -- HUD used to talk through: standing at a fire, settled at one, and carrying the buff away.
    local function Line(t) return CF.CampLines(t) or "-" end
    if Line({ nearby = true, benefits = false, settled = false }) ~= "Campfire nearby" then
        return false, "CampLines() doesn't say a camp is near when one is"
    end
    if Line({ nearby = true, benefits = false, settled = true }) == "Campfire nearby" then
        return false, "CampLines() says the same thing settled at a fire as walking past one"
    end
    if Line({ nearby = true, benefits = true, settled = true }) ~= "-" then
        return false, "CampLines() still talks once you have the benefit, where the timer says it"
    end
    -- The resting state still says something - a grey fire with nothing under it reads as broken -
    -- but what it says is about YOUR buff, never about the world. Claiming no camp is near would be
    -- a guess: one aura means "in range", and not having it is not proof.
    local resting = Line({ nearby = false, benefits = false, settled = false })
    if resting == "-" then
        return false, "CampLines() leaves the resting state with no line at all"
    end
    if resting:lower():find("nearby") then
        return false, "CampLines() claims something about camps nearby when it cannot know"
    end
    checked = checked + 5

    -- The stats exist nowhere but the buff's own tooltip. This is the real line off a camp, and it
    -- has to come out as a stat and a number rather than as a sentence.
    local parsed = CF.CampStats("Sharpening Wheel: Strength increased by 6.")
    if #parsed ~= 1 or parsed[1].label ~= "Strength" or parsed[1].value ~= "+6" then
        return false, "CampStats() no longer reads 'Sharpening Wheel: Strength increased by 6.'"
    end
    -- Only the stat reaches the screen, whatever sentence the game wrapped it in - the row is one
    -- line on a HUD, and the full text is still in the buff's own tooltip.
    local shapes = {
        { "Camp: Increases your Stamina by 12.", "Stamina", "+12" },
        { "Camp: +9 Agility", "Agility", "+9" },
        { "Camp: Attack Power increased by 20.", "Attack Power", "+20" },
        { "Camp: Critical Strike increased by 3.", "Crit", "+3" },
        { "Camp: Haste Rating increased by 5.", "Haste", "+5" },
    }
    for _, case in ipairs(shapes) do
        local got = CF.CampStats(case[1])
        if #got ~= 1 or got[1].label ~= case[2] or got[1].value ~= case[3] then
            return false, ("CampStats(%q) gives %s %s, not %s %s"):format(case[1],
                tostring(got[1] and got[1].label), tostring(got[1] and got[1].value), case[2], case[3])
        end
        checked = checked + 1
    end
    -- The camp's description arrives as ONE tooltip line: a header, a blank line, then the
    -- benefit. Flattening that merged the header onto the stat and put the station in front of it,
    -- which is how "Sharpening Wheel: Stre..." reached the screen instead of "Strength".
    local merged = CF.CampStats("Gained the following camp benefits:\n\nSharpening Wheel: Strength increased by 6.")
    if #merged ~= 1 or merged[1].label ~= "Strength" or merged[1].value ~= "+6" then
        return false, "CampStats() keeps the station name when the header shares the benefit's line"
    end
    checked = checked + 1

    -- Every station, in Camp Benefits' own text from the game data. The tent read as "You" and the
    -- fish bowl's "5%" as "All" before; the lute is three stats in one sentence.
    local stations = {
        { "Tent: You received a small amount of rest experience. You can only receive this effect once per 1 hr.",
            { { "Rested XP" } } },
        { "Mana Well: Restores 40 Mana every 5 seconds.", { { "Mana", "+40/5s" } } },
        { "Enchanted Lute: Armor increased by 50, all attributes increased by 5, and all resistances increased by 10.",
            { { "Armor", "+50" }, { "All stats", "+5" }, { "Resistances", "+10" } } },
        { "Fish Bowl: All stats increased by 5%.", { { "All stats", "+5%" } } },
        { "Lodestone: Melee Attack Power increased by 12.", { { "Attack Power", "+12" } } },
        { "Camp Chair: Critical strike chance with all spells and attacks increased by 1%.", { { "Crit", "+1%" } } },
    }
    for _, case in ipairs(stations) do
        local got = CF.CampStats(case[1])
        local ok = #got == #case[2]
        for i, want in ipairs(case[2]) do
            ok = ok and got[i] and got[i].label == want[1] and got[i].value == want[2]
        end
        if not ok then
            return false, ("CampStats(%q) gives %s %s first"):format(case[1],
                tostring(got[1] and got[1].label), tostring(got[1] and got[1].value))
        end
        checked = checked + 1
    end

    -- A shape we have never seen must still put the stat's NAME on screen, not the whole sentence.
    local odd = CF.CampStats("Some Station: Dodge goes up a bit somehow")
    if #odd ~= 1 or odd[1].label ~= "Dodge" then
        return false, "CampStats() prints a sentence it can't parse instead of the stat's name"
    end
    if #CF.CampStats(nil) ~= 0 then return false, "CampStats() invents stats out of nothing" end
    -- WoW's own pluralisation markup carries a COLON - "60 |4minute:minutes; remaining" - and the
    -- rule that recognises a stat looks for a colon. That line reached the screen once, as
    -- "minutes; remaining", which is what this stops happening again.
    if #CF.CampStats("60 |4minute:minutes; remaining") ~= 0 then
        return false, "CampStats() reads WoW's plural markup as a stat"
    end
    if CF.StatColor("Strength") == CF.StatColor("Intellect") then
        return false, "StatColor() gives every stat the same colour"
    end

    -- The whole look hangs off this one number now: the fire keeps its colour up to the fraction
    -- left and goes grey above it. A sign error here would be a fire that relights itself.
    local now = GetTime()
    if CF.CampFraction({ expires = now + 1800, duration = 3600 }) > 0.6 then
        return false, "CampFraction() says a half-spent buff is more than half left"
    end
    if CF.CampFraction({ expires = now - 10, duration = 3600 }) ~= 0 then
        return false, "CampFraction() gives a finished buff something left"
    end
    if CF.CampFraction({ expires = now + 7200, duration = 3600 }) ~= 1 then
        return false, "CampFraction() goes over a full bar"
    end
    if CF.CampFraction(nil) ~= nil or CF.CampFraction({ duration = 0 }) ~= nil then
        return false, "CampFraction() invents a fraction for a buff with no timer"
    end
    checked = checked + 12

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
