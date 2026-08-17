local addonName = ...
local Addon = _G[addonName] or {}
_G[addonName] = Addon

local ADDON_PREFIX = Addon.ADDON_PREFIX or "MENTIONED_UTILS"
local BIGWIGS_PREFIX = Addon.BIGWIGS_PREFIX or "BigWigs"
local DBM_PREFIX = Addon.DBM_PREFIX or "D5"
local DBM_PREFIX_ALT = Addon.DBM_PREFIX_ALT or "D4"
local DEFAULT_PULL = Addon.DEFAULT_PULL or 10

local frame = CreateFrame("Frame")

local activeTimer = nil
local activeBreak = nil
local memeHideTimer = nil
local breakDragActive = false

local pullBar = CreateFrame("StatusBar", nil, UIParent)
pullBar:SetSize(300, 24)
pullBar:SetPoint("CENTER", UIParent, "CENTER", 0, 200)
pullBar:SetStatusBarTexture("Interface\\TARGETINGFRAME\\UI-StatusBar")
pullBar:SetStatusBarColor(0.8, 0, 0)
pullBar:Hide()

pullBar.bg = pullBar:CreateTexture(nil, "BACKGROUND")
pullBar.bg:SetAllPoints()
pullBar.bg:SetColorTexture(0, 0, 0, 0.6)

pullBar.text = pullBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
pullBar.text:SetPoint("CENTER")

pullBar.timeText = pullBar:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
pullBar.timeText:SetPoint("RIGHT", -5, 0)

local localFrame = CreateFrame("Frame", "MentionedBreakFrame", UIParent)

local function ApplyBreakFramePosition()
    local position = MentionedUtilsDB and MentionedUtilsDB.breakFramePosition
    local x = (position and position.x) or math.floor(UIParent:GetWidth() / 6)
    local y = (position and position.y) or 0

    localFrame:ClearAllPoints()
    localFrame:SetPoint("CENTER", UIParent, "CENTER", x, y)
end

local function SaveBreakFramePosition()
    if not MentionedUtilsDB then
        MentionedUtilsDB = {}
    end

    local frameX, frameY = localFrame:GetCenter()
    local parentX, parentY = UIParent:GetCenter()
    local frameScale = localFrame:GetEffectiveScale() or 1
    local parentScale = UIParent:GetEffectiveScale() or 1

    if not frameX or not frameY or not parentX or not parentY then
        return
    end

    local x = (frameX * frameScale - parentX * parentScale) / parentScale
    local y = (frameY * frameScale - parentY * parentScale) / parentScale
    MentionedUtilsDB.breakFramePosition = {
        x = x,
        y = y,
    }
end

localFrame.texture = localFrame:CreateTexture(nil, "BACKGROUND")
localFrame.texture:SetAllPoints(localFrame)

localFrame.timerText = localFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
localFrame.timerText:SetPoint("LEFT", localFrame, "RIGHT", 12, 0)
localFrame.timerText:SetJustifyH("LEFT")
localFrame.timerText:SetTextColor(1, 0.82, 0, 1)
do
    local fontPath, _, fontFlags = localFrame.timerText:GetFont()
    if fontPath then
        localFrame.timerText:SetFont(fontPath, 18, fontFlags)
    end
end
localFrame.timerText:Hide()

localFrame:SetClampedToScreen(true)
localFrame:SetMovable(true)
localFrame:EnableMouse(true)
localFrame:RegisterForDrag("LeftButton")
localFrame:SetScript("OnDragStart", function(self)
    if IsShiftKeyDown() then
        breakDragActive = true
        self:StartMoving()
    end
end)

localFrame:SetScript("OnDragStop", function(self)
    if not breakDragActive then
        return
    end

    self:StopMovingOrSizing()
    breakDragActive = false
    SaveBreakFramePosition()
end)

local countdownSounds = {
    [3] = "Interface\\AddOns\\MentionedUtils\\Sounds\\3.mp3",
    [2] = "Interface\\AddOns\\MentionedUtils\\Sounds\\2.mp3",
    [1] = "Interface\\AddOns\\MentionedUtils\\Sounds\\1.mp3",
}

local function FormatBreakTime(seconds)
    local total = math.max(0, math.ceil(tonumber(seconds) or 0))
    local mins = math.floor(total / 60)
    local secs = total % 60
    return string.format("%d:%02d", mins, secs)
end

local function PlayVoiceCountdown(sec)
    if (MentionedUtilsDB and MentionedUtilsDB.countDownChoice == 1 and sec == 3) then
        PlaySoundFile("Interface\\AddOns\\MentionedUtils\\Sounds\\leeroy.mp3", "Master")
    else
        PlaySoundFile(countdownSounds[sec], "Master")
    end
