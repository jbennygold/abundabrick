local addonName, addon = ...

---------------------------
-- Lua / WoW upvalues
---------------------------
local pairs = pairs
local math_floor = math.floor
local math_max = math.max
local math_min = math.min

local GetPlayerAuraBySpellID = C_UnitAuras.GetPlayerAuraBySpellID
local InCombatLockdown = InCombatLockdown
local CreateFrame = CreateFrame

---------------------------
-- Constants
---------------------------
-- Abundance buff: this is the visible stacking aura, not the talent ID (207383).
-- It's a private aura that doesn't fire UNIT_AURA reliably, so we poll.
local ABUNDANCE_SPELL_ID = 207640
local MAX_STACKS = 10

local SOLID = "Interface\\Buttons\\WHITE8X8"

local COLOR_RED    = { 0.85, 0.20, 0.20 }
local COLOR_YELLOW = { 0.95, 0.80, 0.20 }
local COLOR_GREEN  = { 0.30, 0.80, 0.30 }
local COLOR_EMPTY  = { 0.10, 0.10, 0.10 }
local COLOR_BORDER = { 0, 0, 0, 0.85 }
local COLOR_BG     = { 0, 0, 0, 0.55 }

local function ColorForStack(i)
    if i <= 3 then return COLOR_RED end
    if i <= 7 then return COLOR_YELLOW end
    return COLOR_GREEN
end

---------------------------
-- Defaults
---------------------------
local defaults = {
    orientation = "vertical", -- "vertical" or "horizontal"
    width = 14,
    height = 132,
    point = "CENTER",
    relPoint = "CENTER",
    x = -120,
    y = 0,
    locked = false,
    hideWhenInactive = false,
    showEmptyBricks = true,
    spacing = 2,
    padding = 2,
    ver = 1,
}

---------------------------
-- Print
---------------------------
function addon:Print(...)
    print("|cFFE8C547Abunda|r|cFFCC4444Brick|r:", ...)
end

---------------------------
-- Bar construction
---------------------------
local function CreateBar()
    local bar = CreateFrame("Frame", "AbundaBrickBar", UIParent, "BackdropTemplate")
    bar:SetClampedToScreen(true)
    bar:SetMovable(true)
    bar:EnableMouse(false)

    -- Background
    local bg = bar:CreateTexture(nil, "BACKGROUND")
    bg:SetTexture(SOLID)
    bg:SetVertexColor(unpack(COLOR_BG))
    bg:SetAllPoints()
    bar.bg = bg

    -- Border (4 thin edges, drawn above bg)
    local function MakeEdge()
        local t = bar:CreateTexture(nil, "BORDER")
        t:SetTexture(SOLID)
        t:SetVertexColor(unpack(COLOR_BORDER))
        return t
    end
    local top, bottom, left, right = MakeEdge(), MakeEdge(), MakeEdge(), MakeEdge()
    top:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, 0)
    top:SetPoint("TOPRIGHT", bar, "TOPRIGHT", 0, 0)
    top:SetHeight(1)
    bottom:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 0, 0)
    bottom:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 0, 0)
    bottom:SetHeight(1)
    left:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, 0)
    left:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 0, 0)
    left:SetWidth(1)
    right:SetPoint("TOPRIGHT", bar, "TOPRIGHT", 0, 0)
    right:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 0, 0)
    right:SetWidth(1)
    bar.edges = { top, bottom, left, right }

    -- Bricks
    bar.bricks = {}
    for i = 1, MAX_STACKS do
        local brick = bar:CreateTexture(nil, "ARTWORK")
        brick:SetTexture(SOLID)
        brick:SetVertexColor(unpack(COLOR_EMPTY))
        bar.bricks[i] = brick
    end

    -- Drag overlay (only enabled when unlocked)
    local drag = CreateFrame("Frame", nil, bar)
    drag:SetAllPoints()
    drag:EnableMouse(false)
    drag:RegisterForDrag("LeftButton")
    drag:SetScript("OnDragStart", function()
        if addon.db.locked or InCombatLockdown() then return end
        bar:StartMoving()
    end)
    drag:SetScript("OnDragStop", function()
        bar:StopMovingOrSizing()
        addon:SavePosition()
    end)
    drag:SetScript("OnEnter", function()
        if addon.db.locked then return end
        GameTooltip:SetOwner(drag, "ANCHOR_TOP")
        GameTooltip:SetText("AbundaBrick")
        GameTooltip:AddLine("Drag to move", 1, 1, 1)
        GameTooltip:AddLine("Right-click for options", 1, 1, 1)
        GameTooltip:Show()
    end)
    drag:SetScript("OnLeave", function() GameTooltip:Hide() end)
    drag:SetScript("OnMouseDown", function(_, btn)
        if btn == "RightButton" and not InCombatLockdown() then
            Settings.OpenToCategory(addon.optionsCategoryID)
        end
    end)
    bar.drag = drag

    bar:SetScript("OnSizeChanged", function()
        addon:LayoutBricks()
    end)

    addon.bar = bar
    return bar
