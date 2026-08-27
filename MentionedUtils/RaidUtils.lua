local addonName = ...
local Addon = _G[addonName] or {}
_G[addonName] = Addon

local ADDON_PREFIX = Addon.ADDON_PREFIX or "MENTIONED_UTILS"
local BIGWIGS_PREFIX = Addon.BIGWIGS_PREFIX or "BigWigs"
local DBM_PREFIX = Addon.DBM_PREFIX or "D5"
local DBM_PREFIX_ALT = Addon.DBM_PREFIX_ALT or "D4"
local DEFAULT_PULL = Addon.DEFAULT_PULL or 10
local frame = CreateFrame("Frame")
local activeTimer, activeBreak, memeHideTimer
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
local textFrame = CreateFrame("Frame", nil, UIParent)
local function ApplyBreakFramePosition()
    local position = MentionedUtilsDB and MentionedUtilsDB.breakFramePosition
    local imageScale = (MentionedUtilsDB and MentionedUtilsDB.breakFrameScale) or 1
    local textScale = (MentionedUtilsDB and MentionedUtilsDB.breakTextScale) or 1
    localFrame:SetScale(imageScale)
    textFrame:SetScale(textScale)
    localFrame:ClearAllPoints()
    localFrame:SetPoint("CENTER", UIParent, "CENTER", (position and position.x) or math.floor(UIParent:GetWidth() / 6), (position and position.y) or 0)
    textFrame:ClearAllPoints()
    textFrame:SetPoint("LEFT", localFrame, "RIGHT", 12, 0)
end
local function SaveBreakFramePosition()
    MentionedUtilsDB = MentionedUtilsDB or {}
    local frameX, frameY = localFrame:GetCenter()
    local parentX, parentY = UIParent:GetCenter()
    local frameScale = localFrame:GetEffectiveScale() or 1
    local parentScale = UIParent:GetEffectiveScale() or 1
    if not frameX or not frameY or not parentX or not parentY then return end
    MentionedUtilsDB.breakFramePosition = { x = (frameX * frameScale - parentX * parentScale) / parentScale, y = (frameY * frameScale - parentY * parentScale) / parentScale }
end
localFrame.texture = localFrame:CreateTexture(nil, "BACKGROUND")
localFrame.texture:SetAllPoints(localFrame)
localFrame.timerText = textFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
localFrame.timerText:SetPoint("LEFT", textFrame, "LEFT")
localFrame.timerText:SetJustifyH("LEFT")
localFrame.timerText:SetTextColor(1, 0.82, 0, 1)
do
    local fontPath, _, fontFlags = localFrame.timerText:GetFont()
    if fontPath then localFrame.timerText:SetFont(fontPath, 18, fontFlags) end
end
localFrame.timerText:Hide()
textFrame:SetSize(180, 30)
textFrame:EnableMouse(true)
textFrame:EnableMouseWheel(true)
textFrame:SetScript("OnMouseWheel", function(_, delta)
    if not IsShiftKeyDown() then return end
    MentionedUtilsDB = MentionedUtilsDB or {}
    MentionedUtilsDB.breakTextScale = math.max(0.5, math.min(2, (MentionedUtilsDB.breakTextScale or 1) + delta * 0.1))
    ApplyBreakFramePosition()
end)
textFrame:Hide()
localFrame:SetClampedToScreen(true)
localFrame:SetMovable(true)
localFrame:EnableMouse(true)
localFrame:EnableMouseWheel(true)
localFrame:SetScript("OnMouseWheel", function(_, delta)
    if not IsShiftKeyDown() then return end
    MentionedUtilsDB = MentionedUtilsDB or {}
    MentionedUtilsDB.breakFrameScale = math.max(0.5, math.min(2, (MentionedUtilsDB.breakFrameScale or 1) + delta * 0.1))
    ApplyBreakFramePosition()
end)
localFrame:RegisterForDrag("LeftButton")
localFrame:SetScript("OnDragStart", function(self) if IsShiftKeyDown() then breakDragActive = true; self:StartMoving() end end)
localFrame:SetScript("OnDragStop", function(self) if breakDragActive then self:StopMovingOrSizing(); breakDragActive = false; SaveBreakFramePosition() end end)

