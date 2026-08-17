-- Watches the item-upgrade UI and warns when a player is about to upgrade an
-- item that is still at rank 1 of its upgrade track.
local addonName = ...
local Addon = _G[addonName] or {}
_G[addonName] = Addon

local defaultLocale = {
    ILVLREF_CREST_ADV = "Adv",
    ILVLREF_CREST_VET = "Vet",
    ILVLREF_CREST_CHAMP = "Champ",
    ILVLREF_CREST_HERO = "Hero",
    ILVLREF_CREST_MYTH = "Myth",
    UPGRADE_WARN_TITLE = "Are you a retard?",
    UPGRADE_WARN_MSG = "Upgrading a 1/6 %s item is a waste of %d crests.\nYou should upgrade a 5/6 %s item instead or ask our chinese overlord if you are doing the right thing.",
}

Addon.L = Addon.L or {}
local L = Addon.L
for key, value in pairs(defaultLocale) do
    if L[key] == nil then
        L[key] = value
    end
end

Addon.VISUAL_STYLE = Addon.VISUAL_STYLE or {
    panelBorderA     = 0.70,
    popupBorderA     = 0.64,
    buttonBgA        = 0.34,
    buttonBorderA    = 0.40,
    buttonHighlightA = 0.08,
    dividerA         = 0.16,
    strongDividerA   = 0.28,
    textShadowA      = 0.75,
}

Addon.THEME = Addon.THEME or {
    bg = { r = 0.08, g = 0.08, b = 0.08, a = 0.96 },
    border = { r = 1.00, g = 0.82, b = 0.00, a = 1 },
    header = { r = 1.00, g = 0.82, b = 0.00, a = 1 },
    text = { r = 1.00, g = 1.00, b = 1.00, a = 1 },
}

local AddonUtils = Addon.AddonUtils or {}
Addon.AddonUtils = AddonUtils

function AddonUtils.SetTooltip(frame, text, anchor)
    GameTooltip:SetOwner(frame, anchor or "ANCHOR_RIGHT")
    GameTooltip:SetText(text, 1, 1, 1, 1, true)
    GameTooltip:Show()
end

function AddonUtils.HideTooltip()
    GameTooltip:Hide()
end

local Controls = Addon.Controls or {}
Addon.Controls = Controls

local BACKDROP_DEF = {
    bgFile = "Interface\\Buttons\\WHITE8x8",
    edgeFile = "Interface\\Buttons\\WHITE8x8",
    tile = false,
    edgeSize = 1,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
}

function Addon:ApplyTheme(frameObj)
    if not frameObj then return end
    if not frameObj.SetBackdrop and BackdropTemplateMixin and Mixin then
        Mixin(frameObj, BackdropTemplateMixin)
    end
    if not frameObj.SetBackdrop then return end

    local theme = self.THEME or {}
    local vs = self.VISUAL_STYLE or {}
    local bg = theme.bg or { r = 0, g = 0, b = 0, a = 1 }
    local border = theme.border or { r = 1, g = 1, b = 1, a = 1 }
    local borderA = math.min(tonumber(border.a) or 1, tonumber(vs.panelBorderA) or 1)

    frameObj:SetBackdrop(BACKDROP_DEF)
    frameObj:SetBackdropColor(bg.r, bg.g, bg.b, bg.a or 1)
    frameObj:SetBackdropBorderColor(border.r, border.g, border.b, borderA)
end

function Addon:NewThemedFrame(name, parent)
    local frameObj
    if BackdropTemplateMixin then
        frameObj = CreateFrame("Frame", name, parent or UIParent, "BackdropTemplate")
    else
        frameObj = CreateFrame("Frame", name, parent or UIParent)
    end
    self:ApplyTheme(frameObj)
    return frameObj
end

function Addon:ApplyPopupBorder(frameObj)
    if not frameObj or not frameObj.SetBackdropBorderColor then return end
    local border = self.THEME and self.THEME.border
    if not border then return end
    local vs = self.VISUAL_STYLE or {}
    frameObj:SetBackdropBorderColor(border.r, border.g, border.b, vs.popupBorderA or border.a or 1)
end

