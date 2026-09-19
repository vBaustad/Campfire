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

function CF.RegisterOptions()
    if category or not (Settings and Settings.RegisterCanvasLayoutCategory) then return end
    local panel = CreateFrame("Frame")
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
    local sub = Note(f, "Find your guildies out in the world: see who is nearby, how many yards away and in which direction.")
    sub:SetPoint("TOPLEFT", head, "BOTTOMLEFT", 0, -8)

    -- Sharing: the one real setting, so it comes first.
    local h1 = Heading(f, "Sharing")
    h1:SetPoint("TOPLEFT", sub, "BOTTOMLEFT", 0, -20)
    local share = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
    share:SetSize(26, 26)
    share:SetPoint("TOPLEFT", h1, "BOTTOMLEFT", -4, -6)
    local label = f:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    label:SetPoint("LEFT", share, "RIGHT", 4, 0)
    label:SetText("Share my position with my guild")
    share:SetScript("OnClick", function(self)
        CF.SetShare(self:GetChecked() and true or false)
    end)
    local shareNote = Note(f, "On by default. Only guildies who also run Campfire see it, over the guild addon channel. "
        .. "Untick to stop at once; you still see guildies who share.")
    shareNote:SetPoint("TOPLEFT", share, "BOTTOMLEFT", 30, -2)

    -- Where to find the window.
    local h2 = Heading(f, "Commands")
    h2:SetPoint("TOPLEFT", shareNote, "BOTTOMLEFT", -26, -20)
    local cmds = Note(f, "|cffffd100/campfire|r opens the window: guildies with Campfire, nearest first. Click a name to whisper them.\n"
        .. "|cffffd100/campfire share|r turns sharing on or off.  |cffffd100/campfire list|r prints the same list in chat.")
    cmds:SetPoint("TOPLEFT", h2, "BOTTOMLEFT", 0, -8)

    -- Bottom: the link to the shared YippYapp page, then the welcome page.
    local anchor, gap = cmds, -20
    if LIB.LauncherOptions then
        local links = LIB.LauncherOptions(f, "Campfire")
        links:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, gap)
        anchor, gap = links, -8
    end
    if LIB.OpenWelcome then
        local welcome = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        welcome:SetSize(170, 22)
        welcome:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, gap)
        welcome:SetText("Welcome / what's new")
        welcome:SetScript("OnClick", function()
            -- The Options panel is protected in combat; leave it open then.
            if SettingsPanel and SettingsPanel:IsShown() and not InCombatLockdown() then SettingsPanel:Close() end
            LIB.OpenWelcome("Campfire")
        end)
    end

    local footer = f:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    footer:SetPoint("BOTTOMLEFT", 8, 6)
    footer:SetPoint("RIGHT", f, "RIGHT", -8, 0)
    footer:SetJustifyH("LEFT")
    footer:SetText("Part of YippYapp - addons for WoW: Forever that work even better together.")

    panel:SetScript("OnShow", function() share:SetChecked(CF.db.share) end)
    if LIB.RegisterOptionsPage then
        -- A subcategory under YippYapp in Options -> AddOns.
        category = LIB.RegisterOptionsPage("Campfire", panel)
    else
        category = Settings.RegisterCanvasLayoutCategory(panel, "Campfire")
        Settings.RegisterAddOnCategory(category)
    end
end

--- Returns true when the settings opened; says why in chat when they can't.
function CF.OpenOptions()
    if not category then print(CF.TAG .. ": the settings page isn't available.") return false end
    -- Blizzard's Options panel is protected in combat.
    if InCombatLockdown() then print(CF.TAG .. ": settings can't open in combat.") return false end
    Settings.OpenToCategory(category:GetID())
    return true
end
