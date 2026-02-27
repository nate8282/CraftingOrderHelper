--[[
    CraftOrderList - Visual shopping list for crafting materials
    Shows what you need, what you have, and lets you search the AH directly.
]]

local addonName, COL = ...

COL.materialList = {}
COL.recipeName = ""
COL.mainFrame = nil
COL.rows = {}
COL.buttonsCreated = {}
COL.settings = {
    qualityFilter = 0,
    hideCompleted = false,
    sortBy = "name",
    craftCount = 1,
    framePos = nil,
}

local MAX_ITEMS = 40
local QUALITY_ICONS = {
    [0] = "Any",
    [1] = CreateAtlasMarkup("Professions-Icon-Quality-Tier1-Small", 20, 20),
    [2] = CreateAtlasMarkup("Professions-Icon-Quality-Tier2", 20, 20),
    [3] = CreateAtlasMarkup("Professions-Icon-Quality-Tier3-Small", 20, 20),
}
local COLORS = {
    have = {0.2, 1, 0.2},
    partial = {1, 1, 0.2},
    need = {1, 0.3, 0.3},
    header = {1, 0.82, 0},
    text = {1, 1, 1},
    dim = {0.5, 0.5, 0.5},
}

-- ============================================================================
-- Utility
-- ============================================================================

local function GetItemCountByQuality(itemID)
    return C_Item.GetItemCount(itemID, true, false, true) or 0
end

local function GetOwnedForMaterial(mat)
    if not mat.reagents then return 0 end
    local filter = COL.settings.qualityFilter

    if filter > 0 then
        local r = mat.reagents[filter]
        if r and r.itemID then
            return GetItemCountByQuality(r.itemID)
        end
    end

    local total = 0
    for i = 1, #mat.reagents do
        if mat.reagents[i] and mat.reagents[i].itemID then
            total = total + GetItemCountByQuality(mat.reagents[i].itemID)
        end
    end
    return total
end

local function GetSearchName(mat)
    local quality = COL.settings.qualityFilter

    if quality > 0 and mat.reagents then
        local r = mat.reagents[quality]
        if r and r.itemID then
            local name = C_Item.GetItemNameByID(r.itemID)
            if name and name ~= "" and name ~= "Loading..." then
                return name
            end
        end
    end

    -- Quality "Any": use base item name
    local name = mat.name
    if not name or name == "Loading..." or name == "Unknown" then
        -- Request load if possible
        if mat.reagents and mat.reagents[1] and mat.reagents[1].itemID then
            C_Item.RequestLoadItemDataByID(mat.reagents[1].itemID)
        end
        return nil
    end
    return name
end

local function GetNeeded(mat)
    return mat.needed * COL.settings.craftCount
end

local function SortMaterials()
    local sortBy = COL.settings.sortBy
    table.sort(COL.materialList, function(a, b)
        if sortBy == "name" then
            return (a.name or "") < (b.name or "")
        elseif sortBy == "needed" then
            return GetNeeded(a) > GetNeeded(b)
        elseif sortBy == "status" then
            local aDone = (GetOwnedForMaterial(a) >= GetNeeded(a)) and 1 or 0
            local bDone = (GetOwnedForMaterial(b) >= GetNeeded(b)) and 1 or 0
            if aDone ~= bDone then return aDone < bDone end
            return (a.name or "") < (b.name or "")
        end
        return false
    end)
end

-- ============================================================================
-- Material List Building
-- ============================================================================

local function BuildMaterialList(recipeID, addToExisting)
    if not addToExisting then
        COL.materialList = {}
    end

    local recipeInfo = C_TradeSkillUI.GetRecipeInfo(recipeID)
    if not recipeInfo then return false end

    if not addToExisting then
        COL.recipeName = recipeInfo.name or "Unknown"
    else
        COL.recipeName = "Multiple Recipes"
    end

    local recipeSchematic = C_TradeSkillUI.GetRecipeSchematic(recipeID, false)
    if not recipeSchematic or not recipeSchematic.reagentSlotSchematics then
        return false
    end

    local existingByName = {}
    local existingByItemID = {}
    for i, mat in ipairs(COL.materialList) do
        existingByName[mat.name] = i
        if mat.reagents and mat.reagents[1] and mat.reagents[1].itemID then
            existingByItemID[mat.reagents[1].itemID] = i
        end
    end

    for _, reagentSlot in ipairs(recipeSchematic.reagentSlotSchematics) do
        if reagentSlot.reagents and reagentSlot.reagentType == Enum.CraftingReagentType.Basic
            and reagentSlot.quantityRequired and reagentSlot.quantityRequired > 0 then
            local firstReagent = reagentSlot.reagents[1]
            if firstReagent and firstReagent.itemID then
                local itemName = C_Item.GetItemNameByID(firstReagent.itemID)
                local itemIcon = C_Item.GetItemIconByID(firstReagent.itemID)

                if not itemName then
                    C_Item.RequestLoadItemDataByID(firstReagent.itemID)
                    itemName = "Loading..."
                end

                local displayName = itemName:gsub(" %|A.-|a$", "")

                -- Dedup by itemID first to avoid "Loading..." collisions
                local existingIdx = existingByItemID[firstReagent.itemID]
                    or (displayName ~= "Loading..." and existingByName[displayName])

                if existingIdx then
                    COL.materialList[existingIdx].needed = COL.materialList[existingIdx].needed + reagentSlot.quantityRequired
                elseif #COL.materialList < MAX_ITEMS then
                    table.insert(COL.materialList, {
                        name = displayName,
                        icon = itemIcon or 134400,
                        needed = reagentSlot.quantityRequired,
                        reagents = reagentSlot.reagents,
                        searched = false,
                        manualCheck = false,
                    })
                    existingByName[displayName] = #COL.materialList
                    existingByItemID[firstReagent.itemID] = #COL.materialList
                end
            end
        end
    end

    SortMaterials()
    return #COL.materialList > 0