local countdownSounds = { [3] = "Interface\\AddOns\\MentionedUtils\\Sounds\\3.mp3", [2] = "Interface\\AddOns\\MentionedUtils\\Sounds\\2.mp3", [1] = "Interface\\AddOns\\MentionedUtils\\Sounds\\1.mp3" }
local function FormatBreakTime(seconds)
    local total = math.max(0, math.ceil(tonumber(seconds) or 0))
    return string.format("%d:%02d", math.floor(total / 60), total % 60)
end
local function PlayVoiceCountdown(second)
    if MentionedUtilsDB and MentionedUtilsDB.countDownChoice == 1 and second == 3 then
        PlaySoundFile("Interface\\AddOns\\MentionedUtils\\Sounds\\leeroy.mp3", "Master")
    else
        PlaySoundFile(countdownSounds[second], "Master")
    end
end
local function GetMemeCount() return MentionedMedia and MentionedMedia.BreakMemes and #MentionedMedia.BreakMemes or 0 end
local function PickRandomMemeIndex()
    local count = GetMemeCount()
    return count > 0 and math.random(1, count) or nil
end
local function GetMemeDisplayName(index)
    local meme = MentionedMedia and MentionedMedia.BreakMemes and MentionedMedia.BreakMemes[index]
    if not meme or not meme[1] then return nil end
    return (meme[1]:match("([^\\/]+)$") or meme[1]):gsub("%.[^.]+$", "")
end
local function ResolveMemeIndex(selection)
    if not selection or selection == "" then return nil end
    local numericIndex, count = tonumber(selection), GetMemeCount()
    if numericIndex and numericIndex >= 1 and numericIndex <= count then return math.floor(numericIndex) end
    local needle = selection:lower()
    for index = 1, count do
        local name = GetMemeDisplayName(index)
        if name and name:lower():find(needle, 1, true) then return index end
    end
end

local function StartPullTimer(seconds, sender)
    if activeTimer then activeTimer:Cancel() end
    seconds, sender = tonumber(seconds) or DEFAULT_PULL, sender or UnitName("player")
    pullBar:SetMinMaxValues(0, seconds); pullBar:SetValue(seconds); pullBar.text:SetText("Pull - " .. sender); pullBar:Show()
    local remaining = seconds
    PlaySoundFile("Interface\\AddOns\\MentionedUtils\\Sounds\\dingding.mp3", "Master")
    activeTimer = C_Timer.NewTicker(0.1, function(ticker)
        remaining = remaining - 0.1
        if remaining <= 0 then pullBar:SetValue(0); C_Timer.After(1, function() pullBar:Hide() end); ticker:Cancel(); activeTimer = nil; return end
        pullBar:SetValue(remaining); pullBar.timeText:SetFormattedText("%.1f", remaining)
        local second = math.ceil(remaining)
        if second >= 1 and second <= 3 and activeTimer.lastPlayed ~= second then activeTimer.lastPlayed = second; PlayVoiceCountdown(second) end
    end)
end
local function ShowRandomMeme(duration, index)
    local memes = MentionedMedia and MentionedMedia.BreakMemes
    local meme = memes and memes[index]
    if not meme then return end
    if memeHideTimer then memeHideTimer:Cancel() end
    localFrame:SetSize(meme[2], meme[3]); ApplyBreakFramePosition(); localFrame.texture:SetTexture(meme[1]); localFrame:Show()
    memeHideTimer = C_Timer.NewTimer(duration, function() localFrame:Hide(); memeHideTimer = nil end)
end
local function CancelPull()
    if activeTimer then activeTimer:Cancel(); activeTimer = nil end
    pullBar:Hide(); print("Pull timer cancelled.")
end
local function StartBreakTimer(seconds, sender, index)
    if activeBreak then activeBreak:Cancel() end
    seconds = tonumber(seconds)
    if not seconds or seconds <= 0 then return end
    index = index or PickRandomMemeIndex()
    if not index then return end
    ShowRandomMeme(seconds, index)
    local endTime = GetTime() + seconds
    local function UpdateBreakDisplay()
        local remaining = math.max(0, endTime - GetTime())
        localFrame.timerText:SetText("Break: " .. FormatBreakTime(remaining))
        return remaining
    end
    UpdateBreakDisplay()
    localFrame.timerText:Show()
    textFrame:Show()
    PlaySoundFile("Interface\\AddOns\\MentionedUtils\\Sounds\\dingding.mp3", "Master")
    activeBreak = C_Timer.NewTicker(0.1, function(ticker)
        local remaining = UpdateBreakDisplay()
        if remaining <= 0 then ticker:Cancel(); activeBreak = nil; localFrame.timerText:Hide(); textFrame:Hide(); return end
    end)
