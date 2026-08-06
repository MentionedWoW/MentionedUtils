local ADDON_NAME = "MentionedUtils"
local ADDON_PREFIX = "MENTIONED_UTILS"
local BIGWIGS_PREFIX = "BigWigs"
local DBM_PREFIX = "D5"
local DBM_PREFIX_ALT = "D4"

local frame = CreateFrame("Frame")
C_ChatInfo.RegisterAddonMessagePrefix(ADDON_PREFIX)
C_ChatInfo.RegisterAddonMessagePrefix(BIGWIGS_PREFIX)
C_ChatInfo.RegisterAddonMessagePrefix(DBM_PREFIX)
C_ChatInfo.RegisterAddonMessagePrefix(DBM_PREFIX_ALT)

local DEFAULT_PULL = 10
local memes = MentionedMedia.BreakMemes

local InFight = C_InstanceEncounter and C_InstanceEncounter.IsEncounterInProgress or IsEncounterInProgress

local activeTimer = nil
local activeBreak = nil
local memeHideTimer = nil
local breakDragActive = false

-- ------------------------
-- SavedVariables Init
-- ------------------------
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
-- ------------------------
-- Create BigWigs-Style Bar
-- ------------------------
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




-- Define two textures (replace with your own files in addon folder)
local textures = {
    "Interface\\AddOns\\SavCat\\catleft.tga",
    "Interface\\AddOns\\SavCat\\catright.tga"
}

-- ------------------------
-- Voice Countdown Sounds (5 → 1)
-- ------------------------


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
    elseif (MentionedUtilsDB and MentionedUtilsDB.countDownChoice == 2) then
        PlaySoundFile(countdownSounds[sec], "Master")
    else
        PlaySoundFile(countdownSounds[sec], "Master")
    end
end

local function GetMemeCount()
    return MentionedMedia and MentionedMedia.BreakMemes and #MentionedMedia.BreakMemes or 0
end

local function GetDeterministicMemeIndex(seconds, sender)
    local memeCount = GetMemeCount()
    if memeCount <= 0 then
        return nil
    end

    local key = string.format("%s:%s", tostring(sender or ""), tostring(tonumber(seconds) or 0))
    local hash = 0

    for i = 1, #key do
        hash = (hash * 33 + key:byte(i)) % 2147483647
    end

    return (hash % memeCount) + 1
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

-- ------------------------
-- Pull Timer Logic
-- ------------------------
local function StartPullTimer(seconds, sender)
    -- C_PartyInfo:DoCountdown(10)
    -- if true then return end 
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
            --pullBar.timeText:SetText("PULL!")
            C_Timer.After(1, function() pullBar:Hide() end)
            ticker:Cancel()
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


