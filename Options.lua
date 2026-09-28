-- CampKit settings page: Options > AddOns > CampKit, or /campkit.
-- Every change goes through ns.actions, the same code the slash commands use.

local addonName, ns = ...
ns = ns or {}

local ROW_HEIGHT = 28
local MAX_ROWS = 10
local LEFT, RIGHT = 16, 340
local DIRECTIONS = { "UP", "DOWN", "LEFT", "RIGHT", "ROUND" }
local DIRECTION_LABELS = { UP = "Up", DOWN = "Down", LEFT = "Left", RIGHT = "Right", ROUND = "Round" }

local panel = CreateFrame("Frame")
panel.name = "CampKit"
local built, Refresh

-- Run a change; say why in chat if it was refused, then redraw.
local function Do(ok, message)
    if not ok and message then print("|cff33ff99CampKit|r: " .. message) end
    Refresh()
end

local function Text(parent, font, text, x, y)
    local fs = parent:CreateFontString(nil, "ARTWORK", font)
    fs:SetPoint("TOPLEFT", x, y)
    fs:SetJustifyH("LEFT")
    fs:SetText(text)
    return fs
end

local function Button(parent, text, width, x, y, onClick)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(width, 22)
    b:SetPoint("TOPLEFT", x, y)
    b:SetText(text)
    b:SetScript("OnClick", onClick)
    return b
end

local function Checkbox(parent, label, x, y, onClick)
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetSize(26, 26)
    cb:SetPoint("TOPLEFT", x, y)
    cb:SetScript("OnClick", function(self) onClick(self:GetChecked() and true or false) end)
    local fs = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    fs:SetPoint("LEFT", cb, "RIGHT", 4, 0)
    fs:SetText(label)
    return cb
end

-- Label, then [-] value [+], stepping by the setting's own step.
local function Stepper(parent, label, key, x, y, action)
    local step = ns.LIMITS[key][3]
    Text(parent, "GameFontHighlight", label, x, y - 4)
    local value = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    value:SetPoint("TOPLEFT", x + 190, y - 4)
    value:SetWidth(30)
    value:SetJustifyH("CENTER")
    Button(parent, "-", 24, x + 162, y, function() Do(action(ns.Get[key]() - step)) end)
    Button(parent, "+", 24, x + 224, y, function() Do(action(ns.Get[key]() + step)) end)
    return value
end

StaticPopupDialogs["CAMPKIT_RESTORE_DEFAULTS"] = {
    text = "Show every camp item CampKit found again, and remove the items you added?",
    button1 = YES or "Yes",
    button2 = NO or "No",
    OnAccept = function() Do(ns.actions.RestoreDefaults()) end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
}

local widgets = {}

-- One row on the flyout list: icon (with tooltip), name, Remove button.
local function ItemRow(parent, i)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(280, ROW_HEIGHT)
    row:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_HEIGHT)

    row.iconFrame = CreateFrame("Frame", nil, row)
    row.iconFrame:SetSize(22, 22)
    row.iconFrame:SetPoint("LEFT")
    row.icon = row.iconFrame:CreateTexture(nil, "ARTWORK")
    row.icon:SetAllPoints()
    row.iconFrame:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetItemByID(row.itemID)
        GameTooltip:Show()
    end)
    row.iconFrame:SetScript("OnLeave", function() GameTooltip:Hide() end)

    row.name = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    row.name:SetPoint("LEFT", row.iconFrame, "RIGHT", 8, 0)
    row.name:SetWidth(170)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)

    row.remove = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    row.remove:SetSize(70, 20)
    row.remove:SetPoint("RIGHT")
    row.remove:SetText("Remove")
    row.remove:SetScript("OnClick", function() Do(ns.actions.RemoveItem(row.itemID)) end)
    return row
end

