-- Busted test suite for CraftingOrderHelper

describe("CraftingOrderHelper", function()
    local MockData

    setup(function()
        MockData = _G.MockData
        dofile("CraftingOrderHelper.lua")
    end)

    before_each(function()
        -- Reset state before each test
        CraftingOrderHelperSettings = {}
    end)

    describe("initialization", function()
        it("should create the addon frame", function()
            assert.is_not_nil(CraftingOrderHelper)
        end)

        it("should register ADDON_LOADED event", function()
            assert.is_true(MockData.registeredEvents["ADDON_LOADED"])
        end)

        it("should initialize settings table", function()
            -- Fire ADDON_LOADED
            local handler = CraftingOrderHelper._scripts["OnEvent"]
            handler(CraftingOrderHelper, "ADDON_LOADED", "CraftingOrderHelper")
            assert.is_table(CraftingOrderHelperSettings)
        end)
    end)
end)