end

-- ============================================================================
-- Progress Helpers
-- ============================================================================

local function GetProgressInfo()
    local total = #COL.materialList
    local complete = 0
    local totalNeeded = 0
    local totalOwned = 0

    for _, mat in ipairs(COL.materialList) do
        local needed = GetNeeded(mat)
        local owned = GetOwnedForMaterial(mat)
        totalNeeded = totalNeeded + needed
        totalOwned = totalOwned + math.min(owned, needed)
        if owned >= needed then
            complete = complete + 1
        end
    end

    return total, complete, totalNeeded, totalOwned
end

-- ============================================================================
-- Main Frame UI
-- ============================================================================

local function CreateMainFrame()
    if COL.mainFrame then return COL.mainFrame end

    local frame = CreateFrame("Frame", "COL_MainFrame", UIParent, "BackdropTemplate")
    frame:SetSize(360, 460)
    frame:SetPoint("CENTER", UIParent, "CENTER", 400, 0)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relPoint, x, y = self:GetPoint()
        COL.settings.framePos = { point, relPoint, x, y }
    end)
    frame:SetFrameStrata("HIGH")
    frame:SetClampedToScreen(true)
    frame:SetBackdrop({
        bgFile = "Interface/Tooltips/UI-Tooltip-Background",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    frame:SetBackdropColor(0.1, 0.1, 0.1, 1)
    frame:SetBackdropBorderColor(0.6, 0.6, 0.6, 1)

    -- Solid background fill to guarantee opacity
    local bg = frame:CreateTexture(nil, "BACKGROUND")
    bg:SetPoint("TOPLEFT", 4, -4)
    bg:SetPoint("BOTTOMRIGHT", -4, 4)
    bg:SetColorTexture(0.1, 0.1, 0.1, 1)

    -- Title bar
    local titleBar = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    titleBar:SetHeight(28)
    titleBar:SetPoint("TOPLEFT", 4, -4)
    titleBar:SetPoint("TOPRIGHT", -4, -4)
    titleBar:SetBackdrop({ bgFile = "Interface/Tooltips/UI-Tooltip-Background" })
    titleBar:SetBackdropColor(0.2, 0.2, 0.2, 1)

    local titleIcon = titleBar:CreateTexture(nil, "ARTWORK")
    titleIcon:SetSize(20, 20)
    titleIcon:SetPoint("LEFT", 6, 0)
    titleIcon:SetTexture("Interface\\AddOns\\CraftOrderList\\Icon")

    local title = titleBar:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("LEFT", titleIcon, "RIGHT", 4, 0)
    title:SetText("Crafting Materials")
    title:SetTextColor(unpack(COLORS.header))

    local version = titleBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    version:SetPoint("RIGHT", -26, 0)
    version:SetText("v" .. (C_AddOns.GetAddOnMetadata(addonName, "Version") or ""))
    version:SetTextColor(0.5, 0.5, 0.5)

    local closeBtn = CreateFrame("Button", nil, titleBar, "UIPanelCloseButton")
    closeBtn:SetPoint("RIGHT", 0, 0)
    closeBtn:SetScript("OnClick", function() frame:Hide() end)

    -- Recipe name
    local recipeName = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    recipeName:SetPoint("TOPLEFT", titleBar, "BOTTOMLEFT", 8, -6)
    recipeName:SetPoint("RIGHT", -8, 0)
    recipeName:SetHeight(14)
    recipeName:SetJustifyH("LEFT")
    frame.recipeName = recipeName

    -- Controls row: anchored with explicit Y offsets from frame top
    -- Row 1 (y = -66): Quality dropdown + Sort dropdown
    local qualityLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    qualityLabel:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, -66)
    qualityLabel:SetText("Quality:")
    qualityLabel:SetTextColor(0.7, 0.7, 0.7)

    local qualityDropdown = CreateFrame("Frame", "COL_QualityDropdown", frame, "UIDropDownMenuTemplate")
    qualityDropdown:SetPoint("LEFT", qualityLabel, "RIGHT", -8, -2)
    UIDropDownMenu_SetWidth(qualityDropdown, 65)
    UIDropDownMenu_SetText(qualityDropdown, QUALITY_ICONS[0])
    -- Center the dropdown text vertically and horizontally
    local qdText = qualityDropdown.Text or _G[qualityDropdown:GetName() .. "Text"]
    if qdText then
        qdText:ClearAllPoints()
        qdText:SetPoint("CENTER", qualityDropdown, "CENTER", -8, 1)
        qdText:SetJustifyH("CENTER")
    end
    UIDropDownMenu_Initialize(qualityDropdown, function(self, level)
        for i = 0, 3 do
            local info = UIDropDownMenu_CreateInfo()
            info.text = QUALITY_ICONS[i]
            info.value = i
            info.justifyH = "CENTER"
            info.func = function()
                COL.settings.qualityFilter = i
                UIDropDownMenu_SetText(qualityDropdown, QUALITY_ICONS[i])
                COL:UpdateMainFrame()
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end)
    frame.qualityDropdown = qualityDropdown

    local sortLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    sortLabel:SetPoint("LEFT", qualityLabel, "LEFT", 155, 0)
    sortLabel:SetText("Sort:")
    sortLabel:SetTextColor(0.7, 0.7, 0.7)

    local SORT_LABELS = { name = "Name", needed = "Amount", status = "Completion" }

    local sortDropdown = CreateFrame("Frame", "COL_SortDropdown", frame, "UIDropDownMenuTemplate")
    sortDropdown:SetPoint("LEFT", sortLabel, "RIGHT", -8, -2)
    UIDropDownMenu_SetWidth(sortDropdown, 80)
    UIDropDownMenu_SetText(sortDropdown, SORT_LABELS[COL.settings.sortBy] or "Name")
    UIDropDownMenu_Initialize(sortDropdown, function(self, level)
        local options = { { "name", "Name" }, { "needed", "Amount" }, { "status", "Completion" } }
        for _, opt in ipairs(options) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = opt[2]
            info.value = opt[1]
            info.func = function()
                COL.settings.sortBy = opt[1]
                UIDropDownMenu_SetText(sortDropdown, opt[2])
                SortMaterials()
                COL:UpdateMainFrame()
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end)
    frame.SORT_LABELS = SORT_LABELS

    -- Row 2 (y = -92): Hide Done + Craft count
    local hideCheck = CreateFrame("CheckButton", "COL_HideCompleted", frame, "UICheckButtonTemplate")
    hideCheck:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, -92)
    hideCheck:SetSize(24, 24)
    hideCheck.text:SetText("Hide Done")
    hideCheck:SetScript("OnClick", function(self)
        COL.settings.hideCompleted = self:GetChecked()
        COL:UpdateMainFrame()
    end)
    hideCheck:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Hide Done", 1, 1, 1)
        GameTooltip:AddLine("Hide materials you already have enough of.", 0.7, 0.7, 0.7, true)
        GameTooltip:Show()
    end)
    hideCheck:SetScript("OnLeave", function() GameTooltip:Hide() end)

    local craftLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    craftLabel:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -68, -97)
    craftLabel:SetText("Craft amount:")
    craftLabel:SetTextColor(0.7, 0.7, 0.7)

    local craftDown = CreateFrame("Button", nil, frame)
    craftDown:SetSize(16, 16)
    craftDown:SetPoint("LEFT", craftLabel, "RIGHT", 4, 0)
    craftDown:SetNormalTexture("Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Up")
    craftDown:SetPushedTexture("Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Down")
    craftDown:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")

    local craftValue = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    craftValue:SetPoint("LEFT", craftDown, "RIGHT", 2, 0)
    craftValue:SetWidth(22)
    craftValue:SetJustifyH("CENTER")
    craftValue:SetText("1")
    craftValue:SetTextColor(1, 1, 1)
    frame.craftValue = craftValue

    local craftUp = CreateFrame("Button", nil, frame)
    craftUp:SetSize(16, 16)
    craftUp:SetPoint("LEFT", craftValue, "RIGHT", 2, 0)
    craftUp:SetNormalTexture("Interface\\Buttons\\UI-SpellbookIcon-NextPage-Up")
    craftUp:SetPushedTexture("Interface\\Buttons\\UI-SpellbookIcon-NextPage-Down")
    craftUp:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")

    local function UpdateCraftCount(val)
        if val < 1 then val = 1 end
        if val > 999 then val = 999 end
        COL.settings.craftCount = val
        craftValue:SetText(tostring(val))
        COL:UpdateMainFrame()
    end

    craftDown:SetScript("OnClick", function()
        UpdateCraftCount(COL.settings.craftCount - 1)
    end)
    craftUp:SetScript("OnClick", function()
        UpdateCraftCount(COL.settings.craftCount + 1)
    end)

    -- Progress bar
    local progressBg = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    progressBg:SetHeight(14)
    progressBg:SetPoint("TOPLEFT", 8, -120)
    progressBg:SetPoint("RIGHT", -8, 0)
    progressBg:SetBackdrop({ bgFile = "Interface/Tooltips/UI-Tooltip-Background" })
    progressBg:SetBackdropColor(0.15, 0.15, 0.15, 1)

    local progressBar = progressBg:CreateTexture(nil, "ARTWORK")
    progressBar:SetPoint("TOPLEFT", 1, -1)
    progressBar:SetPoint("BOTTOMLEFT", 1, 1)
    progressBar:SetWidth(1)
    progressBar:SetColorTexture(0.2, 0.8, 0.2, 0.8)
    frame.progressBar = progressBar
    frame.progressBg = progressBg

    local progressText = progressBg:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    progressText:SetPoint("CENTER", 0, 0)
    progressText:SetTextColor(1, 1, 1)
    frame.progressText = progressText

    -- Scroll frame
    local scrollFrame = CreateFrame("ScrollFrame", "COL_ScrollFrame", frame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 8, -138)
    scrollFrame:SetPoint("BOTTOMRIGHT", -28, 60)

    local content = CreateFrame("Frame", nil, scrollFrame)
    content:SetWidth(324)
    content:SetHeight(1)
    scrollFrame:SetScrollChild(content)
    frame.content = content
    frame.scrollFrame = scrollFrame

    -- Summary line
    local summary = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    summary:SetPoint("BOTTOMLEFT", 8, 36)
    summary:SetPoint("RIGHT", -8, 0)
    summary:SetJustifyH("LEFT")
    summary:SetTextColor(0.7, 0.7, 0.7)
    frame.summary = summary

    -- Bottom buttons
    local clearBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    clearBtn:SetSize(70, 22)
    clearBtn:SetPoint("BOTTOMLEFT", 8, 8)
    clearBtn:SetText("Clear")
    clearBtn.confirmPending = false
    clearBtn:SetScript("OnClick", function(self)
        if self.confirmPending then
            COL.materialList = {}
            COL.recipeName = ""
            COL:UpdateMainFrame()
            self.confirmPending = false
            self:SetText("Clear")
        else
            self.confirmPending = true
            self:SetText("Confirm?")
            C_Timer.After(3, function()
                if self.confirmPending then
                    self.confirmPending = false
                    self:SetText("Clear")
                end
            end)
        end
    end)
    clearBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Clear List", 1, 1, 1)
        GameTooltip:AddLine("Remove all materials from the shopping list.", 0.7, 0.7, 0.7, true)
        GameTooltip:Show()
    end)
    clearBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    local copyBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    copyBtn:SetSize(70, 22)
    copyBtn:SetPoint("LEFT", clearBtn, "RIGHT", 4, 0)
    copyBtn:SetText("Copy")
    copyBtn:SetScript("OnClick", function() COL:CopyListToChat() end)
    copyBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Copy to Chat", 1, 1, 1)
        GameTooltip:AddLine("Copy missing materials to chat or clipboard.", 0.7, 0.7, 0.7, true)
        GameTooltip:Show()
    end)
    copyBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    local uncheckBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    uncheckBtn:SetSize(70, 22)
    uncheckBtn:SetPoint("LEFT", copyBtn, "RIGHT", 4, 0)
    uncheckBtn:SetText("Reset")
    uncheckBtn:SetScript("OnClick", function()
        for _, mat in ipairs(COL.materialList) do
            mat.searched = false
            mat.manualCheck = false
        end
        COL:UpdateMainFrame()
    end)
    uncheckBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Reset Searches", 1, 1, 1)
        GameTooltip:AddLine("Unmark all searched and manually checked items.", 0.7, 0.7, 0.7, true)
        GameTooltip:Show()
    end)
    uncheckBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    local searchNextBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    searchNextBtn:SetSize(90, 22)
    searchNextBtn:SetPoint("LEFT", uncheckBtn, "RIGHT", 4, 0)
    searchNextBtn:SetText("Search Next")
    searchNextBtn:SetScript("OnClick", function() COL:SearchNextMaterial() end)
    searchNextBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Search Next Material", 1, 1, 1)
        GameTooltip:AddLine("Searches the AH for the next material you still need.", 0.7, 0.7, 0.7, true)
        GameTooltip:Show()
    end)
    searchNextBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    frame.searchNextBtn = searchNextBtn

    frame:Hide()
    COL.mainFrame = frame
    return frame
