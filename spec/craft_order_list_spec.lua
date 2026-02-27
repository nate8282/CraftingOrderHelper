-- Busted test suite for CraftOrderList

describe("CraftOrderList", function()
    local MockData
    local COL

    setup(function()
        MockData = _G.MockData
        loadfile("CraftOrderList.lua")("CraftOrderList", {})
    end)

    before_each(function()
        COL_SavedData = nil
        MockData.itemCounts = {}
        MockData.itemNames = {}
        MockData.recipeInfos = {}
        MockData.recipeSchematics = {}
    end)

    describe("initialization", function()
        it("should register expected events", function()
            assert.is_true(MockData.registeredEvents["ADDON_LOADED"])
            assert.is_true(MockData.registeredEvents["BAG_UPDATE"])
            assert.is_true(MockData.registeredEvents["PLAYER_LOGOUT"])
        end)

        it("should register slash commands", function()
            assert.is_not_nil(SlashCmdList["COL"])
        end)
    end)

    describe("slash commands", function()
        it("should handle /col clear", function()
            SlashCmdList["COL"]("clear")
            -- Should not error
        end)

        it("should handle /col reset", function()
            SlashCmdList["COL"]("reset")
            -- Should not error
        end)

        it("should handle /col show", function()
            SlashCmdList["COL"]("show")
        end)

        it("should handle /col hide", function()
            SlashCmdList["COL"]("hide")
        end)
    end)
end)