function ShowRandomMeme(duration, index)
    local memes = MentionedMedia.BreakMemes
    if not memes or #memes == 0 then return end

    local meme = memes[index]
    if not meme then return end

    local path, width, height = meme[1], meme[2], meme[3]

       -- Cancel previous hide timer
    if memeHideTimer then
        memeHideTimer:Cancel()
        memeHideTimer = nil
    end


    -- Set size & position
    localFrame:SetSize(width, height)
    ApplyBreakFramePosition()
    -- Set texture
    localFrame.texture:SetTexture(path)

    -- Show it
    localFrame:Show()

    -- Start new hide timer
    memeHideTimer = C_Timer.NewTimer(duration, function()
        print("Hiding meme after break.")
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



-- -------------------------
-- Break Logic 
-- -------------------------
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
        index = GetDeterministicMemeIndex(seconds, sender)
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

local originalPullSlash = nil
local function MentionedPullSlashOverride(input)
    if not originalPullSlash then return end

    local trimmed = input and input:match("^%s*(.-)%s*$") or ""
    if trimmed == "" then
        local seconds = (MentionedUtilsDB and MentionedUtilsDB.defaultTime) or DEFAULT_PULL
        originalPullSlash(tostring(seconds))
        return
    end

    originalPullSlash(input)
end

local function OverridePullSlashDirect()
    if not SlashCmdList or type(SlashCmdList.pull) ~= "function" then
        return
    end

    if SlashCmdList.pull ~= MentionedPullSlashOverride then
        originalPullSlash = SlashCmdList.pull
        SlashCmdList.pull = MentionedPullSlashOverride
    end
end

local function RegisterBigWigsPullOverride()
    if not BigWigsAPI or not BigWigsAPI.RegisterSlashCommand or not BigWigsLoader or not BigWigs then
        return
    end

    local InChatMessagingLockdown = C_ChatInfo.InChatMessagingLockdown or function() return false end
    local L = BigWigsAPI:GetLocale("BigWigs")

    BigWigsAPI.RegisterSlashCommand("/pull", function(input)
        if InFight() or InChatMessagingLockdown() then
            BigWigs:Print(L.encounterRestricted)
            return
        end

        if not IsInGroup() or (IsInGroup(2) and UnitGroupRolesAssigned("player") == "TANK") or UnitIsGroupLeader("player") or UnitIsGroupAssistant("player") or (IsInGroup(1) and not IsInRaid()) then
            if not BigWigs:IsEnabled() then
                BigWigs:Enable()
            end

            local seconds
            if input == "" then
                seconds = (MentionedUtilsDB and MentionedUtilsDB.defaultTime) or DEFAULT_PULL
            else
                seconds = tonumber(input)
                if not seconds or seconds < 0 or seconds > 86400 then
                    BigWigs:Print(L.wrongPullFormat)
                    return
                end
            end

            if seconds ~= 0 then
                BigWigs:Print(L.sendPull)
            end
            BigWigsLoader.DoCountdown(seconds)
        else
            BigWigs:Print(L.requiresLeadOrAssist)
        end
    end, true)

    OverridePullSlashDirect()
end






-- -------------------------
-- Slash Commands
-- ------------------------
SLASH_MENTIONEDUTILSCONFIG1 = "/muc"
SlashCmdList["MENTIONEDUTILSCONFIG"] = function(msg)
    local cmd, rest = msg:match("^(%S*)%s*(.*)$")
    if cmd == "pulltimer" and rest ~= "" then
        MentionedUtilsDB = MentionedUtilsDB or {}
        local seconds = tonumber(rest)
        if not seconds or seconds <= 0 then
            print("Invalid time. Please enter a positive number.")
            return
        end
        MentionedUtilsDB.defaultTime = seconds
        print("Default pull timer set to " .. seconds .. " seconds for /mpull and /pull.")
    elseif cmd == "countdownsound" and rest ~= "" then
        MentionedUtilsDB = MentionedUtilsDB or {}
        local choice = tonumber(rest)
        if choice ~= 1 and choice ~= 2 then
            print("Invalid choice. Please enter 1 for Leeroy or 2 for Robo (default) countdown.")
            return
        end
        MentionedUtilsDB.countDownChoice = choice
        print("Countdown sound set to " .. (choice == 1 and "Leeroy" or "Robo") .. ".")
    else
        print("Usage:")
        print("/muc pulltimer <seconds> - Set default pull timer duration for /pull and /mpull.")
        print("/muc countdownsound <1 or 2> - Set countdown sound (1 for Leeroy, 2 for Robo).")
    end
end




SLASH_MENTIONEDBREAKDEFAULT1 = "/break"
SlashCmdList["MENTIONEDBREAKDEFAULT"] = function(msg)
	if InFight() then return end 
	if not IsInGroup() or UnitIsGroupLeader("player") or UnitIsGroupAssistant("player") then -- Solo or leader/assist
		local minutes = tonumber(msg)
		if not minutes or minutes < 0 or minutes > 60 or (minutes > 0 and minutes < 1) then return end

        if minutes == 0 then
            CancelBreak()
            C_ChatInfo.SendAddonMessage(ADDON_PREFIX, "CANCEL_BREAK", IsInGroup(2) and "INSTANCE_CHAT" or "RAID")
            return
        end

		if minutes ~= 0 then
			print("Starting break timer for " .. minutes .. " minute(s).")
		end
		local seconds = minutes * 60
        local selectedIndex = PickRandomMemeIndex()
        StartBreakTimer(seconds, UnitName("player"), selectedIndex)
		
		if IsInGroup() then
            C_ChatInfo.SendAddonMessage(ADDON_PREFIX, ("BI\t%d\t%d"):format(selectedIndex or 0, seconds), IsInGroup(2) and "INSTANCE_CHAT" or "RAID")
		end
	end
end

SLASH_MENTIONEDUTILSTESTMEME1 = "/mutestmeme"
SLASH_MENTIONEDUTILSTESTMEME2 = "/mumeme"
SlashCmdList["MENTIONEDUTILSTESTMEME"] = function(msg)
    local selection, rest = msg:match("^(%S+)%s*(.*)$")

    if not selection or selection == "" then
        print("Usage: /mutestmeme <index|name|list> [seconds]")
        return
    end

    if selection:lower() == "list" then
        local memeCount = GetMemeCount()
        print("MentionedUtils memes:")
        for i = 1, memeCount do
            local name = GetMemeDisplayName(i) or ("meme" .. i)
            print(i .. ". " .. name)
        end
        return
    end

    local index = ResolveMemeIndex(selection)
    if not index then
        print("Meme not found. Use /mutestmeme list to see available choices.")
        return
    end

    local seconds = tonumber(rest)
    if not seconds or seconds <= 0 then
        seconds = 8
    end

    local channel = nil
    if IsInGroup(2) then
        channel = "INSTANCE_CHAT"
    elseif IsInRaid() then
        channel = "RAID"
    elseif IsInGroup() then
        channel = "PARTY"
    end

    local myName = UnitName("player")
    print(("Sending test meme #%d (%s) for %d second(s).")
        :format(index, GetMemeDisplayName(index) or "unknown", seconds))

    HandleIncomingTestMeme(seconds, myName, index)

    if channel then
        C_ChatInfo.SendAddonMessage(ADDON_PREFIX, ("TM\t%d\t%d"):format(index, seconds), channel)
    end
end



-- ------------------------
-- Event Handling
-- ------------------------
frame:RegisterEvent("CHAT_MSG_ADDON")

frame:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        local addonName = ...
        if addonName == "BigWigs" or addonName == "BigWigs_Plugins" then
            RegisterBigWigsPullOverride()
            OverridePullSlashDirect()
            return
        end

        if addonName ~= ADDON_NAME then return end

        -- Initialize SavedVariables safely
        MentionedUtilsDB = MentionedUtilsDB or {}

        -- Defaults (only set if missing)
        if MentionedUtilsDB.defaultTime == nil then
            MentionedUtilsDB.defaultTime = DEFAULT_PULL
        end

        if MentionedUtilsDB.countDownChoice == nil then
            MentionedUtilsDB.countDownChoice = 2
        end

        MentionedUtilsDB.breakFramePosition = MentionedUtilsDB.breakFramePosition or {
            x = math.floor(UIParent:GetWidth() / 6),
            y = 0,
        }

        ApplyBreakFramePosition()

        print("Mentioned Utils loaded.")
        return
    end

    if event == "PLAYER_LOGIN" then
        RegisterBigWigsPullOverride()
        OverridePullSlashDirect()
        return
    end

    if event == "CHAT_MSG_ADDON" then
        local prefix, message, channel, sender = ...

        -- Handle BigWigs break formats.
        -- Common format: P^Break^<seconds>
        -- Tolerated variants: Break^<seconds> and fallback shapes.
        if prefix == BIGWIGS_PREFIX then
            local bwPrefix, bwMsg, extra = strsplit("^", message)
            local seconds = nil

            if bwPrefix == "P" and bwMsg == "Break" then
                seconds = extra
            elseif bwPrefix == "Break" then
                seconds = bwMsg
            elseif bwMsg == "Break" then
                seconds = extra
            end

            if seconds then
                HandleIncomingBreak(seconds, sender)
            end
            return
        end

        -- Handle DBM break format: <name-realm>\t1\tBT\t<seconds>
        if prefix == DBM_PREFIX or prefix == DBM_PREFIX_ALT then
            local _, _, subPrefix, seconds = strsplit("\t", message)
            if subPrefix == "BT" and seconds then
                HandleIncomingBreak(seconds, sender, nil)
            elseif message:find("\tBT\t") then
                local _, _, _, fallbackSeconds = strsplit("\t", message)
                HandleIncomingBreak(fallbackSeconds, sender, nil)
            end
            return
        end

        -- Ignore other prefixes
        if prefix ~= ADDON_PREFIX then return end

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

        -- Backward-compatibility with legacy generic cancel payload.
        if message == "CANCEL" then
            CancelPull()
            CancelBreak()
            PlaySoundFile("Interface\\AddOns\\MentionedUtils\\Sounds\\cancel.mp3", "Master")
            return
        end

        -- Handle DBM-style break payload sent on our own prefix: <name-realm>\t1\tBT\t<seconds>
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
    end
end)