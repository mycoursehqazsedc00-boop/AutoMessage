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
    GameTooltip:AddLine(AM.StatusLine(), 0.8, 0.8, 0.8)
    GameTooltip:AddLine("Left-click: start / stop", 0.5, 1, 0.5)
    GameTooltip:AddLine("Right-click: settings", 0.5, 1, 0.5)
    GameTooltip:AddLine("Ctrl-click: translation on / off", 0.5, 1, 0.5)
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
            AM.SetTranslate(not AutoMessageDB.translate)
            AM.Print("Translation with WoWTranslate: " .. (AutoMessageDB.translate and "ON" or "OFF") .. ".")
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
    config:SetHeight(300)
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

    Label(config, "Message (separate several with ;;):", 20, -42)
    config.msg = Edit("AutoMessageMsgBox", config, 24, -62, 330, 1000)

    Label(config, "Channel:", 20, -92)
    config.chan = Edit("AutoMessageChanBox", config, 24, -112, 190, 60)
    Label(config, "say, yell, guild, party, raid, bg, w, 1-10 or a channel name (joined automatically)", 20, -136, true)

    Label(config, "Interval (s):", 230, -92)
    config.interval = Edit("AutoMessageIntervalBox", config, 234, -112, 60, 8)

    Label(config, "Whisper to:", 20, -158)
    config.whisper = Edit("AutoMessageWhisperBox", config, 24, -178, 190, 40)

    local check = CreateFrame("CheckButton", "AutoMessageTranslateCheck", config, "UICheckButtonTemplate")
    check:SetPoint("TOPLEFT", config, "TOPLEFT", 16, -204)
    check:SetScript("OnClick", function()
        AM.SetTranslate(this:GetChecked() and true or false)
    end)
    local checkText = getglobal("AutoMessageTranslateCheckText")
    if checkText then checkText:SetText("Translate with WoWTranslate") end
    config.check = check

    config.status = config:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    config.status:SetPoint("TOPLEFT", config, "TOPLEFT", 22, -236)
    config.status:SetWidth(340)
    config.status:SetJustifyH("LEFT")

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

function AM.ApplyFromUI()
    if not config then return end
    AM.SetMessages(config.msg:GetText())
    AM.SetChannel(config.chan:GetText())
    AM.SetInterval(config.interval:GetText())
    AM.SetWhisperTarget(config.whisper:GetText())
end

-- fill = true: copy the saved values into the edit boxes
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
        if fill then
            config.msg:SetText(AM.GetMessagesText())
            config.chan:SetText(db.channel)
            config.interval:SetText(tostring(db.interval))
            config.whisper:SetText(db.whisperTarget or "")
        end
        config.check:SetChecked(db.translate and 1 or nil)
        if AM.HasWoWTranslate() then
            config.check:Enable()
        else
            config.check:Disable()
        end
        config.start:SetText(AM.running and "Stop" or "Start")
        config.status:SetText(AM.StatusLine())
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
    -- keep the status line and countdown fresh while the window is open
    local ticker = CreateFrame("Frame", "AutoMessageTicker")
    local acc = 0
    ticker:SetScript("OnUpdate", function()
        acc = acc + arg1
        if acc < 1 then return end
        acc = 0
        if config and config:IsShown() then AM.RefreshUI() end
    end)
end