local function Build()
    local p = panel
    local version = (C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata)(addonName, "Version")
    Text(p, "GameFontNormalLarge", "CampKit", LEFT, -16)
    Text(p, "GameFontDisableSmall", "Version " .. (version or "?") .. "  ·  Right-drag the campfire to move it", LEFT, -40)

    widgets.notReady = Text(p, "GameFontHighlight", "CampKit finishes loading after combat.", LEFT, -72)

    -- Everything below shows only once CampKit has loaded.
    p = CreateFrame("Frame", nil, panel)
    p:SetAllPoints()
    widgets.content = p

    -- Left column: how the button looks and behaves.
    Text(p, "GameFontNormal", "Flyout Direction", LEFT, -72)
    widgets.directions = {}
    for i, dir in ipairs(DIRECTIONS) do
        widgets.directions[dir] = Button(p, DIRECTION_LABELS[dir], 58, LEFT + (i - 1) * 60, -94,
            function() Do(ns.actions.SetDirection(dir)) end)
    end

    Text(p, "GameFontNormal", "Campfire Button", LEFT, -134)
    widgets.hideInCombat = Checkbox(p, "Hide in Combat", LEFT - 4, -152,
        function(on) Do(ns.actions.SetHideInCombat(on)) end)
    widgets.locked = Checkbox(p, "Lock Position", LEFT - 4, -180,
        function(on) Do(ns.actions.SetLocked(on)) end)
    widgets.buttonSize = Stepper(p, "Button Size", "buttonSize", LEFT, -216, ns.actions.SetButtonSize)
    widgets.cooldownFontSize = Stepper(p, "Cooldown Number Size", "cooldownFontSize", LEFT, -244,
        ns.actions.SetCooldownFontSize)
    Button(p, "Reset Position", 120, LEFT, -284, function() Do(ns.actions.ResetPosition()) end)

    -- Right column: what's on the flyout.
    Text(p, "GameFontNormal", "Flyout Items", RIGHT, -72)
    widgets.list = CreateFrame("Frame", nil, p)
    widgets.list:SetPoint("TOPLEFT", RIGHT, -94)
    widgets.list:SetSize(280, ROW_HEIGHT)
    widgets.rows = {}
    for i = 1, MAX_ROWS do widgets.rows[i] = ItemRow(widgets.list, i) end

    widgets.empty = widgets.list:CreateFontString(nil, "ARTWORK", "GameFontDisable")
    widgets.empty:SetPoint("TOPLEFT", 0, -6)
    widgets.empty:SetText("No camp items found yet.")

    local footer = CreateFrame("Frame", nil, p)
    footer:SetSize(280, 120)
    footer:SetPoint("TOPLEFT", widgets.list, "BOTTOMLEFT", 0, -8)
    widgets.more = Text(footer, "GameFontDisableSmall", "", 0, 0)

    -- Drop an item here (or click here while holding one) to add it.
    local slot = CreateFrame("Button", nil, footer)
    slot:SetSize(32, 32)
    slot:SetPoint("TOPLEFT", 0, -18)
    slot:SetNormalTexture("Interface\\PaperDoll\\UI-Backpack-EmptySlot")
    slot:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    local function TakeCursorItem()
        local kind, id = GetCursorInfo()
        if kind ~= "item" then return end
        ClearCursor()
        Do(ns.actions.AddItem(id))
    end
    slot:SetScript("OnReceiveDrag", TakeCursorItem)
    slot:SetScript("OnClick", TakeCursorItem)
    local hint = footer:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    hint:SetPoint("LEFT", slot, "RIGHT", 8, 0)
    hint:SetWidth(230)
    hint:SetJustifyH("LEFT")
    hint:SetText("Drag an item from your bags here to add it to the flyout.")

    Button(footer, "Rescan Bags", 110, 0, -62, function() Do(ns.actions.Rescan()) end)
    Button(footer, "Restore Defaults", 130, 116, -62, function() StaticPopup_Show("CAMPKIT_RESTORE_DEFAULTS") end)

    built = true
end

function Refresh()
    if not built then return end
    local ready = ns.IsReady and ns.IsReady()
    widgets.notReady:SetShown(not ready)
    widgets.content:SetShown(ready)
    if not ready then return end

    local current = ns.Get.direction()
    for dir, b in pairs(widgets.directions) do
        if dir == current then b:LockHighlight() else b:UnlockHighlight() end
    end
    widgets.hideInCombat:SetChecked(ns.Get.hideInCombat())
    widgets.locked:SetChecked(ns.Get.locked())
    widgets.buttonSize:SetText(ns.Get.buttonSize())
    widgets.cooldownFontSize:SetText(ns.Get.cooldownFontSize())

    local items = ns.CurrentItems()
    local shown = math.min(#items, MAX_ROWS)
    for i, row in ipairs(widgets.rows) do
        local id = items[i]
        if i <= shown then
            row.itemID = id
            row.icon:SetTexture(ns.ItemIcon(id))
            row.name:SetText(ns.ItemName(id) .. (ns.IsFound(id) and "" or "  |cff999999(added)|r"))
            row:Show()
        else
            row:Hide()
        end
    end
    widgets.empty:SetShown(#items == 0)
    widgets.list:SetHeight(math.max(shown, 1) * ROW_HEIGHT)

    local notes = {}
    if #items > MAX_ROWS then notes[#notes + 1] = ("%d more: /campkit list"):format(#items - MAX_ROWS) end
    local hidden = ns.HiddenCount()
    if hidden > 0 then notes[#notes + 1] = ("%d removed (Restore Defaults brings them back)"):format(hidden) end
    widgets.more:SetText(table.concat(notes, "  ·  "))
end

panel:SetScript("OnShow", function()
    if not built then Build() end
    Refresh()
end)

ns.OnChanged = function()
    if panel:IsVisible() then Refresh() end
end

-- Newer clients have the Settings panel; older ones the Interface Options frame.
if Settings and Settings.RegisterCanvasLayoutCategory then
    local category = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
    Settings.RegisterAddOnCategory(category)
    ns.OpenOptions = function() Settings.OpenToCategory(category:GetID()) end
elseif InterfaceOptions_AddCategory then
    InterfaceOptions_AddCategory(panel)
    ns.OpenOptions = function()
        -- The first call only opens the frame on some clients; the second selects the page.
        InterfaceOptionsFrame_OpenToCategory(panel)
        InterfaceOptionsFrame_OpenToCategory(panel)
    end
end
