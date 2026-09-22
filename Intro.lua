-- Campfire - its page in LibForever's shared YippYapp welcome window (/yippyapp).
-- No setup is needed, so the page never opens by itself; it's reached from /yippyapp or the settings page.
local ADDON, CF = ...
local LIB = LibStub("LibForever-1.0")

local function Build(page)
    local width = page:GetWidth()
    local y = 0
    local function section(title, text)
        local h = page:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        h:SetPoint("TOPLEFT", 0, y)
        h:SetText(title)
        local body = page:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        body:SetPoint("TOPLEFT", h, "BOTTOMLEFT", 0, -4)
        body:SetWidth(width)
        body:SetJustifyH("LEFT")
        body:SetSpacing(2)
        body:SetText(text)
        y = y - 18 - body:GetStringHeight() - 14
        return body
    end

    section("What it does",
        "Campfire shows which players are in your zone and where: your guildies and other Campfire players on "
        .. "your faction. You see the spot they're at (\"Goldshire\"), their level and class, and which way and "
        .. "how far. Handy for meeting up or grouping for a quest.")
    section("How it works",
        "Everyone who runs Campfire shares their own position with the guild, over the guild addon channel. "
        .. "Only players who also run Campfire can see it, and you still see theirs if you turn yours off.\n"
        .. "|cffffd100Your position is shared while Campfire is on - tick 'Hide my position' to stop.|r\n"
        .. "Other Campfire players on your faction see you too; untick that in the settings to share with your "
        .. "guild only.")

    local hide = CreateFrame("CheckButton", nil, page, "UICheckButtonTemplate")
    hide:SetSize(24, 24)
    hide:SetPoint("TOPLEFT", -4, y + 8)
    local label = page:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    label:SetPoint("LEFT", hide, "RIGHT", 2, 0)
    label:SetText("Hide my position")
    hide:SetScript("OnClick", function(self) CF.SetHidden(self:GetChecked() and true or false) end)
    page.hide = hide
    y = y - 30

    section("Where to find it",
        "Click the Campfire icon on the minimap - behind the YippYapp button if you use several YippYapp "
        .. "addons - or type |cffffd100/campfire|r. Click a player in the list to whisper them. Right-click "
        .. "the icon for settings.")

    local open = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
    open:SetSize(130, 22)
    open:SetPoint("TOPLEFT", 0, y + 2)
    open:SetText("Open Campfire")
    open:SetScript("OnClick", function() CF.OpenPanel() end)
end

function CF.RegisterIntro()
    if not LIB.RegisterWelcome then return end
    LIB.RegisterWelcome({
        id = "Campfire", title = "Campfire", version = 1, order = 30,
        icon = "Interface\\AddOns\\Campfire\\Media\\icon",
        subtitle = "See who's nearby, and meet up.",
        build = Build,
        onShow = function(page) if page.hide then page.hide:SetChecked(CF.db.hidden) end end,
    }, CF.db)
end