function Addon:ApplyOpaquePopupTheme(frameObj)
    if not frameObj then return end
    self:ApplyTheme(frameObj)
    self:ApplyPopupBorder(frameObj)
    local bg = self.THEME and self.THEME.bg
    if bg and frameObj.SetBackdropColor then
        frameObj:SetBackdropColor(bg.r, bg.g, bg.b, 1)
    end
end

function Addon:ApplyWarningPanelTheme(frameObj, opts)
    if not frameObj then return 48 end
    opts = opts or {}

    self:ApplyOpaquePopupTheme(frameObj)

    local hdr = self.THEME and self.THEME.header or { r = 1, g = 0.82, b = 0, a = 1 }
    local txt = self.THEME and self.THEME.text or { r = 1, g = 1, b = 1, a = 1 }
    local vs = self.VISUAL_STYLE or {}
    local pad = tonumber(opts.pad) or 14
    local titleTop = tonumber(opts.titleTop) or 11
    local bodyTop = tonumber(opts.bodyTop) or 50

    if not frameObj._lariasWarnHeaderGlow and frameObj.CreateTexture then
        local glow = frameObj:CreateTexture(nil, "ARTWORK", nil, 0)
        glow:SetPoint("TOPLEFT", frameObj, "TOPLEFT", 0, 0)
        glow:SetPoint("TOPRIGHT", frameObj, "TOPRIGHT", 0, 0)
        glow:SetHeight(3)
        frameObj._lariasWarnHeaderGlow = glow
    end
    if frameObj._lariasWarnHeaderGlow then
        frameObj._lariasWarnHeaderGlow:SetColorTexture(hdr.r, hdr.g, hdr.b, vs.strongDividerA or 0.45)
    end

    if not frameObj._lariasWarnHeaderFill and frameObj.CreateTexture then
        local fill = frameObj:CreateTexture(nil, "BACKGROUND", nil, 1)
        fill:SetPoint("TOPLEFT", frameObj, "TOPLEFT", 1, -1)
        fill:SetPoint("TOPRIGHT", frameObj, "TOPRIGHT", -1, -1)
        fill:SetHeight(bodyTop - 10)
        frameObj._lariasWarnHeaderFill = fill
    end
    if frameObj._lariasWarnHeaderFill then
        frameObj._lariasWarnHeaderFill:SetColorTexture(0, 0, 0, 0)
        frameObj._lariasWarnHeaderFill:Hide()
    end

    if not frameObj._lariasWarnTitle and frameObj.CreateFontString then
        local title = frameObj:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        title:SetPoint("TOPLEFT", frameObj, "TOPLEFT", pad, -titleTop)
        title:SetPoint("TOPRIGHT", frameObj, "TOPRIGHT", -pad, -titleTop)
        title:SetJustifyH("CENTER")
        title:SetJustifyV("MIDDLE")
        title:SetShadowOffset(1, -1)
        title:SetShadowColor(0, 0, 0, 0.7)
        frameObj._lariasWarnTitle = title
    end
    if frameObj._lariasWarnTitle then
        frameObj._lariasWarnTitle:SetText(opts.title or L.UPGRADE_WARN_TITLE)
        frameObj._lariasWarnTitle:SetTextColor(hdr.r, hdr.g, hdr.b, 1)
    end

    if not frameObj._lariasWarnDivider and frameObj.CreateTexture then
        local div = frameObj:CreateTexture(nil, "ARTWORK", nil, 0)
        div:SetPoint("TOPLEFT", frameObj, "TOPLEFT", pad, -bodyTop + 8)
        div:SetPoint("TOPRIGHT", frameObj, "TOPRIGHT", -pad, -bodyTop + 8)
        div:SetHeight(1)
        frameObj._lariasWarnDivider = div
    end
    if frameObj._lariasWarnDivider then
        frameObj._lariasWarnDivider:SetColorTexture(txt.r, txt.g, txt.b, vs.dividerA or 0.22)
    end

    frameObj._lariasWarnBodyTop = bodyTop
    frameObj._lariasWarnPad = pad
    return bodyTop
end

