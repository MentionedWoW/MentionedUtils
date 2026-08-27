local addonName = ...
local Addon = _G[addonName] or {}
_G[addonName] = Addon

local ADDON_NAME = "MentionedUtils"
local ADDON_PREFIX = "MENTIONED_UTILS"
local BIGWIGS_PREFIX = "BigWigs"
local DBM_PREFIX = "D5"
local DBM_PREFIX_ALT = "D4"
local DEFAULT_PULL = 10

Addon.ADDON_NAME = ADDON_NAME
Addon.ADDON_PREFIX = ADDON_PREFIX
Addon.BIGWIGS_PREFIX = BIGWIGS_PREFIX
Addon.DBM_PREFIX = DBM_PREFIX
Addon.DBM_PREFIX_ALT = DBM_PREFIX_ALT
Addon.DEFAULT_PULL = DEFAULT_PULL

local frame = CreateFrame("Frame")

C_ChatInfo.RegisterAddonMessagePrefix(ADDON_PREFIX)
C_ChatInfo.RegisterAddonMessagePrefix(BIGWIGS_PREFIX)
C_ChatInfo.RegisterAddonMessagePrefix(DBM_PREFIX)
C_ChatInfo.RegisterAddonMessagePrefix(DBM_PREFIX_ALT)

local function EnsureDatabase()
    MentionedUtilsDB = MentionedUtilsDB or {}

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

    if MentionedUtilsDB.breakFrameScale == nil then
        MentionedUtilsDB.breakFrameScale = 1
    end

    return MentionedUtilsDB
end

local function GetDefaultPullSeconds()
    return (MentionedUtilsDB and MentionedUtilsDB.defaultTime) or DEFAULT_PULL
end

local originalPullSlash = nil
local function MentionedPullSlashOverride(input)
    if not originalPullSlash then return end

    local inputText = tostring(input or "")
    local trimmed = inputText:match("^%s*(.-)%s*$")
    if trimmed == "" then
        originalPullSlash(tostring(GetDefaultPullSeconds()))
        return
    end

    originalPullSlash(inputText)
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
    local InFight = C_InstanceEncounter and C_InstanceEncounter.IsEncounterInProgress or IsEncounterInProgress
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
                seconds = GetDefaultPullSeconds()
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

SLASH_MENTIONEDUTILSCONFIG1 = "/muc"
SlashCmdList["MENTIONEDUTILSCONFIG"] = function(msg)
    local cmd, rest = msg:match("^(%S*)%s*(.*)$")
    if cmd == "pulltimer" and rest ~= "" then
        local db = EnsureDatabase()
        local seconds = tonumber(rest)
        if not seconds or seconds <= 0 then
            print("Invalid time. Please enter a positive number.")
            return
        end
        db.defaultTime = seconds
        print("Default pull timer set to " .. seconds .. " seconds for /mpull and /pull.")
    elseif cmd == "countdownsound" and rest ~= "" then
        local db = EnsureDatabase()
        local choice = tonumber(rest)
        if choice ~= 1 and choice ~= 2 then
            print("Invalid choice. Please enter 1 for Leeroy or 2 for Robo (default) countdown.")
            return
        end
        db.countDownChoice = choice
        print("Countdown sound set to " .. (choice == 1 and "Leeroy" or "Robo") .. ".")
    elseif cmd == "upgradewarning" and rest ~= "" then
        local setting = rest:lower()
        if setting ~= "on" and setting ~= "off" then
            print("Invalid choice. Please enter on or off.")
            return
        end

        if Addon.SetUpgradeWarningEnabled then
            Addon:SetUpgradeWarningEnabled(setting == "on")
        else
            local db = EnsureDatabase()
            db.upgradeWarnDisabled = (setting == "off") or nil
        end

        print("Upgrade warning " .. (setting == "on" and "enabled" or "disabled") .. ".")
    else
        print("Usage:")
        print("/muc pulltimer <seconds> - Set default pull timer duration for /pull and /mpull.")
        print("/muc countdownsound <1 or 2> - Set countdown sound (1 for Leeroy, 2 for Robo).")
        print("/muc upgradewarning <on or off> - Enable or disable the upgrade warning notification.")
    end
end

SLASH_MENTIONEDBREAKDEFAULT1 = "/break"
SlashCmdList["MENTIONEDBREAKDEFAULT"] = function(msg)
    if not Addon.StartBreakTimer or not Addon.PickRandomMemeIndex or not Addon.CancelBreak then
        return
    end

    local InFight = C_InstanceEncounter and C_InstanceEncounter.IsEncounterInProgress or IsEncounterInProgress
    if InFight() then return end

    if not IsInGroup() or UnitIsGroupLeader("player") or UnitIsGroupAssistant("player") then
        local minutes = tonumber(msg)
        if not minutes or minutes < 0 or minutes > 60 or (minutes > 0 and minutes < 1) then return end

        if minutes == 0 then
            Addon.CancelBreak()
            C_ChatInfo.SendAddonMessage(ADDON_PREFIX, "CANCEL_BREAK", IsInGroup(2) and "INSTANCE_CHAT" or "RAID")
            return
        end

        print("Starting break timer for " .. minutes .. " minute(s).")

        local seconds = minutes * 60
        local selectedIndex = Addon.PickRandomMemeIndex()
        Addon.StartBreakTimer(seconds, UnitName("player"), selectedIndex)

        if IsInGroup() then
            C_ChatInfo.SendAddonMessage(ADDON_PREFIX, ("BI\t%d\t%d"):format(selectedIndex or 0, seconds), IsInGroup(2) and "INSTANCE_CHAT" or "RAID")
        end
    end
end

SLASH_MENTIONEDUTILSTESTMEME1 = "/mutestmeme"
SLASH_MENTIONEDUTILSTESTMEME2 = "/mumeme"
SlashCmdList["MENTIONEDUTILSTESTMEME"] = function(msg)
    if not Addon.ResolveMemeIndex or not Addon.GetMemeCount or not Addon.GetMemeDisplayName or not Addon.HandleIncomingTestMeme then
        return
    end

    local selection, rest = msg:match("^(%S+)%s*(.*)$")

    if not selection or selection == "" then
        print("Usage: /mutestmeme <index|name|list> [seconds]")
        return
    end

    if selection:lower() == "list" then
        local memeCount = Addon.GetMemeCount()
        print("MentionedUtils memes:")
        for i = 1, memeCount do
            local name = Addon.GetMemeDisplayName(i) or ("meme" .. i)
            print(i .. ". " .. name)
        end
        return
    end

    local index = Addon.ResolveMemeIndex(selection)
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
        :format(index, Addon.GetMemeDisplayName(index) or "unknown", seconds))

    Addon.HandleIncomingTestMeme(seconds, myName, index)

    if channel then
        C_ChatInfo.SendAddonMessage(ADDON_PREFIX, ("TM\t%d\t%d"):format(index, seconds), channel)
    end
end

frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")

frame:SetScript("OnEvent", function(_, event, ...)
    if event == "ADDON_LOADED" then
        local loadedAddon = ...

        if loadedAddon == "BigWigs" or loadedAddon == "BigWigs_Plugins" then
            RegisterBigWigsPullOverride()
            OverridePullSlashDirect()
            return
        end

        if loadedAddon ~= ADDON_NAME then return end

        EnsureDatabase()

        if Addon.ApplyBreakFramePosition then
            Addon.ApplyBreakFramePosition()
        end

        print("Mentioned Utils loaded.")
        return
    end

    if event == "PLAYER_LOGIN" then
        RegisterBigWigsPullOverride()
        OverridePullSlashDirect()
        return
    end
end)