local addonName, addon = ...

---------------------------
-- Style helpers
---------------------------
local SOLID = "Interface\\Buttons\\WHITE8X8"

local COLOR_HEADER     = { 1.00, 0.86, 0.30 }
local COLOR_DIVIDER    = { 1.00, 0.82, 0.00, 0.45 }
local COLOR_SUBTLE     = { 0.65, 0.65, 0.65 }

local DIVIDER_WIDTH = 580

local function CreateDivider(parent, anchor, yOffset)
    local line = parent:CreateTexture(nil, "ARTWORK")
    line:SetTexture(SOLID)
    line:SetVertexColor(unpack(COLOR_DIVIDER))
    line:SetSize(DIVIDER_WIDTH, 1)
    line:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, yOffset)
    return line
end

local function CreateSectionHeader(parent, anchor, yOffset, text)
    local label = parent:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    label:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, yOffset)
    label:SetTextColor(unpack(COLOR_HEADER))
    label:SetText(text)
    return label
end

local function CreateCheckbox(parent, label, tooltip, getter, onClick)
    local cb = CreateFrame("CheckButton", nil, parent, "InterfaceOptionsCheckButtonTemplate")
    cb:SetHitRectInsets(0, -240, 0, 0)
    cb.text:SetText(label)
    cb.text:SetTextColor(0.95, 0.95, 0.95)
    cb.tooltipText = tooltip
    cb:SetChecked(getter())
    cb:SetScript("OnClick", function(s) onClick(s:GetChecked()) end)
    cb:SetScript("OnEnter", function(s)
        GameTooltip:SetOwner(s, "ANCHOR_RIGHT")
        GameTooltip:SetText(s.tooltipText, nil, nil, nil, nil, true)
    end)
    cb:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return cb
end

local function CreateSlider(parent, label, tooltip, minVal, maxVal, step, getter, onChange)
    local slider = CreateFrame("Slider", nil, parent, "OptionsSliderTemplate")
    slider:SetMinMaxValues(minVal, maxVal)
    slider:SetValueStep(step)
    slider:SetObeyStepOnDrag(true)
    slider:SetWidth(260)
    slider.Low:SetText(tostring(minVal))
    slider.High:SetText(tostring(maxVal))
    slider.tooltipText = tooltip

    local function setText(v) slider.Text:SetText(label .. ": " .. tostring(v)) end

    local initial = getter()
    slider:SetValue(initial)
    setText(math.floor(initial + 0.5))

    slider:SetScript("OnValueChanged", function(s, value)
        value = math.floor(value / step + 0.5) * step
        setText(value)
        onChange(value)
    end)
    slider:SetScript("OnEnter", function(s)
        GameTooltip:SetOwner(s, "ANCHOR_RIGHT")
        GameTooltip:SetText(s.tooltipText, nil, nil, nil, nil, true)
    end)
    slider:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return slider
end

local function CreateColorSwatchRow(parent, anchor, yOffset)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(360, 22)
    row:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, yOffset)

    local label = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    label:SetPoint("LEFT", row, "LEFT", 0, 0)
    label:SetText("Brick colors:")

    local function MakeSwatch(prevAnchor, color, text)
        local sw = CreateFrame("Frame", nil, row, "BackdropTemplate")
        sw:SetSize(14, 14)
        sw:SetBackdrop({
            bgFile = SOLID,
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 8,
            insets = { left = 1, right = 1, top = 1, bottom = 1 },
        })
        sw:SetBackdropColor(color[1], color[2], color[3], 1)
        sw:SetBackdropBorderColor(0, 0, 0, 0.8)
        sw:SetPoint("LEFT", prevAnchor, "RIGHT", 8, 0)

        local t = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        t:SetPoint("LEFT", sw, "RIGHT", 4, 0)
        t:SetText(text)
        return t
    end

    local r = MakeSwatch(label,  { 0.85, 0.20, 0.20 }, "1-3")
    local y = MakeSwatch(r,      { 0.95, 0.80, 0.20 }, "4-7")
    MakeSwatch(y,                { 0.30, 0.80, 0.30 }, "8-10")

    return row
end

