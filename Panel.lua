-- Campfire - the small "who is where" window (minimap button, /campfire).
local ADDON, CF = ...
local LIB = LibStub("LibForever-1.0")

local W, H = 340, 380
local ROW_H, ROWS = 34, 7
local win

--- What the empty list says, depending on the settings: who can show up here, and how to see more.
function CF.EmptyText(elsewhere)
    local open = CF.OpenActive and CF.OpenActive()
    local inGuild = IsInGuild()
    local tick = "Tick \"Also share with other Campfire players on my faction\" in the settings"
    if not inGuild and not open then
        if CF.db.hidden then
            return "Your position is hidden and you're not in a guild, so Campfire has no one to show.\n\n"
                .. "Untick \"Hide my position\" below to see Campfire players on your faction."
        end
        return "You're not in a guild and sharing with other Campfire players is off, so Campfire has no "
            .. "one to show.\n\n" .. tick .. " to see players on your faction."
    end
    local where = CF.db.zoneOnly and "in your zone" or "online"
    local head = open and ("No one with Campfire " .. where .. " right now.")
        or ("No guildies with Campfire " .. where .. " right now.")
    local more
    if CF.db.zoneOnly and elsewhere > 0 then
        more = elsewhere .. " more elsewhere. Tick \"Show all zones\" below to list them too."
    elseif open then
        more = "Guildies and other Campfire players on your faction show up here with where they are and how far away."
    elseif CF.db.hidden then
        more = "While your position is hidden you only see guildies. Untick \"Hide my position\" below to see "
            .. "Campfire players on your faction too."
    else
        more = tick .. " to see more players."
    end
    return head .. "\n\n" .. more
end

local function Refresh()
    if not (win and win:IsShown()) then return end
    local list, elsewhere = CF.Nearby()
    win.list:SetData(list)
    win.empty:SetText(#list == 0 and CF.EmptyText(elsewhere) or "")
    win.hide:SetChecked(CF.db.hidden)
    win.allZones:SetChecked(not CF.db.zoneOnly)
    win.status:SetText(CF.ShortStatus())
end

local function BuildRow(row)
    -- Two lines on each side:
    --   Swim Shady                 Redridge Mountains
    --   20 Priest                         1300 yd SW
    row.name = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    row.name:SetPoint("TOPLEFT", 6, -3)
    row.where = row:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    row.where:SetPoint("TOPRIGHT", -6, -3)
    -- Meets the name at most; a long place name ends in "...".
    row.where:SetPoint("LEFT", row.name, "RIGHT", 8, 0)
    row.where:SetJustifyH("RIGHT")
    row.where:SetWordWrap(false)
    row.who = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    row.who:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -3)
    row.who:SetJustifyH("LEFT")
    row.who:SetWordWrap(false)
    row.how = row:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    row.how:SetPoint("TOPRIGHT", row.where, "BOTTOMRIGHT", 0, -3)
    row.how:SetPoint("LEFT", row.who, "RIGHT", 8, 0)
    row.how:SetJustifyH("RIGHT")
    row.how:SetWordWrap(false)
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
        if self.open then GameTooltip:AddLine("Not in your guild", 0.15, 1, 0.4) end
        GameTooltip:AddLine("Click to whisper", 0.8, 0.8, 0.8)
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

local function FillRow(row, e)
    row.full, row.open = e.full, e.peer.open
    local name, where, who, how = CF.RowText(e)
    row.name:SetText(name)
    row.where:SetText(where)
    row.who:SetText(who)
    row.how:SetText(how)
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

    local function Toggle(x, text, onClick)
        local cb = CreateFrame("CheckButton", nil, win, "UICheckButtonTemplate")
        cb:SetSize(24, 24)
        cb:SetPoint("BOTTOMLEFT", x, 46)
        local label = win:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        label:SetPoint("LEFT", cb, "RIGHT", 2, 0)
        label:SetText(text)
        cb:SetScript("OnClick", function(self)
            onClick(self:GetChecked() and true or false)
            Refresh()
        end)
        return cb
    end
    win.hide = Toggle(16, "Hide my position", CF.SetHidden)
    win.allZones = Toggle(180, "Show all zones", CF.SetShowAllZones)

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

    -- Distances change as you move, without any event; a light tick keeps them current. It only
    -- matters while the window is up and has something in it.
    local elapsed = 0
    win:SetScript("OnUpdate", function(self, dt)
        if not self:IsShown() or not next(CF.peers) then return end
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

-- Same as the map: coalesce a burst of positions into one refresh. The window's own 1 Hz tick is
-- the backstop when messages never stop arriving.
LIB.Listen("CAMPFIRE_PEERS", function() LIB.Debounce("CampfirePanel", 0.3, Refresh) end)