function Controls.StyleButton(btn)
    if not btn then return end

    local theme = Addon.THEME
    local vs = Addon.VISUAL_STYLE or {}

    Addon:ApplyTheme(btn)
    if btn.SetBackdropColor and theme then
        btn:SetBackdropColor(theme.bg.r, theme.bg.g, theme.bg.b, 0)
    end
    if btn.SetBackdropBorderColor and theme then
        local border = theme.border or { r = 0.3, g = 0.3, b = 0.3, a = 1 }
        btn:SetBackdropBorderColor(border.r, border.g, border.b, vs.buttonBorderA or border.a or 1)
    end

    local function ClearTex(texture)
        if not texture then return end
        if texture.SetTexture then texture:SetTexture(nil) end
        if texture.SetAlpha then texture:SetAlpha(0) end
        if texture.Hide then texture:Hide() end
    end

    if btn.GetNormalTexture then ClearTex(btn:GetNormalTexture()) end
    if btn.GetPushedTexture then ClearTex(btn:GetPushedTexture()) end
    if btn.GetDisabledTexture then ClearTex(btn:GetDisabledTexture()) end
    if btn.GetHighlightTexture then ClearTex(btn:GetHighlightTexture()) end

    if btn.Left and btn.Left.Hide then btn.Left:Hide() end
    if btn.Middle and btn.Middle.Hide then btn.Middle:Hide() end
    if btn.Right and btn.Right.Hide then btn.Right:Hide() end

    if btn.SetTextInsets then btn:SetTextInsets(0, 0, 0, 0) end

    if btn.CreateTexture and theme then
        if not btn._lariasButtonFill then
            local fill = btn:CreateTexture(nil, "BACKGROUND")
            fill:SetPoint("TOPLEFT", btn, "TOPLEFT", 1, -1)
            fill:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -1, 1)
            btn._lariasButtonFill = fill
        end
        btn._lariasButtonFill:SetColorTexture(
            math.min(1, theme.bg.r + 0.035),
            math.min(1, theme.bg.g + 0.035),
            math.min(1, theme.bg.b + 0.035),
            vs.buttonBgA or 0.34
        )

        if not btn._lariasButtonAccent then
            local accent = btn:CreateTexture(nil, "ARTWORK")
            accent:SetPoint("TOPLEFT", btn, "TOPLEFT", 2, -1)
            accent:SetPoint("TOPRIGHT", btn, "TOPRIGHT", -2, -1)
            accent:SetHeight(1)
            btn._lariasButtonAccent = accent
        end
        local hdr = theme.header or theme.text or { r = 1, g = 1, b = 1 }
        btn._lariasButtonAccent:SetColorTexture(hdr.r, hdr.g, hdr.b, 0.20)
    end

    local textRegion = btn.Text or (btn.GetFontString and btn:GetFontString())
    if textRegion then
        if textRegion.SetJustifyH then textRegion:SetJustifyH("CENTER") end
        if textRegion.SetJustifyV then textRegion:SetJustifyV("MIDDLE") end
        if textRegion.ClearAllPoints and textRegion.SetPoint then
            textRegion:ClearAllPoints()
            textRegion:SetPoint("CENTER", btn, "CENTER", 0, 0)
        end
        if textRegion.SetTextColor then
            if theme and theme.text then
                textRegion:SetTextColor(theme.text.r, theme.text.g, theme.text.b, theme.text.a or 1)
            else
                textRegion:SetTextColor(1, 1, 1, 1)
            end
        end
    end

    if btn.CreateTexture then
        if not btn._lariasCustomHighlight then
            local hl = btn:CreateTexture(nil, "HIGHLIGHT")
            hl:SetAllPoints(btn)
            btn._lariasCustomHighlight = hl
        end
        if theme and theme.header then
            btn._lariasCustomHighlight:SetColorTexture(theme.header.r, theme.header.g, theme.header.b, vs.buttonHighlightA or 0.08)
        else
            btn._lariasCustomHighlight:SetColorTexture(1, 1, 1, vs.buttonHighlightA or 0.06)
        end
    end

    btn._lariasTabStyled = true
end

