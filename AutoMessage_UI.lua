-- AutoMessage user interface: a movable on/off button and a configuration window.
-- Built in Lua with stock 1.12 templates.

local AM = AutoMessage

local button, config
local dragging = false
local lastDrag = 0

local function Colour(r, g, b, text)
    return string.format("|cff%02x%02x%02x%s|r", math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5), text)
end

-- ---------------------------------------------------------------------------
-- on/off button
-- ---------------------------------------------------------------------------
local function PlaceButton()
    local pos = AutoMessageDB.button
    button:ClearAllPoints()
    button:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", pos.x, pos.y)
end

local function SaveButtonPosition()
    local x, y = button:GetLeft(), button:GetBottom()
    if x and y then
        AutoMessageDB.button.x = x
        AutoMessageDB.button.y = y
    end
end

local function ButtonTooltip()
    GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
    GameTooltip:SetText("AutoMessage")
    GameTooltip:AddLine(AM.running and "Running" or "Stopped", 1, 1, 1)
    for n = 1, AM.MAX_SLOTS do
        if AM.Slot(n).enabled or AM.state[n].running then
            GameTooltip:AddLine("Slot " .. n .. ": " .. AM.StatusLine(n), 0.8, 0.8, 0.8)
        end
    end
    GameTooltip:AddLine("Left-click: start / stop all slots", 0.5, 1, 0.5)
    GameTooltip:AddLine("Right-click: settings", 0.5, 1, 0.5)
    GameTooltip:AddLine("Ctrl-click: translation of the current slot", 0.5, 1, 0.5)
    GameTooltip:AddLine("Drag: move", 0.5, 1, 0.5)
    GameTooltip:Show()
end

local function CreateButton()
    button = CreateFrame("Button", "AutoMessageToggleButton", UIParent)
    button:SetWidth(44)
    button:SetHeight(34)
    button:SetFrameStrata("MEDIUM")
    button:SetMovable(true)
    button:EnableMouse(true)
    button:SetClampedToScreen(true)
    button:RegisterForDrag("LeftButton")
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    button:SetBackdropColor(0, 0, 0, 0.8)

    local title = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    title:SetPoint("TOP", button, "TOP", 0, -5)
    title:SetText("AutoMsg")
    button.title = title

    local state = button:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    state:SetPoint("BOTTOM", button, "BOTTOM", 0, 5)
    button.state = state

    button:SetScript("OnDragStart", function()
        dragging = true
        this:StartMoving()
    end)
    button:SetScript("OnDragStop", function()
        this:StopMovingOrSizing()
        dragging = false
        lastDrag = GetTime()
        SaveButtonPosition()
    end)
    button:SetScript("OnClick", function()
        -- releasing the mouse after a drag also produces a click; ignore it
        if dragging or (GetTime() - lastDrag) < 0.2 then return end
        if arg1 == "RightButton" then
            AM.ShowConfig()
        elseif IsControlKeyDown and IsControlKeyDown() then
            local s = AM.Slot()
            AM.SetTranslate(not s.translate)
            AM.Print(AM.Tag() .. "Translation with WoWTranslate: " .. (s.translate and "ON" or "OFF") .. ".")
        else
            AM.Toggle()
        end
    end)
    button:SetScript("OnEnter", ButtonTooltip)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)

    PlaceButton()
    if AutoMessageDB.button.shown then button:Show() else button:Hide() end
end

function AM.ShowButton(show)
    AutoMessageDB.button.shown = show and true or false
    if button then
        if show then button:Show() else button:Hide() end
    end
    AM.Print("Button " .. (show and "shown." or "hidden. Show it again with /autobutton."))
end

function AM.ResetButton()
    AutoMessageDB.button.x = 400
    AutoMessageDB.button.y = 300
    AutoMessageDB.button.shown = true
    if button then PlaceButton(); button:Show() end
end

-- ---------------------------------------------------------------------------
-- configuration window
-- ---------------------------------------------------------------------------
local function Label(parent, text, x, y, small)
    local fs = parent:CreateFontString(nil, "OVERLAY", small and "GameFontNormalSmall" or "GameFontNormal")
    fs:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    fs:SetText(text)
    return fs
