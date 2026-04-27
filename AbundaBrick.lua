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
local UnitClass = UnitClass
local UnitGUID = UnitGUID
local GetSpecialization = GetSpecialization
local GetSpecializationInfo = GetSpecializationInfo
local GetTime = GetTime
local string_format = string.format
local table_insert = table.insert
local table_remove = table.remove
local table_wipe = wipe

---------------------------
-- Constants
---------------------------
-- Abundance buff: this is the visible stacking aura, not the talent ID (207383).
-- It's a private aura that doesn't fire UNIT_AURA reliably, AND is hidden
-- from the aura API entirely while in combat in instanced content.
-- We poll the API (works out-of-combat) and track our own Rejuv casts as
-- a fallback so the bar still works during pulls.
local ABUNDANCE_SPELL_ID = 207640
local MAX_STACKS = 10
local RESTO_DRUID_SPEC_ID = 105

-- Spells that grant a stack of Abundance (one stack per active aura).
local REJUV_SPELL_IDS = {
    [774] = true,    -- Rejuvenation
    [155777] = true, -- Germination
}
-- Approximate Rejuv base duration. Talents/empowerment can extend it; the
-- count will recover on the next out-of-combat poll when the API returns.
local REJUV_DURATION = 15

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
    debugLog = false, -- diagnostic log: off by default, /abrick log on enables
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
    bar:Hide() -- stay hidden until Refresh decides we should show

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
-- Per-target tracking: "<target>:<spellID>" -> expireTime. Refreshing on the
-- same target overwrites the same key, so refreshes don't double-count.
addon._byTarget = {}
-- castGUID -> target name, populated on _SENT, consumed on _SUCCEEDED.
addon._sentMap = {}
-- Flat fallback list for casts where _SENT didn't fire / had no target.
addon._castExpires = {}

function addon:GetTrackedStacks()
    local now = GetTime()
    local count = 0
    -- Per-target entries (refresh-aware)
    for key, expire in pairs(self._byTarget) do
        if expire > now then
            count = count + 1
        else
            self._byTarget[key] = nil
        end
    end
    -- Flat fallback entries
    for i = #self._castExpires, 1, -1 do
        if self._castExpires[i] > now then
            count = count + 1
        else
            table_remove(self._castExpires, i)
        end
    end
    if count > MAX_STACKS then count = MAX_STACKS end
    return count
end

-- Count player-applied Rejuv/Germination auras on group members.
-- Works out of combat / outside instances. In instance combat, aura fields
-- like spellId and name are returned as SECRET values which can't be used
-- as table keys or compared, so this function bails out and the caller
-- falls through to the cast tracker.
local issecretvalue = issecretvalue or function() return false end

function addon:CountGroupRejuvs()
    local count = 0
    local function scanUnit(unit)
        if not UnitExists(unit) then return end
        for i = 1, 40 do
            local data = C_UnitAuras.GetAuraDataByIndex(unit, i, "HELPFUL|PLAYER")
            if not data then break end
            local sid = data.spellId
            -- Secret values can't be used as keys / compared — skip them.
            if sid and not issecretvalue(sid) then
                -- pcall is belt-and-braces in case future patches add new
                -- secret kinds we don't recognize.
                local ok, isRejuv = pcall(function() return REJUV_SPELL_IDS[sid] end)
                if ok and isRejuv then
                    count = count + 1
                end
            end
        end
    end

    if IsInRaid() then
        for i = 1, 40 do scanUnit("raid" .. i) end
    else
        scanUnit("player")
        for i = 1, 4 do scanUnit("party" .. i) end
    end

    if count > MAX_STACKS then count = MAX_STACKS end
    return count
end