end

local function GetMemeCount()
    return MentionedMedia and MentionedMedia.BreakMemes and #MentionedMedia.BreakMemes or 0
end

local function PickRandomMemeIndex()
    local memeCount = GetMemeCount()
    if memeCount <= 0 then
        return nil
    end

    return math.random(1, memeCount)
end

local function GetMemeDisplayName(index)
    local meme = MentionedMedia and MentionedMedia.BreakMemes and MentionedMedia.BreakMemes[index]
    if not meme or not meme[1] then
        return nil
    end

    local fileName = meme[1]:match("([^\\/]+)$") or meme[1]
    return fileName:gsub("%.[^.]+$", "")
end

local function ResolveMemeIndex(selection)
    if not selection or selection == "" then
        return nil
    end

    local numericIndex = tonumber(selection)
    local memeCount = GetMemeCount()
    if numericIndex and numericIndex >= 1 and numericIndex <= memeCount then
        return math.floor(numericIndex)
    end

    local needle = selection:lower()
    for i = 1, memeCount do
        local name = GetMemeDisplayName(i)
        if name and name:lower():find(needle, 1, true) then
            return i
        end
    end

    return nil
end

local function StartPullTimer(seconds, sender)
    if activeTimer then
        activeTimer:Cancel()
    end

    seconds = tonumber(seconds) or DEFAULT_PULL
    sender = sender or UnitName("player")

    pullBar:SetMinMaxValues(0, seconds)
    pullBar:SetValue(seconds)
    pullBar.text:SetText("Pull - " .. sender)
    pullBar:Show()

    local remaining = seconds

    PlaySoundFile("Interface\\AddOns\\MentionedUtils\\Sounds\\dingding.mp3", "Master")
    activeTimer = C_Timer.NewTicker(0.1, function(ticker)
        remaining = (remaining or 0) - 0.1
        if remaining <= 0 then
            pullBar:SetValue(0)
            C_Timer.After(1, function() pullBar:Hide() end)
            ticker:Cancel()
            activeTimer = nil
            return
        end

        pullBar:SetValue(remaining)
        pullBar.timeText:SetFormattedText("%.1f", remaining)

        local currentSecond = math.ceil(tonumber(remaining) or 0)
        if currentSecond <= 3 and currentSecond >= 1 then
            if activeTimer.lastPlayed ~= currentSecond then
                activeTimer.lastPlayed = currentSecond
                PlayVoiceCountdown(currentSecond)
            end
        end
    end)
end

local function ShowRandomMeme(duration, index)
    local memes = MentionedMedia and MentionedMedia.BreakMemes
    if not memes or #memes == 0 then return end

    local meme = memes[index]
    if not meme then return end

    local path, width, height = meme[1], meme[2], meme[3]

    if memeHideTimer then
        memeHideTimer:Cancel()
        memeHideTimer = nil
    end

    localFrame:SetSize(width, height)
    ApplyBreakFramePosition()
    localFrame.texture:SetTexture(path)
    localFrame:Show()

    memeHideTimer = C_Timer.NewTimer(duration, function()
        localFrame:Hide()
        memeHideTimer = nil
    end)
end

local function CancelPull()
    if activeTimer then
        activeTimer:Cancel()
        activeTimer = nil
    end
    pullBar:Hide()
    print("Pull timer cancelled.")
end

local function StartBreakTimer(seconds, sender, index)
    if activeBreak then
        activeBreak:Cancel()
    end

    sender = sender or UnitName("player")

    seconds = tonumber(seconds)
    if not seconds or seconds <= 0 then return end

    ShowRandomMeme(seconds, index)
    local remaining = seconds

    localFrame.timerText:SetText("Break: " .. FormatBreakTime(remaining))
    localFrame.timerText:Show()

    PlaySoundFile("Interface\\AddOns\\MentionedUtils\\Sounds\\dingding.mp3", "Master")
    activeBreak = C_Timer.NewTicker(0.1, function(ticker)
        remaining = (remaining or 0) - 0.1
        if remaining <= 0 then
            ticker:Cancel()
            activeBreak = nil
            localFrame.timerText:Hide()
            return
        end

        localFrame.timerText:SetText("Break: " .. FormatBreakTime(remaining))
    end)
end

local function CancelBreak()
    if activeBreak then
        activeBreak:Cancel()
        activeBreak = nil
    end
    if memeHideTimer then
        memeHideTimer:Cancel()
        memeHideTimer = nil
    end
    localFrame:Hide()
    localFrame.timerText:Hide()
end

