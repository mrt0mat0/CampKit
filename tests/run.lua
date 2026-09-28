-- Tests for CampKit's pure helpers. Run from the repo root: lua tests/run.lua
-- Loads CampKit.lua with just enough of the WoW API stubbed for the file to load.

local function stub()
    return setmetatable({}, { __index = function() return function() end end })
end
CreateFrame = stub
SlashCmdList = {}
StaticPopupDialogs = {}

-- Load both files the way the game does: in .toc order, sharing one namespace.
local ns = {}
assert(loadfile("CampKit.lua"))("CampKit", ns)
assert(loadfile("Options.lua"))("CampKit", ns)

local failures, total = 0, 0
local function check(name, got, want)
    total = total + 1
    if got ~= want then
        failures = failures + 1
        print(("FAIL %s: got %s, want %s"):format(name, tostring(got), tostring(want)))
    end
end

-- ChooseDirection
local C = ns.ChooseDirection
check("fits: keep up", C("UP", { UP = 300, DOWN = 50 }, 200), "UP")
check("no room up, room down: flip", C("UP", { UP = 40, DOWN = 600 }, 200), "DOWN")
check("no room either way, more down: flip", C("UP", { UP = 40, DOWN = 100 }, 200), "DOWN")
check("no room either way, more up: keep", C("UP", { UP = 100, DOWN = 40 }, 200), "UP")
check("no room left, room right: flip", C("LEFT", { LEFT = 10, RIGHT = 900 }, 200), "RIGHT")
check("exact fit keeps direction", C("DOWN", { DOWN = 200, UP = 900 }, 200), "DOWN")
check("round is never flipped", C("ROUND", {}, 200), "ROUND")

-- IsFireAura
local F = ns.IsFireAura
check("fire by spell ID", F("Whatever", 7353), true)
check("fire by name, any case", F("Cozy Fire", nil), true)
check("WoW Forever fire buff by name", F("Campfire Nearby", nil), true)
check("other buff", F("Arcane Intellect", 1459), false)
check("no data", F(nil, nil), false)

-- ClampSetting
local S = ns.ClampSetting
check("button size in range", S("buttonSize", 44), 44)
check("button size below min", S("buttonSize", 4), 24)
check("button size above max", S("buttonSize", 200), 64)
check("button size snaps to step", S("buttonSize", 42), 44)
check("font size in range", S("cooldownFontSize", 11), 11)
check("font size below min", S("cooldownFontSize", 7), 8)

-- Wiring between the files
check("settings page hooked up", type(ns.OnChanged), "function")
check("restore defaults dialog", type(StaticPopupDialogs.CAMPKIT_RESTORE_DEFAULTS), "table")
for _, name in ipairs({ "SetDirection", "SetHideInCombat", "SetLocked", "SetButtonSize",
        "SetCooldownFontSize", "AddItem", "RemoveItem", "Rescan", "RestoreDefaults", "ResetPosition" }) do
    check("action " .. name, type(ns.actions[name]), "function")
end

print(("%d/%d passed"):format(total - failures, total))
os.exit(failures == 0 and 0 or 1)