end

-- ============================================================================
-- Material Rows
-- ============================================================================

local function CreateMaterialRow(parent, index)
    local row = CreateFrame("Button", nil, parent, "BackdropTemplate")
    row:SetHeight(32)
    row:SetPoint("TOPLEFT", 0, -((index - 1) * 34))
    row:SetPoint("RIGHT", 0, 0)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    row.highlight = row:CreateTexture(nil, "BACKGROUND")
    row.highlight:SetAllPoints()
    row.highlight:SetColorTexture(1, 1, 1, 0.1)
    row.highlight:Hide()

    row:SetScript("OnEnter", function(self)
        self.highlight:Show()
        if self.itemID then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetItemByID(self.itemID)
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("Right-click to toggle checkmark", 0.7, 0.7, 0.7)
            GameTooltip:Show()
        end
    end)
    row:SetScript("OnLeave", function(self)
        self.highlight:Hide()
        GameTooltip:Hide()
    end)

    row:SetScript("OnClick", function(self, button)
        if button == "RightButton" and self.matIndex then
            local mat = COL.materialList[self.matIndex]
            if mat then
                mat.manualCheck = not mat.manualCheck
                COL:UpdateMainFrame()
            end
        end
    end)

    local icon = row:CreateTexture(nil, "ARTWORK")
    icon:SetSize(28, 28)
    icon:SetPoint("LEFT", 2, 0)
    row.icon = icon

    local checkmark = row:CreateTexture(nil, "OVERLAY")
    checkmark:SetSize(18, 18)
    checkmark:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 4, -4)
    checkmark:SetTexture("Interface\\RaidFrame\\ReadyCheck-Ready")
    checkmark:Hide()
    row.checkmark = checkmark

    local name = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    name:SetPoint("LEFT", icon, "RIGHT", 6, 0)
    name:SetPoint("RIGHT", -145, 0)
    name:SetJustifyH("LEFT")
    name:SetWordWrap(false)
    row.name = name

    local count = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    count:SetPoint("RIGHT", -90, 0)
    count:SetWidth(50)
    count:SetJustifyH("RIGHT")
    row.count = count

    local searchBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    searchBtn:SetSize(80, 22)
    searchBtn:SetPoint("RIGHT", -4, 0)
    searchBtn:SetText("Search AH")
    searchBtn:SetScript("OnClick", function()
        local mat = COL.materialList[row.matIndex]
        if mat then
            local searchName = GetSearchName(mat)
            if not searchName then
                print("|cFFFFCC00COL:|r Item data still loading, try again in a moment.")
                return
            end
            COL:SearchAuctionHouse(searchName)
            mat.searched = true
            COL:UpdateMainFrame()
        end
    end)
    row.searchBtn = searchBtn

    return row