local function HandleIncomingBreak(seconds, sender, index)
    seconds = tonumber(seconds)
    if seconds == 0 then
        CancelBreak()
        return
    end
    if not seconds or seconds < 0 then
        return
    end

    index = tonumber(index)
    local memeCount = GetMemeCount()
    if not index or index < 1 or index > memeCount then
        index = PickRandomMemeIndex()
        if IsInGroup() and (UnitIsGroupLeader("player") or UnitIsGroupAssistant("player")) then
            C_ChatInfo.SendAddonMessage(ADDON_PREFIX, ("BI\t%d\t%d"):format(index or 0, seconds), IsInGroup(2) and "INSTANCE_CHAT" or "RAID")
        end
    end

    StartBreakTimer(seconds, sender, index)
end

local function HandleIncomingTestMeme(seconds, sender, index)
    local duration = tonumber(seconds)
    local memeCount = GetMemeCount()

    if not duration or duration <= 0 then
        duration = 8
    end

    index = tonumber(index)
    if not index or index < 1 or index > memeCount then
        return
    end

    if activeBreak then
        activeBreak:Cancel()
        activeBreak = nil
    end

    localFrame.timerText:Hide()
    ShowRandomMeme(duration, index)
end

frame:RegisterEvent("CHAT_MSG_ADDON")

frame:SetScript("OnEvent", function(_, event, ...)
    if event ~= "CHAT_MSG_ADDON" then
        return
    end

    local prefix, message, _, sender = ...

    if prefix == BIGWIGS_PREFIX then
        local bwPrefix, bwMsg, extra = strsplit("^", message)

        if bwPrefix == "P" and bwMsg == "Break" then
            HandleIncomingBreak(extra, sender)
            return
        end
        if bwPrefix == "Break" then
            HandleIncomingBreak(bwMsg, sender)
            return
        end
        if bwMsg == "Break" then
            HandleIncomingBreak(extra, sender)
            return
        end
        if bwPrefix == "P" and bwMsg == "Pull" then
            StartPullTimer(extra, sender)
            return
        end
    end

    if prefix == DBM_PREFIX or prefix == DBM_PREFIX_ALT then
        local _, _, subPrefix, seconds = strsplit("\t", message)
        if subPrefix == "BT" and seconds then
            HandleIncomingBreak(seconds, sender, nil)
            return
        end

        if message:find("\tBT\t") then
            local _, _, _, fallbackSeconds = strsplit("\t", message)
            HandleIncomingBreak(fallbackSeconds, sender, nil)
            return
        end
    end

    if prefix ~= ADDON_PREFIX then
        return
    end

    if message == "CANCEL_BREAK" then
        CancelBreak()
        PlaySoundFile("Interface\\AddOns\\MentionedUtils\\Sounds\\cancel.mp3", "Master")
        return
    end

    if message == "CANCEL_PULL" then
        CancelPull()
        PlaySoundFile("Interface\\AddOns\\MentionedUtils\\Sounds\\cancel.mp3", "Master")
        return
    end

    if message == "CANCEL" then
        CancelPull()
        CancelBreak()
        PlaySoundFile("Interface\\AddOns\\MentionedUtils\\Sounds\\cancel.mp3", "Master")
        return
    end

    if message:find("\tBT\t") then
        local _, _, subPrefix, seconds = strsplit("\t", message)
        if subPrefix == "BT" and seconds then
            HandleIncomingBreak(seconds, sender, nil)
        else
            local _, _, _, fallbackSeconds = strsplit("\t", message)
            HandleIncomingBreak(fallbackSeconds, sender, nil)
        end
        return
    end

    if message:find("^BI\t") then
        local _, index, seconds = strsplit("\t", message)
        index = tonumber(index)
        seconds = tonumber(seconds)
        if seconds then
            StartBreakTimer(seconds, sender, index)
        end
        return
    end

    if message:find("^TM\t") then
        local _, index, seconds = strsplit("\t", message)
        index = tonumber(index)
        seconds = tonumber(seconds)
        if index then
            HandleIncomingTestMeme(seconds, sender, index)
        end
        return
    end

    if message:find("^PULL\t") then
        local _, seconds = strsplit("\t", message)
        StartPullTimer(seconds, sender)
        return
    end
end)

Addon.ApplyBreakFramePosition = ApplyBreakFramePosition
Addon.SaveBreakFramePosition = SaveBreakFramePosition
Addon.GetMemeCount = GetMemeCount
Addon.PickRandomMemeIndex = PickRandomMemeIndex
Addon.GetMemeDisplayName = GetMemeDisplayName
Addon.ResolveMemeIndex = ResolveMemeIndex
Addon.StartBreakTimer = StartBreakTimer
Addon.CancelBreak = CancelBreak
Addon.CancelPull = CancelPull
Addon.HandleIncomingBreak = HandleIncomingBreak
Addon.HandleIncomingTestMeme = HandleIncomingTestMeme