end

local function Edit(name, parent, x, y, width, maxLetters)
    local eb = CreateFrame("EditBox", name, parent, "InputBoxTemplate")
    eb:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    eb:SetWidth(width)
    eb:SetHeight(20)
    eb:SetAutoFocus(false)
    eb:SetMaxLetters(maxLetters or 255)
    if ChatFontNormal then eb:SetFontObject(ChatFontNormal) end
    eb:SetScript("OnEscapePressed", function() this:ClearFocus() end)
    eb:SetScript("OnEnterPressed", function() this:ClearFocus(); AM.ApplyFromUI() end)
    return eb
end

local function CreateConfig()
    config = CreateFrame("Frame", "AutoMessageConfigFrame", UIParent)
    config:SetWidth(380)
    config:SetHeight(372)
    config:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    config:SetFrameStrata("DIALOG")
    config:SetMovable(true)
    config:EnableMouse(true)
    config:SetClampedToScreen(true)
    config:RegisterForDrag("LeftButton")
    config:SetScript("OnDragStart", function() this:StartMoving() end)
    config:SetScript("OnDragStop", function() this:StopMovingOrSizing() end)
    config:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 8, right = 8, top = 8, bottom = 8 },
    })
    config:Hide()
    if UISpecialFrames then table.insert(UISpecialFrames, "AutoMessageConfigFrame") end

    local title = config:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", config, "TOP", 0, -16)
    title:SetText("AutoMessage " .. AM.VERSION)

    -- slot tabs
    config.tabs = {}
    for n = 1, AM.MAX_SLOTS do
        local tab = CreateFrame("Button", "AutoMessageSlotTab" .. n, config, "UIPanelButtonTemplate")
        tab:SetWidth(40)
        tab:SetHeight(22)
        tab:SetPoint("TOPLEFT", config, "TOPLEFT", 20 + (n - 1) * 44, -42)
        tab.slot = n
        tab:SetScript("OnClick", function()
            AM.ApplyFromUI()
            AM.SelectSlot(this.slot)
        end)
        config.tabs[n] = tab
    end

    local enabled = CreateFrame("CheckButton", "AutoMessageEnabledCheck", config, "UICheckButtonTemplate")
    enabled:SetPoint("TOPLEFT", config, "TOPLEFT", 204, -39)
    enabled:SetScript("OnClick", function()
        AM.SetEnabled(this:GetChecked() and true or false)
    end)
    local enabledText = getglobal("AutoMessageEnabledCheckText")
    if enabledText then enabledText:SetText("Slot enabled") end
    config.enabled = enabled

    Label(config, "Message (separate several with ;;):", 20, -76)
    config.msg = Edit("AutoMessageMsgBox", config, 24, -96, 330, 1000)

    Label(config, "Channel:", 20, -126)
    config.chan = Edit("AutoMessageChanBox", config, 24, -146, 190, 60)
    Label(config, "say, yell, guild, party, raid, bg, w, 1-10 or a channel name (joined automatically)", 20, -170, true)

    Label(config, "Interval (s):", 230, -126)
    config.interval = Edit("AutoMessageIntervalBox", config, 234, -146, 60, 8)

    Label(config, "Whisper to:", 20, -192)
    config.whisper = Edit("AutoMessageWhisperBox", config, 24, -212, 190, 40)

    Label(config, "Limit (0 = none):", 230, -192)
    config.limit = Edit("AutoMessageLimitBox", config, 234, -212, 60, 8)

    local check = CreateFrame("CheckButton", "AutoMessageTranslateCheck", config, "UICheckButtonTemplate")
    check:SetPoint("TOPLEFT", config, "TOPLEFT", 16, -238)
    check:SetScript("OnClick", function()
        AM.SetTranslate(this:GetChecked() and true or false)
    end)
    local checkText = getglobal("AutoMessageTranslateCheckText")
    if checkText then checkText:SetText("Translate this slot with WoWTranslate") end
    config.check = check

    config.status = config:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    config.status:SetPoint("TOPLEFT", config, "TOPLEFT", 22, -270)
    config.status:SetWidth(340)
    config.status:SetHeight(60)
    config.status:SetJustifyH("LEFT")
    config.status:SetJustifyV("TOP")

    local start = CreateFrame("Button", "AutoMessageStartButton", config, "UIPanelButtonTemplate")
    start:SetWidth(90); start:SetHeight(22)
    start:SetPoint("BOTTOMLEFT", config, "BOTTOMLEFT", 20, 18)
    start:SetScript("OnClick", function() AM.ApplyFromUI(); AM.Toggle() end)
    config.start = start

    local apply = CreateFrame("Button", "AutoMessageApplyButton", config, "UIPanelButtonTemplate")
    apply:SetWidth(90); apply:SetHeight(22)
    apply:SetPoint("BOTTOM", config, "BOTTOM", 0, 18)
    apply:SetText("Apply")
    apply:SetScript("OnClick", function() AM.ApplyFromUI() end)

    local close = CreateFrame("Button", "AutoMessageCloseButton", config, "UIPanelButtonTemplate")
    close:SetWidth(90); close:SetHeight(22)
    close:SetPoint("BOTTOMRIGHT", config, "BOTTOMRIGHT", -20, 18)
    close:SetText("Hide")
    close:SetScript("OnClick", function() config:Hide() end)

    config:SetScript("OnShow", function() AM.RefreshUI(true) end)
