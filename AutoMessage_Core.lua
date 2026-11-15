--[[
AutoMessage 2.0

Based on AutoMessager V1.0 by The BOFH (Stewarta of Nordrassil) - "Please Don't Spam!"

Repeats one or more chat messages at a fixed interval.
 - channel by alias, number or NAME (joined automatically when needed)
 - optional translation through WoWTranslate (translated once, then re-sent from memory)
 - message rotation, {zone}/{name}/... variables, send limit, target checks
 - debug trace (/autodebug, /autolog)
]]

AutoMessage = AutoMessage or {}
local AM = AutoMessage
AM.VERSION = "2.1"

local MAX_SLOTS         = 4     -- independent message/channel pairs
local MIN_INTERVAL      = 5     -- seconds; lower values only get you muted
local MIN_GAP           = 2     -- seconds between two sends of any slots
local MAX_LENGTH        = 255   -- bytes, the chat limit
local JOIN_TIMEOUT      = 10    -- seconds to wait for a channel join
local TRANSLATE_TIMEOUT = 30    -- seconds to wait for WoWTranslate
local TRANSLATE_RETRY   = 300   -- seconds to send untranslated after a translation failure
local CACHE_MAX         = 20
local LOG_MAX           = 100
local FAR               = 86400

AM.MAX_SLOTS = MAX_SLOTS
AM.current = 1          -- the slot the slash commands and the settings window edit
AM.running = false      -- true while at least one slot runs
AM.lastSend = 0
AM.trCache = {}
AM.trCount = 0
AM.trFailUntil = 0
AM.log = {}

local function NewState()
    return { running = false, gen = 0, index = 1, sent = 0, nextTick = 0,
             waiting = false, waitDeadline = 0, join = nil, warned = nil, hold = nil }
end
AM.state = {}
for i = 1, MAX_SLOTS do AM.state[i] = NewState() end

-- ---------------------------------------------------------------------------
-- helpers
-- ---------------------------------------------------------------------------
local function Trim(s)
    return (string.gsub(s or "", "^%s*(.-)%s*$", "%1"))
end
AM.Trim = Trim

function AM.Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cff33ccffAutoMessage|r " .. msg)
end

-- Debug trace: kept in memory (see /autolog), only while /autodebug is on.
function AM.Trace(a, b, c, d)
    if not AutoMessageDB or not AutoMessageDB.debug then return end
    local args = { a, b, c, d }
    local parts = {}
    for i = 1, 4 do
        if args[i] ~= nil then table.insert(parts, tostring(args[i])) end
    end
    table.insert(AM.log, string.format("[%.1f] ", GetTime()) .. table.concat(parts, " "))
    if table.getn(AM.log) > LOG_MAX then table.remove(AM.log, 1) end
end
local Trace = AM.Trace

local function CopyDefaults(dst, src)
    for k, v in pairs(src) do
        if dst[k] == nil then
            if type(v) == "table" then
                dst[k] = {}
                CopyDefaults(dst[k], v)
            else
                dst[k] = v
            end
        elseif type(v) == "table" and type(dst[k]) == "table" then
            CopyDefaults(dst[k], v)
        end
    end
end

local function NewSlot()
    return { enabled = false, messages = {}, interval = 30, channel = "say",
             whisperTarget = "", translate = false, limit = 0 }
end

local DEFAULTS = {
    version = 3,
    debug = false,
    button = { shown = true, x = 400, y = 300 },
}

function AM.Slot(n)
    return AutoMessageDB.slots[n or AM.current]
end

-- "[slot 2] " in front of messages, unless there is only slot 1 in use
function AM.Tag(n)
    n = n or AM.current
    local enabled = 0
    for i = 1, MAX_SLOTS do
        if AutoMessageDB.slots[i].enabled then enabled = enabled + 1 end
    end
    if n == 1 and enabled <= 1 then return "" end
    return "[slot " .. n .. "] "
end

-- ---------------------------------------------------------------------------
-- saved variables
-- ---------------------------------------------------------------------------
local SLOT_FIELDS = { "messages", "interval", "channel", "whisperTarget", "translate", "limit" }

