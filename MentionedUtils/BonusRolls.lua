local ADDON_NAME = "MentionedUtils"
local MAX_BONUS_ROLL_ENTRIES = 1000
local DEFAULT_VIEW_COUNT = 100
local MAX_VIEW_COUNT = 300
local DEBUG_IGNORE_RAID_CONTEXT = true

local raidLeadFrame = CreateFrame("Frame")
local lastMessageHash = nil
local lastMessageAt = 0
local bonusRollViewer = nil
local bonusRollRows = {}
local exportFrame = nil
local AddSearchControls
local ShowBonusRollViewer
local BuildFilteredEntries
local ClearBonusRollLog
local guildRosterCache = { byName = {}, updatedAt = 0 }
local originalChatEditInsertLink = nil

local function NormalizeSearchText(value)
    return (value or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
end

local function EnsureDatabase()
    MentionedUtilsDB = MentionedUtilsDB or {}
    MentionedUtilsDB.bonusRollLog = MentionedUtilsDB.bonusRollLog or {}
    if MentionedUtilsDB.bonusRollDebugIgnoreRaidContext == nil then
        MentionedUtilsDB.bonusRollDebugIgnoreRaidContext = true
    end
    if MentionedUtilsDB.bonusRollGuildTrackOnly == nil then
        MentionedUtilsDB.bonusRollGuildTrackOnly = false
    end
    if MentionedUtilsDB.bonusRollGuildViewOnly == nil then
        MentionedUtilsDB.bonusRollGuildViewOnly = false
    end
    DEBUG_IGNORE_RAID_CONTEXT = MentionedUtilsDB.bonusRollDebugIgnoreRaidContext
    return MentionedUtilsDB.bonusRollLog
end

local function SetDebugIgnoreRaidContext(value)
    DEBUG_IGNORE_RAID_CONTEXT = value and true or false
    MentionedUtilsDB = MentionedUtilsDB or {}
    MentionedUtilsDB.bonusRollDebugIgnoreRaidContext = DEBUG_IGNORE_RAID_CONTEXT
end

local function InRaidContext()
    if DEBUG_IGNORE_RAID_CONTEXT then
        return true
    end

    local _, instanceType = IsInInstance()
    return IsInRaid() or instanceType == "raid"
end

local function GetNormalizedRealmToken(realmName)
    return NormalizeSearchText((realmName or ""):gsub("[%s']", ""))
end

local function NormalizePlayerKey(name, fallbackRealm)
    local full = NormalizeSearchText(name)
    if full == "" then
        return nil, nil
    end

    local player, realm = full:match("^([^%-]+)%-(.+)$")
    if not player then
        player = full
        realm = GetNormalizedRealmToken(fallbackRealm)
    else
        realm = GetNormalizedRealmToken(realm)
    end

    local fullKey = realm ~= "" and (player .. "-" .. realm) or player
    return fullKey, player
end

local function RebuildGuildRosterCache()
    guildRosterCache.byName = {}
    guildRosterCache.updatedAt = GetTime()

    if not IsInGuild() then
        return
    end

    GuildRoster()

    local numMembers = GetNumGuildMembers() or 0
    local _, playerRealm = UnitFullName("player")
    local realmToken = GetNormalizedRealmToken(playerRealm)

    for i = 1, numMembers do
        local fullName = GetGuildRosterInfo(i)
        if fullName then
            local fullKey, shortKey = NormalizePlayerKey(fullName, realmToken)
            if fullKey then
                guildRosterCache.byName[fullKey] = true
            end
            if shortKey then
                guildRosterCache.byName[shortKey] = true
            end
        end
    end
end

local function IsGuildMemberByName(name)
    if not name or name == "" then
        return false
    end

    if (GetTime() - (guildRosterCache.updatedAt or 0)) > 30 then
        RebuildGuildRosterCache()
    end

    local _, playerRealm = UnitFullName("player")
    local fullKey, shortKey = NormalizePlayerKey(name, playerRealm)
    return (fullKey and guildRosterCache.byName[fullKey]) or (shortKey and guildRosterCache.byName[shortKey]) or false
end

local function ShouldTrackPlayer(playerFullName)
    EnsureDatabase()
    if not MentionedUtilsDB.bonusRollGuildTrackOnly then
        return true
    end

    return IsGuildMemberByName(playerFullName)
end

local function ExtractItemID(itemLink)
    if not itemLink then
        return ""
    end

    local itemID = itemLink:match("item:(%d+)")
    if itemID then
        return itemID
    end

    return ""
end

local function SplitByColon(value)
    if not value or value == "" then
        return {}
    end

    local parts = {}
    local startIndex = 1

    while true do
        local colonIndex = value:find(":", startIndex, true)
        if not colonIndex then
            parts[#parts + 1] = value:sub(startIndex)
            break
        end

        parts[#parts + 1] = value:sub(startIndex, colonIndex - 1)
        startIndex = colonIndex + 1

        if #parts > 200 then
            break
        end
    end

    return parts
end

local function ExtractItemMetadata(itemLink)
    local itemString = ""
    if itemLink then
        itemString = itemLink:match("|Hitem:([^|]+)|h") or itemLink:match("item:([^|]+)") or ""
    end

    local itemID = ExtractItemID(itemLink)
    local bonusIDs = ""
    local context = ""

    if itemString ~= "" then
        local fields = SplitByColon(itemString)
        if itemID == "" then
            itemID = fields[1] or ""
        end

        local numBonusIDs = tonumber(fields[13]) or 0
        if numBonusIDs > 0 then
            local ids = {}
            for i = 1, numBonusIDs do
                local bonusField = fields[13 + i]
                if bonusField and bonusField ~= "" then
                    ids[#ids + 1] = bonusField
                end
            end
            bonusIDs = table.concat(ids, ",")
        end

        local contextField = fields[14 + numBonusIDs]
        if contextField and contextField ~= "" then
            context = contextField
        end
    end

    if C_Item and C_Item.GetItemLinkItemContext then
        local ctx = C_Item.GetItemLinkItemContext(itemLink)
        if ctx ~= nil then
            context = tostring(ctx)
        end
    end

    local variantKey = table.concat({
        itemID ~= "" and itemID or "0",
        context ~= "" and context or "na",
        bonusIDs ~= "" and bonusIDs or "none",
        itemString ~= "" and itemString or "raw-none",
    }, "|")

    return {
        itemID = itemID,
        itemString = itemString,
        bonusIDs = bonusIDs,
        context = context,
        variantKey = variantKey,
    }
end

local function EnsureEntryMetadata(entry)
    if not entry then
        return nil
    end

    local metadata = ExtractItemMetadata(entry.item)

    entry.itemID = metadata.itemID ~= "" and metadata.itemID or (entry.itemID or "")
    entry.itemString = metadata.itemString ~= "" and metadata.itemString or (entry.itemString or "")
    entry.bonusIDs = metadata.bonusIDs or ""
    entry.context = metadata.context or ""
    entry.variantKey = metadata.variantKey or ""

    return entry
end

local function BuildVariantSummary(entry)
    entry = EnsureEntryMetadata(entry)
    if not entry then
        return ""
    end

    local parts = {}
    if entry.itemID and entry.itemID ~= "" then
        parts[#parts + 1] = "id " .. entry.itemID
    end
    if entry.bonusIDs and entry.bonusIDs ~= "" then
        parts[#parts + 1] = "bonus " .. entry.bonusIDs
    end
    if entry.context and entry.context ~= "" then
        parts[#parts + 1] = "ctx " .. entry.context
    end

    if #parts == 0 then
        return ""
    end

    return " [" .. table.concat(parts, " | ") .. "]"
end

local function BuildTooltipHyperlink(entry)
    if not entry then
        return nil
    end

    entry = EnsureEntryMetadata(entry)
    if entry and entry.item and entry.item:find("|Hitem:", 1, true) then
        return entry.item
    end

    if entry and entry.itemString and entry.itemString ~= "" then
        return "item:" .. entry.itemString
    end

    if entry and entry.item then
        local itemString = entry.item:match("|Hitem:([^|]+)|h")
        if itemString and itemString ~= "" then
            return "item:" .. itemString
        end
        return entry.item
    end

    return nil
end

local function ParseBonusRollMessage(message)
    if not message or message == "" then
        return nil
    end

    local selfItemLink = message:match("^You receive bonus loot:%s*(.+)$")
    if selfItemLink and selfItemLink ~= "" then
        local playerName, realmName = UnitFullName("player")
        local playerFullName = realmName and realmName ~= "" and (playerName .. "-" .. realmName) or (playerName or "You")
        return playerFullName, selfItemLink
    end

    -- Handle others with small grammar/typo variants (receive/receives, bonus/bonut).
    local fullName, itemLink = message:match("^(.+) receives? bon[ou]s loot:%s*(.+)$")
    if not fullName then
        fullName, itemLink = message:match("^(.+) receives? bonus item%s*(.+)$")
    end

    if not fullName or not itemLink or fullName == "You" then
        return nil
    end

    fullName = fullName:gsub("^%s+", ""):gsub("%s+$", "")
    itemLink = itemLink:gsub("^%s+", ""):gsub("%s+$", "")

    if fullName == "" or itemLink == "" then
        return nil
    end

    return fullName, itemLink
end

local function InsertBonusRollEntry(playerFullName, itemLink)
    local log = EnsureDatabase()
    local now = time()
    local metadata = ExtractItemMetadata(itemLink)

    table.insert(log, {
        timestamp = now,
        player = playerFullName,
        item = itemLink,
        itemID = metadata.itemID,
        itemString = metadata.itemString,
        bonusIDs = metadata.bonusIDs,
        context = metadata.context,
        variantKey = metadata.variantKey,
        date = date("%Y-%m-%d %H:%M:%S", now),
    })

    table.sort(log, function(a, b)
        return (a.timestamp or 0) > (b.timestamp or 0)
    end)

    while #log > MAX_BONUS_ROLL_ENTRIES do
        table.remove(log)
    end
end

local function HandleBonusRollMessage(message)
    if not InRaidContext() then
        return
    end

    local playerFullName, itemLink = ParseBonusRollMessage(message)
    if not playerFullName then
        return
    end

    if not ShouldTrackPlayer(playerFullName) then
        return
    end

    local now = GetTime()
    local msgHash = playerFullName .. "|" .. itemLink

    if lastMessageHash == msgHash and (now - lastMessageAt) < 1 then
        return
    end

    lastMessageHash = msgHash
    lastMessageAt = now
    InsertBonusRollEntry(playerFullName, itemLink)
end

local function GetBagItemLinkForTest()
    if C_Container and C_Container.GetContainerNumSlots and C_Container.GetContainerItemLink then
        for bag = 0, 4 do
            local slotCount = C_Container.GetContainerNumSlots(bag) or 0
            for slot = 1, slotCount do
                local itemLink = C_Container.GetContainerItemLink(bag, slot)
                if itemLink then
                    return itemLink
                end
            end
        end
    else
        for bag = 0, 4 do
            local slotCount = GetContainerNumSlots and (GetContainerNumSlots(bag) or 0) or 0
            for slot = 1, slotCount do
                local itemLink = GetContainerItemLink and GetContainerItemLink(bag, slot)
                if itemLink then
                    return itemLink
                end
            end
        end
    end

    return nil
end

local function EmitSystemStyledMessage(text)
    local info = ChatTypeInfo and ChatTypeInfo.SYSTEM
    if DEFAULT_CHAT_FRAME and info then
        DEFAULT_CHAT_FRAME:AddMessage(text, info.r, info.g, info.b, info.id)
    else
        print(text)
    end
end

local function ParseItemLinkFromText(text)
    if not text or text == "" then
        return nil
    end

    local directLink = text:match("(|c%x+|Hitem:.-|h.-|h|r)")
    if directLink then
        return directLink
    end

    local plainLink = text:match("(|Hitem:.-|h.-|h)")
    if plainLink then
        return plainLink
    end

    local trimmed = text:gsub("^%s+", ""):gsub("%s+$", "")
    if trimmed ~= "" then
        return trimmed
    end

    return nil
end

local function TryInsertLinkIntoTestBox(linkText)
    if not linkText or linkText == "" then
        return false
    end

    if not bonusRollViewer or not bonusRollViewer.testItemInput then
        return false
    end

    local box = bonusRollViewer.testItemInput
    if not box:IsShown() or not box:HasFocus() then
        return false
    end

    box:Insert(linkText)
    return true
end

local function EnsureTestBoxLinkHook()
    if originalChatEditInsertLink then
        return
    end

    originalChatEditInsertLink = ChatEdit_InsertLink
    ChatEdit_InsertLink = function(linkText, ...)
        if TryInsertLinkIntoTestBox(linkText) then
            return true
        end

        return originalChatEditInsertLink(linkText, ...)
    end
end

local function RunBonusRollTestMessage(preferredItemLink)
    local itemLink = ParseItemLinkFromText(preferredItemLink)
    if not itemLink then
        itemLink = GetBagItemLinkForTest()
    end

    if not itemLink then
        print("MentionedUtils: No bag item found for test message.")
        return
    end

    local testMessage = "You receive bonus loot: " .. itemLink
    EmitSystemStyledMessage(testMessage)
    HandleBonusRollMessage(testMessage)

    if bonusRollViewer and bonusRollViewer:IsShown() then
        ShowBonusRollViewer(bonusRollViewer.currentCount)
    end
end

ClearBonusRollLog = function()
    EnsureDatabase()
    MentionedUtilsDB.bonusRollLog = {}
    lastMessageHash = nil
    lastMessageAt = 0

    if bonusRollViewer and bonusRollViewer:IsShown() then
        ShowBonusRollViewer(bonusRollViewer.currentCount)
    end

    if exportFrame and exportFrame:IsShown() and exportFrame.editBox then
        exportFrame.editBox:SetText("MentionedUtils: No bonus roll entries saved yet.")
    end

    print("MentionedUtils: Bonus roll log cleared.")
end

local function ShowClearLogConfirmation()
    local dialogKey = "MENTIONEDUTILS_CLEAR_BROLL_LOG"
    if not StaticPopupDialogs[dialogKey] then
        StaticPopupDialogs[dialogKey] = {
            text = "Clear all saved bonus roll log entries?",
            button1 = "Yes",
            button2 = "No",
            OnAccept = function()
                ClearBonusRollLog()
            end,
            timeout = 0,
            whileDead = true,
            hideOnEscape = true,
            preferredIndex = 3,
        }
    end

    StaticPopup_Show(dialogKey)
end

local function ParseCount(rawCount, fallback, maxAllowed)
    local count = tonumber(rawCount) or fallback
    if count < 1 then
        count = 1
    end
    if count > maxAllowed then
        count = maxAllowed
    end
    return math.floor(count)
end

local function BuildExportText(countArg, filterText, guildOnly)
    local log = EnsureDatabase()
    if #log == 0 then
        return "MentionedUtils: No bonus roll entries saved yet."
    end

    local count = ParseCount(countArg, DEFAULT_VIEW_COUNT, MAX_BONUS_ROLL_ENTRIES)
    local filtered = BuildFilteredEntries(log, count, NormalizeSearchText(filterText), guildOnly and true or false)
    local lines = {}

    lines[#lines + 1] = "date\tplayer\titemID\titemString\tbonusIDs\tcontext\tvariantKey\titem"
    for i = 1, #filtered do
        local entry = EnsureEntryMetadata(filtered[i])
        local stamp = entry.date or date("%Y-%m-%d %H:%M:%S", entry.timestamp or time())
        local player = entry.player or "Unknown"
        local itemID = entry.itemID or ""
        local itemString = entry.itemString or ""
        local bonusIDs = entry.bonusIDs or ""
        local context = entry.context or ""
        local variantKey = entry.variantKey or ""
        local item = entry.item or "Unknown item"
        lines[#lines + 1] = ("%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s")
            :format(stamp, player, itemID, itemString, bonusIDs, context, variantKey, item)
    end

    return table.concat(lines, "\n")
end

local function EnsureExportFrame()
    if exportFrame then
        return exportFrame
    end

    local frame = CreateFrame("Frame", "MentionedUtilsBonusRollExportFrame", UIParent, "BackdropTemplate")
    frame:SetSize(760, 420)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true,
        tileSize = 32,
        edgeSize = 32,
        insets = { left = 8, right = 8, top = 8, bottom = 8 },
    })
    frame:Hide()

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    title:SetPoint("TOP", 0, -18)
    title:SetText("MentionedUtils Bonus Roll Export")

    CreateFrame("Button", nil, frame, "UIPanelCloseButton"):SetPoint("TOPRIGHT", -4, -4)

    local info = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    info:SetPoint("TOPLEFT", 20, -48)
    info:SetText("Copy-friendly tab-separated export. Click in the box and press Ctrl+A, Ctrl+C.")

    local scroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 20, -74)
    scroll:SetPoint("BOTTOMRIGHT", -40, 20)

    local editBox = CreateFrame("EditBox", nil, scroll)
    editBox:SetMultiLine(true)
    editBox:SetAutoFocus(false)
    editBox:SetWidth(680)
    editBox:SetFontObject(ChatFontNormal)
    editBox:SetScript("OnEscapePressed", function()
        frame:Hide()
    end)
    editBox:SetScript("OnTextChanged", function(self)
        self:SetHeight(math.max(320, self:GetStringHeight() + 30))
    end)

    scroll:SetScrollChild(editBox)

    frame.editBox = editBox
    exportFrame = frame

    if not tContains(UISpecialFrames, frame:GetName()) then
        table.insert(UISpecialFrames, frame:GetName())
    end

    return exportFrame
end

local function ShowExportFrame(countArg, filterText, guildOnly)
    local frame = EnsureExportFrame()
    frame:Show()
    frame.editBox:SetText(BuildExportText(countArg, filterText, guildOnly))
    frame.editBox:HighlightText(0, 0)
    frame.editBox:SetFocus()
end

local function EnsureBonusRollViewer()
    if bonusRollViewer then
        return bonusRollViewer
    end

    local frame = CreateFrame("Frame", "MentionedUtilsBonusRollViewer", UIParent, "BackdropTemplate")
    frame:SetSize(820, 500)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true,
        tileSize = 32,
        edgeSize = 32,
        insets = { left = 8, right = 8, top = 8, bottom = 8 },
    })
    frame:Hide()

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    title:SetPoint("TOP", 0, -18)
    title:SetText("MentionedUtils Bonus Rolls")

    local subtitle = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    subtitle:SetPoint("TOPLEFT", 20, -46)
    subtitle:SetText("Newest first. Hover a row to see the item tooltip.")
    frame.subtitle = subtitle

    CreateFrame("Button", nil, frame, "UIPanelCloseButton"):SetPoint("TOPRIGHT", -4, -4)

    local exportButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    exportButton:SetSize(80, 22)
    exportButton:SetPoint("TOPRIGHT", -44, -42)
    exportButton:SetText("Export")
    exportButton:SetScript("OnClick", function()
        ShowExportFrame(frame.currentCount, frame.currentFilter, frame.currentGuildOnly)
    end)

    local clearButtonTop = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    clearButtonTop:SetSize(80, 22)
    clearButtonTop:SetPoint("RIGHT", exportButton, "LEFT", -8, 0)
    clearButtonTop:SetText("Delete")
    clearButtonTop:SetScript("OnClick", function()
        ShowClearLogConfirmation()
    end)

    local testInputLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    testInputLabel:SetPoint("TOPLEFT", 20, -70)
    testInputLabel:SetText("Test item:")

    local testItemInput = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
    testItemInput:SetSize(320, 22)
    testItemInput:SetPoint("LEFT", testInputLabel, "RIGHT", 8, 0)
    testItemInput:SetAutoFocus(false)
    testItemInput:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)
    testItemInput:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
        RunBonusRollTestMessage(self:GetText())
    end)
    testItemInput:SetScript("OnReceiveDrag", function(self)
        local infoType, itemID, itemLink = GetCursorInfo()
        if infoType == "item" then
            local exactLink = nil

            if type(itemLink) == "string" and itemLink:find("|Hitem:", 1, true) then
                exactLink = itemLink
            end

            if not exactLink and itemID then
                local itemName, resolvedLink = GetItemInfo(itemID)
                exactLink = resolvedLink or itemName
            end

            self:SetText(exactLink or "")
            self:SetFocus()
            self:HighlightText(0, 0)
            ClearCursor()
        end
    end)
    frame.testItemInput = testItemInput

    local testButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    testButton:SetSize(80, 22)
    testButton:SetPoint("LEFT", testItemInput, "RIGHT", 8, 0)
    testButton:SetText("Test")
    testButton:SetScript("OnClick", function()
        RunBonusRollTestMessage(frame.testItemInput and frame.testItemInput:GetText())
    end)

    AddSearchControls(frame)

    local scroll = CreateFrame("ScrollFrame", "MentionedUtilsBonusRollScrollFrame", frame, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 20, -126)
    scroll:SetPoint("BOTTOMRIGHT", -40, 20)

    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(1, 1)
    scroll:SetScrollChild(content)

    frame.scroll = scroll
    frame.content = content
    bonusRollViewer = frame

    if not tContains(UISpecialFrames, frame:GetName()) then
        table.insert(UISpecialFrames, frame:GetName())
    end

    return bonusRollViewer
end

local function GetItemIcon(itemLink)
    if not itemLink then
        return 134400
    end

    local icon = select(5, GetItemInfoInstant(itemLink))
    if icon then
        return icon
    end

    return 134400
end

local function EntryMatchesFilter(entry, filterText)
    if filterText == "" then
        return true
    end

    local player = NormalizeSearchText(entry.player or "")
    if player:find(filterText, 1, true) then
        return true
    end

    local itemText = NormalizeSearchText(entry.item or "")
    if itemText:find(filterText, 1, true) then
        return true
    end

    return false
end

BuildFilteredEntries = function(log, count, filterText, guildOnly)
    local entries = {}
    local wanted = math.min(count, #log)

    for i = 1, #log do
        local entry = log[i]
        local guildMatch = (not guildOnly) or IsGuildMemberByName(entry.player)
        if guildMatch and EntryMatchesFilter(entry, filterText) then
            entries[#entries + 1] = entry
            if #entries >= wanted then
                break
            end
        end
    end

    return entries
end

local function CreateViewerRow(parent, rowIndex)
    local row = CreateFrame("Button", nil, parent)
    row:SetSize(730, 22)
    row:SetPoint("TOPLEFT", 4, -((rowIndex - 1) * 24))

    local bg = row:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    if rowIndex % 2 == 0 then
        bg:SetColorTexture(0.2, 0.2, 0.2, 0.25)
    else
        bg:SetColorTexture(0.1, 0.1, 0.1, 0.2)
    end

    local icon = row:CreateTexture(nil, "ARTWORK")
    icon:SetSize(18, 18)
    icon:SetPoint("LEFT", 6, 0)

    local text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    text:SetPoint("LEFT", icon, "RIGHT", 8, 0)
    text:SetPoint("RIGHT", -10, 0)
    text:SetJustifyH("LEFT")

    row.icon = icon
    row.text = text

    row:SetScript("OnEnter", function(self)
        if not self.tooltipLink and not self.itemLink then
            return
        end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")

        local linkForTooltip = self.tooltipLink or self.itemLink
        if not GameTooltip:SetHyperlink(linkForTooltip) then
            GameTooltip:SetText(self.itemLink or linkForTooltip)
        end
        GameTooltip:Show()
    end)

    row:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    return row
end

ShowBonusRollViewer = function(countArg)
    local log = EnsureDatabase()
    local frame = EnsureBonusRollViewer()

    local count = ParseCount(countArg, DEFAULT_VIEW_COUNT, MAX_VIEW_COUNT)
    local filterText = NormalizeSearchText(frame.searchBox and frame.searchBox:GetText() or "")
    local guildOnly = MentionedUtilsDB and MentionedUtilsDB.bonusRollGuildViewOnly or false
    local filtered = BuildFilteredEntries(log, count, filterText, guildOnly)
    local visibleCount = #filtered
    frame.currentCount = count
    frame.currentFilter = filterText
    frame.currentGuildOnly = guildOnly

    if frame.guildOnlyCheck then
        frame.guildOnlyCheck:SetChecked(guildOnly)
    end

    if filterText == "" and not guildOnly then
        frame.subtitle:SetText(("Showing %d of %d saved entries. Hover a row to see tooltip."):format(visibleCount, #log))
    elseif filterText == "" and guildOnly then
        frame.subtitle:SetText(("Showing %d guild entries (from %d total). Hover a row to see tooltip."):format(visibleCount, #log))
    elseif not guildOnly then
        frame.subtitle:SetText(("Showing %d filtered entries (from %d total). Hover a row to see tooltip."):format(visibleCount, #log))
    else
        frame.subtitle:SetText(("Showing %d filtered guild entries (from %d total). Hover a row to see tooltip."):format(visibleCount, #log))
    end

    for i = 1, visibleCount do
        local row = bonusRollRows[i]
        if not row then
            row = CreateViewerRow(frame.content, i)
            bonusRollRows[i] = row
        end

        local entry = EnsureEntryMetadata(filtered[i])
        local stamp = entry.date or date("%Y-%m-%d %H:%M:%S", entry.timestamp or time())
        local player = entry.player or "Unknown"
        local item = entry.item or "Unknown item"
        local variantSummary = BuildVariantSummary(entry)
        local tooltipLink = BuildTooltipHyperlink(entry)

        row.itemLink = item
        row.tooltipLink = tooltipLink
        row.icon:SetTexture(GetItemIcon(item))
        row.text:SetText(("[%s] %s won %s%s"):format(stamp, player, item, variantSummary))
        row:Show()
    end

    for i = visibleCount + 1, #bonusRollRows do
        bonusRollRows[i]:Hide()
        bonusRollRows[i].itemLink = nil
        bonusRollRows[i].tooltipLink = nil
    end

    local contentHeight = math.max(1, visibleCount * 24)
    frame.content:SetHeight(contentHeight)
    frame.scroll:SetVerticalScroll(0)
    frame:Show()

    if visibleCount == 0 then
        if #log == 0 then
            print("MentionedUtils: No bonus roll entries saved yet.")
        else
            print("MentionedUtils: No entries match the current search filter.")
        end
    end
end

local function HandleBrollsGuildCommand(argString)
    EnsureDatabase()

    local scope, rest = (argString or ""):match("^(%S*)%s*(.-)%s*$")
    scope = NormalizeSearchText(scope)
    local opt = NormalizeSearchText(rest)

    if scope == "" or scope == "status" then
        print(("MentionedUtils: guild tracking filter is %s; list guild filter is %s.")
            :format(MentionedUtilsDB.bonusRollGuildTrackOnly and "ON" or "OFF", MentionedUtilsDB.bonusRollGuildViewOnly and "ON" or "OFF"))
        return
    end

    local function parseOnOff(value)
        if value == "on" then
            return true
        end
        if value == "off" then
            return false
        end
        return nil
    end

    if scope == "track" then
        local setValue = parseOnOff(opt)
        if setValue == nil then
            print("Usage: /mu brollsguild track on|off")
            return
        end
        MentionedUtilsDB.bonusRollGuildTrackOnly = setValue
        print(("MentionedUtils: guild-only tracking is now %s."):format(setValue and "ON" or "OFF"))
        return
    end

    if scope == "view" then
        local setValue = parseOnOff(opt)
        if setValue == nil then
            print("Usage: /mu brollsguild view on|off")
            return
        end
        MentionedUtilsDB.bonusRollGuildViewOnly = setValue
        print(("MentionedUtils: guild-only list filter is now %s."):format(setValue and "ON" or "OFF"))
        if bonusRollViewer and bonusRollViewer:IsShown() then
            ShowBonusRollViewer(bonusRollViewer.currentCount)
        end
        return
    end

    print("Usage: /mu brollsguild status")
    print("Usage: /mu brollsguild track on|off")
    print("Usage: /mu brollsguild view on|off")
end

local function HandleBrollsCommand(argString)
    local first, rest = (argString or ""):match("^(%S*)%s*(.-)%s*$")
    first = (first or ""):lower()

    if first == "" then
        ShowBonusRollViewer(nil)
        return
    end

    if first == "export" then
        local exportCount = rest
        local exportFilter = ""
        local exportGuildOnly = false

        if bonusRollViewer and bonusRollViewer:IsShown() then
            exportCount = bonusRollViewer.currentCount or rest
            exportFilter = bonusRollViewer.currentFilter or ""
            exportGuildOnly = bonusRollViewer.currentGuildOnly and true or false
        end

        ShowExportFrame(exportCount, exportFilter, exportGuildOnly)
        return
    end

    if first == "guild" then
        HandleBrollsGuildCommand(rest)
        return
    end

    if first == "clear" then
        ShowClearLogConfirmation()
        return
    end

    if first == "test" then
        local preferredItem = ""
        if bonusRollViewer and bonusRollViewer.testItemInput then
            preferredItem = bonusRollViewer.testItemInput:GetText() or ""
        end
        RunBonusRollTestMessage(preferredItem)
        return
    end

    local numericCount = tonumber(first)
    if numericCount then
        ShowBonusRollViewer(numericCount)
        return
    end

    print("MentionedUtils /mu brolls commands:")
    print("/mu brolls - Open bonus roll log window.")
    print("/mu brolls <count> - Open window with up to count rows.")
    print("/mu brolls export [count] - Open copy-friendly export text.")
    print("/mu brolls clear - Clear all saved bonus roll entries.")
    print("/mu brolls test - Send a local system-style test message using a bag item.")
    print("/mu brolls guild status|track on|off|view on|off - Guild filtering options.")
end

local function RegisterSlashCommands()
    SLASH_MENTIONEDUTILS1 = "/mu"
    SlashCmdList["MENTIONEDUTILS"] = function(msg)
        local cmd, rest = (msg or ""):match("^(%S*)%s*(.-)%s*$")
        cmd = (cmd or ""):lower()

        if cmd == "brolls" then
            HandleBrollsCommand(rest)
            return
        end

        if cmd == "brollsguild" then
            HandleBrollsGuildCommand(rest)
            return
        end

        if cmd == "brollsdebug" then
            local opt = NormalizeSearchText(rest)
            if opt == "on" then
                SetDebugIgnoreRaidContext(true)
                print("MentionedUtils: bonus roll debug mode enabled (raid context bypass ON).")
                return
            end

            if opt == "off" then
                SetDebugIgnoreRaidContext(false)
                print("MentionedUtils: bonus roll debug mode disabled (raid context required).")
                return
            end

            if opt == "" or opt == "status" then
                print(("MentionedUtils: brollsdebug is %s."):format(DEBUG_IGNORE_RAID_CONTEXT and "ON" or "OFF"))
                return
            end

            print("Usage: /mu brollsdebug on|off|status")
            return
        end

        print("MentionedUtils commands:")
        print("/mu brolls - Open bonus roll log window.")
        print("/mu brolls export [count] - Open copy-friendly export text.")
        print("/mu brolls clear - Clear all saved bonus roll entries.")
        print("/mu brolls test - Send a local system-style test message using a bag item.")
        print("/mu brollsguild status|track on|off|view on|off - Guild filtering options.")
        print("/mu brollsdebug on|off|status - Toggle raid-context requirement for logging.")
    end
end

AddSearchControls = function(frame)
    local searchLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    searchLabel:SetPoint("TOPLEFT", 20, -98)
    searchLabel:SetText("Search:")

    local searchBox = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
    searchBox:SetSize(220, 22)
    searchBox:SetPoint("LEFT", searchLabel, "RIGHT", 8, 0)
    searchBox:SetAutoFocus(false)
    searchBox:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)
    searchBox:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
    end)
    searchBox:SetScript("OnTextChanged", function()
        if frame:IsShown() then
            ShowBonusRollViewer(frame.currentCount)
        end
    end)
    frame.searchBox = searchBox

    local clearButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    clearButton:SetSize(52, 22)
    clearButton:SetPoint("LEFT", searchBox, "RIGHT", 8, 0)
    clearButton:SetText("Clear")
    clearButton:SetScript("OnClick", function()
        searchBox:SetText("")
        searchBox:ClearFocus()
        ShowBonusRollViewer(frame.currentCount)
    end)

    local guildOnlyCheck = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
    guildOnlyCheck:SetPoint("LEFT", clearButton, "RIGHT", 12, 0)
    guildOnlyCheck.text:SetText("Guild only")
    guildOnlyCheck:SetScript("OnClick", function(self)
        EnsureDatabase()
        MentionedUtilsDB.bonusRollGuildViewOnly = self:GetChecked() and true or false
        ShowBonusRollViewer(frame.currentCount)
    end)
    frame.guildOnlyCheck = guildOnlyCheck
end

raidLeadFrame:RegisterEvent("ADDON_LOADED")
raidLeadFrame:RegisterEvent("CHAT_MSG_LOOT")
raidLeadFrame:RegisterEvent("CHAT_MSG_SYSTEM")

raidLeadFrame:SetScript("OnEvent", function(_, event, ...)
    if event == "ADDON_LOADED" then
        local addonName = ...
        if addonName ~= ADDON_NAME then
            return
        end

        EnsureDatabase()
        EnsureTestBoxLinkHook()
        RegisterSlashCommands()
        return
    end

    if event == "CHAT_MSG_LOOT" or event == "CHAT_MSG_SYSTEM" then
        local message = ...
        HandleBonusRollMessage(message)
    end
end)