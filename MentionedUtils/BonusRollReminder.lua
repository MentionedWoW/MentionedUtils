local addonName = ...
local Addon = _G[addonName] or {}
_G[addonName] = Addon

local ADDON_NAME = "MentionedUtils"
local REMINDER_DURATION = 5
local SETTINGS_WIDTH = 360
local SETTINGS_HEIGHT = 400
local DEBUG_TEST_ENCOUNTER_ID = 999999

local bosses = {
    { name = "Nek'zali the Soulcoiler", instance = "The Venomous Abyss" },
    { name = "Entombed Sentinels", instance = "The Venomous Abyss" },
    { name = "The Lost Explorers", instance = "The Venomous Abyss" },
    { name = "Vashnik the Malignant", instance = "The Venomous Abyss" },
    { name = "Sszorak", instance = "The Venomous Abyss" },
    { name = "The Twin Fangs", instance = "The Venomous Abyss" },
    { name = "The Coiled Altar", instance = "The Venomous Abyss" },
    { name = "Ula'tek", instance = "The Venomous Abyss" },
    { name = "Nymrissa Wavecaller", instance = "The Tidebound Grotto" },
    { name = "Debug Test Boss", encounterID = DEBUG_TEST_ENCOUNTER_ID, debug = true },
}

Addon.BonusRollReminderBosses = bosses

local eventFrame = CreateFrame("Frame")
local settingsFrame
local reminderFrame
local reminderTimer
local slashCommandWrapped = false

local function EnsureDatabase()
    MentionedUtilsDB = MentionedUtilsDB or {}
    if MentionedUtilsDB.bonusRollReminderDebugID == nil then
        MentionedUtilsDB.bonusRollReminderDebugID = DEBUG_TEST_ENCOUNTER_ID
    end
    if MentionedUtilsDB.bonusRollReminderDebug == nil then
        MentionedUtilsDB.bonusRollReminderDebug = false
    end
    return MentionedUtilsDB
end

local function IsDebugModeEnabled()
    return EnsureDatabase().bonusRollReminderDebug == true
end

local function SetDebugModeEnabled(enabled)
    EnsureDatabase().bonusRollReminderDebug = enabled and true or false
    if settingsFrame and settingsFrame.debugCheck then
        settingsFrame.debugCheck:SetChecked(enabled)
    end
end

local function GetDebugEncounterID()
    local encounterID = tonumber(EnsureDatabase().bonusRollReminderDebugID)
    if not encounterID or encounterID < 1 then
        return DEBUG_TEST_ENCOUNTER_ID
    end
    return math.floor(encounterID)
end

local function SetDebugEncounterID(value)
    local encounterID = tonumber(value)
    if not encounterID or encounterID < 1 then
        return false
    end

    EnsureDatabase().bonusRollReminderDebugID = math.floor(encounterID)
    return true
end

local function GetCurrentLootSpec()
    local lootSpecID = 0
    if C_SpecializationInfo and C_SpecializationInfo.GetLootSpecialization then
        lootSpecID = C_SpecializationInfo.GetLootSpecialization() or 0
    elseif GetLootSpecialization then
        lootSpecID = GetLootSpecialization() or 0
    end
    local specID = lootSpecID

    if not specID or specID == 0 then
        specID = GetSpecialization and GetSpecialization()
        if specID and specID > 0 and GetSpecializationInfo then
            specID = GetSpecializationInfo(specID)
        end
    end

    if not specID or specID == 0 or not GetSpecializationInfoByID then
        return nil, nil
    end

    local _, name, _, icon = GetSpecializationInfoByID(specID)
    return name, icon
end

local function GetSelectedBoss()
    local selectedName = EnsureDatabase().bonusRollReminderBoss
    for _, boss in ipairs(bosses) do
        if boss.name == selectedName then
            return boss
        end
    end
    return nil
end

local function SetSelectedBoss(boss)
    EnsureDatabase().bonusRollReminderBoss = boss and boss.name or nil
end

local function HideReminder()
    if reminderTimer then
        reminderTimer:Cancel()
        reminderTimer = nil
    end
    if reminderFrame then
        reminderFrame:Hide()
    end
end

