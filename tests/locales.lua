-- Checks every translation file against the strings the addon actually uses.
-- Run from the repo root: lua tests/locales.lua
-- A key the code doesn't use is a typo (it would never show); a translation whose %d/%s
-- don't match the English in the same order would throw an error in game.

local function read(path)
    local f = assert(io.open(path, "r"))
    local text = f:read("a")
    f:close()
    return text
end

-- Every English string the code looks up.
local used = {}
for _, file in ipairs({ "CampKit.lua", "Options.lua" }) do
    local src = read(file)
    for key in src:gmatch('L%["(.-)"%]') do used[key] = true end
    for key in src:gmatch('{ "/campkit[^"]*", "([^"]+)" }') do used[key] = true end
end
for _, word in ipairs({ "up", "down", "left", "right" }) do used[word] = true end

local function specifiers(text)
    local list = {}
    for spec in text:gmatch("%%[ds]") do list[#list + 1] = spec end
    return table.concat(list, ",")
end

local failures, files = 0, 0
local function fail(msg)
    failures = failures + 1
    print("FAIL " .. msg)
end

local toc = read("CampKit.toc")
for path in toc:gmatch("(Locales/(%a%a%u%u)%.lua)") do
    local locale = path:match("Locales/(%a%a%u%u)%.lua")
    files = files + 1
    local L = {}
    local ns = { locale = locale, L = L }
    local chunk, err = loadfile(path)
    if not chunk then
        fail(err)
    else
        chunk("CampKit", ns)
        local count = 0
        for key, value in pairs(L) do
            count = count + 1
            if not used[key] then fail(("%s: key not used by the addon: %q"):format(locale, key)) end
            if specifiers(key) ~= specifiers(value) then
                fail(("%s: %%d/%%s don't match for %q"):format(locale, key))
            end
            if value:find("\226\128\148") then fail(("%s: em dash in %q"):format(locale, key)) end
        end
        local missing = 0
        for key in pairs(used) do if L[key] == nil then missing = missing + 1 end end
        if missing > 0 then fail(("%s: %d strings not translated"):format(locale, missing)) end
        -- Another client's file must stay empty.
        local other = {}
        loadfile(path)("CampKit", { locale = "enUS", L = other })
        if next(other) then fail(locale .. ": translations load on an English client") end
    end
end

if files == 0 then fail("no locale files listed in CampKit.toc") end
print(("%d locale files checked, %d problems"):format(files, failures))
os.exit(failures == 0 and 0 or 1)