function Controls.NewActionButton(parent, width, height)
    local btn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    if width and height then
        btn:SetSize(width, height)
    elseif height then
        btn:SetHeight(height)
    end
    Controls.StyleButton(btn)
    return btn
end

function Addon:RefreshUpgradeWarningTheme()
    if not _warn then return end
    local txt = Addon.THEME and Addon.THEME.text
    local bg = Addon.THEME and Addon.THEME.bg
    local vs = Addon.VISUAL_STYLE or {}
    if _warn.label and _warn.label.SetTextColor then
        if txt then
            _warn.label:SetTextColor(txt.r, txt.g, txt.b, txt.a or 1)
        end
        if _warn.label.SetShadowColor and bg then
            _warn.label:SetShadowColor(bg.r, bg.g, bg.b, vs.textShadowA or bg.a or 1)
        end
    end
end

local CREST_LOCALE_KEYS = {
    "ILVLREF_CREST_ADV",
    "ILVLREF_CREST_VET",
    "ILVLREF_CREST_CHAMP",
    "ILVLREF_CREST_HERO",
    "ILVLREF_CREST_MYTH",
}

local CREST_SHORT_NAMES = { "Adv", "Vet", "Champ", "Hero", "Myth" }
local CREST_COLORS = {
    "1EFF00",
    "0070DD",
    "A335EE",
    "FF8000",
    "FFD100",
}
local CREST_CURRENCY_TO_TIER = {
    [3383] = 1, [3341] = 2, [3343] = 3, [3345] = 4, [3347] = 5,
    [3442] = 1, [3443] = 2, [3444] = 3, [3445] = 4, [3446] = 5,
}

local function GetEscapePrefix(tierIdx)
    local hex = CREST_COLORS[tierIdx]
    if hex then
        return "|cFF" .. hex
    end
    return "|cFFFFFFFF"
end

local function GetCrestShort(tierIdx)
    local key = CREST_LOCALE_KEYS[tierIdx]
    local name = (key and L[key]) or CREST_SHORT_NAMES[tierIdx]
    if not name then
        return ""
    end
    name = tostring(name):gsub("%.$", "")
    return GetEscapePrefix(tierIdx) .. name .. "|r"
end

function Addon:GetCrestTierFromCosts(costs)
    if type(costs) ~= "table" then return nil end

    local bestTier, bestCurrencyID, bestCost
    for _, costInfo in ipairs(costs) do
        local currencyID = costInfo and tonumber(costInfo.currencyID)
        if currencyID then
            local tierIdx = CREST_CURRENCY_TO_TIER[currencyID]
            if tierIdx and (not bestTier or tierIdx > bestTier) then
                bestTier = tierIdx
                bestCurrencyID = currencyID
                bestCost = tonumber(costInfo.cost) or 0
            end
        end
    end
    return bestTier, bestCurrencyID, bestCost
end

function Addon:EnsurePrefs()
    MentionedUtilsDB = MentionedUtilsDB or {}
    if MentionedUtilsDB.upgradeWarnDisabled == nil then
        MentionedUtilsDB.upgradeWarnDisabled = false
    end
    return MentionedUtilsDB
end

function Addon:IsUpgradeWarningDisabled()
    local prefs = MentionedUtilsDB or self:EnsurePrefs()
    return prefs.upgradeWarnDisabled == true
end

function Addon:SetUpgradeWarningEnabled(enabled)
    local prefs = self:EnsurePrefs()
    prefs.upgradeWarnDisabled = not enabled

    if not enabled and _warn then
        _warn.holder:Hide()
    elseif enabled then
        self:CheckUpgradeWarning()
    end
end

local _devChecked, _devValue
local function IsDevBuild()
    if not _devChecked then
        _devChecked = true
        local getMeta = C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata
        local ver = (getMeta and getMeta(addonName, "Version")) or ""
        _devValue = ver:find("-") ~= nil
    end
    return _devValue
end

local _warn

local function ApplyUpgradeWarningTheme()
    if not _warn then return end
    local txt = Addon.THEME and Addon.THEME.text
    local bg = Addon.THEME and Addon.THEME.bg
    local vs = Addon.VISUAL_STYLE or {}
    if _warn.label and _warn.label.SetTextColor then
        if txt then
            _warn.label:SetTextColor(txt.r, txt.g, txt.b, txt.a or 1)
        end
        if _warn.label.SetShadowColor and bg then
            _warn.label:SetShadowColor(bg.r, bg.g, bg.b, vs.textShadowA or bg.a or 1)
        end
    end