function AM.Init()
    if type(AutoMessageDB) ~= "table" then AutoMessageDB = {} end
    local db = AutoMessageDB
    CopyDefaults(db, DEFAULTS)

    if type(db.slots) ~= "table" then
        -- first run of this layout: carry the old settings over into slot 1
        local first = NewSlot()
        first.enabled = true
        if db.channel ~= nil or db.messages ~= nil then
            -- AutoMessage 2.0 kept one set of fields at the top level
            for _, k in ipairs(SLOT_FIELDS) do
                if db[k] ~= nil then first[k] = db[k]; db[k] = nil end
            end
        elseif not db.migrated then
            -- AutoMessager 1.0 lived in four globals
            if type(am) == "string" and am ~= "" and am ~= "Message goes here" then
                first.messages = { am }
            end
            if tonumber(ticktime) then first.interval = tonumber(ticktime) end
            if type(channame) == "string" and channame ~= "" then first.channel = channame end
            if type(charname) == "string" and charname ~= "" and charname ~= "Trump" then
                first.whisperTarget = charname
            end
        end
        db.slots = { first }
    end
    db.migrated = true
    am, ticktime, channame, charname = nil, nil, nil, nil

    for i = 1, MAX_SLOTS do
        if type(db.slots[i]) ~= "table" then db.slots[i] = NewSlot() end
        CopyDefaults(db.slots[i], NewSlot())
        if db.slots[i].interval < MIN_INTERVAL then db.slots[i].interval = MIN_INTERVAL end
    end
    db.version = 3
    Trace("init", "slot 1 messages", table.getn(db.slots[1].messages))
end

-- ---------------------------------------------------------------------------
-- settings (all take an optional slot number; default: the current slot)
-- ---------------------------------------------------------------------------
function AM.SelectSlot(n)
    if n and n >= 1 and n <= MAX_SLOTS then
        AM.current = n
        Trace("current slot", n)
        if AM.RefreshUI then AM.RefreshUI(true) end
        return true
    end
    return false
end

-- Several messages are separated by ";;".
function AM.SplitMessages(text)
    local out = {}
    local rest = text or ""
    while true do
        local s, e = string.find(rest, ";;", 1, true)
        local piece
        if s then
            piece = string.sub(rest, 1, s - 1)
            rest = string.sub(rest, e + 1)
        else
            piece = rest
        end
        piece = Trim(piece)
        if piece ~= "" then table.insert(out, piece) end
        if not s then break end
    end
    return out
end

function AM.SetMessages(text, n)
    n = n or AM.current
    local list = AM.SplitMessages(text)
    local kept = {}
    for i = 1, table.getn(list) do
        if string.len(list[i]) > MAX_LENGTH then
            AM.Print(AM.Tag(n) .. "Message " .. i .. " is longer than " .. MAX_LENGTH .. " characters and was not saved.")
        else
            table.insert(kept, list[i])
        end
    end
    AM.Slot(n).messages = kept
    AM.state[n].index = 1
    Trace("messages set", n, table.getn(kept))
    if AM.RefreshUI then AM.RefreshUI() end
    return table.getn(kept)
end

function AM.GetMessagesText(n)
    return table.concat(AM.Slot(n).messages, " ;; ")
end

function AM.SetInterval(value, n)
    n = n or AM.current
    local v = tonumber(value)
    if not v then
        AM.Print("The interval must be a number of seconds.")
        return false
    end
    if v < MIN_INTERVAL then
        AM.Print("Intervals under " .. MIN_INTERVAL .. " seconds are not allowed; using " .. MIN_INTERVAL .. ".")
        v = MIN_INTERVAL
    end
    AM.Slot(n).interval = v
    Trace("interval", n, v)
    if AM.RefreshUI then AM.RefreshUI() end
    return true
end

function AM.SetChannel(value, n)
    n = n or AM.current
    local text = Trim(value or "")
    if text == "" then return false end
    AM.Slot(n).channel = text
    AM.state[n].join = nil
    Trace("channel", n, text)
    if AM.RefreshUI then AM.RefreshUI() end
    return true
end

function AM.SetWhisperTarget(value, n)
    AM.Slot(n).whisperTarget = Trim(value or "")
    if AM.RefreshUI then AM.RefreshUI() end
end

function AM.HasWoWTranslate()
    return WoWTranslate_PrepareOutgoing ~= nil
end

function AM.SetTranslate(on, n)
    n = n or AM.current
    local s = AM.Slot(n)
    if on and not AM.HasWoWTranslate() then
        AM.Print("WoWTranslate 2.2 or newer is needed for translation (not found).")
        s.translate = false
    else
        s.translate = on and true or false
        Trace("translate", n, s.translate)
    end
    AM.trFailUntil = 0
    if AM.RefreshUI then AM.RefreshUI() end
    return s.translate