end

-- ============================================================================
-- Frame Updates
-- ============================================================================

function COL:UpdateMainFrame()
    local frame = COL.mainFrame
    if not frame then return end

    frame.recipeName:SetText(COL.recipeName ~= "" and COL.recipeName or "No recipe selected")

    for _, row in ipairs(COL.rows) do
        row:Hide()
    end

    -- Progress
    local total, complete, totalNeeded, totalOwned = GetProgressInfo()
    if total > 0 then
        local pct = totalOwned / totalNeeded
        local barWidth = math.max(1, (frame.progressBg:GetWidth() - 2) * pct)
        frame.progressBar:SetWidth(barWidth)

        if pct >= 1 then
            frame.progressBar:SetColorTexture(0.2, 0.8, 0.2, 0.8)
        elseif pct >= 0.5 then
            frame.progressBar:SetColorTexture(1, 1, 0.2, 0.8)
        else
            frame.progressBar:SetColorTexture(1, 0.3, 0.3, 0.8)
        end

        frame.progressText:SetText(string.format("%d/%d materials complete", complete, total))
        frame.progressBg:Show()
    else
        frame.progressBg:Hide()
    end

    -- Build rows
    local content = frame.content
    local rowIndex = 0

    for i, mat in ipairs(COL.materialList) do
        local needed = GetNeeded(mat)
        local owned = GetOwnedForMaterial(mat)
        local isComplete = owned >= needed

        if not (COL.settings.hideCompleted and isComplete) then
            rowIndex = rowIndex + 1

            local row = COL.rows[rowIndex]
            if not row then
                row = CreateMaterialRow(content, rowIndex)
                COL.rows[rowIndex] = row
            end

            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", 0, -((rowIndex - 1) * 34))
            row:SetPoint("RIGHT", 0, 0)

            if not row.icon or not row.name or not row.count or not row.searchBtn then
                break
            end

            local displayID = mat.reagents and mat.reagents[1] and mat.reagents[1].itemID
            if COL.settings.qualityFilter > 0 and mat.reagents and mat.reagents[COL.settings.qualityFilter] then
                displayID = mat.reagents[COL.settings.qualityFilter].itemID
            end

            row.itemID = displayID
            row.matIndex = i
            row.icon:SetTexture(displayID and C_Item.GetItemIconByID(displayID) or mat.icon)
            row.name:SetText(mat.name or "Unknown")

            local color
            if isComplete then
                color = COLORS.have
            elseif owned > 0 then
                color = COLORS.partial
            else
                color = COLORS.need
            end

            row.count:SetText(string.format("%d/%d", owned, needed))
            row.count:SetTextColor(unpack(color))
            row.name:SetTextColor(unpack(color))

            if mat.manualCheck or isComplete then
                row.checkmark:Show()
            else
                row.checkmark:Hide()
            end

            row:Show()
        end
    end

    content:SetHeight(math.max(1, rowIndex * 34))

    -- Summary line
    if total > 0 then
        local missing = total - complete
        local hiddenCount = COL.settings.hideCompleted and complete or 0
        if missing == 0 then
            frame.summary:SetText("All materials collected!")
            frame.summary:SetTextColor(unpack(COLORS.have))
        elseif hiddenCount > 0 then
            frame.summary:SetText(string.format("Still need %d material%s (%d hidden)", missing, missing == 1 and "" or "s", hiddenCount))
            frame.summary:SetTextColor(0.7, 0.7, 0.7)
        else
            frame.summary:SetText(string.format("Still need %d material%s", missing, missing == 1 and "" or "s"))
            frame.summary:SetTextColor(0.7, 0.7, 0.7)
        end
    else
        frame.summary:SetText("Click 'Get Materials List' on a recipe")
        frame.summary:SetTextColor(unpack(COLORS.dim))
    end

    -- Craft count display
    if frame.craftValue then
        frame.craftValue:SetText(tostring(COL.settings.craftCount))
    end
