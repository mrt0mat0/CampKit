-- CampKit: a standalone, movable campfire button with a hover flyout of camp items.
-- Left-click the main button to set down your campfire; right-drag it to move it.
-- Hover it to see your other camp items, each with the number you're carrying.

---------------------------------------------------------------------------
-- CONFIGURATION: edit these to match your items.
-- Item IDs (numbers) are the most reliable. Exact item names in quotes also work.
---------------------------------------------------------------------------
local MAIN = { kind = "item", value = 279981 }   -- Basic Campfire Kit
-- If your campfire is a spell instead of an item, use:
-- local MAIN = { kind = "spell", value = "Basic Campfire" }

-- Camp items are found automatically: any camping recipe you know (read from your
-- profession windows) and any camping item in your bags. Known recipes stay on the
-- flyout at 0, so you can see what to craft more of. Anything else you want on the
-- flyout, like the Cozy Sleeping Bag, can be added with /campkit add in game.

-- Camp items CampKit recognizes even before reading their tooltips.
local KNOWN_CAMP_ITEMS = {
    [279960] = true,   -- Lodestone (Mining)
    [279967] = true,   -- Fish Bowl (Fishing)
    [279968] = true,   -- First Aid Kit (First Aid)
    [279978] = true,   -- Camp Tent (Leatherworking)
    [279979] = true,   -- Camp Chair (Skinning)
}

-- Tooltip text that marks an item as a camp object (checked in lowercase).
local CAMP_TEXT = { "requires a campfire nearby", "camping features share a cooldown" }

-- The buff you get standing near a campfire: spell IDs, or names in lowercase.
-- /campkit buffs lists your current buffs with their IDs if yours isn't here.
local FIRE_AURAS = {
    [7353] = true,          -- Cozy Fire
    ["cozy fire"] = true,
}

local BUTTON_SIZE = 40
local SPACING     = 4
local DIRECTION   = "ROUND" -- which way the flyout opens: "UP", "DOWN", "LEFT", "RIGHT" or "ROUND"
local HIDE_DELAY  = 0.3     -- seconds the flyout stays open after the mouse leaves
local COOLDOWN_FONT_SIZE = 11   -- the countdown number in the middle of a button
---------------------------------------------------------------------------

local QUESTION_MARK = 134400
local CIRCLE = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local GLOW   = "Interface\\Buttons\\UI-ActionButton-Border"
local VALID_DIRECTIONS = { up = "UP", down = "DOWN", left = "LEFT", right = "RIGHT", round = "ROUND" }

-- API shims: the modern client uses C_Item / C_Container / C_Spell, older ones use globals.
local GetCount = (C_Item and C_Item.GetItemCount) or GetItemCount
local GetInfoInstant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
local GetItemCD = (C_Container and C_Container.GetItemCooldown) or GetItemCooldown

local function GetSpellIcon(spell)
    if C_Spell and C_Spell.GetSpellTexture then return C_Spell.GetSpellTexture(spell) end
    if GetSpellTexture then return GetSpellTexture(spell) end
end

local function GetSpellCD(spell)
    if C_Spell and C_Spell.GetSpellCooldown then
        local info = C_Spell.GetSpellCooldown(spell)
        if info then return info.startTime, info.duration, info.isEnabled end
        return
    end
    if GetSpellCooldown then return GetSpellCooldown(spell) end
end

local _, ns = ...
ns = ns or {}

local main, flyout
local RebuildFlyout, RequestRebuild, ShrinkCountdown
local needsRebuild = false
local flyButtons = {}   -- the buttons currently in use
local flyPool = {}      -- every flyout button ever made (secure buttons can't be deleted, so they're reused)
local initialized = false

---------------------------------------------------------------------------
-- Buttons
---------------------------------------------------------------------------
-- Walk every bag slot, calling fn(itemID, name, icon, stackCount, bag) for each item.
-- Includes the extra profession/reagent bag slot, which sits after the four normal bags.
local function LastBagIndex()
    local n = NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4
    if n < (NUM_BAG_SLOTS or 4) + 1 then n = (NUM_BAG_SLOTS or 4) + 1 end
    return n
end

local GetNumSlots = (C_Container and C_Container.GetContainerNumSlots) or GetContainerNumSlots

