-- Legacy unit tests for CraftingOrderHelper
-- Run: lua5.3 tests/test_addon.lua

local passed, failed = 0, 0

local function test(name, fn)
    local ok, err = pcall(fn)
    if ok then
        passed = passed + 1
        print("  PASS: " .. name)
    else
        failed = failed + 1
        print("  FAIL: " .. name .. " — " .. tostring(err))
    end
end

local function assertEqual(a, b) assert(a == b, "Expected " .. tostring(b) .. ", got " .. tostring(a)) end
local function assertNotNil(a) assert(a ~= nil, "Expected non-nil") end

-- Mock WoW API
CreateFrame = function() return {
    _scripts = {},
    SetScript = function(self, s, h) self._scripts[s] = h end,
    RegisterEvent = function() end,
    UnregisterEvent = function() end,
} end
UIParent = {}
UISpecialFrames = {}
SlashCmdList = {}
C_Timer = { After = function(_, f) f() end }
C_AddOns = { GetAddOnMetadata = function(_, f) if f == "Version" then return "test" end return nil end }
UnitName = function() return "TestPlayer" end
GetRealmName = function() return "TestRealm" end
function strsplit(d, s) local p = s:find(d); if p then return s:sub(1, p-1), s:sub(p+1) end; return s, nil end
function strtrim(s) return s and s:match("^%s*(.-)%s*$") or "" end

-- Load addon
print("Loading CraftingOrderHelper...")
dofile("CraftingOrderHelper.lua")

print("\n=== CraftingOrderHelper Tests ===\n")

test("addon frame exists", function()
    assertNotNil(CraftingOrderHelper)
end)

test("slash command registered", function()
    assertNotNil(SlashCmdList["CRAFTINGORDERHELPER"])
end)

test("settings table initializes", function()
    CraftingOrderHelperSettings = nil
    local handler = CraftingOrderHelper._scripts["OnEvent"]
    handler(CraftingOrderHelper, "ADDON_LOADED", "CraftingOrderHelper")
    assertNotNil(CraftingOrderHelperSettings)
end)

-- Summary
print(string.format("\n=== Results: %d passed, %d failed ===", passed, failed))
if failed > 0 then os.exit(1) end