end

-- ============================================================================
-- Auction House Integration
-- ============================================================================

function COL:SearchAuctionHouse(itemName)
    if not itemName then return end
    itemName = itemName:gsub("^%d+%s+", "")

    if AuctionHouseFrame and AuctionHouseFrame:IsShown() then
        local searchBar = AuctionHouseFrame.SearchBar
        if searchBar and searchBar.SearchBox then
            searchBar.SearchBox:SetText(itemName)
            searchBar.SearchBox:HighlightText()
            if searchBar.SearchButton and searchBar.SearchButton:IsEnabled() then
                searchBar.SearchButton:Click()
            end
        else
            print("|cFFFFCC00COL:|r Search bar not available.")
        end
    else
        print("|cFFFFCC00COL:|r Open the Auction House to search.")
    end
end

function COL:SearchNextMaterial()
    for _, mat in ipairs(COL.materialList) do
        local needed = GetNeeded(mat)
        local owned = GetOwnedForMaterial(mat)
        if owned < needed and not mat.searched then
            local searchName = GetSearchName(mat)
            if searchName then
                COL:SearchAuctionHouse(searchName)
                mat.searched = true
                COL:UpdateMainFrame()
                return
            end
        end
    end
    print("|cFFFFCC00COL:|r All materials searched!")
end

function COL:CopyListToChat()
    if #COL.materialList == 0 then
        print("|cFFFFCC00COL:|r No materials in list.")
        return
    end

    local parts = {}
    for _, mat in ipairs(COL.materialList) do
        local needed = GetNeeded(mat)
        local owned = GetOwnedForMaterial(mat)
        local need = needed - owned
        if need > 0 then
            table.insert(parts, need .. "x " .. mat.name)
        end
    end

    if #parts == 0 then
        print("|cFFFFCC00COL:|r You have all materials!")
        return
    end

    local text = "Need: " .. table.concat(parts, ", ")

    -- Try to paste directly into chat edit box if open
    local chatBox = ChatFrame1EditBox
    if chatBox and chatBox:IsShown() then
        chatBox:Insert(text)
        print("|cFFFFCC00COL:|r Pasted into chat.")
        return
    end

    -- Fallback: popup edit box for Ctrl+C
    if not COL.editBox then
        local eb = CreateFrame("EditBox", "COL_CopyBox", UIParent, "InputBoxTemplate")
        eb:SetSize(400, 30)
        eb:SetPoint("TOP", 0, -100)
        eb:SetAutoFocus(true)
        eb:SetScript("OnEscapePressed", function(self) self:Hide() end)
        eb:SetScript("OnEnterPressed", function(self) self:Hide() end)
        eb:Hide()
        COL.editBox = eb
    end

    COL.editBox:SetText(text)
    COL.editBox:Show()
    COL.editBox:HighlightText()
    COL.editBox:SetFocus()
    print("|cFFFFCC00COL:|r Press Ctrl+C to copy, then Escape to close.")
