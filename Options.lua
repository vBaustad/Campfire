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
    { "Camps",
      "Separately from all of that, Campfire watches for wilderness camps and shows a small campfire "
      .. "icon when one is near or when you're carrying its benefit. The game tells addons that a camp "
      .. "is within about 100 yards, but never where it is, so there's no arrow and no distance." },
}

local PAGE_WIDTH = 572   -- the YippYapp window's inner width
local PAGE_HEIGHT = 620  -- the lib scrolls the page when this is taller than the window's room;
                         -- Refresh grows it again to fit the help text once that is laid out

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

    --- A small "(i)" after a label. The explanation lives in its tooltip rather than as a paragraph
    --- under every switch, which is what made this page a wall of text you had to read past to find
    --- the thing you came to change.
    --- Text and not a texture on purpose: a texture path that no longer exists draws as a green
    --- square, and this is the first page in the family to do this, so there is no house icon to
    --- borrow yet. If the others want the same, this belongs in LibForever rather than copied.
    local function Info(after, text)
        local b = CreateFrame("Button", nil, f)
        b:SetSize(18, 16)
        b:SetPoint("LEFT", after, "RIGHT", 5, 0)
        local fs = b:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
        fs:SetPoint("CENTER")
        fs:SetText("(i)")
        local function Colour(hot) fs:SetTextColor(hot and 1 or 0.5, hot and 1 or 0.7, hot and 1 or 0.95) end
        Colour(false)
        b:SetScript("OnEnter", function(self)
            Colour(true)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(text, 1, 1, 1, true)   -- true: wrap, so these can be whole sentences
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() Colour(false) GameTooltip:Hide() end)
        return b
    end

    --- One row per setting: box, label, and the "(i)" that holds what used to be the paragraph.
    --- `anchor` is the row above, so the rows chain and no caller counts pixels.
    local function Check(anchor, text, onClick, info, gap)
        local cb = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
        cb:SetSize(26, 26)
        cb:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", anchor.isHeading and -4 or 0, gap or -4)
        local l = f:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        l:SetPoint("LEFT", cb, "RIGHT", 4, 0)
        l:SetText(text)
        if info then Info(l, info) end
        cb:SetScript("OnClick", function(self) onClick(self:GetChecked() and true or false) end)
        return cb
    end

    local function Section(above, title)
        local h = Heading(f, title)
        h:SetPoint("TOPLEFT", above, "BOTTOMLEFT", above.isHeading and 0 or 4, -16)
        h.isHeading = true
        return h
    end
    h1.isHeading = true

    local hide = Check(h1, "Hide my position", CF.SetHidden,
        "Off by default. While Campfire is on, your guildies and other Campfire players on your "
        .. "faction can see where you are. Tick this to share nothing: they stop seeing you at once, "
        .. "and you still see guildies who share. It's also in the Campfire window.")
    local open = Check(hide, "Also share with other Campfire players on my faction", CF.SetOpenShare,
        "Other Campfire players on your faction can see where you are, and you see them - they show "
        .. "up grey in the list. Untick to share with your guild only.")

    -- Who is listed.
    local hList = Section(open, "List")
    local allZones = Check(hList, "Show all zones", CF.SetShowAllZones,
        "Off by default: only players in your zone are listed, and the rest are counted. It's also "
        .. "in the Campfire window.")
    local mapPins = Check(allZones, "Show Campfire players on the map", CF.SetMapPins,
        "A small dot on the world map and the zone map for everyone Campfire can see, in their class "
        .. "colour. Off by default when GuildMap is installed, since that is what GuildMap does.")
    local mapGuild = Check(mapPins, "Only show guildies on the map", CF.SetMapGuildOnly,
        "On by default. Your guild is small enough to show everywhere, so this also turns the zone "
        .. "limit below off: you see your guild across the zone map and the continent. Leave Campfire "
        .. "players outside your guild in, and the zone limit comes back on to keep the map readable.")
    local mapZone = Check(mapGuild, "Map dots only in my zone", CF.SetMapZoneOnly,
        "Dots are drawn on a zone map only, so the continent map stays clean. At most 40 dots are "
        .. "drawn at once, nearest first - a safety net that guild-only rarely reaches.")

    -- The camp HUD, which has nothing to do with other players: it reads your own auras.
    local hCamp = Section(mapZone, "Camps")
    local camp = Check(hCamp, "Show a campfire icon when a camp is near", CF.SetCampIcon,
        "On by default. The fire keeps its colour down to the time left on the camp's benefit, so it "
        .. "burns out from the tips as the hour goes. The game doesn't tell addons where a camp is, "
        .. "only that one is near, so there's no arrow and no distance.")
    local campList = Check(camp, "List what the camp gives you, with the time left", CF.SetCampList,
        "Under the icon: what the camp is giving you, read from the buff itself - \"Strength +6\". "
        .. "Untick for the fire and the timer on their own. Buffs can't be read in combat, so during "
        .. "a fight the whole thing dims to say it's showing what it last saw.")
    local campAlways = Check(campList, "Keep the campfire icon on screen away from camps", CF.SetCampAlways,
        "On by default. With nothing going on it's a grey fire with \"No camp benefit\" under it. "
        .. "Untick and the icon turns up only when a camp is near or its buff is running.")
    local campLock = Check(campAlways, "Lock the campfire icon in place", CF.SetCampLocked,
        "On by default. Untick and the icon appears wherever you are, as a preview with a blue edge, "
        .. "so you can drag it where you want it. /campfire camp unlock does the same.")

    -- Grouping is fixed on now, so the only choice left is whether Campfire is in that row at all.
    local hMini = Section(campLock, "Minimap")
    local mini = Check(hMini, "Show Campfire in the YippYapp minimap button", function(on)
        if LIB.SetMinimapButtonShown then LIB.SetMinimapButtonShown("Campfire", on) end
    end, "On by default. YippYapp addons share one minimap button; this is whether Campfire is one "
        .. "of the icons behind it. Left-click opens Campfire, right-click these settings.")

    -- Where to find the window.
    local h2 = Section(mini, "Commands")
    local cmds = Note(f, "|cffffd100/campfire|r opens the window: players with Campfire, nearest first. Click a name to whisper them.\n"
        .. "|cffffd100/campfire hide|r hides your position or shares it again.  |cffffd100/campfire list|r prints the same list in chat.\n"
        .. "|cffffd100/campfire camp|r turns the campfire icon on or off.")
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
        camp:SetChecked(CF.db.camp)
        campList:SetChecked(CF.db.campList)
        campAlways:SetChecked(CF.db.campAlways)
        campLock:SetChecked(CF.db.campLocked)
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