end

function AM.SetLimit(value, n)
    local v = tonumber(value)
    if not v or v < 0 then
        AM.Print("The limit must be a number (0 = no limit).")
        return false
    end
    AM.Slot(n).limit = math.floor(v)
    if AM.RefreshUI then AM.RefreshUI() end
    return true
end

-- Enabled slots take part in Start. Enabling a slot while others run starts it at once.
function AM.SetEnabled(on, n)
    n = n or AM.current
    local s = AM.Slot(n)
    s.enabled = on and true or false
    Trace("slot enabled", n, s.enabled)
    if s.enabled and AM.running and not AM.state[n].running then
        AM.StartSlot(n)
    elseif not s.enabled and AM.state[n].running then
        AM.StopSlot(n, "slot disabled")
    end
    if AM.RefreshUI then AM.RefreshUI() end
end

-- ---------------------------------------------------------------------------
-- channels
-- ---------------------------------------------------------------------------
local ALIASES = {
    s = "SAY", say = "SAY",
    y = "YELL", yell = "YELL",
    g = "GUILD", guild = "GUILD",
    o = "OFFICER", officer = "OFFICER",
    p = "PARTY", party = "PARTY",
    r = "RAID", raid = "RAID",
    rw = "RAID_WARNING", raidwarning = "RAID_WARNING", raid_warning = "RAID_WARNING",
    bg = "BATTLEGROUND", battleground = "BATTLEGROUND",
    e = "EMOTE", emote = "EMOTE",
    w = "WHISPER", whisper = "WHISPER",
    de = "DOEMOTE", rs = "RUNSCRIPT",
}

-- Returns { kind = "SAY" | ... | "CHANNEL", id = n or nil, name = text or nil }
function AM.ParseChannel(input)
    local text = Trim(input or "")
    if text == "" then return nil end
    local kind = ALIASES[string.lower(text)]
    if kind then return { kind = kind } end
    local n = tonumber(text)
    if n then
        if n >= 1 and n <= 10 and n == math.floor(n) then
            return { kind = "CHANNEL", id = n }
        end
        return nil
    end
    return { kind = "CHANNEL", name = text }
end

-- Joined channels as a list of { id =, name = }
function AM.GetJoinedChannels()
    local out = {}
    local list = { GetChannelList() }
    for i = 1, table.getn(list), 2 do
        if list[i] and list[i + 1] then
            table.insert(out, { id = list[i], name = list[i + 1] })
        end
    end
    return out
end

-- Channel number of a joined channel (by number or by name), or nil.
-- Names match case-insensitively, exactly or as a prefix ("trade" finds "Trade - City").
function AM.FindChannel(spec)
    local joined = AM.GetJoinedChannels()
    if spec.id then
        for i = 1, table.getn(joined) do
            if joined[i].id == spec.id then return joined[i].id end
        end
        return nil
    end
    local want = string.lower(spec.name)
    for i = 1, table.getn(joined) do
        if string.lower(joined[i].name) == want then return joined[i].id end
    end
    local len = string.len(want)
    for i = 1, table.getn(joined) do
        local n = string.lower(joined[i].name)
        if string.sub(n, 1, len) == want then return joined[i].id end
    end
    return nil
end

-- Can this kind of message be sent right now? (n = slot, for the whisper target)
function AM.TargetAvailable(spec, n)
    local k = spec.kind
    if k == "PARTY" then
        if GetNumPartyMembers() > 0 then return true end
        return false, "you are not in a party"
    elseif k == "RAID" or k == "RAID_WARNING" then
        if GetNumRaidMembers() > 0 then return true end
        return false, "you are not in a raid"
    elseif k == "GUILD" or k == "OFFICER" then
        if GetGuildInfo("player") then return true end
        return false, "you are not in a guild"
    elseif k == "WHISPER" then
        if Trim(AM.Slot(n).whisperTarget or "") ~= "" then return true end
        return false, "no whisper target set (/autochar <name>)"
    end
    return true
end