end

-- ============================================================================
-- Frame Visibility
-- ============================================================================

function COL:ToggleFrame()
    local frame = COL.mainFrame or CreateMainFrame()
    if frame:IsShown() then
        frame:Hide()
    else
        frame:Show()
        COL:UpdateMainFrame()
    end
end

function COL:ShowFrame()
    local frame = COL.mainFrame or CreateMainFrame()
    frame:Show()
    COL:UpdateMainFrame()
end

function COL:DockToAuctionHouse()
    if not COL.mainFrame or not AuctionHouseFrame then return end
    if COL.settings.framePos then return end -- Respect saved position

    COL.mainFrame:ClearAllPoints()
    COL.mainFrame:SetPoint("TOPLEFT", AuctionHouseFrame, "TOPRIGHT", 5, 0)
end

-- ============================================================================
-- Minimap Button
-- ============================================================================

local function CreateMinimapButton()
    local btn = CreateFrame("Button", "COL_MinimapButton", Minimap)
    btn:SetSize(36, 36)
    btn:SetFrameStrata("MEDIUM")
    btn:SetFrameLevel(8)
    btn:RegisterForDrag("LeftButton")

    -- Border ring (anchor everything relative to this)
    local overlay = btn:CreateTexture(nil, "OVERLAY")
    overlay:SetSize(56, 56)
    overlay:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    overlay:SetPoint("TOPLEFT", 0, 0)

    -- Dark background circle behind the icon
    local iconBg = btn:CreateTexture(nil, "BACKGROUND", nil, -1)
    iconBg:SetSize(28, 28)
    iconBg:SetPoint("CENTER", overlay, "TOPLEFT", 18, -18)
    iconBg:SetColorTexture(0, 0, 0, 1)

    local bgMask = btn:CreateMaskTexture()
    bgMask:SetSize(28, 28)
    bgMask:SetPoint("CENTER", overlay, "TOPLEFT", 18, -18)
    bgMask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    iconBg:AddMaskTexture(bgMask)

    -- Custom icon centered on the visible ring
    local icon = btn:CreateTexture(nil, "BACKGROUND")
    icon:SetSize(28, 28)
    icon:SetPoint("CENTER", overlay, "TOPLEFT", 18, -18)
    icon:SetTexture("Interface\\AddOns\\CraftOrderList\\Icon")

    local mask = btn:CreateMaskTexture()
    mask:SetSize(28, 28)
    mask:SetPoint("CENTER", overlay, "TOPLEFT", 18, -18)
    mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    icon:AddMaskTexture(mask)

    -- Highlight glow
    local highlight = btn:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetSize(28, 28)
    highlight:SetPoint("CENTER", overlay, "TOPLEFT", 18, -18)
    highlight:SetTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    highlight:SetBlendMode("ADD")

    btn.icon = icon

    local angle = COL.settings.minimapAngle or 220
    local function UpdatePosition()
        local rad = math.rad(angle)
        local x = math.cos(rad) * 80
        local y = math.sin(rad) * 80
        btn:SetPoint("CENTER", Minimap, "CENTER", x, y)
    end

    btn:SetScript("OnDragStart", function(self)
        self.dragging = true
    end)
    btn:SetScript("OnDragStop", function(self)
        self.dragging = false
    end)
    btn:SetScript("OnUpdate", function(self)
        if not self.dragging then return end
        local mx, my = Minimap:GetCenter()
        local cx, cy = GetCursorPosition()
        local scale = UIParent:GetEffectiveScale()
        cx, cy = cx / scale, cy / scale
        angle = math.deg(math.atan2(cy - my, cx - mx))
        COL.settings.minimapAngle = angle
        UpdatePosition()
    end)

    btn:SetScript("OnClick", function()
        COL:ToggleFrame()
    end)
    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("Craft Order List", 1, 0.82, 0)
        GameTooltip:AddLine("Click to toggle materials list.", 0.7, 0.7, 0.7)
        GameTooltip:AddLine("Drag to reposition.", 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    UpdatePosition()
    COL.minimapButton = btn
end

-- ============================================================================
-- Integration Buttons
-- ============================================================================

local function CreateGetMaterialsButton(parent, getRecipeFunc)
    local parentName = parent:GetName() or ("COL_Anon_" .. tostring(parent))
    local buttonName = parentName .. "_COL_Btn"

    if COL.buttonsCreated[buttonName] then return COL.buttonsCreated[buttonName] end

    local btn = CreateFrame("Button", buttonName, parent, "UIPanelButtonTemplate")
    btn:SetSize(130, 22)
    btn:SetText("Get Materials List")
    btn:SetScript("OnClick", function()
        local recipeID = getRecipeFunc()
        if recipeID then
            local addToExisting = #COL.materialList > 0
            if BuildMaterialList(recipeID, addToExisting) then
                COL:ShowFrame()
                if addToExisting then
                    print("|cFFFFCC00COL:|r Added to material list.")
                else
                    print("|cFFFFCC00COL:|r Material list ready!")
                end
            else
                print("|cFFFFCC00COL:|r No basic materials found.")
            end
        else
            print("|cFFFFCC00COL:|r No recipe selected.")
        end
    end)
    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Get Materials List", 1, 1, 1)
        if #COL.materialList > 0 then
            GameTooltip:AddLine("Adds to existing list", 0.7, 0.7, 0.7)
        else
            GameTooltip:AddLine("Creates new shopping list", 0.7, 0.7, 0.7)
        end
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    COL.buttonsCreated[buttonName] = btn
    return btn
end

local function SetupProfessionsButton()
    if not ProfessionsFrame or not ProfessionsFrame.CraftingPage then return end
    local craftingPage = ProfessionsFrame.CraftingPage
    if not craftingPage.CreateAllButton then return end

    local btn = CreateGetMaterialsButton(craftingPage, function()
        if craftingPage.SchematicForm and craftingPage.SchematicForm.transaction then
            return craftingPage.SchematicForm.transaction:GetRecipeID()
        end
        return nil
    end)

    if btn then
        btn:SetPoint("RIGHT", craftingPage.CreateAllButton, "LEFT", -5, 0)
    end
end

local function SetupCraftingOrderButton()
    if not ProfessionsCustomerOrdersFrame then return end
    local frame = ProfessionsCustomerOrdersFrame
    local buttonName = "COL_CraftingOrderButton"

    if COL.buttonsCreated[buttonName] then return end

    local btn = CreateFrame("Button", buttonName, frame, "UIPanelButtonTemplate")
    btn:SetSize(130, 22)
    btn:SetText("Get Materials List")
    btn:SetFrameStrata("HIGH")
    btn:SetFrameLevel(100)

    local function GetRecipeID()
        if frame.Form and frame.Form.transaction then
            return frame.Form.transaction:GetRecipeID()
        end
        return nil
    end

    btn:SetScript("OnClick", function()
        local recipeID = GetRecipeID()
        if recipeID then
            local addToExisting = #COL.materialList > 0
            if BuildMaterialList(recipeID, addToExisting) then
                COL:ShowFrame()
                if addToExisting then
                    print("|cFFFFCC00COL:|r Added to material list.")
                else
                    print("|cFFFFCC00COL:|r Material list ready!")
                end
            end
        end
    end)

    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Get Materials List", 1, 1, 1)
        if #COL.materialList > 0 then
            GameTooltip:AddLine("Adds to existing list", 0.7, 0.7, 0.7)
        else
            GameTooltip:AddLine("Creates new shopping list", 0.7, 0.7, 0.7)
        end
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    local function PositionButton()
        btn:ClearAllPoints()
        btn:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -15, 5)
    end

    local function UpdateVisibility()
        if frame.Form and frame.Form:IsVisible() then
            PositionButton()
            btn:Show()
        else
            btn:Hide()
        end
    end

    frame:HookScript("OnShow", function() C_Timer.After(0.1, UpdateVisibility) end)
    frame:HookScript("OnHide", function() btn:Hide() end)
    if frame.Form then
        frame.Form:HookScript("OnShow", function() C_Timer.After(0.1, UpdateVisibility) end)
    end

    C_Timer.After(0.2, UpdateVisibility)
    COL.buttonsCreated[buttonName] = true
