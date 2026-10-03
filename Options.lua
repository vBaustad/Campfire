-- Campfire - settings page in Blizzard's Options -> AddOns -> YippYapp -> Campfire.
local ADDON, CF = ...
local LIB = LibStub("LibForever-1.0")

local category

-- Gold section heading with the Options panel's divider after it.
local function Heading(parent, text)
    local fs = parent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    fs:SetText(text)
    local line = parent:CreateTexture(nil, "ARTWORK")
    line:SetAtlas("Options_HorizontalDivider")
    line:SetHeight(1)
    line:SetPoint("LEFT", fs, "RIGHT", 8, 0)
    line:SetPoint("RIGHT", parent, "RIGHT", -8, 0)
    return fs
end

local function Note(parent, text)
    local fs = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    fs:SetWidth(560)
    fs:SetJustifyH("LEFT")
    fs:SetSpacing(2)
    fs:SetText(text)
    return fs
end

-- What used to be Campfire's page in the YippYapp welcome window. The window is gone; the text is
-- the same text, at the bottom of this page, where the settings it describes are. The checkbox and
-- the "Open Campfire" button that sat among these sections did not come with it: both already exist
-- above, and a second copy is a second thing to keep in step.
local HELP = {
    { "What it does",
      "Campfire shows which players are in your zone and where: your guildies and other Campfire "
      .. "players on your faction. You see the spot they're at (\"Goldshire\"), their level and class, "
      .. "and which way and how far. Handy for meeting up or grouping for a quest." },
    { "How it works",
      "Everyone who runs Campfire shares their own position with the guild, over the guild addon "
      .. "channel. Only players who also run Campfire can see it, and you still see theirs if you turn "
      .. "yours off. Your position is shared while Campfire is on - tick \"Hide my position\" above to "
      .. "stop. Other Campfire players on your faction see you too; untick that above to share with "
      .. "your guild only." },
    { "Where to find it",
      "Click the Campfire icon on the minimap - behind the YippYapp button, with the other YippYapp "
      .. "addons - or type /campfire. Click a player in the list to whisper them. Right-click the icon "
      .. "for these settings." },
}

local PAGE_WIDTH = 572   -- the YippYapp window's inner width
local PAGE_HEIGHT = 560  -- the lib scrolls the page when this is taller than the window's room