end

-- Copy the edit boxes into the CURRENT slot.
function AM.ApplyFromUI()
    if not config then return end
    AM.SetMessages(config.msg:GetText())
    AM.SetChannel(config.chan:GetText())
    AM.SetInterval(config.interval:GetText())
    AM.SetWhisperTarget(config.whisper:GetText())
    local limit = config.limit:GetText()
    if limit and AM.Trim(limit) ~= "" then AM.SetLimit(limit) end
end

-- fill = true: copy the saved values of the current slot into the edit boxes
function AM.RefreshUI(fill)
    local db = AutoMessageDB
    if button then
        if AM.running then
            button.state:SetText(Colour(0.2, 1, 0.2, "ON"))
        else
            button.state:SetText(Colour(1, 0.3, 0.3, "OFF"))
        end
    end
    if config then
        local s = AM.Slot()
        if fill then
            config.msg:SetText(AM.GetMessagesText())
            config.chan:SetText(s.channel)
            config.interval:SetText(tostring(s.interval))
            config.whisper:SetText(s.whisperTarget or "")
            config.limit:SetText(tostring(s.limit or 0))
        end
        for n = 1, AM.MAX_SLOTS do
            local label = tostring(n)
            if AM.state[n].running then label = Colour(0.2, 1, 0.2, label)
            elseif AM.Slot(n).enabled then label = Colour(1, 1, 1, label)
            else label = Colour(0.5, 0.5, 0.5, label) end
            if n == AM.current then label = "[" .. label .. "]" end
            config.tabs[n]:SetText(label)
        end
        config.enabled:SetChecked(s.enabled and 1 or nil)
        config.check:SetChecked(s.translate and 1 or nil)
        if AM.HasWoWTranslate() then
            config.check:Enable()
        else
            config.check:Disable()
        end
        config.start:SetText(AM.running and "Stop all" or "Start")
        local lines = {}
        for n = 1, AM.MAX_SLOTS do
            if AM.Slot(n).enabled or AM.state[n].running then
                table.insert(lines, "Slot " .. n .. ": " .. AM.StatusLine(n))
            end
        end
        if table.getn(lines) == 0 then lines[1] = "No slot is enabled." end
        config.status:SetText(table.concat(lines, "\n"))
    end
end

function AM.ShowConfig()
    if not config then return end
    config:Show()
end

function AM.InitUI()
    CreateButton()
    CreateConfig()
    AM.RefreshUI(true)
    -- keep the status lines and countdowns fresh while the window is open
    local ticker = CreateFrame("Frame", "AutoMessageTicker")
    local acc = 0
    ticker:SetScript("OnUpdate", function()
        acc = acc + arg1
        if acc < 1 then return end
        acc = 0
        if config and config:IsShown() then AM.RefreshUI() end
    end)
end
