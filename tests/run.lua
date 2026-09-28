-- Tests for CampKit's pure helpers. Run from the repo root: lua tests/run.lua
-- Loads CampKit.lua with just enough of the WoW API stubbed for the file to load.

local function stub()
    return setmetatable({}, { __index = function() return function() end end })
end
CreateFrame = stub
SlashCmdList = {}

local ns = {}
assert(loadfile("CampKit.lua"))("CampKit", ns)

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
check("other buff", F("Arcane Intellect", 1459), false)
check("no data", F(nil, nil), false)

print(("%d/%d passed"):format(total - failures, total))
os.exit(failures == 0 and 0 or 1)