-- Returns dest (table) or nil, state ("joining" | "failed" | "unavailable"), reason
function AM.ResolveDestination(spec, n)
    n = n or AM.current
    local st = AM.state[n]
    local k = spec.kind
    if k == "DOEMOTE" or k == "RUNSCRIPT" then return { kind = k } end
    if k == "CHANNEL" then
        local id = AM.FindChannel(spec)
        if id then
            st.join = nil
            return { kind = "CHANNEL", channel = id }
        end
        if spec.name then
            local now = GetTime()
            if not st.join or st.join.name ~= spec.name then
                Trace("joining channel", spec.name)
                AM.Print(AM.Tag(n) .. "Joining channel '" .. spec.name .. "'...")
                JoinChannelByName(spec.name)
                st.join = { name = spec.name, since = now }
                return nil, "joining"
            end
            if now - st.join.since > JOIN_TIMEOUT then
                st.join = nil
                return nil, "failed"
            end
            return nil, "joining"
        end
        return nil, "unavailable", "channel " .. spec.id .. " is not joined"
    end
    local ok, why = AM.TargetAvailable(spec, n)
    if not ok then return nil, "unavailable", why end
    if k == "WHISPER" then
        return { kind = "WHISPER", channel = Trim(AM.Slot(n).whisperTarget) }
    end
    return { kind = k }
end

-- ---------------------------------------------------------------------------
-- sending
-- ---------------------------------------------------------------------------
-- Raw send: when WoWTranslate is loaded, bypass its outgoing hook so a message is
-- never translated twice and the "Translate" switch of AutoMessage decides.
local function RawSend(text, chatType, language, channel)
    if WoWTranslate_SendRaw then
        return WoWTranslate_SendRaw(text, chatType, language, channel)
    end
    return SendChatMessage(text, chatType, language, channel)
end

function AM.SendNow(text, dest)
    local k = dest.kind
    Trace("send", k, dest.channel, string.sub(text, 1, 30))
    AM.lastSend = GetTime()
    if k == "DOEMOTE" then
        DoEmote(text)
    elseif k == "RUNSCRIPT" then
        RunScript(text)
    elseif k == "CHANNEL" then
        RawSend(text, "CHANNEL", nil, dest.channel)
    elseif k == "WHISPER" then
        RawSend(text, "WHISPER", nil, dest.channel)
    else
        RawSend(text, k)
    end
    return true
end

-- {zone} {subzone} {name} {level} {class}
function AM.Expand(text)
    if not string.find(text, "{", 1, true) then return text end
    local values = {
        zone = GetZoneText and GetZoneText() or "",
        subzone = GetSubZoneText and GetSubZoneText() or "",
        name = UnitName("player"),
        level = UnitLevel("player"),
        class = (UnitClass("player")),
    }
    local out = string.gsub(text, "{(%a+)}", function(key)
        local v = values[string.lower(key)]
        if v ~= nil and v ~= "" then return tostring(v) end
    end)
    return out
end

local function TranslateSignature()
    local db = WoWTranslateDB
    if not db then return "" end
    return tostring(db.outgoingFromLang) .. ">" .. tostring(db.outgoingToLang) .. "|" ..
           tostring(db.outgoingPrefixEnabled) .. "|" .. tostring(db.outgoingPrefix)
end

local function WantTranslate(spec, n)
    if not AM.Slot(n).translate then return false end
    if not AM.HasWoWTranslate() then return false end
    if spec.kind == "DOEMOTE" or spec.kind == "RUNSCRIPT" then return false end
    return true
end

local function CacheTranslation(key, value)
    if AM.trCount >= CACHE_MAX then
        AM.trCache = {}
        AM.trCount = 0
    end
    if AM.trCache[key] == nil then AM.trCount = AM.trCount + 1 end
    AM.trCache[key] = value
end

local function ScheduleNext(n)
    AM.state[n].nextTick = GetTime() + AM.Slot(n).interval
end

