-- Campfire - the small "who is where" window (minimap button, /campfire).
local ADDON, CF = ...
local LIB = LibStub("LibForever-1.0")

local W, H = 340, 380
local ROW_H, ROWS = 34, 7
local win

local function Refresh()
    if not (win and win:IsShown()) then return end
    local list = CF.Nearby()
    win.list:SetData(list)
    if not IsInGuild() then
        win.empty:SetText("You're not in a guild.")
    elseif #list == 0 then
        win.empty:SetText("No guildies with Campfire online yet.\n\nWhen guildies run Campfire too, they show up here with how far away they are.")
    else
        win.empty:SetText("")
    end
    win.share:SetChecked(CF.db.share)
    win.status:SetText(CF.StatusText())
end

local function BuildRow(row)
    row.name = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    row.name:SetPoint("TOPLEFT", 6, -3)
    row.dist = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    row.dist:SetPoint("TOPRIGHT", -6, -3)
    row.zone = row:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    row.zone:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -2)
    row.zone:SetPoint("RIGHT", -6, 0)
    row.zone:SetJustifyH("LEFT")
    row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    row:SetScript("OnClick", function(self)
        local target = self.full and CF.WhisperName(self.full)
        if not target then return end
        if ChatFrameUtil and ChatFrameUtil.OpenChat then ChatFrameUtil.OpenChat("/w " .. target .. " ")
        elseif ChatFrame_OpenChat then ChatFrame_OpenChat("/w " .. target .. " ") end
    end)
    row:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(LIB.ShortName(self.full))
        GameTooltip:AddLine("Click to whisper", 0.8, 0.8, 0.8)
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

local function FillRow(row, e)
    local r = LIB.roster[e.full]
    row.full = e.full
    row.name:SetText(LIB.ColorName(e.full, r and r.class))
    local p = e.peer
    if p.hidden then
        row.dist:SetText("|cff999999-|r")
        row.zone:SetText("Indoors or in an instance")
    elseif e.yards then
        row.dist:SetText(("%d yd%s"):format(math.floor(e.yards + 0.5), e.dir and (" |cffaaaaaa" .. e.dir .. "|r") or ""))
        row.zone:SetText(LIB.MapName(p.map))
    else
        row.dist:SetText("|cff999999far|r")
        row.zone:SetText(LIB.MapName(p.map))
    end
end

-- A fixed pool of rows inside a FauxScrollFrame, as in Guildhall's ScrollList.
local function ScrollList(parent)
    local list = CreateFrame("Frame", nil, parent)
    local scroll = CreateFrame("ScrollFrame", nil, list, "FauxScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT")
    scroll:SetPoint("BOTTOMRIGHT", -24, 0)
    list.rows = {}
    for i = 1, ROWS do
        local row = CreateFrame("Button", nil, list)
        row:SetHeight(ROW_H)
        row:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
        row:SetPoint("RIGHT", scroll, "RIGHT", 0, 0)
        BuildRow(row)
        list.rows[i] = row
    end
    list.data = {}
    function list:Refresh()
        local offset = FauxScrollFrame_GetOffset(scroll)
        FauxScrollFrame_Update(scroll, #self.data, ROWS, ROW_H)
        for i, row in ipairs(self.rows) do
            local item = self.data[i + offset]
            if item then row:Show(); FillRow(row, item) else row:Hide() end
        end
    end
    function list:SetData(data)
        self.data = data
        self:Refresh()
    end
    scroll:SetScript("OnVerticalScroll", function(self, value)
        FauxScrollFrame_OnVerticalScroll(self, value, ROW_H, function() list:Refresh() end)
    end)
    return list
end

local function Build()
    -- Same frame as Blizzard's Options panel; Forever swaps in its bronze art behind the atlas names.
    win = CreateFrame("Frame", "CampfireFrame", UIParent, "SettingsFrameTemplate")
    win:SetSize(W, H)
    win:SetClampedToScreen(true)
    win:EnableMouse(true)
    win.NineSlice.Text:SetText("Campfire")
    local bg = win:CreateTexture(nil, "BACKGROUND")
    bg:SetPoint("TOPLEFT", 7, -18)
    bg:SetPoint("BOTTOMRIGHT", -3, 3)
    bg:SetAtlas("heavybronze-frame-background")
    win.Bg:Hide()
    -- Default spot; LibForever's window handling restores the saved one (CF.db.panel) and does
    -- dragging, stacking with our other windows and Escape.
    win:SetPoint("CENTER", 0, 60)

    local inset = CreateFrame("Frame", nil, win, "BackdropTemplate")
    inset:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    inset:SetBackdropColor(0.03, 0.02, 0.01, 0.4)
    inset:SetBackdropBorderColor(0.85, 0.80, 0.70, 1)
    inset:SetPoint("TOPLEFT", 16, -32)
    inset:SetPoint("BOTTOMRIGHT", -16, 78)

    win.list = ScrollList(inset)
    win.list:SetPoint("TOPLEFT", 6, -6)
    win.list:SetPoint("BOTTOMRIGHT", -4, 6)

    win.empty = inset:CreateFontString(nil, "ARTWORK", "GameFontDisable")
    win.empty:SetPoint("TOPLEFT", 20, -40)
    win.empty:SetPoint("RIGHT", -20, 0)

    win.share = CreateFrame("CheckButton", nil, win, "UICheckButtonTemplate")
    win.share:SetSize(24, 24)
    win.share:SetPoint("BOTTOMLEFT", 16, 46)
    local label = win:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    label:SetPoint("LEFT", win.share, "RIGHT", 2, 0)
    label:SetText("Share my position with my guild")
    win.share:SetScript("OnClick", function(self)
        CF.SetShare(self:GetChecked() and true or false)
        Refresh()
    end)

    local close = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
    close:SetSize(90, 22)
    close:SetPoint("BOTTOMRIGHT", -16, 16)
    close:SetText(CLOSE or "Close")
    close:SetScript("OnClick", function() win:Hide() end)

    local settings = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
    settings:SetSize(90, 22)
    settings:SetPoint("RIGHT", close, "LEFT", -6, 0)
    settings:SetText(SETTINGS or "Settings")
    -- Only close the window once the settings have actually opened (they can't in combat).
    settings:SetScript("OnClick", function() if CF.OpenOptions() then win:Hide() end end)

    win.status = win:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    win.status:SetPoint("BOTTOMLEFT", 20, 22)
    win.status:SetPoint("RIGHT", settings, "LEFT", -8, 0)
    win.status:SetJustifyH("LEFT")

    -- Distances change as you move, without any event; a light tick keeps them current.
    local elapsed = 0
    win:SetScript("OnUpdate", function(_, dt)
        elapsed = elapsed + dt
        if elapsed >= 1 then elapsed = 0; Refresh() end
    end)
    win:SetScript("OnShow", Refresh)
    win:Hide()
    if LIB.RegisterWindow then LIB.RegisterWindow(win, CF.db, "panel") end
end

function CF.TogglePanel()
    if not win then Build() end
    win:SetShown(not win:IsShown())
end

function CF.OpenPanel()
    if not win then Build() end
    win:Show()
    win:Raise()
end

LIB.Listen("CAMPFIRE_PEERS", Refresh)