local function ForEachBagItem(fn)
    for bag = 0, LastBagIndex() do
        local slots = GetNumSlots(bag) or 0
        for slot = 1, slots do
            local id, link, icon, stack
            if C_Container and C_Container.GetContainerItemInfo then
                local info = C_Container.GetContainerItemInfo(bag, slot)
                if info then
                    id, link, icon, stack = info.itemID, info.hyperlink, info.iconFileID, info.stackCount
                end
            else
                local c
                icon, c, _, _, _, _, link, _, _, id = GetContainerItemInfo(bag, slot)
                stack = c
            end
            if id then
                local name = link and link:match("%[(.-)%]")
                fn(id, name, icon, stack or 1, bag)
            end
        end
    end
end

-- Count every item by walking the bags ourselves, so nothing is missed.
-- One pass serves every button; walking the bags per button was slow on busy events.
local function CountBags()
    local counts = {}
    ForEachBagItem(function(id, _, _, stack)
        counts[id] = (counts[id] or 0) + stack
    end)
    return counts
end

local function ResolveItem(b)
    if b.itemID then return end

    if type(b.value) == "number" then
        local _, _, _, _, icon = GetInfoInstant(b.value)
        b.itemID, b.iconTex = b.value, icon
        return
    end

    -- A name only resolves if the game has seen the item, so check the bags first.
    local wanted = b.value:lower()
    ForEachBagItem(function(id, name, icon)
        if not b.itemID and name and name:lower() == wanted then
            b.itemID, b.iconTex = id, icon
        end
    end)
    if b.itemID then return end

    local id, _, _, _, icon = GetInfoInstant(b.value)
    if id then b.itemID, b.iconTex = id, icon end
end

---------------------------------------------------------------------------
-- Finding camp items
---------------------------------------------------------------------------
local MAIN_ID = type(MAIN.value) == "number" and MAIN.value or nil
local checked = {}   -- this session's answers: itemID -> true/false
local waiting = {}   -- items whose data hasn't loaded yet