function CF.RegisterOptions()
    if category then return end
    -- The panel is ours; LibForever hosts it in the YippYapp window and gives it the window's width.
    local panel = CreateFrame("Frame")
    panel:SetSize(PAGE_WIDTH, PAGE_HEIGHT)
    local f = CreateFrame("Frame", nil, panel)
    f:SetPoint("TOPLEFT", 10, -10)
    f:SetPoint("BOTTOMRIGHT", -10, 10)

    -- Title, version and what Campfire does.
    local head = f:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    head:SetPoint("TOPLEFT", 8, -6)
    head:SetText("Campfire")
    local version = f:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    version:SetPoint("BOTTOMLEFT", head, "BOTTOMRIGHT", 8, 1)
    version:SetText("v" .. CF.version)
    local sub = Note(f, "Find other players out in the world: see which guildies and Campfire players on your faction "
        .. "are nearby, where they are and how far away.")
    sub:SetPoint("TOPLEFT", head, "BOTTOMLEFT", 0, -8)

    -- Sharing: the one real setting, so it comes first.
    local h1 = Heading(f, "Sharing")
    h1:SetPoint("TOPLEFT", sub, "BOTTOMLEFT", 0, -20)
    local function Check(anchor, x, y, text, onClick)
        local cb = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
        cb:SetSize(26, 26)
        cb:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", x, y)
        local l = f:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        l:SetPoint("LEFT", cb, "RIGHT", 4, 0)
        l:SetText(text)
        cb:SetScript("OnClick", function(self) onClick(self:GetChecked() and true or false) end)
        return cb
    end

    local hide = Check(h1, -4, -6, "Hide my position", CF.SetHidden)
    local hideNote = Note(f, "Off by default. While Campfire is on, your guildies and other Campfire players on your "
        .. "faction (below) can see where you are. Tick this to share nothing; they stop seeing you at once, and you "
        .. "still see guildies who share. It's also in the Campfire window.")
    hideNote:SetPoint("TOPLEFT", hide, "BOTTOMLEFT", 30, -2)

    local open = Check(hideNote, -30, -12, "Also share with other Campfire players on my faction", CF.SetOpenShare)
    local openNote = Note(f, "Other Campfire players on your faction can see where you are. Only your guild when unticked. "
        .. "Players outside your guild show up grey.")
    openNote:SetPoint("TOPLEFT", open, "BOTTOMLEFT", 30, -2)

    -- Who is listed.
    local hList = Heading(f, "List")
    hList:SetPoint("TOPLEFT", openNote, "BOTTOMLEFT", -26, -20)
    local allZones = Check(hList, -4, -6, "Show all zones", CF.SetShowAllZones)
    local zoneNote = Note(f, "Off by default: only players in your zone are listed, and the rest are counted. "
        .. "It's also in the Campfire window.")
    zoneNote:SetPoint("TOPLEFT", allZones, "BOTTOMLEFT", 30, -2)

    local mapPins = Check(zoneNote, -30, -12, "Show Campfire players on the map", CF.SetMapPins)
    local mapNote = Note(f, "A small dot on the world map and the zone map for everyone Campfire can see, in "
        .. "their class colour. Off by default when GuildMap is installed, since that is what GuildMap does.")
    mapNote:SetPoint("TOPLEFT", mapPins, "BOTTOMLEFT", 30, -2)

    local mapGuild = Check(mapNote, -30, -12, "Only show guildies on the map", CF.SetMapGuildOnly)
    local mapGuildNote = Note(f, "On by default. Your guild is small enough to show everywhere, so this also "
        .. "turns the zone limit below off: you see your guild across the zone map and the continent. Leave "
        .. "Campfire players outside your guild in, and the zone limit comes back on to keep the map readable.")
    mapGuildNote:SetPoint("TOPLEFT", mapGuild, "BOTTOMLEFT", 30, -2)

    local mapZone = Check(mapGuildNote, -30, -12, "Map dots only in my zone", CF.SetMapZoneOnly)
    local mapZoneNote = Note(f, "Dots are drawn on a zone map only, so the continent map stays clean. At most "
        .. "40 dots are drawn at once, nearest first - a safety net that guild-only rarely reaches.")
    mapZoneNote:SetPoint("TOPLEFT", mapZone, "BOTTOMLEFT", 30, -2)


    -- Grouping is fixed on now, so the only choice left is whether Campfire is in that row at all.
    local hMini = Heading(f, "Minimap")
    hMini:SetPoint("TOPLEFT", mapZoneNote, "BOTTOMLEFT", -26, -20)
    local mini = Check(hMini, -4, -6, "Show Campfire in the YippYapp minimap button", function(on)
        if LIB.SetMinimapButtonShown then LIB.SetMinimapButtonShown("Campfire", on) end
    end)
    local miniNote = Note(f, "On by default. YippYapp addons share one minimap button; this is whether "
        .. "Campfire is one of the icons behind it. Left-click opens Campfire, right-click these settings.")
    miniNote:SetPoint("TOPLEFT", mini, "BOTTOMLEFT", 30, -2)

    -- Where to find the window.
    local h2 = Heading(f, "Commands")
    h2:SetPoint("TOPLEFT", miniNote, "BOTTOMLEFT", -26, -20)
    local cmds = Note(f, "|cffffd100/campfire|r opens the window: players with Campfire, nearest first. Click a name to whisper them.\n"
        .. "|cffffd100/campfire hide|r hides your position or shares it again.  |cffffd100/campfire list|r prints the same list in chat.")
    cmds:SetPoint("TOPLEFT", h2, "BOTTOMLEFT", 0, -8)

    -- The footer is re-anchored under the help text in Refresh, once there is a help text to be
    -- under. This point is only so it has one before the first real layout.
    local footer = f:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    footer:SetPoint("TOPLEFT", cmds, "BOTTOMLEFT", 0, -20)
    footer:SetJustifyH("LEFT")
    footer:SetText("Part of YippYapp - addons for WoW: Forever that work even better together.")

    -- Refresh whenever the page is shown: the lib runs the panel's OnShow, and the old Blizzard path
    -- needed OnRefresh plus the content frame's own OnShow.
    local function Refresh()
        hide:SetChecked(CF.db.hidden)
        open:SetChecked(CF.db.openShare)
        allZones:SetChecked(not CF.db.zoneOnly)
        mapPins:SetChecked(CF.db.mapPins)
        mapGuild:SetChecked(CF.db.mapGuildOnly)
        mapZone:SetChecked(CF.db.mapZoneOnly)
        -- nil reads as shown: a button nobody has hidden is on.
        if LIB.IsMinimapButtonShown then
            mini:SetChecked(LIB.IsMinimapButtonShown("Campfire") ~= false)
        end

        -- The help text used to be Campfire's page in the welcome window. It lives at the bottom of
        -- this page now. There is no running y to put it at - the page is built from relative
        -- anchors - so it is measured from the last thing on the page, which only works once the
        -- page has been laid out. GetTop() is nil at build time, so the first real call is this one,
        -- from OnShow; calling AddHelp again replaces rather than stacks, which is what makes that
        -- safe to run on every show.
        --
        -- Measured from `cmds`, which never moves, and NOT from the footer: the footer is placed
        -- BELOW the help from the value this returns, so measuring the help from the footer made
        -- each show push both of them further down the page. That is the hole in the middle.
        if LIB.AddHelp and panel:GetTop() and cmds:GetBottom() then
            local y = -(panel:GetTop() - cmds:GetBottom()) - 24
            local bottom = LIB.AddHelp(panel, HELP, y)
            footer:ClearAllPoints()
            footer:SetPoint("TOPLEFT", panel, "TOPLEFT", 18, bottom - 20)
            -- The page scrolls, so it has to be tall enough to scroll TO the help.
            panel:SetHeight(math.max(PAGE_HEIGHT, -bottom + 60))
        end
    end
    -- The lib runs the panel's OnShow every time the page is shown; the rest is belt and braces
    -- for the old Blizzard-hosted path.
    panel:SetScript("OnShow", Refresh)
    panel.OnRefresh = Refresh
    f:HookScript("OnShow", Refresh)
    Refresh()
    if LIB.RegisterOptionsPage then
        -- Hosted in the YippYapp window; height lets the lib scroll the page.
        category = LIB.RegisterOptionsPage("Campfire", panel, "Campfire", PAGE_HEIGHT)
    elseif Settings and Settings.RegisterCanvasLayoutCategory then
        category = Settings.RegisterCanvasLayoutCategory(panel, "Campfire")
        Settings.RegisterAddOnCategory(category)
    end
end

--- Returns true when the settings opened; says why in chat when they can't.
function CF.OpenOptions()
    -- Our own window: no Blizzard category, so this works in combat too.
    if LIB.OpenAddonSettings then
        LIB.OpenAddonSettings("Campfire")
        return true
    end
    if not (category and category.GetID and category:GetID()) then
        print(CF.TAG .. ": the settings page isn't available.")
        return false
    end
    -- Blizzard's Options panel is protected in combat.
    if InCombatLockdown() then print(CF.TAG .. ": settings can't open in combat.") return false end
    Settings.OpenToCategory(category:GetID())
    return true
end
