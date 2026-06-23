local ADDON_NAME = "Mentioned Utils"
local ADDON_PREFIX = "MENTIONED_UTILS"
local BIGWIGS_PREFIX = "BigWigs"
local DBM_PREFIX = "D5"

local frame = CreateFrame("Frame")
C_ChatInfo.RegisterAddonMessagePrefix(ADDON_PREFIX)
C_ChatInfo.RegisterAddonMessagePrefix(BIGWIGS_PREFIX)
C_ChatInfo.RegisterAddonMessagePrefix(DBM_PREFIX)

local DEFAULT_PULL = 10
local memes = MentionedMedia.BreakMemes

local InFight = C_InstanceEncounter and C_InstanceEncounter.IsEncounterInProgress or IsEncounterInProgress

local activeTimer = nil
local activeBreak = nil
local memeHideTimer = nil
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

-- Default settings
local defaults = {
    width = 128,
    height = 128,
    x = 0,
    y = 0,
}

SavCatDB = SavCatDB or {}

-- Merge defaults into saved variables
local function InitSettings()
    for k, v in pairs(defaults) do
        if SavCatDB[k] == nil then
            SavCatDB[k] = v
        end
    end
end

local function ApplySettings()
    localFrame:SetSize(SavCatDB.width, SavCatDB.height)
    localFrame:ClearAllPoints()
    localFrame:SetPoint("CENTER", UIParent, "CENTER", SavCatDB.x, SavCatDB.y)
end

localFrame.texture = localFrame:CreateTexture(nil, "BACKGROUND")
localFrame.texture:SetAllPoints(localFrame)




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

local function PlayVoiceCountdown(sec)
    if (MentionedUtilsDB and MentionedUtilsDB.countDownChoice == 1 and sec == 3) then
        PlaySoundFile("Interface\\AddOns\\MentionedUtils\\Sounds\\leeroy.mp3", "Master") 
    elseif (MentionedUtilsDB and MentionedUtilsDB.countDownChoice == 2) then
        PlaySoundFile(countdownSounds[sec], "Master")
    else
        PlaySoundFile(countdownSounds[sec], "Master")
    end
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
    localFrame:ClearAllPoints()
    localFrame:SetPoint("CENTER", UIParent, "CENTER", UIParent:GetWidth() / 6, 0)
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


    PlaySoundFile("Interface\\AddOns\\MentionedUtils\\Sounds\\dingding.mp3", "Master")
    activeBreak = C_Timer.NewTicker(0.1, function(ticker)
        remaining = (remaining or 0) - 0.1
        if remaining <= 0 then
            ticker:Cancel()
            return
        end
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
    print("Break timer cancelled.")
end

local function HandleIncomingBreak(seconds, sender)
    seconds = tonumber(seconds)
    if seconds == 0 then
        CancelBreak()
        return
    end
    if not seconds or seconds < 0 then
        return
    end
    local memeCount = MentionedMedia and MentionedMedia.BreakMemes and #MentionedMedia.BreakMemes or 0
    local index = memeCount > 0 and math.random(1, memeCount) or nil
    StartBreakTimer(seconds, sender, index)
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
            C_ChatInfo.SendAddonMessage(ADDON_PREFIX, "CANCEL", IsInGroup(2) and "INSTANCE_CHAT" or "RAID")
            return
        end

		if minutes ~= 0 then
			print("Starting break timer for " .. minutes .. " minute(s).")
		end
		local seconds = minutes * 60
		
		if IsInGroup() then
			local name = UnitName("player")
			local realm = GetRealmName()
			local normalizedPlayerRealm = realm:gsub("[%s-]+", "") -- Has to mimic DBM code
			local result =  C_ChatInfo.SendAddonMessage(ADDON_PREFIX, ("%s-%s\t1\tBT\t%d"):format(name, normalizedPlayerRealm, seconds), IsInGroup(2) and "INSTANCE_CHAT" or "RAID") -- DBM message
		
		end
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

        -- Handle BigWigs break: P^Break^<seconds>
        if prefix == BIGWIGS_PREFIX then
            local bwPrefix, bwMsg, extra = strsplit("^", message)
            if bwPrefix == "P" and bwMsg == "Break" then
                HandleIncomingBreak(extra, sender)
            end
            return
        end

        -- Handle DBM break format: <name-realm>\t1\tBT\t<seconds>
        if prefix == DBM_PREFIX then
            if message:find("\tBT\t") then
                local _, _, _, seconds = strsplit("\t", message)
                HandleIncomingBreak(seconds, sender)
            end
            return
        end

        -- Ignore other prefixes
        if prefix ~= ADDON_PREFIX then return end

        if message == "CANCEL" then
            CancelPull()
            CancelBreak()
            PlaySoundFile("Interface\\AddOns\\MentionedUtils\\Sounds\\cancel.mp3", "Master")
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
    end
end)