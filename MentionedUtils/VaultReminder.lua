local addonName = ...
local Addon = _G[addonName] or {}
_G[addonName] = Addon

local VAULT_SPELL_ID = 1271478
local vaultFrame

local function GetCurrentLootSpec()
    local lootSpecID = 0
    if C_SpecializationInfo and C_SpecializationInfo.GetLootSpecialization then
        lootSpecID = C_SpecializationInfo.GetLootSpecialization() or 0
    elseif GetLootSpecialization then
        lootSpecID = GetLootSpecialization() or 0
    end

    local specID = lootSpecID
    if not specID or specID == 0 then
        local specializationIndex = GetSpecialization and GetSpecialization()
        if specializationIndex and specializationIndex > 0 and GetSpecializationInfo then
            specID = GetSpecializationInfo(specializationIndex)
        end
    end

    if not specID or specID == 0 or not GetSpecializationInfoByID then
        return nil, nil
    end

    local _, name, _, icon = GetSpecializationInfoByID(specID)
    return name, icon
end

local function HideVaultReminder()
    if vaultFrame then
        vaultFrame:Hide()
    end
end

local function RefreshVaultReminder()
    local lootSpecName, lootSpecIcon = GetCurrentLootSpec()
    if lootSpecName and lootSpecIcon then
        vaultFrame.specName:SetText(lootSpecName)
        vaultFrame.specIcon:SetTexture(lootSpecIcon)
        vaultFrame.specIcon:Show()
    else
        vaultFrame.specName:SetText("Unavailable")
        vaultFrame.specIcon:Hide()
    end
end

local function ShowVaultReminder()
    if not vaultFrame then
        vaultFrame = CreateFrame("Frame", "MentionedUtilsVaultReminder", UIParent, "BackdropTemplate")
        vaultFrame:SetSize(560, 230)
        vaultFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 180)
        vaultFrame:SetFrameStrata("TOOLTIP")
        vaultFrame:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = 2,
            insets = { left = 2, right = 2, top = 2, bottom = 2 },
        })
        vaultFrame:SetBackdropColor(0.03, 0.03, 0.03, 0.96)
        vaultFrame:SetBackdropBorderColor(1, 0.82, 0, 1)

        local closeButton = CreateFrame("Button", nil, vaultFrame, "UIPanelCloseButton")
        closeButton:SetSize(24, 24)
        closeButton:SetPoint("TOPRIGHT", -2, -2)
        closeButton:SetScript("OnClick", HideVaultReminder)

        vaultFrame.title = vaultFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        vaultFrame.title:SetPoint("TOP", 0, -18)
        vaultFrame.title:SetText("Weekly Vault Loot Spec")
        vaultFrame.title:SetTextColor(1, 0.82, 0, 1)

        vaultFrame.specIcon = vaultFrame:CreateTexture(nil, "ARTWORK")
        vaultFrame.specIcon:SetSize(48, 48)
        vaultFrame.specIcon:SetPoint("TOP", vaultFrame.title, "BOTTOM", 0, -14)

        vaultFrame.specName = vaultFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        vaultFrame.specName:SetPoint("TOP", vaultFrame.specIcon, "BOTTOM", 0, -10)
        vaultFrame.specName:SetWidth(520)
        vaultFrame.specName:SetJustifyH("CENTER")
        local fontPath, _, fontFlags = vaultFrame.specName:GetFont()
        if fontPath then
            vaultFrame.specName:SetFont(fontPath, 36, fontFlags)
        end
    end

    RefreshVaultReminder()
    vaultFrame:Show()
    PlaySound(SOUNDKIT and SOUNDKIT.RAID_WARNING or 8959, "Master")
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_START", "player")
eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_FAILED", "player")
eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_INTERRUPTED", "player")
eventFrame:SetScript("OnEvent", function(_, event, _, _, spellID)
    if event == "UNIT_SPELLCAST_START" then
        if spellID ~= VAULT_SPELL_ID then return
        end
        ShowVaultReminder()
    elseif event == "UNIT_SPELLCAST_FAILED" or event == "UNIT_SPELLCAST_INTERRUPTED" then
        if spellID ~= VAULT_SPELL_ID then return
        end
        HideVaultReminder()
    end
end)