function addon:GetAbundanceStacks()
    local aura = GetPlayerAuraBySpellID(ABUNDANCE_SPELL_ID)
    local apiStacks = 0
    if aura and aura.applications and not issecretvalue(aura.applications) then
        apiStacks = aura.applications
    end
    local groupCount = self:CountGroupRejuvs()
    local authoritative = math_max(apiStacks, groupCount)

    -- When an authoritative source can read stacks, return that AND seed the
    -- tracker so it has a reasonable starting state if the source is silenced
    -- a moment later (e.g., combat begins inside an instance).
    if authoritative > 0 then
        local tracked = self:GetTrackedStacks()
        if authoritative > tracked then
            -- Authoritative source sees more than we've tracked — seed up
            -- so the tracker survives if the source is silenced next tick.
            local seedTime = GetTime() + REJUV_DURATION
            for _ = 1, authoritative - tracked do
                table_insert(self._castExpires, seedTime)
            end
        elseif authoritative < tracked then
            -- Authoritative source sees less — refresh-overcount cleanup.
            -- Drop oldest entries from the flat fallback list first; if we
            -- still need to trim, drop oldest per-target entries.
            local diff = tracked - authoritative
            table.sort(self._castExpires)
            local toRemove = math_min(diff, #self._castExpires)
            for _ = 1, toRemove do
                table_remove(self._castExpires, 1)
            end
            diff = diff - toRemove
            if diff > 0 then
                local entries = {}
                for k, v in pairs(self._byTarget) do
                    entries[#entries + 1] = { k, v }
                end
                table.sort(entries, function(a, b) return a[2] < b[2] end)
                for i = 1, math_min(diff, #entries) do
                    self._byTarget[entries[i][1]] = nil
                end
            end
        end
        return authoritative
    end

    -- Both authoritative sources are silenced: rely on cast tracker.
    return self:GetTrackedStacks()
end

function addon:UNIT_SPELLCAST_SENT(unit, target, castGUID, spellID)
    if unit ~= "player" then return end
    if not REJUV_SPELL_IDS[spellID] then return end
    if target and target ~= "" and castGUID then
        self._sentMap[castGUID] = target
    end
end

function addon:UNIT_SPELLCAST_SUCCEEDED(unit, castGUID, spellID)
    if unit ~= "player" then return end
    if not REJUV_SPELL_IDS[spellID] then return end
    local expireAt = GetTime() + REJUV_DURATION
    local target = self._sentMap[castGUID]
    self._sentMap[castGUID] = nil
    if target then
        -- Per-target: same key overwrites on refresh -> no double count.
        self._byTarget[target .. ":" .. spellID] = expireAt
    else
        -- Unknown target: fall back to flat list (may over-count refreshes
        -- but keeps the bar from going empty).
        table_insert(self._castExpires, expireAt)
    end
end

function addon:IsRestoDruid()
    local _, class = UnitClass("player")
    if class ~= "DRUID" then return false end
    local specIndex = GetSpecialization()
    if not specIndex then return false end
    local specID = GetSpecializationInfo(specIndex)
    return specID == RESTO_DRUID_SPEC_ID
end

function addon:UpdateActiveSpec()
    self._isResto = self:IsRestoDruid()
    -- Force the next Refresh to re-evaluate.
    self._lastStacks = nil
    self:Refresh()
end

---------------------------
-- Diagnostic log
-- Records aura-API state, combat-log Abundance events, and zone changes so
-- we can compare what the API says vs. what the combat log says.
-- Always recording (low overhead, only logs on changes).
---------------------------
local LOG_MAX = 150
addon._log = {}

local function pushLog(text)
    if not (addon.db and addon.db.debugLog) then return end
    table_insert(addon._log, string_format("[%.1f] %s", GetTime(), text))
    if #addon._log > LOG_MAX then table_remove(addon._log, 1) end
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
    if not self._isResto then
        if self.bar and self.bar:IsShown() then self.bar:Hide() end
        return
    end

    -- Diagnostic: log instance and combat state changes via polling
    -- (we deliberately avoid registering more events to dodge taint issues
    -- some users have hit with additional event registrations.)
    local _, instanceType = IsInInstance()
    if instanceType ~= self._lastInstance then
        pushLog(string_format("ZONE inst=%s", tostring(instanceType)))
        self._lastInstance = instanceType
    end
    local inCombat = UnitAffectingCombat("player") and true or false
    if inCombat ~= self._lastCombat then
        pushLog(inCombat and "COMBAT_ENTER" or "COMBAT_LEAVE")
        self._lastCombat = inCombat
    end

    local stacks = self:GetAbundanceStacks()
    local aura = GetPlayerAuraBySpellID(ABUNDANCE_SPELL_ID)
    local apiOnly = 0
    if aura and aura.applications and not issecretvalue(aura.applications) then
        apiOnly = aura.applications
    end
    local groupOnly = self:CountGroupRejuvs()
    local trackedOnly = self:GetTrackedStacks()

    -- Diagnostic logging (opt-in via /abrick log on).
    if self.db.debugLog then
        local now = GetTime()
        if inCombat and (now - (self._lastCombatTickLog or 0) >= 1.0) then
            self._lastCombatTickLog = now
            pushLog(string_format("tick stacks=%d  api=%d  group=%d  tracked=%d",
                stacks, apiOnly, groupOnly, trackedOnly))
        elseif not inCombat then
            self._lastCombatTickLog = nil
        end
    end

    if stacks == self._lastStacks then return end
    if self.db.debugLog then
        pushLog(string_format("stacks=%d (was %s)  api=%d  group=%d  tracked=%d  combat=%s  inst=%s",
            stacks, tostring(self._lastStacks),
            apiOnly, groupOnly, trackedOnly,
            tostring(inCombat), tostring(instanceType)))
    end
    self._lastStacks = stacks
    self:UpdateBricks(stacks)
end

---------------------------
-- Events
---------------------------
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_SENT", "player")
eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
eventFrame:SetScript("OnEvent", function(_, event, ...)
    local fn = addon[event]
    if fn then fn(addon, ...) end
end)

function addon:PLAYER_SPECIALIZATION_CHANGED(unit)
    if not self.bar then return end -- not yet initialized
    if unit == "player" then
        self:UpdateActiveSpec()
    end
end

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
        elseif msg == "log" or msg == "log show" then
            local _, inst = IsInInstance()
            local aura = GetPlayerAuraBySpellID(ABUNDANCE_SPELL_ID)
            local apiOnly = 0
            if aura and aura.applications and not issecretvalue(aura.applications) then
                apiOnly = aura.applications
            end
            self:Print(string_format("=== log (%d entries, recording=%s) ===",
                #self._log, self.db.debugLog and "on" or "off"))
            for _, line in ipairs(self._log) do
                self:Print(line)
            end
            self:Print(string_format("=== now: stacks=%d  api=%d  group=%d  tracked=%d  combat=%s  inst=%s  isResto=%s ===",
                self:GetAbundanceStacks(),
                apiOnly,
                self:CountGroupRejuvs(),
                self:GetTrackedStacks(),
                tostring(UnitAffectingCombat("player") and true or false),
                tostring(inst),
                tostring(self._isResto)))
        elseif msg == "log on" then
            self.db.debugLog = true
            self:Print("Diagnostic log: ON")
        elseif msg == "log off" then
            self.db.debugLog = false
            self:Print("Diagnostic log: OFF (existing entries kept; '/abrick log clear' to wipe)")
        elseif msg == "log clear" then
            table_wipe(self._log)
            self:Print("Log cleared.")
        elseif msg == "help" then
            self:Print("/abrick           - open options")
            self:Print("/abrick lock      - lock the bar")
            self:Print("/abrick unlock    - unlock the bar")
            self:Print("/abrick reset     - reset position and size")
            self:Print("/abrick test      - cycle test stack counts")
            self:Print("/abrick log on    - turn on diagnostic logging")
            self:Print("/abrick log off   - turn off diagnostic logging")
            self:Print("/abrick log       - dump diagnostic log")
            self:Print("/abrick log clear - clear diagnostic log")
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

    self._playerGUID = UnitGUID("player")
    eventFrame:RegisterUnitEvent("PLAYER_SPECIALIZATION_CHANGED", "player")
    self:UpdateActiveSpec()

    self:Print("Loaded. Type |cFFE8C547/abrick|r for options.")
end
