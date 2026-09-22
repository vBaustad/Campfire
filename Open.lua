-- Campfire - sharing with Campfire players on our faction outside the guild, over a hidden custom
-- channel. On by default (opt-out): custom channels are split by faction, so the other faction can't
-- see it. While it's off we don't join the channel at all.
-- Safety net: every position carries our faction. If one from the other faction ever arrives, the
-- channel isn't faction-split after all, so we turn open sharing off and say so once.
-- Separate from the guild path: its own prefix, sent straight through SendAddonMessage (LibForever's
-- comms only take guild messages and guild whispers), less often, and rate-limited per sender.
local ADDON, CF = ...
local LIB = LibStub("LibForever-1.0")

local CHANNEL = "YippYappCampfire"
local OPREFIX = "CampfireO"
local HEARTBEAT = 180   -- resend at least this often while standing still
local MIN_GAP = 30      -- never send more often than this while moving
local MOVE_YARDS = 100  -- ...and only once we've moved this far
local ACCEPT_GAP = 20   -- ignore a player's positions that arrive faster than this
local MAX_PEERS = 60    -- cap on strangers we keep track of
CF.OPEN_STALE = 420     -- forget a stranger after this long without news

C_ChatInfo.RegisterAddonMessagePrefix(OPREFIX)

local last = { at = -math.huge }
local heard = {}        -- ["Name-Realm"] = GetTime() of the last accepted position
local crossFaction = 0  -- positions seen from the other faction (should stay 0)

local function MyFaction()
    local f = UnitFactionGroup("player")
    return f == "Alliance" and "A" or f == "Horde" and "H" or "N"
end

local function ChannelId()
    local id = GetChannelName(CHANNEL)
    return (id and id > 0) and id or nil
end

--- On the channel only while open sharing is on and we aren't hiding.
local function Active()
    return CF.db and CF.db.openShare and not CF.db.hidden
end
CF.OpenActive = Active

-- ---------------------------------------------------------------------------
-- Keeping the channel out of sight
-- ---------------------------------------------------------------------------
local function HideFromChatFrames()
    for i = 1, (NUM_CHAT_WINDOWS or 10) do
        local frame = _G["ChatFrame" .. i]
        if frame then
            if frame.RemoveChannel then
                pcall(frame.RemoveChannel, frame, CHANNEL)
            elseif ChatFrame_RemoveChannel then
                pcall(ChatFrame_RemoveChannel, frame, CHANNEL)
            end
        end
    end
end

-- "Joined channel" / "Left channel" lines for our channel. channelBaseName (the 9th payload value)
-- is never secret, so this is safe during chat lockdown.
local function NoticeFilter(_, _, _, _, _, _, _, _, _, _, channelBaseName)
    return channelBaseName == CHANNEL
end

local addFilter = (ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter) or ChatFrame_AddMessageEventFilter
if addFilter then
    addFilter("CHAT_MSG_CHANNEL_NOTICE", NoticeFilter)
    addFilter("CHAT_MSG_CHANNEL_NOTICE_USER", NoticeFilter)
end

local function Join()
    if ChannelId() then HideFromChatFrames() return end
    if not JoinTemporaryChannel then return end
    JoinTemporaryChannel(CHANNEL)
    C_Timer.After(1, HideFromChatFrames)
    C_Timer.After(5, HideFromChatFrames)
end

local function Leave()
    if ChannelId() and LeaveChannelByName then LeaveChannelByName(CHANNEL) end
end