local scanTip
local function TooltipLines(itemID)
    local lines = {}
    if C_TooltipInfo and C_TooltipInfo.GetItemByID then
        local data = C_TooltipInfo.GetItemByID(itemID)
        if data and data.lines then
            for _, line in ipairs(data.lines) do
                if line.leftText then lines[#lines + 1] = line.leftText end
            end
        end
        return lines
    end
    if not scanTip then
        scanTip = CreateFrame("GameTooltip", "CampKitScanTip", nil, "GameTooltipTemplate")
    end
    scanTip:SetOwner(WorldFrame, "ANCHOR_NONE")
    scanTip:ClearLines()
    scanTip:SetItemByID(itemID)
    for i = 1, scanTip:NumLines() do
        local fs = _G["CampKitScanTipTextLeft" .. i]
        local text = fs and fs:GetText()
        if text then lines[#lines + 1] = text end
    end
    return lines
end

-- true / false, or nil if the item's data isn't loaded yet (we'll hear back later).
local function IsCampItem(itemID)
    if not itemID or itemID == MAIN_ID then return false end
    if KNOWN_CAMP_ITEMS[itemID] then return true end
    if checked[itemID] ~= nil then return checked[itemID] end

    if C_Item and C_Item.IsItemDataCachedByID and not C_Item.IsItemDataCachedByID(itemID) then
        waiting[itemID] = true
        if C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(itemID) end
        return nil
    end

    local lines = TooltipLines(itemID)
    if #lines <= 1 then
        waiting[itemID] = true
        return nil
    end
    for _, text in ipairs(lines) do
        local lower = text:lower()
        for _, key in ipairs(CAMP_TEXT) do
            if lower:find(key, 1, true) then
                checked[itemID] = true
                return true
            end
        end
    end
    checked[itemID] = false
    return false
end

local function Learn(itemID)
    if itemID and not CampKitCharDB.learned[itemID] and IsCampItem(itemID) then
        CampKitCharDB.learned[itemID] = true
        return true
    end
    return false
end

-- Anything camp-related you're carrying.
local function LearnFromBags()
    local found = false
    ForEachBagItem(function(id)
        if Learn(id) then found = true end
    end)
    if found then RequestRebuild() end
end

local function LinkToID(link)
    return link and tonumber(link:match("item:(%d+)"))
end

-- Every camping recipe you know, read while a profession window is open.
local function LearnFromTradeSkill()
    local found = false
    if C_TradeSkillUI and C_TradeSkillUI.GetAllRecipeIDs then
        local ok, recipes = pcall(C_TradeSkillUI.GetAllRecipeIDs)
        for _, recipeID in ipairs(ok and recipes or {}) do
            local info = C_TradeSkillUI.GetRecipeInfo(recipeID)
            if info and info.learned then
                local itemID
                if C_TradeSkillUI.GetRecipeOutputItemData then
                    local okOut, out = pcall(C_TradeSkillUI.GetRecipeOutputItemData, recipeID)
                    itemID = okOut and out and out.itemID
                end
                if not itemID and C_TradeSkillUI.GetRecipeItemLink then
                    itemID = LinkToID(C_TradeSkillUI.GetRecipeItemLink(recipeID))
                end
                if Learn(itemID) then found = true end
            end
        end
    elseif GetNumTradeSkills then
        for i = 1, GetNumTradeSkills() do
            local _, kind = GetTradeSkillInfo(i)
            if kind and kind ~= "header" and Learn(LinkToID(GetTradeSkillItemLink(i))) then
                found = true
            end
        end
    end
    if found then RequestRebuild() end
end

-- What goes on the flyout: learned camp items (minus hidden ones), then your own additions.
local function CurrentItems()
    local list, seen, auto = {}, {}, {}
    for id in pairs(CampKitCharDB.learned) do
        if not CampKitCharDB.hidden[id] then auto[#auto + 1] = id end
    end
    table.sort(auto)
    for _, id in ipairs(auto) do
        list[#list + 1] = id
        seen[id] = true
    end
    for _, id in ipairs(CampKitCharDB.extra) do
        if not seen[id] then
            list[#list + 1] = id
            seen[id] = true
        end
    end
    return list
end

local function UpdateButton(b, bagCounts)
    local count, start, duration, enable

    if b.kind == "item" then
        ResolveItem(b)
        count = GetCount(b.itemID or b.value) or 0
        if b.itemID then count = math.max(count, bagCounts[b.itemID] or 0) end
        if b.itemID then start, duration, enable = GetItemCD(b.itemID) end
        b.icon:SetTexture(b.iconTex or QUESTION_MARK)
        b.count:SetText(count)
        b.icon:SetDesaturated(count == 0)
        b.icon:SetAlpha(count == 0 and 0.5 or 1)
        b.ring:SetDesaturated(count == 0)
        if b.pulse then
            if count > 0 then
                b.glow:Show()
                if not b.pulse:IsPlaying() then b.pulse:Play() end
            else
                b.pulse:Stop()
                b.glow:Hide()
            end
        end
    else
        b.icon:SetTexture(GetSpellIcon(b.value) or QUESTION_MARK)
        b.count:SetText("")
        start, duration, enable = GetSpellCD(b.value)
    end

    if start and duration then
        CooldownFrame_Set(b.cooldown, start, duration, enable)
        ShrinkCountdown(b.cooldown)
    else
        b.cooldown:Clear()
    end
end

local function IsFireAura(name, spellID)
    return (spellID and FIRE_AURAS[spellID]) or (name and FIRE_AURAS[name:lower()]) or false
end
ns.IsFireAura = IsFireAura

-- Walk the player's buffs, calling fn(name, spellID) for each.
local function ForEachBuff(fn)
    for i = 1, 40 do
        local name, spellID
        if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
            local aura = C_UnitAuras.GetAuraDataByIndex("player", i, "HELPFUL")
            if aura then name, spellID = aura.name, aura.spellId end
        else
            local n, _, _, _, _, _, _, _, _, id = UnitBuff("player", i)
            name, spellID = n, id
        end
        if not name then return end
        fn(name, spellID)
    end
end

local function NearFire()
    local found = false
    ForEachBuff(function(name, spellID)
        if IsFireAura(name, spellID) then found = true end
    end)
    return found
end

-- A steady warm ring on the campfire while you're standing by a fire.
local function UpdateFireGlow()
    if main and main.fireGlow then main.fireGlow:SetShown(NearFire()) end
end

local function UpdateAll()
    if not initialized then return end
    UpdateFireGlow()
    local bagCounts = CountBags()
    UpdateButton(main, bagCounts)
    for _, b in ipairs(flyButtons) do UpdateButton(b, bagCounts) end
end

local function ShowTooltip(b)
    GameTooltip:SetOwner(b, "ANCHOR_RIGHT")
    if b.kind == "item" and b.itemID then
        GameTooltip:SetItemByID(b.itemID)
    elseif b.kind == "spell" and GameTooltip.SetSpellByID and C_Spell and C_Spell.GetSpellInfo then
        local info = C_Spell.GetSpellInfo(b.value)
        if info then GameTooltip:SetSpellByID(info.spellID) else GameTooltip:SetText(b.value) end
    else
        GameTooltip:SetText(tostring(b.value))
    end
    if b == main then
        GameTooltip:AddLine("Left-click: use    Right-drag: move", 0.6, 0.8, 1, true)
    end
    GameTooltip:Show()
end

local function SetButtonAction(b, kind, value)
    b.kind, b.value = kind, value
    b.itemID, b.iconTex = nil, nil
    if kind == "item" and type(value) == "number" then
        b:SetAttribute("item", "item:" .. value)
    else
        b:SetAttribute(kind, value)
    end
end

-- The default countdown number is large enough to hide the icon, so use a smaller one.
local cooldownFont
function ShrinkCountdown(cooldown)
    if cooldown.shrunk then return end
    if not cooldownFont then
        cooldownFont = CreateFont("CampKitCooldownFont")
        cooldownFont:SetFont(STANDARD_TEXT_FONT, COOLDOWN_FONT_SIZE, "OUTLINE")
    end
    if cooldown.SetCountdownFont then
        cooldown:SetCountdownFont("CampKitCooldownFont")
        cooldown.shrunk = true
        return
    end
    -- Older clients: the number is a font string inside the cooldown frame, made on first use.
    for _, region in ipairs({ cooldown:GetRegions() }) do
        if region.GetObjectType and region:GetObjectType() == "FontString" then
            region:SetFontObject(cooldownFont)
            cooldown.shrunk = true
        end
    end
end

local function CreateButton(name, parent, kind, value)
    local b = CreateFrame("Button", name, parent, "SecureActionButtonTemplate")
    b:SetSize(BUTTON_SIZE, BUTTON_SIZE)
    b:RegisterForClicks("AnyUp", "AnyDown")

    b:SetAttribute("type", kind)
    SetButtonAction(b, kind, value)

    -- Leather-and-ember ring: a warm outer disc with a dark disc just inside it.
    b.ring = b:CreateTexture(nil, "BACKGROUND", nil, 0)
    b.ring:SetTexture(CIRCLE)
    b.ring:SetPoint("TOPLEFT", -3, 3)
    b.ring:SetPoint("BOTTOMRIGHT", 3, -3)
    b.ring:SetVertexColor(0.78, 0.47, 0.18)

    b.inner = b:CreateTexture(nil, "BACKGROUND", nil, 1)
    b.inner:SetTexture(CIRCLE)
    b.inner:SetPoint("TOPLEFT", -1, 1)
    b.inner:SetPoint("BOTTOMRIGHT", 1, -1)
    b.inner:SetVertexColor(0.12, 0.07, 0.03)

    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetPoint("TOPLEFT", 1, -1)
    b.icon:SetPoint("BOTTOMRIGHT", -1, 1)
    b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    b.mask = b:CreateMaskTexture()
    b.mask:SetTexture(CIRCLE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    b.mask:SetAllPoints(b.icon)
    b.icon:AddMaskTexture(b.mask)

    -- Round firelight highlight on hover.
    b:SetHighlightTexture(CIRCLE, "ADD")
    local hl = b:GetHighlightTexture()
    hl:ClearAllPoints()
    hl:SetAllPoints(b.icon)
    hl:SetVertexColor(1, 0.6, 0.2, 0.35)

    b.cooldown = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
    b.cooldown:SetAllPoints(b.icon)
    if b.cooldown.SetSwipeTexture then b.cooldown:SetSwipeTexture(CIRCLE) end
    if b.cooldown.SetDrawEdge then b.cooldown:SetDrawEdge(false) end

    b.count = b:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    b.count:SetPoint("BOTTOMRIGHT", -2, 2)

    b:HookScript("OnEnter", ShowTooltip)
    b:HookScript("OnLeave", function() GameTooltip:Hide() end)
    return b
end

---------------------------------------------------------------------------
-- Flyout
---------------------------------------------------------------------------
local function Direction()
    return (CampKitDB and CampKitDB.direction) or DIRECTION
end

local OPPOSITE = { UP = "DOWN", DOWN = "UP", LEFT = "RIGHT", RIGHT = "LEFT" }

-- Open toward the other side when the chosen side doesn't have room and the other side has more.
-- space: free pixels between the button and each screen edge; need: length of the flyout.
local function ChooseDirection(dir, space, need)
    local other = OPPOSITE[dir]
    if not other or space[dir] >= need or space[other] <= space[dir] then return dir end
    return other
end
ns.ChooseDirection = ChooseDirection

local function ScreenSpace()
    local top, bottom, left, right = main:GetTop(), main:GetBottom(), main:GetLeft(), main:GetRight()
    if not (top and bottom and left and right) then return nil end
    return {
        UP = UIParent:GetTop() - top, DOWN = bottom,
        LEFT = left, RIGHT = UIParent:GetRight() - right,
    }
end

local function LayoutFlyout()
    local DIRECTION = Direction()
    local n = #flyButtons
    if n == 0 then return end

    if DIRECTION == "ROUND" then
        -- Seat the items in a ring around the fire, starting at the top and going clockwise.
        local step = BUTTON_SIZE + SPACING + 6
        local radius = math.max(step, (n * step) / (2 * math.pi))
        local span = 2 * (radius + BUTTON_SIZE / 2 + 4)

        flyout:ClearAllPoints()
        flyout:SetSize(span, span)
        flyout:SetPoint("CENTER", main, "CENTER")

        for i, b in ipairs(flyButtons) do
            local angle = math.pi / 2 - (i - 1) * (2 * math.pi / n)
            b:ClearAllPoints()
            b:SetPoint("CENTER", flyout, "CENTER", radius * math.cos(angle), radius * math.sin(angle))
        end
        return
    end
    local long = n * BUTTON_SIZE + (n - 1) * SPACING
    local space = ScreenSpace()
    if space then DIRECTION = ChooseDirection(DIRECTION, space, long + SPACING) end
    local vertical = (DIRECTION == "UP" or DIRECTION == "DOWN")

    flyout:ClearAllPoints()
    if vertical then flyout:SetSize(BUTTON_SIZE, long) else flyout:SetSize(long, BUTTON_SIZE) end

    if DIRECTION == "UP" then
        flyout:SetPoint("BOTTOM", main, "TOP", 0, SPACING)
    elseif DIRECTION == "DOWN" then
        flyout:SetPoint("TOP", main, "BOTTOM", 0, -SPACING)
    elseif DIRECTION == "LEFT" then
        flyout:SetPoint("RIGHT", main, "LEFT", -SPACING, 0)
    else
        flyout:SetPoint("LEFT", main, "RIGHT", SPACING, 0)
    end

    for i, b in ipairs(flyButtons) do
        local offset = (i - 1) * (BUTTON_SIZE + SPACING)
        b:ClearAllPoints()
        if DIRECTION == "UP" then
            b:SetPoint("BOTTOM", flyout, "BOTTOM", 0, offset)
        elseif DIRECTION == "DOWN" then
            b:SetPoint("TOP", flyout, "TOP", 0, -offset)
        elseif DIRECTION == "LEFT" then
            b:SetPoint("RIGHT", flyout, "RIGHT", -offset, 0)
        else
            b:SetPoint("LEFT", flyout, "LEFT", offset, 0)
        end
    end
end

-- Match the flyout buttons to the current item list. Out of combat only.
function RebuildFlyout()
    if InCombatLockdown() then
        needsRebuild = true
        return
    end
    needsRebuild = false
    if flyout:IsShown() then flyout:Hide() end
    wipe(flyButtons)
    local items = CurrentItems()
    for i, value in ipairs(items) do
        local b = flyPool[i]
        if b then
            SetButtonAction(b, "item", value)
        else
            b = CreateButton("CampKitFlyButton" .. i, flyout, "item", value)
            flyPool[i] = b
        end
        b:Show()
        flyButtons[i] = b
    end
    for i = #items + 1, #flyPool do flyPool[i]:Hide() end
    LayoutFlyout()
    UpdateAll()
end

function RequestRebuild()
    if initialized then RebuildFlyout() end
end

local function ShowFlyout()
    if #flyButtons == 0 or InCombatLockdown() or main.dragging then return end
    UpdateAll()
    LayoutFlyout()
    flyout.outside = 0
    flyout:Show()
end

-- MouseIsOver() is a Blizzard helper that not every client has, so ask the frames directly.
local function IsHovered(frame)
    if frame.IsMouseOver then return frame:IsMouseOver() end
    if MouseIsOver then return MouseIsOver(frame) end
    return false
end

local function FlyoutOnUpdate(self, elapsed)
    if IsHovered(self) or IsHovered(main) then
        self.outside = 0
        return
    end
    self.outside = (self.outside or 0) + elapsed
    if self.outside >= HIDE_DELAY and not InCombatLockdown() then
        self:Hide()
    end
end

---------------------------------------------------------------------------
-- Position
---------------------------------------------------------------------------
local function SavePosition()
    local point, _, relPoint, x, y = main:GetPoint()
    CampKitDB.point, CampKitDB.relPoint, CampKitDB.x, CampKitDB.y = point, relPoint, x, y
end

local function ApplyCombatVisibility()
    if CampKitDB.hideInCombat == false then
        UnregisterStateDriver(main, "visibility")
        main:Show()
    else
        RegisterStateDriver(main, "visibility", "[combat] hide; show")
    end
end

local function RestorePosition()
    main:ClearAllPoints()
    main:SetPoint(CampKitDB.point or "CENTER", UIParent, CampKitDB.relPoint or "CENTER",
        CampKitDB.x or 0, CampKitDB.y or -150)
end

---------------------------------------------------------------------------
-- Setup
---------------------------------------------------------------------------
local function Initialize()
    if initialized then return end
    CampKitDB = CampKitDB or {}
    CampKitCharDB = CampKitCharDB or {}
    CampKitCharDB.learned = CampKitCharDB.learned or {}
    CampKitCharDB.hidden = CampKitCharDB.hidden or {}
    CampKitCharDB.extra = CampKitCharDB.extra or {}

    main = CreateButton("CampKitMainButton", UIParent, MAIN.kind, MAIN.value)
    -- Only the left button uses the item; the right button is free for moving.
    main:SetAttribute("type", nil)
    main:SetAttribute("type1", MAIN.kind)
    main:SetMovable(true)
    main:SetClampedToScreen(true)
    main:RegisterForDrag("RightButton")
    main:SetScript("OnDragStart", function(self)
        if InCombatLockdown() then return end
        self.dragging = true
        if flyout:IsShown() then flyout:Hide() end
        GameTooltip:Hide()
        self:StartMoving()
    end)
    main:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        self.dragging = false
        SavePosition()
    end)
    main:HookScript("OnEnter", ShowFlyout)
    RestorePosition()
    ApplyCombatVisibility()

    -- A soft ember glow that breathes behind the campfire while you have kits.
    main.glow = main:CreateTexture(nil, "BACKGROUND", nil, -1)
    main.glow:SetTexture(GLOW)
    main.glow:SetBlendMode("ADD")
    main.glow:SetVertexColor(1, 0.5, 0.1)
    main.glow:SetPoint("CENTER")
    main.glow:SetSize(BUTTON_SIZE * 1.9, BUTTON_SIZE * 1.9)
    local pulse = main.glow:CreateAnimationGroup()
    pulse:SetLooping("BOUNCE")
    local fade = pulse:CreateAnimation("Alpha")
    fade:SetFromAlpha(0.25)
    fade:SetToAlpha(0.7)
    fade:SetDuration(1.6)
    fade:SetSmoothing("IN_OUT")
    main.pulse = pulse

    main.fireGlow = main:CreateTexture(nil, "OVERLAY", nil, 1)
    main.fireGlow:SetTexture(CIRCLE)
    main.fireGlow:SetBlendMode("ADD")
    main.fireGlow:SetVertexColor(1, 0.55, 0.15, 0.45)
    main.fireGlow:SetPoint("TOPLEFT", -2, 2)
    main.fireGlow:SetPoint("BOTTOMRIGHT", 2, -2)
    main.fireGlow:Hide()

    flyout = CreateFrame("Frame", "CampKitFlyout", main)
    flyout:Hide()
    flyout:SetClampedToScreen(true)
    flyout:SetScript("OnUpdate", FlyoutOnUpdate)

    CampKitDB.items = nil   -- the old hand-made list; items are found automatically now
    LearnFromBags()
    initialized = true
    RebuildFlyout()

    if not CampKitCharDB.hinted then
        CampKitCharDB.hinted = true
        print("|cff33ff99CampKit|r: open each of your profession windows once so CampKit can find your camp recipes.")
    end
    -- Detection reads English tooltip text, so other clients only find the items listed by ID.
    local locale = GetLocale and GetLocale()
    if locale and locale ~= "enUS" and locale ~= "enGB" and not CampKitCharDB.localeHinted then
        CampKitCharDB.localeHinted = true
        print("|cff33ff99CampKit|r: on non-English clients some camp items aren't found automatically. Add them with /campkit add and shift-click the item.")
    end
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:RegisterEvent("PLAYER_REGEN_DISABLED")
events:RegisterEvent("BAG_UPDATE_DELAYED")
events:RegisterEvent("BAG_UPDATE_COOLDOWN")
events:RegisterEvent("SPELL_UPDATE_COOLDOWN")
events:RegisterEvent("GET_ITEM_INFO_RECEIVED")
events:RegisterEvent("UNIT_AURA")
-- Profession window events differ between clients; register whichever exist.
for _, e in ipairs({ "TRADE_SKILL_SHOW", "TRADE_SKILL_LIST_UPDATE", "TRADE_SKILL_UPDATE", "TRADE_SKILL_DATA_SOURCE_CHANGED" }) do
    pcall(events.RegisterEvent, events, e)
end

local tradeSkillEvents = {
    TRADE_SKILL_SHOW = true, TRADE_SKILL_LIST_UPDATE = true,
    TRADE_SKILL_UPDATE = true, TRADE_SKILL_DATA_SOURCE_CHANGED = true,
}

events:SetScript("OnEvent", function(_, event, arg1)
    if event == "PLAYER_LOGIN" or event == "PLAYER_REGEN_ENABLED" then
        -- Secure buttons can't be created in combat, so a login mid-fight waits until it ends.
        if not initialized and not InCombatLockdown() then Initialize() end
        if initialized and needsRebuild then RebuildFlyout() end
        UpdateAll()
    elseif not initialized then
        return
    elseif tradeSkillEvents[event] then
        LearnFromTradeSkill()
    elseif event == "BAG_UPDATE_DELAYED" then
        LearnFromBags()
        UpdateAll()
    elseif event == "GET_ITEM_INFO_RECEIVED" then
        if arg1 and waiting[arg1] then
            waiting[arg1] = nil
            if Learn(arg1) then RequestRebuild() end
        end
        UpdateAll()
    elseif event == "UNIT_AURA" then
        if arg1 == "player" then UpdateFireGlow() end
    elseif event == "PLAYER_REGEN_DISABLED" then
        -- Last moment before combat lockdown: close the flyout so it isn't stuck open.
        if flyout and flyout:IsShown() then flyout:Hide() end
    else
        UpdateAll()
    end
end)

---------------------------------------------------------------------------
-- Slash commands
---------------------------------------------------------------------------
-- Turn "/campkit add ..." input into an item ID: a shift-clicked link, an ID, or a name in your bags.
local function ParseItem(text)
    local id = text:match("item:(%d+)")
    if id then return tonumber(id) end
    id = tonumber(text)
    if id then return id end
    local wanted = text:lower()
    local found
    ForEachBagItem(function(itemID, name)
        if not found and name and name:lower() == wanted then found = itemID end
    end)
    return found
end

local function ItemName(id)
    local name = (C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(id))
        or (GetItemInfo and GetItemInfo(id))
    return name or ("item " .. id)
end

local function IndexOf(list, id)
    for i, v in ipairs(list) do
        if v == id then return i end
    end
end

SLASH_CAMPKIT1 = "/campkit"
SlashCmdList.CAMPKIT = function(msg)
    local raw = (msg or ""):match("^%s*(.-)%s*$")
    msg = raw:lower()
    local rawArg = raw:match("^%S*%s*(.-)$")
    if not initialized then
        print("|cff33ff99CampKit|r: not ready yet (it finishes loading after combat).")
        return
    end
    if InCombatLockdown() then
        print("|cff33ff99CampKit|r: can't change that in combat.")
        return
    end
    local cmd, arg = msg:match("^(%S*)%s*(.-)$")
    if cmd == "grow" then
        local dir = VALID_DIRECTIONS[arg]
        if not dir then
            print("|cff33ff99CampKit|r: use /campkit grow up, down, left, right or round.")
            return
        end
        CampKitDB.direction = dir
        if flyout:IsShown() then flyout:Hide() end
        LayoutFlyout()
        if dir == "ROUND" then
            print("|cff33ff99CampKit|r: your camp items now circle the campfire.")
        else
            print("|cff33ff99CampKit|r: flyout now opens " .. arg .. ".")
        end
    elseif cmd == "add" then
        local id = rawArg ~= "" and ParseItem(rawArg)
        if not id then
            print("|cff33ff99CampKit|r: type /campkit add, then shift-click the item from your bags (or give its ID).")
            return
        end
        if CampKitCharDB.hidden[id] then
            CampKitCharDB.hidden[id] = nil
        elseif IndexOf(CurrentItems(), id) then
            print("|cff33ff99CampKit|r: " .. ItemName(id) .. " is already on the flyout.")
            return
        else
            table.insert(CampKitCharDB.extra, id)
        end
        RebuildFlyout()
        print("|cff33ff99CampKit|r: added " .. ItemName(id) .. ".")
    elseif cmd == "remove" then
        local items = CurrentItems()
        local n = tonumber(rawArg)
        local id = (n and n >= 1 and n <= #items) and items[n] or (rawArg ~= "" and ParseItem(rawArg))
        if not id or not IndexOf(items, id) then
            print("|cff33ff99CampKit|r: that item isn't on the flyout. /campkit list shows what is.")
            return
        end
        local extraIndex = IndexOf(CampKitCharDB.extra, id)
        if extraIndex then table.remove(CampKitCharDB.extra, extraIndex) end
        if CampKitCharDB.learned[id] then CampKitCharDB.hidden[id] = true end
        RebuildFlyout()
        print("|cff33ff99CampKit|r: removed " .. ItemName(id) .. ".")
    elseif msg == "list" then
        print("|cff33ff99CampKit|r: flyout items, in order:")
        for i, id in ipairs(CurrentItems()) do
            local source = CampKitCharDB.learned[id] and "found" or "added"
            print(("  %d. %s (%d, %s)"):format(i, ItemName(id), id, source))
        end
        local hiddenCount = 0
        for _ in pairs(CampKitCharDB.hidden) do hiddenCount = hiddenCount + 1 end
        if hiddenCount > 0 then
            print(("  %d hidden. /campkit defaults brings them back."):format(hiddenCount))
        end
    elseif msg == "scan" then
        wipe(checked)
        LearnFromBags()
        RebuildFlyout()
        print("|cff33ff99CampKit|r: bags scanned. Open a profession window to pick up its camp recipes.")
    elseif msg == "defaults" then
        wipe(CampKitCharDB.hidden)
        wipe(CampKitCharDB.extra)
        RebuildFlyout()
        print("|cff33ff99CampKit|r: showing every camp item found, and removed your own additions.")
    elseif msg == "bags" then
        print("|cff33ff99CampKit|r: items in your bags (name = ID):")
        local seen = {}
        ForEachBagItem(function(id, name, _, _, bag)
            if not seen[id] then
                seen[id] = true
                print(("  %s = %d  (bag %d)"):format(name or "?", id, bag))
            end
        end)
    elseif msg == "combat" then
        CampKitDB.hideInCombat = CampKitDB.hideInCombat == false
        ApplyCombatVisibility()
        print("|cff33ff99CampKit|r: " .. (CampKitDB.hideInCombat and "hiding in combat." or "staying visible in combat."))
    elseif msg == "buffs" then
        print("|cff33ff99CampKit|r: your buffs (name = ID):")
        ForEachBuff(function(name, spellID)
            print(("  %s = %s%s"):format(name, tostring(spellID), IsFireAura(name, spellID) and "  (fire)" or ""))
        end)
    elseif msg == "reset" then
        CampKitDB.point, CampKitDB.relPoint, CampKitDB.x, CampKitDB.y = nil, nil, nil, nil
        RestorePosition()
        print("|cff33ff99CampKit|r: position reset.")
    else
        print("|cff33ff99CampKit|r commands:")
        print("  /campkit add <shift-click item>  -  add any item to the flyout")
        print("  /campkit remove <item or number>  -  take one off (found items stay hidden)")
        print("  /campkit list  -  show the flyout items")
        print("  /campkit scan  -  look through your bags again")
        print("  /campkit defaults  -  unhide found items and clear your additions")
        print("  /campkit grow up/down/left/right/round")
        print("  /campkit combat  -  toggle hiding the button in combat")
        print("  /campkit reset  -  recenter the button")
        print("  /campkit bags  -  list your bag items with IDs")
        print("  /campkit buffs  -  list your buffs with IDs (to find the fire aura)")
    end
end
