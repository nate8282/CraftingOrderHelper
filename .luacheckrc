std = "lua51"
max_line_length = false

exclude_files = {
    "Libs/**",
    "libs/**",
    ".release/**",
    ".luacheckrc",
}

ignore = {
    "11./SLASH_.*",     -- Slash command globals (SLASH_CRAFTINGORDERHELPER1, etc.)
    "11./BINDING_.*",   -- Keybinding globals
    "212",              -- Unused arguments (WoW callbacks have fixed signatures)
    "432",              -- Shadowing upvalue 'self' (intentional in WoW SetScript callbacks and method defs)
}

-- Globals the addon WRITES to
globals = {
    "CraftingOrderHelper",
    "CraftingOrderHelperSettings",
    "SlashCmdList",
    "UISpecialFrames",
}

-- WoW API functions the addon READS (organized by category)
-- NOTE: Update this list as you add new WoW API calls to the addon
read_globals = {
    -- Frame system
    "CreateFrame",
    "UIParent",

    -- Player info
    "UnitName",
    "GetRealmName",

    -- Profession / Trade Skill API
    "GetProfessions",
    "GetProfessionInfo",

    -- Addon metadata
    "C_AddOns",

    -- Utility
    "C_Timer",
    "strsplit",
    "strtrim",
}

-- Busted test files mock the entire WoW API as globals
files["spec/**"] = {
    globals = {
        "CreateFrame", "UIParent", "UISpecialFrames",
        "UnitName", "GetRealmName",
        "GetProfessions", "GetProfessionInfo",
        "strsplit", "strtrim",
        "C_Timer", "C_AddOns", "SlashCmdList",
        "CraftingOrderHelper", "CraftingOrderHelperSettings", "MockData",
    },
    ignore = {
        "211",  -- Unused local variable (mock data)
        "212",  -- Unused argument (mock signatures)
        "213",  -- Unused loop variable
    },
    read_globals = {
        "dofile", "setmetatable", "os",
        -- Busted globals
        "describe", "it", "setup", "teardown",
        "before_each", "after_each",
        "assert", "spy", "stub", "mock", "match",
        "insulate", "expose",
    },
}

-- Legacy test files (custom runner)
files["tests/**"] = {
    globals = {
        "CreateFrame", "UIParent", "UISpecialFrames",
        "UnitName", "GetRealmName",
        "GetProfessions", "GetProfessionInfo",
        "strsplit", "strtrim",
        "C_Timer", "C_AddOns", "SlashCmdList",
        "CraftingOrderHelper", "CraftingOrderHelperSettings",
    },
    ignore = { "211", "212", "213", "311" },
    read_globals = { "dofile", "setmetatable", "os" },
}