end

function Addon:CheckUpgradeWarning()
    if _warn then _warn.holder:Hide() end

    if self:IsUpgradeWarningDisabled() then return end

    if not _warn then return end

    if not (C_ItemUpgrade and C_ItemUpgrade.GetItemUpgradeItemInfo) then return end

    local info = C_ItemUpgrade.GetItemUpgradeItemInfo()
    if not info then return end

    local currentLevel = tonumber(info.currUpgrade)
    local maxLevel = tonumber(info.maxUpgrade)
    if not (currentLevel and maxLevel) then return end

    if maxLevel < 2 or currentLevel > 1 then return end

    local lvlInfos = info.upgradeLevelInfos
    local step = lvlInfos and (lvlInfos[currentLevel + 1] or lvlInfos[currentLevel])
    local costs = step and step.currencyCostsToUpgrade
    local tierIdx, upgradeCurrencyID, upgradeCount = self:GetCrestTierFromCosts(costs)

    local isDev = IsDevBuild()
    if not upgradeCurrencyID and not isDev then return end

    if not isDev and (not tierIdx or tierIdx < 2) then return end
    if not tierIdx then tierIdx = 1 end

    local upgradeCost = upgradeCount or 0
    if upgradeCost <= 0 then return end

    local currentName = GetCrestShort(tierIdx)
    local prevName = GetCrestShort(math.max(tierIdx - 1, 1))
    local fmt = L.UPGRADE_WARN_MSG
    _warn.label:SetText(string.format(fmt, currentName, upgradeCost, prevName))
    _warn.holder:Show()
end

local function SetupHooks()
    if ItemUpgradeFrame then
        local PAD_W = 14
        local BTN_H = 24
        local GAP = 10
        local PANEL_H = 108

        local holder = Addon:NewThemedFrame(nil, UIParent)
        holder:SetFrameStrata("DIALOG")
        holder:SetFrameLevel(200)
        holder:SetSize(430, PANEL_H)
        holder:SetClampedToScreen(true)
        holder:EnableMouse(true)
        holder:SetPoint("TOP", ItemUpgradeFrame, "BOTTOM", 0, -6)
        local bodyTop = Addon:ApplyWarningPanelTheme(holder, {
            title = L.UPGRADE_WARN_TITLE,
            pad = PAD_W,
            bodyTop = 52,
        })
        holder:Hide()

        local label = holder:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        label:SetPoint("TOPLEFT", holder, "TOPLEFT", PAD_W, -bodyTop)
        label:SetPoint("TOPRIGHT", holder, "TOPRIGHT", -PAD_W, -bodyTop)
        label:SetJustifyH("CENTER")
        label:SetSpacing(2)
        label:SetWordWrap(true)
        label:SetShadowOffset(1, -1)

        _warn = { holder = holder, label = label }
        ApplyUpgradeWarningTheme()

        hooksecurefunc(ItemUpgradeFrame, "Show", function()
            C_Timer.After(0, function()
                Addon:CheckUpgradeWarning()
            end)
        end)
        hooksecurefunc(ItemUpgradeFrame, "Hide", function()
            if _warn then _warn.holder:Hide() end
        end)
    end

    local slotFrame = CreateFrame("Frame")
    slotFrame:RegisterEvent("ITEM_UPGRADE_MASTER_SET_ITEM")
    slotFrame:SetScript("OnEvent", function()
        Addon:CheckUpgradeWarning()
    end)
end

if ItemUpgradeFrame then
    SetupHooks()
else
    local setupFrame = CreateFrame("Frame")
    setupFrame:RegisterEvent("ADDON_LOADED")
    setupFrame:SetScript("OnEvent", function(_, _, loadedAddon)
        if loadedAddon ~= "Blizzard_ItemUpgradeUI" then return end
        setupFrame:UnregisterAllEvents()
        SetupHooks()
    end)
end