-- Final step: send, count, schedule the next one.
local function Deliver(n, final, spec, gen)
    local st, s = AM.state[n], AM.Slot(n)
    if not st.running or gen ~= st.gen then
        Trace("late result dropped", n)
        return
    end
    st.waiting = false
    -- two slots never send within MIN_GAP seconds of each other (server flood control)
    local now = GetTime()
    if now - AM.lastSend < MIN_GAP then
        st.hold = { final = final, spec = spec }
        st.nextTick = AM.lastSend + MIN_GAP
        Trace("held back", n)
        return
    end
    local dest, state, why = AM.ResolveDestination(spec, n)
    if not dest then
        if state == "failed" then
            AM.StopSlot(n, "could not join channel '" .. tostring(spec.name) .. "'")
        else
            Trace("not sent:", state, why)
            ScheduleNext(n)
        end
        return
    end
    if string.len(final) > MAX_LENGTH then
        if st.warned ~= "long" then
            AM.Print(AM.Tag(n) .. "A message is longer than " .. MAX_LENGTH .. " characters after expansion or translation; skipped.")
            st.warned = "long"
        end
        st.index = st.index + 1
        ScheduleNext(n)
        return
    end
    AM.SendNow(final, dest)
    st.sent = st.sent + 1
    st.index = st.index + 1
    st.warned = nil
    local limit = s.limit or 0
    if limit > 0 and st.sent >= limit then
        AM.StopSlot(n, "limit of " .. limit .. " messages reached")
        return
    end
    ScheduleNext(n)
    if AM.RefreshUI then AM.RefreshUI() end
end

function AM.Step(n)
    local s, st = AM.Slot(n), AM.state[n]
    local now = GetTime()
    local count = table.getn(s.messages)
    if count == 0 then AM.StopSlot(n, "no message set"); return end
    local spec = AM.ParseChannel(s.channel)
    if not spec then AM.StopSlot(n, "channel '" .. tostring(s.channel) .. "' is not valid"); return end

    -- a result that was held back because another slot sent a moment ago
    if st.hold then
        if now - AM.lastSend < MIN_GAP then
            st.nextTick = AM.lastSend + MIN_GAP
            return
        end
        local h = st.hold
        st.hold = nil
        Deliver(n, h.final, h.spec, st.gen)
        return
    end
    if now - AM.lastSend < MIN_GAP then
        st.nextTick = AM.lastSend + MIN_GAP
        return
    end

    local dest, state, why = AM.ResolveDestination(spec, n)
    if not dest then
        if state == "joining" then
            st.nextTick = now + 0.5
        elseif state == "failed" then
            AM.StopSlot(n, "could not join channel '" .. tostring(spec.name) .. "'")
        else
            if st.warned ~= why then
                AM.Print(AM.Tag(n) .. "Not sending: " .. tostring(why) .. ".")
                st.warned = why
            end
            Trace("waiting:", n, why)
            ScheduleNext(n)
        end
        return
    end
    st.warned = nil

    if st.index > count then st.index = 1 end
    local text = AM.Expand(s.messages[st.index])
    if text == "" then
        st.index = st.index + 1
        ScheduleNext(n)
        return
    end

    if not WantTranslate(spec, n) then
        Deliver(n, text, spec, st.gen)
        return
    end

    local key = TranslateSignature() .. "\1" .. text
    local cached = AM.trCache[key]
    if cached then
        Trace("translation from memory", n)
        Deliver(n, cached, spec, st.gen)
        return
    end
    if now < AM.trFailUntil then
        Trace("translation paused, sending original", n)
        Deliver(n, text, spec, st.gen)
        return
    end

    -- Ask WoWTranslate once; the result is reused for every later repeat.
    st.waiting = true
    st.waitDeadline = now + TRANSLATE_TIMEOUT
    st.nextTick = FAR
    local gen = st.gen
    Trace("translating", n, string.sub(text, 1, 30))
    WoWTranslate_PrepareOutgoing(text, function(translated, err)
        if gen ~= st.gen then return end
        if translated then
            CacheTranslation(key, translated)
            Deliver(n, translated, spec, gen)
        else
            AM.Print(AM.Tag(n) .. "Translation failed (" .. tostring(err) .. "); sending the original text.")
            AM.trFailUntil = GetTime() + TRANSLATE_RETRY
            Deliver(n, text, spec, gen)
        end
    end)
end

function AM.OnUpdate(elapsed)
    if not AM.running then return end
    local now = GetTime()
    for n = 1, MAX_SLOTS do
        local st = AM.state[n]
        if st.running then
            if st.waiting then
                if now > st.waitDeadline then
                    -- WoWTranslate never answered: send the original and ignore a late answer.
                    st.gen = st.gen + 1
                    st.waiting = false
                    AM.trFailUntil = now + TRANSLATE_RETRY
                    AM.Print(AM.Tag(n) .. "Translation timed out; sending the original text.")
                    local s = AM.Slot(n)
                    local spec = AM.ParseChannel(s.channel)
                    local text = AM.Expand(s.messages[st.index] or "")
                    if spec and text ~= "" then Deliver(n, text, spec, st.gen) else ScheduleNext(n) end
                end
            elseif now >= st.nextTick then
                AM.Step(n)
            end
        end
    end
