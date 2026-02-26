-- CraftingOrderHelper
-- Helps manage and track crafting orders

local addonName = "CraftingOrderHelper"
CraftingOrderHelper = CreateFrame("Frame")
CraftingOrderHelperSettings = CraftingOrderHelperSettings or {}

-- Slash command
SLASH_CRAFTINGORDERHELPER1 = "/coh"
SlashCmdList["CRAFTINGORDERHELPER"] = function(msg)
    print("|cff00ccff" .. addonName .. "|r: v" .. (C_AddOns.GetAddOnMetadata(addonName, "Version") or "?"))
end

-- Event handling
CraftingOrderHelper:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" and ... == addonName then
        -- Initialize saved variables
        CraftingOrderHelperSettings = CraftingOrderHelperSettings or {}
        print("|cff00ccff" .. addonName .. "|r loaded.")
    end
end)

CraftingOrderHelper:RegisterEvent("ADDON_LOADED")