---------------------------
-- Panel
---------------------------
function addon:Options()
    local panel = CreateFrame("Frame", addonName .. "OptionsPanel")
    panel.name = addonName
    panel:Hide()

    --
    -- Header
    --
    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalHuge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("|cFFE8C547Abunda|r|cFFCC4444Brick|r")

    local version = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    version:SetPoint("BOTTOMLEFT", title, "BOTTOMRIGHT", 8, 2)
    version:SetTextColor(unpack(COLOR_SUBTLE))
    version:SetFormattedText("v%s", C_AddOns.GetAddOnMetadata(addonName, "Version"))

    local desc = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    desc:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -10)
    desc:SetWidth(560)
    desc:SetJustifyH("LEFT")
    desc:SetText("Tracks the Restoration Druid Abundance buff stacks with colored bricks.")

    local swatch = CreateColorSwatchRow(panel, desc, -10)
    local headerDivider = CreateDivider(panel, swatch, -12)
    --
    -- Display section
    --
    local displayHeader = CreateSectionHeader(panel, headerDivider, -12, "Display")

    local lock = CreateCheckbox(panel,
        "Lock bar",
        "Lock prevents moving the bar and hides the bar's background outline.",
        function() return self.db.locked end,
        function(checked) self.db.locked = checked; self:ApplyLock() end)
    lock:SetPoint("TOPLEFT", displayHeader, "BOTTOMLEFT", -2, -6)

    local hideInactive = CreateCheckbox(panel,
        "Hide when inactive",
        "Hide the bar entirely when there are 0 stacks of Abundance.",
        function() return self.db.hideWhenInactive end,
        function(checked) self.db.hideWhenInactive = checked; self:Refresh() end)
    hideInactive:SetPoint("TOPLEFT", lock, "BOTTOMLEFT", 0, -2)

    local showEmpty = CreateCheckbox(panel,
        "Show empty bricks",
        "Show dimmed placeholder bricks for stacks you don't yet have.",
        function() return self.db.showEmptyBricks end,
        function(checked) self.db.showEmptyBricks = checked; self:Refresh() end)
    showEmpty:SetPoint("TOPLEFT", hideInactive, "BOTTOMLEFT", 0, -2)

    local horizontal
    horizontal = CreateCheckbox(panel,
        "Horizontal layout",
        "Lay the bar out left-to-right instead of bottom-to-top. Width and height are swapped automatically when toggled.",
        function() return self.db.orientation == "horizontal" end,
        function(checked)
            self:SetOrientation(checked and "horizontal" or "vertical")
            -- Sliders below need to reflect the swapped values.
            if self._OnOrientationChanged then self:_OnOrientationChanged() end
        end)
    horizontal:SetPoint("TOPLEFT", showEmpty, "BOTTOMLEFT", 0, -2)

    --
    -- Layout section
    --
    local layoutDivider = CreateDivider(panel, horizontal, -16)
    local layoutHeader = CreateSectionHeader(panel, layoutDivider, -12, "Bar Layout")

    local widthSlider = CreateSlider(panel, "Width", "Width of the bar in pixels.",
        6, 400, 1,
        function() return self.db.width end,
        function(v) self.db.width = v; self:ApplyPositionAndSize() end)
    widthSlider:SetPoint("TOPLEFT", layoutHeader, "BOTTOMLEFT", 8, -16)

    local heightSlider = CreateSlider(panel, "Height", "Height of the bar in pixels.",
        6, 400, 1,
        function() return self.db.height end,
        function(v) self.db.height = v; self:ApplyPositionAndSize() end)
    heightSlider:SetPoint("TOPLEFT", widthSlider, "BOTTOMLEFT", 0, -28)

    self._OnOrientationChanged = function()
        widthSlider:SetValue(self.db.width)
        heightSlider:SetValue(self.db.height)
    end

    local spacingSlider = CreateSlider(panel, "Brick spacing", "Pixels between bricks.",
        0, 8, 1,
        function() return self.db.spacing end,
        function(v) self.db.spacing = v; self:LayoutBricks() end)
    spacingSlider:SetPoint("TOPLEFT", heightSlider, "BOTTOMLEFT", 0, -28)

    local paddingSlider = CreateSlider(panel, "Padding", "Inner padding from the bar edge.",
        0, 8, 1,
        function() return self.db.padding end,
        function(v) self.db.padding = v; self:LayoutBricks() end)
    paddingSlider:SetPoint("TOPLEFT", spacingSlider, "BOTTOMLEFT", 0, -28)

    --
    -- Footer
    --
    local footerDivider = CreateDivider(panel, paddingSlider, -22)
    local reset = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    reset:SetSize(180, 24)
    reset:SetText("Reset Position & Size")
    reset:SetPoint("TOPLEFT", footerDivider, "BOTTOMLEFT", 0, -10)
    reset:SetScript("OnClick", function()
        self:ResetPosition()
        widthSlider:SetValue(self.db.width)
        heightSlider:SetValue(self.db.height)
        horizontal:SetChecked(self.db.orientation == "horizontal")
    end)

    local hint = panel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    hint:SetPoint("LEFT", reset, "RIGHT", 16, 0)
    hint:SetText("Slash: /abrick  ·  /abrick lock  ·  /abrick unlock  ·  /abrick reset  ·  /abrick test")

    local category = Settings.RegisterCanvasLayoutCategory(panel, addonName)
    Settings.RegisterAddOnCategory(category)
    self.optionsCategoryID = category:GetID()
end