end

local function SetupAuctionHouseToggle()
    if not AuctionHouseFrame then return end
    local buttonName = "COL_AHToggleButton"
    if COL.buttonsCreated[buttonName] then return end

    local btn = CreateFrame("Button", buttonName, AuctionHouseFrame, "UIPanelButtonTemplate")
    btn:SetSize(100, 22)
    btn:SetText("Materials")

    local searchBar = AuctionHouseFrame.SearchBar
    if searchBar and searchBar.FavoritesSearchButton then
        btn:SetPoint("RIGHT", searchBar.FavoritesSearchButton, "LEFT", -5, 0)
    elseif searchBar then
        btn:SetPoint("RIGHT", searchBar, "RIGHT", -30, 0)
    else
        btn:SetPoint("TOPRIGHT", AuctionHouseFrame, "TOPRIGHT", -60, -30)
    end

    btn:SetScript("OnClick", function() COL:ToggleFrame() end)
    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Crafting Materials", 1, 1, 1)
        GameTooltip:AddLine("Toggle your crafting materials shopping list.", 0.7, 0.7, 0.7, true)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    COL.buttonsCreated[buttonName] = true
end

-- ============================================================================
-- Saved Variables
-- ============================================================================

local function LoadSettings()
    if not COL_SavedData then return end

    if COL_SavedData.settings then
        for k, v in pairs(COL_SavedData.settings) do
            COL.settings[k] = v
        end
    end

    -- Validate loaded settings
    COL.settings.craftCount = math.max(1, math.min(999, tonumber(COL.settings.craftCount) or 1))
    COL.settings.qualityFilter = tonumber(COL.settings.qualityFilter) or 0
    if COL.settings.qualityFilter < 0 or COL.settings.qualityFilter > 3 then
        COL.settings.qualityFilter = 0
    end
    local validSorts = { name = true, needed = true, status = true }
    if not validSorts[COL.settings.sortBy] then
        COL.settings.sortBy = "name"
    end
    if type(COL.settings.hideCompleted) ~= "boolean" then
        COL.settings.hideCompleted = false
    end

    if COL_SavedData.materialList and #COL_SavedData.materialList > 0 then
        COL.materialList = COL_SavedData.materialList
        COL.recipeName = COL_SavedData.recipeName or ""
    end
end