local function ShowReminder(bossName)
    if not reminderFrame then
        reminderFrame = CreateFrame("Frame", "MentionedUtilsBonusRollReminder", UIParent, "BackdropTemplate")
        reminderFrame:SetSize(440, 175)
        reminderFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 180)
        reminderFrame:SetFrameStrata("TOOLTIP")
        reminderFrame:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = 2,
            insets = { left = 2, right = 2, top = 2, bottom = 2 },
        })
        reminderFrame:SetBackdropColor(0.03, 0.03, 0.03, 0.96)
        reminderFrame:SetBackdropBorderColor(1, 0.82, 0, 1)

        reminderFrame.title = reminderFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        reminderFrame.title:SetPoint("TOP", 0, -14)
        reminderFrame.title:SetFontObject("GameFontNormalLarge")
        do
            local fontPath, _, fontFlags = reminderFrame.title:GetFont()
            if fontPath then
                reminderFrame.title:SetFont(fontPath, 22, fontFlags)
            end
        end
        reminderFrame.title:SetTextColor(1, 0.82, 0, 1)

        reminderFrame.lootSpecIcon = reminderFrame:CreateTexture(nil, "ARTWORK")
        reminderFrame.lootSpecIcon:SetSize(24, 24)
        reminderFrame.lootSpecIcon:SetPoint("TOP", reminderFrame.title, "BOTTOM", 0, -8)

        reminderFrame.lootSpecText = reminderFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        reminderFrame.lootSpecText:SetPoint("TOP", reminderFrame.lootSpecIcon, "BOTTOM", 0, -4)
        reminderFrame.lootSpecText:SetWidth(400)
        reminderFrame.lootSpecText:SetJustifyH("CENTER")
        do
            local fontPath, _, fontFlags = reminderFrame.lootSpecText:GetFont()
            if fontPath then
                reminderFrame.lootSpecText:SetFont(fontPath, 17, fontFlags)
            end
        end

        reminderFrame.message = reminderFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        reminderFrame.message:SetPoint("TOP", reminderFrame.lootSpecText, "BOTTOM", 0, -10)
        reminderFrame.message:SetWidth(400)
        reminderFrame.message:SetJustifyH("CENTER")
        do
            local fontPath, _, fontFlags = reminderFrame.message:GetFont()
            if fontPath then
                reminderFrame.message:SetFont(fontPath, 19, fontFlags)
            end
        end
        reminderFrame.message:SetText("Press Bonus Roll now!")
    end

    HideReminder()
    reminderFrame.title:SetText("Bonus roll: " .. bossName)
    local lootSpecName, lootSpecIcon = GetCurrentLootSpec()
    if lootSpecName and lootSpecIcon then
        reminderFrame.lootSpecText:SetText("Current Loot spec: " .. lootSpecName)
        reminderFrame.lootSpecIcon:SetTexture(lootSpecIcon)
        reminderFrame.lootSpecIcon:Show()
    else
        reminderFrame.lootSpecText:SetText("Loot spec: unavailable")
        reminderFrame.lootSpecIcon:Hide()
    end
    reminderFrame:Show()
    PlaySound(SOUNDKIT and SOUNDKIT.RAID_WARNING or 8959, "Master")
    reminderTimer = C_Timer.NewTimer(REMINDER_DURATION, HideReminder)
end

local function RefreshSettings()
    if not settingsFrame then return end

    local selected = GetSelectedBoss()
    for _, row in ipairs(settingsFrame.rows) do
        row:SetChecked(row.boss == selected)
        if row.debugIDBox then
            row.debugIDBox:SetText(tostring(GetDebugEncounterID()))
        end
    end

    if selected then
        settingsFrame.status:SetText("Reminder enabled for " .. selected.name)
    else
        settingsFrame.status:SetText("Select one boss to enable the reminder.")
    end
end

local function CreateSettingsFrame()
    settingsFrame = CreateFrame("Frame", "MentionedUtilsBonusRollReminderSettings", UIParent, "BackdropTemplate")
    settingsFrame:SetSize(SETTINGS_WIDTH, SETTINGS_HEIGHT)
    settingsFrame:SetPoint("CENTER")
    settingsFrame:SetFrameStrata("DIALOG")
    settingsFrame:SetMovable(true)
    settingsFrame:EnableMouse(true)
    settingsFrame:RegisterForDrag("LeftButton")
    settingsFrame:SetScript("OnDragStart", settingsFrame.StartMoving)
    settingsFrame:SetScript("OnDragStop", settingsFrame.StopMovingOrSizing)
    settingsFrame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 2,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    settingsFrame:SetBackdropColor(0.03, 0.03, 0.03, 0.97)
    settingsFrame:SetBackdropBorderColor(1, 0.82, 0, 1)

    local title = settingsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -16)
    title:SetText("Bonus Roll Reminder")
    title:SetTextColor(1, 0.82, 0, 1)

    local subtitle = settingsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    subtitle:SetPoint("TOP", title, "BOTTOM", 0, -8)
    subtitle:SetText("Choose the boss whose bonus roll you want to remember.")

    settingsFrame.rows = {}
    for index, boss in ipairs(bosses) do
        local row = CreateFrame("CheckButton", nil, settingsFrame, "UICheckButtonTemplate")
        row:SetPoint("TOPLEFT", 26, -70 - ((index - 1) * 25))
        row.boss = boss
        row.text:SetText(boss.name)
        row:SetScript("OnClick", function(self)
            SetSelectedBoss(self:GetChecked() and self.boss or nil)
            RefreshSettings()
        end)

        if boss.debug then
            row.text:SetText("Debug Test Boss ID:")

            local debugIDBox = CreateFrame("EditBox", nil, settingsFrame, "InputBoxTemplate")
            debugIDBox:SetSize(92, 22)
            debugIDBox:SetPoint("LEFT", row.text, "RIGHT", 8, 0)
            debugIDBox:SetAutoFocus(false)
            debugIDBox:SetNumeric(true)
            debugIDBox:SetMaxLetters(10)
            debugIDBox:SetText(tostring(GetDebugEncounterID()))
            debugIDBox:SetScript("OnEnterPressed", function(self)
                if not SetDebugEncounterID(self:GetText()) then
                    self:SetText(tostring(GetDebugEncounterID()))
                end
                self:ClearFocus()
            end)
            debugIDBox:SetScript("OnEditFocusLost", function(self)
                if not SetDebugEncounterID(self:GetText()) then
                    self:SetText(tostring(GetDebugEncounterID()))
                end
            end)
            debugIDBox:SetScript("OnEscapePressed", function(self)
                self:SetText(tostring(GetDebugEncounterID()))
                self:ClearFocus()
            end)
            row.debugIDBox = debugIDBox
        end

        settingsFrame.rows[index] = row
    end

    settingsFrame.status = settingsFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    settingsFrame.status:SetPoint("BOTTOM", 0, 18)
    settingsFrame.status:SetWidth(SETTINGS_WIDTH - 30)
    settingsFrame.status:SetJustifyH("CENTER")

    settingsFrame.debugCheck = CreateFrame("CheckButton", nil, settingsFrame, "UICheckButtonTemplate")
    settingsFrame.debugCheck:SetPoint("BOTTOMLEFT", 20, 42)
    settingsFrame.debugCheck.text:SetText("Print ENCOUNTER_END data")
    settingsFrame.debugCheck:SetChecked(IsDebugModeEnabled())
    settingsFrame.debugCheck:SetScript("OnClick", function(self)
        SetDebugModeEnabled(self:GetChecked())
    end)

    local close = CreateFrame("Button", nil, settingsFrame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -4, -4)
    settingsFrame:Hide()
    RefreshSettings()