end

-- ---------------------------------------------------------------------------
-- start / stop
-- ---------------------------------------------------------------------------
local function SyncRunning()
    AM.running = false
    for n = 1, MAX_SLOTS do
        if AM.state[n].running then AM.running = true end
    end
end

function AM.StartSlot(n)
    local s, st = AM.Slot(n), AM.state[n]
    if table.getn(s.messages) == 0 then
        AM.Print(AM.Tag(n) .. "Set a message first: /automsg <text>")
        return false
    end
    if not AM.ParseChannel(s.channel) then
        AM.Print(AM.Tag(n) .. "Set a valid channel first: /autochan <say|yell|guild|party|raid|bg|w|1-10|name>")
        return false
    end
    st.running = true
    st.gen = st.gen + 1
    st.waiting = false
    st.hold = nil
    st.sent = 0
    st.index = 1
    st.warned = nil
    st.join = nil
    st.nextTick = GetTime()
    SyncRunning()
    Trace("start", n)
    AM.Print(AM.Tag(n) .. "Started: every " .. s.interval .. "s to " .. s.channel .. ".")
    if AM.RefreshUI then AM.RefreshUI() end
    return true
end

-- Starts every enabled slot. Returns true when at least one started.
function AM.Start()
    local enabled, started = 0, 0
    for n = 1, MAX_SLOTS do
        if AM.Slot(n).enabled then
            enabled = enabled + 1
            if AM.StartSlot(n) then started = started + 1 end
        end
    end
    if enabled == 0 then
        AM.Print("No slot is enabled. Enable one with /autoslot <n> on.")
    end
    return started > 0
end

function AM.StopSlot(n, reason)
    local st = AM.state[n]
    local was = st.running
    st.running = false
    st.gen = st.gen + 1
    st.waiting = false
    st.hold = nil
    st.join = nil
    SyncRunning()
    Trace("stop", n, reason)
    if was then
        AM.Print(AM.Tag(n) .. "Stopped" .. (reason and (": " .. reason) or ".") .. (reason and "." or ""))
    end
    if AM.RefreshUI then AM.RefreshUI() end
end

function AM.Stop(reason)
    for n = 1, MAX_SLOTS do
        if AM.state[n].running then AM.StopSlot(n, reason) end
    end
    SyncRunning()
    if AM.RefreshUI then AM.RefreshUI() end
end

function AM.Toggle()
    if AM.running then AM.Stop() else AM.Start() end
end

function AM.StatusLine(n)
    n = n or AM.current
    local s, st = AM.Slot(n), AM.state[n]
    local parts = {}
    table.insert(parts, st.running and "RUNNING" or (s.enabled and "stopped" or "disabled"))
    table.insert(parts, "channel " .. tostring(s.channel))
    table.insert(parts, "every " .. s.interval .. "s")
    table.insert(parts, table.getn(s.messages) .. " message(s)")
    local tr = "translate off"
    if s.translate then tr = AM.HasWoWTranslate() and "translate ON" or "translate ON (WoWTranslate missing)" end
    table.insert(parts, tr)
    if st.running then
        table.insert(parts, "sent " .. st.sent .. ((s.limit or 0) > 0 and ("/" .. s.limit) or ""))
        if not st.waiting then
            local left = st.nextTick - GetTime()
            if left > 0 and left < FAR then table.insert(parts, "next in " .. math.floor(left) .. "s") end
        end
    end
    return table.concat(parts, " | ")
end

-- ---------------------------------------------------------------------------
-- events
-- ---------------------------------------------------------------------------
local frame = CreateFrame("Frame", "AutoMessageFrame")
frame:RegisterEvent("VARIABLES_LOADED")
frame:SetScript("OnEvent", function()
    if event == "VARIABLES_LOADED" then
        AM.Init()
        if AM.InitUI then AM.InitUI() end
        AM.Print("v" .. AM.VERSION .. " loaded. /autohelp for commands.")
    end
end)
frame:SetScript("OnUpdate", function()
    AM.OnUpdate(arg1)
end)