-- ---------------------------------------------------------------------------
-- Sending
-- ---------------------------------------------------------------------------
-- SendAddonMessage results we act on (values from the client's SendAddonMessageResult enum).
local RESULT = Enum and Enum.SendAddonMessageResult or {}
local SUCCESS = RESULT.Success or 0
local INVALID_CHANNEL = RESULT.InvalidChannel or 7
local CHANNEL_THROTTLE = RESULT.ChannelThrottle or 8
local LOCKDOWN = RESULT.AddOnMessageLockdown or 11

local stats = { sent = 0, lockdown = 0, throttle = 0, invalidChannel = 0, other = 0, rejoins = 0 }
local rejoined = false  -- one rejoin per InvalidChannel streak

--- Returns true when the message went out. A position that doesn't go out is simply skipped: the
--- next tick sends a fresher one.
local function SendOpen(text)
    local id = ChannelId()
    if not id then return false end
    local result = C_ChatInfo.SendAddonMessage(OPREFIX, text, "CHANNEL", tostring(id))
    if result == nil or result == true or result == SUCCESS then
        stats.sent = stats.sent + 1
        rejoined = false
        return true
    elseif result == LOCKDOWN then
        stats.lockdown = stats.lockdown + 1
    elseif result == CHANNEL_THROTTLE then
        stats.throttle = stats.throttle + 1
    elseif result == INVALID_CHANNEL then
        stats.invalidChannel = stats.invalidChannel + 1
        -- The channel went away under us (kicked, or the client rejoined its channels): join again, once.
        if not rejoined then
            rejoined = true
            stats.rejoins = stats.rejoins + 1
            if LeaveChannelByName then LeaveChannelByName(CHANNEL) end
            C_Timer.After(2, function() if Active() then Join() end end)
        end
    else
        stats.other = stats.other + 1
    end
    return false
end

local function Stop()
    SendOpen(("X;%d"):format(CF.PROTO))
    last = { at = -math.huge }
end

--- reason: "tick" sends only when moved or due; anything else sends unless we just did.
local function SendPosition(reason)
    if not Active() then return end
    local now = GetTime()
    local map, x, y = LIB.MyPosition()
    if not map then
        -- No position (indoors or in an instance): drop out instead of saying where we went.
        if last.map then Stop() end
        return
    end
    local elapsed = now - last.at
    if reason == "tick" then
        if elapsed < MIN_GAP then return end
        local moved = LIB.Distance(map, x, y, last.map, last.x, last.y)
        if elapsed < HEARTBEAT and moved and moved < MOVE_YARDS then return end
    elseif elapsed < 10 then
        return
    end
    local sub, level, class = CF.AboutMe()
    if SendOpen(("P;%d;%d;%.4f;%.4f;%s;%s;%d;%s"):format(CF.PROTO, map, x, y, MyFaction(), sub, level, class)) then
        last = { at = now, map = map, x = x, y = y }
    end
end

-- ---------------------------------------------------------------------------
-- Receiving
-- ---------------------------------------------------------------------------
local function DropStrangers()
    for full, p in pairs(CF.peers) do
        if p.open then CF.peers[full] = nil end
    end
    wipe(heard)
end

local function OpenCount()
    local n = 0
    for _, p in pairs(CF.peers) do if p.open then n = n + 1 end end
    return n
end

LIB.On("CHAT_MSG_ADDON", function(prefix, text, chatType, sender)
    if prefix ~= OPREFIX or chatType ~= "CHANNEL" or not Active() then return end
    sender = LIB.FullName(sender)
    if not sender or sender == LIB.Me() then return end
    -- Guildies come through the guild channel, which we trust more.
    if LIB.IsGuildie(sender) then return end
    -- Strangers can send anything here: anything that isn't exactly "X;proto" or
    -- "P;proto;map;x;y;faction[;subzone;level;class]" is dropped without a word.
    local fields = { strsplit(";", text) }
    local kind, proto, a, b, c, faction, sub, level, class = unpack(fields)
    if tonumber(proto) ~= CF.PROTO then return end
    if kind == "X" then
        if #fields ~= 2 then return end
    elseif kind == "P" then
        if (#fields ~= 6 and #fields ~= 9) or not (faction == "A" or faction == "H" or faction == "N") then return end
    else
        return
    end
    local now = GetTime()
    if kind == "P" and faction ~= MyFaction() and faction ~= "N" and MyFaction() ~= "N" then
        -- The other faction can hear this channel: stop sharing on it.
        crossFaction = crossFaction + 1
        if crossFaction == 1 then
            print(CF.TAG .. ": the other faction can see Campfire's shared channel, so sharing with players "
                .. "outside your guild is now off. Your guild still sees you.")
            CF.SetOpenShare(false)
        end
        return
    end
    if kind == "X" then
        if CF.peers[sender] and CF.peers[sender].open then
            CF.peers[sender] = nil
            LIB.Fire("CAMPFIRE_PEERS")
        end
        return
    end
    if kind ~= "P" then return end
    if heard[sender] and now - heard[sender] < ACCEPT_GAP then return end
    local map, x, y = tonumber(a), tonumber(b), tonumber(c)
    if not (map and x and y) or x < 0 or x > 1 or y < 0 or y > 1 then return end
    if not ((LIB.Maps and LIB.Maps[map]) or C_Map.GetMapInfo(map)) then return end
    if not CF.peers[sender] and OpenCount() >= MAX_PEERS then return end
    heard[sender] = now
    CF.peers[sender] = { map = map, x = x, y = y, seen = now, open = true,
        sub = CF.CleanText(sub), level = CF.ValidLevel(level), class = CF.ValidClass(class) }
    LIB.Fire("CAMPFIRE_PEERS")
end)

-- ---------------------------------------------------------------------------
-- Switching it on and off
-- ---------------------------------------------------------------------------
local function GoOn()
    Join()
    C_Timer.After(4, function() SendPosition("share") end)
end

local function GoOff()
    Stop()
    -- Let the stop message go out before leaving.
    C_Timer.After(1, Leave)
    DropStrangers()
end

function CF.SetOpenShare(on)
    on = on and true or false
    if CF.db.openShare == on then return end
    local was = Active()
    CF.db.openShare = on
    if Active() and not was then GoOn() elseif was and not Active() then GoOff() end
    LIB.Fire("CAMPFIRE_PEERS")
end

--- Called when "Hide my position" changes: hiding leaves the channel too.
function CF.OpenHiddenChanged()
    if not CF.db.openShare then return end
    if CF.db.hidden then GoOff() else GoOn() end
end

function CF.OpenDebug()
    print(("  open channel: %s, id %s, %d players outside the guild listed, %d from the other faction seen"):format(
        Active() and "on" or "off", tostring(ChannelId()), OpenCount(), crossFaction))
    print(("  open sends: %d sent, %d lockdown, %d throttled, %d invalid channel (%d rejoins), %d other"):format(
        stats.sent, stats.lockdown, stats.throttle, stats.invalidChannel, stats.rejoins, stats.other))
end

function CF.StartOpen()
    if Active() then
        -- The client joins its default channels first; joining ours right away can take their slots.
        C_Timer.After(10, function()
            if not Active() then return end
            Join()
            C_Timer.After(4, function() SendPosition("login") end)
        end)
    end
    C_Timer.NewTicker(10, function() SendPosition("tick") end)
end