end
local function CancelBreak()
    if activeBreak then activeBreak:Cancel(); activeBreak = nil end
    if memeHideTimer then memeHideTimer:Cancel(); memeHideTimer = nil end
    localFrame:Hide(); textFrame:Hide(); localFrame.timerText:Hide()
end
local function HandleIncomingBreak(seconds, sender, index)
    seconds = tonumber(seconds)
    if seconds == 0 then CancelBreak(); return end
    if not seconds or seconds < 0 then return end
    index = tonumber(index)
    if not index or index < 1 or index > GetMemeCount() then
        index = PickRandomMemeIndex()
        if IsInGroup() and (UnitIsGroupLeader("player") or UnitIsGroupAssistant("player")) then
            C_ChatInfo.SendAddonMessage(ADDON_PREFIX, ("BI\t%d\t%d"):format(index or 0, seconds), IsInGroup(2) and "INSTANCE_CHAT" or "RAID")
        end
    end
    StartBreakTimer(seconds, sender, index)
end
local function HandleIncomingTestMeme(seconds, sender, index)
    seconds = tonumber(seconds) or 8
    index = tonumber(index)
    if not index or index < 1 or index > GetMemeCount() then return end
    if activeBreak then activeBreak:Cancel(); activeBreak = nil end
    textFrame:Hide(); localFrame.timerText:Hide(); ShowRandomMeme(seconds, index)
end

frame:RegisterEvent("CHAT_MSG_ADDON")
frame:SetScript("OnEvent", function(_, event, ...)
    if event ~= "CHAT_MSG_ADDON" then return end
    local prefix, message, _, sender = ...
    if prefix == BIGWIGS_PREFIX then
        local first, second, extra = strsplit("^", message)
        if first == "P" and second == "Break" then HandleIncomingBreak(extra, sender); return end
        if first == "Break" then HandleIncomingBreak(second, sender); return end
        if second == "Break" then HandleIncomingBreak(extra, sender); return end
        if first == "P" and second == "Pull" then StartPullTimer(extra, sender); return end
    elseif prefix == DBM_PREFIX or prefix == DBM_PREFIX_ALT then
        local _, _, subPrefix, seconds = strsplit("\t", message)
        if subPrefix == "BT" and seconds then HandleIncomingBreak(seconds, sender); return end
        if message:find("\tBT\t") then
            local _, _, _, fallbackSeconds = strsplit("\t", message)
            HandleIncomingBreak(fallbackSeconds, sender)
            return
        end
    end
    if prefix ~= ADDON_PREFIX then return end
    if message == "CANCEL_BREAK" then CancelBreak(); PlaySoundFile("Interface\\AddOns\\MentionedUtils\\Sounds\\cancel.mp3", "Master"); return end
    if message == "CANCEL_PULL" then CancelPull(); PlaySoundFile("Interface\\AddOns\\MentionedUtils\\Sounds\\cancel.mp3", "Master"); return end
    if message == "CANCEL" then CancelPull(); CancelBreak(); PlaySoundFile("Interface\\AddOns\\MentionedUtils\\Sounds\\cancel.mp3", "Master"); return end
    if message:find("\tBT\t") then
        local _, _, subPrefix, seconds = strsplit("\t", message)
        if subPrefix == "BT" and seconds then
            HandleIncomingBreak(seconds, sender)
        else
            local _, _, _, fallbackSeconds = strsplit("\t", message)
            HandleIncomingBreak(fallbackSeconds, sender)
        end
        return
    end
    if message:find("^BI\t") then local _, index, seconds = strsplit("\t", message); StartBreakTimer(seconds, sender, tonumber(index)); return end
    if message:find("^TM\t") then local _, index, seconds = strsplit("\t", message); HandleIncomingTestMeme(seconds, sender, tonumber(index)); return end
    if message:find("^PULL\t") then local _, seconds = strsplit("\t", message); StartPullTimer(seconds, sender) end
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