end

local function ShowSettings()
    if not settingsFrame then
        CreateSettingsFrame()
    end
    RefreshSettings()
    settingsFrame:Show()
end

local function NormalizeName(value)
    return (value or ""):lower():gsub("[^%a%d]", "")
end

local function HandleEncounterEnd(encounterID, encounterName, difficultyID, groupSize, success)
    if IsDebugModeEnabled() then
        local lootSpecName, lootSpecIcon = GetCurrentLootSpec()
        print(("MentionedUtils ENCOUNTER_END: encounterID=%s, encounterName=%s, difficultyID=%s, groupSize=%s, success=%s")
            :format(
                tostring(encounterID),
                tostring(encounterName),
                tostring(difficultyID),
                tostring(groupSize),
                tostring(success)
            ))
        print(("MentionedUtils loot spec: name=%s, icon=%s")
            :format(tostring(lootSpecName or "unavailable"), tostring(lootSpecIcon or "unavailable")))
    end

    local selected = GetSelectedBoss()

    if success ~= 1 then return end

    if not selected then
        return
    end

    local matches = selected.debug and encounterID == GetDebugEncounterID()
    if not selected.debug then
        matches = selected.encounterID and encounterID == selected.encounterID
    end
    if not matches and not selected.encounterID then
        matches = NormalizeName(encounterName) == NormalizeName(selected.name)
    end

    if not matches then
        return
    end

    ShowReminder(selected.name)
end

local function TestEncounterFinish()
    local selected = GetSelectedBoss()
    if not selected then
        print("MentionedUtils: select a boss in /mu brr before running the test.")
        return
    end

    local encounterID = selected.debug and GetDebugEncounterID() or selected.encounterID
    local encounterName = selected.debug and selected.name or selected.name
    print("MentionedUtils: simulating a successful encounter finish for " .. selected.name .. ".")
    HandleEncounterEnd(encounterID, encounterName, 0, 1, 1)
end

local function RegisterSlashCommand()
    if slashCommandWrapped or not SlashCmdList then return end

    local previous = SlashCmdList["MENTIONEDUTILS"]
    SlashCmdList["MENTIONEDUTILS"] = function(msg)
        local command, rest = (msg or ""):match("^(%S*)%s*(.-)%s*$")
        if (command or ""):lower() == "brr" then
            local option = (rest or ""):lower()
            if option == "debug on" then
                SetDebugModeEnabled(true)
                print("MentionedUtils: ENCOUNTER_END debug mode enabled.")
            elseif option == "debug off" then
                SetDebugModeEnabled(false)
                print("MentionedUtils: ENCOUNTER_END debug mode disabled.")
            elseif option == "debug" or option == "debug status" then
                print("MentionedUtils: ENCOUNTER_END debug mode is " .. (IsDebugModeEnabled() and "ON" or "OFF") .. ".")
            elseif option == "test" then
                TestEncounterFinish()
            elseif option == "" then
                ShowSettings()
            else
                print("Usage: /mu brr [test|debug on|off|status]")
            end
            return
        end

        if previous then
            previous(msg)
        end
    end
    slashCommandWrapped = true
end

eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("ENCOUNTER_END")
eventFrame:SetScript("OnEvent", function(_, event, ...)
    if event == "ADDON_LOADED" then
        if ... == ADDON_NAME then
            EnsureDatabase()
            RegisterSlashCommand()
        end
        return
    end

    HandleEncounterEnd(...)
end)