end

---------------------------
-- Layout
---------------------------
function addon:LayoutBricks()
    local bar = self.bar
    if not bar then return end

    local db = self.db
    local pad = db.padding
    local spacing = db.spacing
    local innerW = math_max(1, bar:GetWidth()  - pad * 2)
    local innerH = math_max(1, bar:GetHeight() - pad * 2)

    local totalSpacing = spacing * (MAX_STACKS - 1)

    if db.orientation == "horizontal" then
        -- Fill left to right: brick 1 leftmost, so reds appear first.
        local brickW = math_max(1, (innerW - totalSpacing) / MAX_STACKS)
        for i = 1, MAX_STACKS do
            local b = bar.bricks[i]
            b:ClearAllPoints()
            b:SetSize(brickW, innerH)
            b:SetPoint("LEFT", bar, "LEFT", pad + (i - 1) * (brickW + spacing), 0)
        end
    else
        -- Fill bottom to top: brick 1 bottom-most, so reds appear first.
        local brickH = math_max(1, (innerH - totalSpacing) / MAX_STACKS)
        for i = 1, MAX_STACKS do
            local b = bar.bricks[i]
            b:ClearAllPoints()
            b:SetSize(innerW, brickH)
            b:SetPoint("BOTTOM", bar, "BOTTOM", 0, pad + (i - 1) * (brickH + spacing))
        end
    end
end

function addon:SetOrientation(orientation)
    if orientation ~= "horizontal" and orientation ~= "vertical" then return end
    if self.db.orientation == orientation then return end
    self.db.orientation = orientation
    -- Swap width/height so the bar reorients to sensible proportions.
    self.db.width, self.db.height = self.db.height, self.db.width
    self:ApplyPositionAndSize()
end

---------------------------
-- Position / Size persistence
---------------------------
function addon:SavePosition()
    local bar = self.bar
    if not bar then return end
    local point, _, relPoint, x, y = bar:GetPoint(1)
    self.db.point = point
    self.db.relPoint = relPoint
    self.db.x = x
    self.db.y = y
end

function addon:ApplyPositionAndSize()
    local bar = self.bar
    if not bar then return end
    bar:ClearAllPoints()
    bar:SetPoint(self.db.point, UIParent, self.db.relPoint, self.db.x, self.db.y)
    bar:SetSize(self.db.width, self.db.height)
    self:LayoutBricks()
end

---------------------------
-- Lock state
---------------------------
function addon:ApplyLock()
    local bar = self.bar
    if not bar then return end

    local locked = self.db.locked
    bar.drag:EnableMouse(not locked)
    if locked then
        for _, e in pairs(bar.edges) do e:SetVertexColor(0, 0, 0, 0) end
        bar.bg:SetVertexColor(0, 0, 0, 0)
    else
        for _, e in pairs(bar.edges) do e:SetVertexColor(unpack(COLOR_BORDER)) end
        bar.bg:SetVertexColor(unpack(COLOR_BG))
    end
end

---------------------------
-- Stack update
---------------------------
function addon:GetAbundanceStacks()
    local aura = GetPlayerAuraBySpellID(ABUNDANCE_SPELL_ID)
    if not aura then return 0 end
    return aura.applications or 0
end

function addon:UpdateBricks(stacks)
    local bar = self.bar
    if not bar then return end

    stacks = math_min(MAX_STACKS, math_max(0, math_floor(stacks or 0)))

    if self.db.hideWhenInactive and stacks == 0 then
        bar:Hide()
        return
    end
    bar:Show()

    for i = 1, MAX_STACKS do
        local b = bar.bricks[i]
        if i <= stacks then
            local c = ColorForStack(i)
            b:SetVertexColor(c[1], c[2], c[3], 1)
            b:Show()
        else
            if self.db.showEmptyBricks then
                b:SetVertexColor(COLOR_EMPTY[1], COLOR_EMPTY[2], COLOR_EMPTY[3], 0.7)
                b:Show()
            else
                b:Hide()
            end
        end
    end
