-- Tests for CampKit's pure helpers. Run from the repo root: lua tests/run.lua
-- Loads CampKit.lua with just enough of the WoW API stubbed for the file to load.

local function stub()
    return setmetatable({}, { __index = function() return function() end end })
end
CreateFrame = stub
SlashCmdList = {}
StaticPopupDialogs = {}

-- A fake bag: slot -> { itemID, name }. Items listed in USABLE have a use effect.
local BAG = {}
local USABLE = {}
C_Container = {
    GetContainerNumSlots = function(bag) return bag == 0 and #BAG or 0 end,
    GetContainerItemInfo = function(bag, slot)
        local item = bag == 0 and BAG[slot]
        if item then return { itemID = item[1], hyperlink = "[" .. item[2] .. "]", stackCount = 1 } end
    end,
}
C_Item = {
    GetItemSpell = function(id) return USABLE[id] and "Use" or nil end,
    GetItemNameByID = function(id) return "item" .. id end,
}

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

-- AntsFrameCoords: 22 frames, 5 per row, each 48/256 wide
local A = ns.AntsFrameCoords
local cell = 48 / 256
local function near(a, b) return math.abs(a - b) < 1e-9 end
local l, r, t, b = A(0)
check("ants frame 0", near(l, 0) and near(r, cell) and near(t, 0) and near(b, cell), true)
l, r, t, b = A(6)
check("ants frame 6 is row 2, col 2", near(l, cell) and near(t, cell), true)
l, r, t, b = A(21)
check("last ants frame stays on the sheet", r <= 1 and b <= 1, true)

-- ClampSetting
local S = ns.ClampSetting
check("button size in range", S("buttonSize", 44), 44)
check("button size below min", S("buttonSize", 4), 24)
check("button size above max", S("buttonSize", 200), 64)
check("button size snaps to step", S("buttonSize", 42), 44)
check("font size in range", S("cooldownFontSize", 11), 11)
check("font size below min", S("cooldownFontSize", 7), 8)

-- BagItemsToAdd: usable, not already on the flyout, not the campfire, no duplicates, sorted
CampKitCharDB = { learned = { [279978] = true }, hidden = {}, extra = {} }
BAG = { { 2, "Zesty Stew" }, { 279978, "Camp Tent" }, { 3, "Rusty Sword" },
    { 279981, "Basic Campfire Kit" }, { 4, "Apple" }, { 2, "Zesty Stew" } }
USABLE = { [2] = true, [279978] = true, [279981] = true, [4] = true }
local picks = ns.BagItemsToAdd()
check("picker offers 2 items", #picks, 2)
check("picker sorts by name", picks[1] and picks[1].name, "Apple")
check("picker second item", picks[2] and picks[2].name, "Zesty Stew")
CampKitCharDB = nil

-- Wiring between the files
check("fire glow is on by default", ns.Get.fireGlow(), true)
CampKitDB = { fireGlow = false }
check("fire glow can be turned off", ns.Get.fireGlow(), false)
CampKitDB = nil
check("settings page hooked up", type(ns.OnChanged), "function")
check("restore defaults dialog", type(StaticPopupDialogs.CAMPKIT_RESTORE_DEFAULTS), "table")
for _, name in ipairs({ "SetDirection", "SetHideInCombat", "SetLocked", "SetFireGlow", "SetButtonSize",
        "SetCooldownFontSize", "AddItem", "RemoveItem", "Rescan", "RestoreDefaults", "ResetPosition" }) do
    check("action " .. name, type(ns.actions[name]), "function")
end

print(("%d/%d passed"):format(total - failures, total))
os.exit(failures == 0 and 0 or 1)