local function SaveSettings()
    COL_SavedData = {
        settings = {
            qualityFilter = COL.settings.qualityFilter,
            hideCompleted = COL.settings.hideCompleted,
            sortBy = COL.settings.sortBy,
            craftCount = COL.settings.craftCount,
            framePos = COL.settings.framePos,
            minimapAngle = COL.settings.minimapAngle,
        },
        materialList = COL.materialList,
        recipeName = COL.recipeName,
    }
end

local function ApplySettings()
    if not COL.mainFrame then return end

    local qf = COL.settings.qualityFilter
    UIDropDownMenu_SetText(COL_QualityDropdown, QUALITY_ICONS[qf])
    COL_HideCompleted:SetChecked(COL.settings.hideCompleted)

    if COL.mainFrame.SORT_LABELS then
        UIDropDownMenu_SetText(COL_SortDropdown, COL.mainFrame.SORT_LABELS[COL.settings.sortBy] or "Name")
    end

    if COL.mainFrame.craftValue then
        COL.mainFrame.craftValue:SetText(tostring(COL.settings.craftCount))
    end

    if COL.settings.framePos then
        local pos = COL.settings.framePos
        COL.mainFrame:ClearAllPoints()
        COL.mainFrame:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
    end
end

-- ============================================================================
-- Event Handling
-- ============================================================================

local bagUpdatePending = false
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("TRADE_SKILL_SHOW")
eventFrame:RegisterEvent("AUCTION_HOUSE_SHOW")
eventFrame:RegisterEvent("BAG_UPDATE")
eventFrame:RegisterEvent("BAG_UPDATE_DELAYED")
eventFrame:RegisterEvent("GET_ITEM_INFO_RECEIVED")
eventFrame:RegisterEvent("CRAFTINGORDERS_CAN_REQUEST")
eventFrame:RegisterEvent("MAIL_INBOX_UPDATE")
eventFrame:RegisterEvent("TRADE_ACCEPT_UPDATE")
eventFrame:RegisterEvent("PLAYER_LOGOUT")

eventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        local loadedAddon = ...
        if loadedAddon == addonName then
            LoadSettings()
            CreateMainFrame()
            CreateMinimapButton()
            ApplySettings()
            COL:UpdateMainFrame()
            print("|cFFFFCC00CraftOrderList|r loaded. /col to toggle.")
        elseif loadedAddon == "Blizzard_Professions" then
            C_Timer.After(0.1, SetupProfessionsButton)
        elseif loadedAddon == "Blizzard_ProfessionsCustomerOrders" then
            C_Timer.After(0.1, SetupCraftingOrderButton)
        elseif loadedAddon == "Blizzard_AuctionHouseUI" then
            C_Timer.After(0.1, SetupAuctionHouseToggle)
        end

    elseif event == "TRADE_SKILL_SHOW" then
        SetupProfessionsButton()

    elseif event == "AUCTION_HOUSE_SHOW" then
        SetupAuctionHouseToggle()
        if #COL.materialList > 0 then
            COL:ShowFrame()
            COL:DockToAuctionHouse()
        end

    elseif event == "CRAFTINGORDERS_CAN_REQUEST" then
        C_Timer.After(0.2, SetupCraftingOrderButton)

    elseif event == "BAG_UPDATE" or event == "BAG_UPDATE_DELAYED"
        or event == "MAIL_INBOX_UPDATE" or event == "TRADE_ACCEPT_UPDATE" then
        if COL.mainFrame and COL.mainFrame:IsShown() and not bagUpdatePending then
            bagUpdatePending = true
            C_Timer.After(0.3, function()
                bagUpdatePending = false
                if COL.mainFrame and COL.mainFrame:IsShown() then
                    COL:UpdateMainFrame()
                end
            end)
        end

    elseif event == "GET_ITEM_INFO_RECEIVED" then
        local itemID = ...
        if not itemID then return end

        for _, mat in ipairs(COL.materialList) do
            -- Only update display name from the base reagent (index 1)
            if mat.reagents and mat.reagents[1] and mat.reagents[1].itemID == itemID then
                local name = C_Item.GetItemNameByID(itemID)
                if name and name ~= "" then
                    mat.name = name:gsub(" %|A.-|a$", "")
                end
            end
        end

        if COL.mainFrame and COL.mainFrame:IsShown() then
            COL:UpdateMainFrame()
        end

    elseif event == "PLAYER_LOGOUT" then
        SaveSettings()
    end
end)

-- ============================================================================
-- Slash Commands
-- ============================================================================

SLASH_COL1 = "/col"
SLASH_COL2 = "/craftorderlist"
SlashCmdList["COL"] = function(msg)
    msg = (msg or ""):lower():trim()
    if msg == "" then
        COL:ToggleFrame()
    elseif msg == "show" then
        COL:ShowFrame()
    elseif msg == "hide" then
        if COL.mainFrame then COL.mainFrame:Hide() end
    elseif msg == "clear" then
        COL.materialList = {}
        COL.recipeName = ""
        COL:UpdateMainFrame()
        print("|cFFFFCC00COL:|r List cleared.")
    elseif msg == "reset" then
        COL.settings.framePos = nil
        if COL.mainFrame then
            COL.mainFrame:ClearAllPoints()
            COL.mainFrame:SetPoint("CENTER", UIParent, "CENTER", 400, 0)
        end
        print("|cFFFFCC00COL:|r Window position reset.")
    elseif msg == "help" then
        print("|cFFFFCC00Craft Order List commands:|r")
        print("  /col — Toggle the materials window")
        print("  /col show — Show the materials window")
        print("  /col hide — Hide the materials window")
        print("  /col clear — Clear the shopping list")
        print("  /col reset — Reset window position")
        print("  /col help — Show this help message")
    else
        print("|cFFFFCC00COL:|r Unknown command '" .. msg .. "'. Type /col help for options.")
    end
end