end

function addon:Refresh()
    local stacks = self:GetAbundanceStacks()
    if stacks == self._lastStacks then return end
    self._lastStacks = stacks
    self:UpdateBricks(stacks)
end

---------------------------
-- Events
---------------------------
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:SetScript("OnEvent", function(_, event, ...)
    local fn = addon[event]
    if fn then fn(addon, ...) end
end)

---------------------------
-- Polling
-- Abundance is a private aura and does not fire UNIT_AURA reliably,
-- so we poll the player aura state.
---------------------------
local POLL_INTERVAL = 0.1

function addon:InitPoller()
    if self._poller then return end
    local f = CreateFrame("Frame", "AbundaBrickPoller", UIParent)
    local accum = 0
    f:SetScript("OnUpdate", function(_, elapsed)
        accum = accum + elapsed
        if accum >= POLL_INTERVAL then
            accum = 0
            addon:Refresh()
        end
    end)
    self._poller = f
end

---------------------------
-- Database
---------------------------
function addon:InitDatabase()
    AbundaBrickDB = AbundaBrickDB or CopyTable(defaults)

    -- Backfill any new keys when defaults expand
    for k, v in pairs(defaults) do
        if AbundaBrickDB[k] == nil then
            AbundaBrickDB[k] = v
        end
    end

    self.db = AbundaBrickDB
end

function addon:ResetPosition()
    self.db.point = defaults.point
    self.db.relPoint = defaults.relPoint
    self.db.x = defaults.x
    self.db.y = defaults.y
    self.db.width = defaults.width
    self.db.height = defaults.height
    self.db.orientation = defaults.orientation
    self:ApplyPositionAndSize()
end

---------------------------
-- Slash commands
---------------------------
function addon:InitCommands()
    SLASH_ABUNDABRICK1 = "/abundabrick"
    SLASH_ABUNDABRICK2 = "/abrick"
    SlashCmdList.ABUNDABRICK = function(msg)
        msg = (msg or ""):lower():match("^%s*(.-)%s*$")
        if msg == "lock" then
            self.db.locked = true
            self:ApplyLock()
            self:Print("Locked.")
        elseif msg == "unlock" then
            self.db.locked = false
            self:ApplyLock()
            self:Print("Unlocked. Drag the bar to move it.")
        elseif msg == "reset" then
            self:ResetPosition()
            self:Print("Position and size reset.")
        elseif msg == "test" then
            local stacks = (self._testStacks or 0) + 1
            if stacks > MAX_STACKS then stacks = 0 end
            self._testStacks = stacks
            self:UpdateBricks(stacks)
            self:Print("Test stacks:", stacks)
        elseif msg == "help" then
            self:Print("/abrick           - open options")
            self:Print("/abrick lock      - lock the bar")
            self:Print("/abrick unlock    - unlock the bar")
            self:Print("/abrick reset     - reset position and size")
            self:Print("/abrick test      - cycle test stack counts")
        else
            if InCombatLockdown() then
                self:Print("Cannot open options while in combat.")
            else
                Settings.OpenToCategory(self.optionsCategoryID)
            end
        end
    end

    if AddonCompartmentFrame then
        local icon = (C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(ABUNDANCE_SPELL_ID))
            or 136085 -- generic druid fallback
        AddonCompartmentFrame:RegisterAddon({
            text = "AbundaBrick",
            icon = icon,
            notCheckable = true,
            func = function()
                if InCombatLockdown() then
                    self:Print("Cannot open options while in combat.")
                else
                    Settings.OpenToCategory(self.optionsCategoryID)
                end
            end,
        })
    end
end

---------------------------
-- Login
---------------------------
function addon:PLAYER_LOGIN()
    self:InitDatabase()

    CreateBar()
    self:ApplyPositionAndSize()
    self:ApplyLock()

    self:Options()
    self:InitCommands()
    self:InitPoller()
    self:Refresh()

    self:Print("Loaded. Type |cFFE8C547/abrick|r for options.")
end
