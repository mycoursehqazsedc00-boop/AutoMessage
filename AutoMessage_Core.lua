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
AM.VERSION = "2.0"

local MIN_INTERVAL      = 5     -- seconds; lower values only get you muted
local MAX_LENGTH        = 255   -- bytes, the chat limit
local JOIN_TIMEOUT      = 10    -- seconds to wait for a channel join
local TRANSLATE_TIMEOUT = 30    -- seconds to wait for WoWTranslate
local TRANSLATE_RETRY   = 300   -- seconds to send untranslated after a translation failure
local CACHE_MAX         = 20
local LOG_MAX           = 100
local FAR               = 86400

AM.running = false
AM.gen = 0              -- bumped on start/stop so late callbacks can be ignored
AM.index = 1
AM.sent = 0
AM.nextTick = 0
AM.waiting = false
AM.waitDeadline = 0
AM.join = nil
AM.warned = nil
AM.trCache = {}
AM.trCount = 0
AM.trFailUntil = 0
AM.log = {}

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

local DEFAULTS = {
    messages = {},
    interval = 30,
    channel = "say",
    whisperTarget = "",
    translate = false,
    limit = 0,
    debug = false,
    button = { shown = true, x = 400, y = 300 },
}

-- ---------------------------------------------------------------------------
-- saved variables
-- ---------------------------------------------------------------------------
function AM.Init()
    if type(AutoMessageDB) ~= "table" then AutoMessageDB = {} end
    local db = AutoMessageDB
    CopyDefaults(db, DEFAULTS)

    -- Settings of AutoMessager 1.0 lived in four globals; take them over once.
    if not db.migrated then
        if type(am) == "string" and am ~= "" and am ~= "Message goes here" then
            db.messages = { am }
        end
        if tonumber(ticktime) then db.interval = tonumber(ticktime) end
        if type(channame) == "string" and channame ~= "" then db.channel = channame end
        if type(charname) == "string" and charname ~= "" and charname ~= "Trump" then
            db.whisperTarget = charname
        end
        db.migrated = true
    end
    am, ticktime, channame, charname = nil, nil, nil, nil

    if db.interval < MIN_INTERVAL then db.interval = MIN_INTERVAL end
    Trace("init", "messages", table.getn(db.messages))
end

-- ---------------------------------------------------------------------------
-- settings
-- ---------------------------------------------------------------------------
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

function AM.SetMessages(text)
    local list = AM.SplitMessages(text)
    local kept = {}
    for i = 1, table.getn(list) do
        if string.len(list[i]) > MAX_LENGTH then
            AM.Print("Message " .. i .. " is longer than " .. MAX_LENGTH .. " characters and was not saved.")
        else
            table.insert(kept, list[i])
        end
    end
    AutoMessageDB.messages = kept
    AM.index = 1
    Trace("messages set", table.getn(kept))
    if AM.RefreshUI then AM.RefreshUI() end
    return table.getn(kept)
end

function AM.GetMessagesText()
    return table.concat(AutoMessageDB.messages, " ;; ")
end

function AM.SetInterval(value)
    local n = tonumber(value)
    if not n then
        AM.Print("The interval must be a number of seconds.")
        return false
    end
    if n < MIN_INTERVAL then
        AM.Print("Intervals under " .. MIN_INTERVAL .. " seconds are not allowed; using " .. MIN_INTERVAL .. ".")
        n = MIN_INTERVAL
    end
    AutoMessageDB.interval = n
    Trace("interval", n)
    if AM.RefreshUI then AM.RefreshUI() end
    return true
end

function AM.SetChannel(value)
    local text = Trim(value or "")
    if text == "" then return false end
    AutoMessageDB.channel = text
    AM.join = nil
    Trace("channel", text)
    if AM.RefreshUI then AM.RefreshUI() end
    return true
end

function AM.SetWhisperTarget(value)
    AutoMessageDB.whisperTarget = Trim(value or "")
    if AM.RefreshUI then AM.RefreshUI() end
end

function AM.HasWoWTranslate()
    return WoWTranslate_PrepareOutgoing ~= nil
end

function AM.SetTranslate(on)
    if on and not AM.HasWoWTranslate() then
        AM.Print("WoWTranslate 2.2 or newer is needed for translation (not found).")
        AutoMessageDB.translate = false
    else
        AutoMessageDB.translate = on and true or false
        Trace("translate", AutoMessageDB.translate)
    end
    AM.trFailUntil = 0
    if AM.RefreshUI then AM.RefreshUI() end
    return AutoMessageDB.translate
end

function AM.SetLimit(value)
    local n = tonumber(value)
    if not n or n < 0 then
        AM.Print("The limit must be a number (0 = no limit).")
        return false
    end
    AutoMessageDB.limit = math.floor(n)
    if AM.RefreshUI then AM.RefreshUI() end
    return true
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

-- Can this kind of message be sent right now?
function AM.TargetAvailable(spec)
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
        if Trim(AutoMessageDB.whisperTarget or "") ~= "" then return true end
        return false, "no whisper target set (/autochar <name>)"
    end
    return true
end

-- Returns dest (table) or nil, state ("joining" | "failed" | "unavailable"), reason
function AM.ResolveDestination(spec)
    local k = spec.kind
    if k == "DOEMOTE" or k == "RUNSCRIPT" then return { kind = k } end
    if k == "CHANNEL" then
        local id = AM.FindChannel(spec)
        if id then
            AM.join = nil
            return { kind = "CHANNEL", channel = id }
        end
        if spec.name then
            local now = GetTime()
            if not AM.join or AM.join.name ~= spec.name then
                Trace("joining channel", spec.name)
                AM.Print("Joining channel '" .. spec.name .. "'...")
                JoinChannelByName(spec.name)
                AM.join = { name = spec.name, since = now }
                return nil, "joining"
            end
            if now - AM.join.since > JOIN_TIMEOUT then
                AM.join = nil
                return nil, "failed"
            end
            return nil, "joining"
        end
        return nil, "unavailable", "channel " .. spec.id .. " is not joined"
    end
    local ok, why = AM.TargetAvailable(spec)
    if not ok then return nil, "unavailable", why end
    if k == "WHISPER" then
        return { kind = "WHISPER", channel = Trim(AutoMessageDB.whisperTarget) }
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

local function WantTranslate(spec)
    if not AutoMessageDB.translate then return false end
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

local function ScheduleNext()
    AM.nextTick = GetTime() + AutoMessageDB.interval
end

-- Final step: send, count, schedule the next one.
local function Deliver(final, spec, gen)
    if not AM.running or gen ~= AM.gen then
        Trace("late result dropped")
        return
    end
    AM.waiting = false
    local dest, state, why = AM.ResolveDestination(spec)
    if not dest then
        if state == "failed" then
            AM.Stop("could not join channel '" .. tostring(spec.name) .. "'")
        else
            Trace("not sent:", state, why)
            ScheduleNext()
        end
        return
    end
    if string.len(final) > MAX_LENGTH then
        if AM.warned ~= "long" then
            AM.Print("A message is longer than " .. MAX_LENGTH .. " characters after expansion or translation; skipped.")
            AM.warned = "long"
        end
        AM.index = AM.index + 1
        ScheduleNext()
        return
    end
    AM.SendNow(final, dest)
    AM.sent = AM.sent + 1
    AM.index = AM.index + 1
    AM.warned = nil
    local limit = AutoMessageDB.limit or 0
    if limit > 0 and AM.sent >= limit then
        AM.Stop("limit of " .. limit .. " messages reached")
        return
    end
    ScheduleNext()
    if AM.RefreshUI then AM.RefreshUI() end
end

function AM.Step()
    local db = AutoMessageDB
    local now = GetTime()
    local count = table.getn(db.messages)
    if count == 0 then AM.Stop("no message set"); return end
    local spec = AM.ParseChannel(db.channel)
    if not spec then AM.Stop("channel '" .. tostring(db.channel) .. "' is not valid"); return end

    local dest, state, why = AM.ResolveDestination(spec)
    if not dest then
        if state == "joining" then
            AM.nextTick = now + 0.5
        elseif state == "failed" then
            AM.Stop("could not join channel '" .. tostring(spec.name) .. "'")
        else
            if AM.warned ~= why then
                AM.Print("Not sending: " .. tostring(why) .. ".")
                AM.warned = why
            end
            Trace("waiting:", why)
            ScheduleNext()
        end
        return
    end
    AM.warned = nil

    if AM.index > count then AM.index = 1 end
    local text = AM.Expand(db.messages[AM.index])
    if text == "" then
        AM.index = AM.index + 1
        ScheduleNext()
        return
    end

    if not WantTranslate(spec) then
        Deliver(text, spec, AM.gen)
        return
    end

    local key = TranslateSignature() .. "\1" .. text
    local cached = AM.trCache[key]
    if cached then
        Trace("translation from memory")
        Deliver(cached, spec, AM.gen)
        return
    end
    if now < AM.trFailUntil then
        Trace("translation paused, sending original")
        Deliver(text, spec, AM.gen)
        return
    end

    -- Ask WoWTranslate once; the result is reused for every later repeat.
    AM.waiting = true
    AM.waitDeadline = now + TRANSLATE_TIMEOUT
    AM.nextTick = FAR
    local gen = AM.gen
    Trace("translating", string.sub(text, 1, 30))
    WoWTranslate_PrepareOutgoing(text, function(translated, err)
        if gen ~= AM.gen then return end
        if translated then
            CacheTranslation(key, translated)
            Deliver(translated, spec, gen)
        else
            AM.Print("Translation failed (" .. tostring(err) .. "); sending the original text.")
            AM.trFailUntil = GetTime() + TRANSLATE_RETRY
            Deliver(text, spec, gen)
        end
    end)
end

function AM.OnUpdate(elapsed)
    if not AM.running then return end
    local now = GetTime()
    if AM.waiting then
        if now > AM.waitDeadline then
            -- WoWTranslate never answered: send the original and ignore a late answer.
            AM.gen = AM.gen + 1
            AM.waiting = false
            AM.trFailUntil = now + TRANSLATE_RETRY
            AM.Print("Translation timed out; sending the original text.")
            local db = AutoMessageDB
            local spec = AM.ParseChannel(db.channel)
            local text = AM.Expand(db.messages[AM.index] or "")
            if spec and text ~= "" then Deliver(text, spec, AM.gen) else ScheduleNext() end
        end
        return
    end
    if now >= AM.nextTick then AM.Step() end
end

-- ---------------------------------------------------------------------------
-- start / stop
-- ---------------------------------------------------------------------------
function AM.Start()
    local db = AutoMessageDB
    if table.getn(db.messages) == 0 then
        AM.Print("Set a message first: /automsg <text>")
        return false
    end
    if not AM.ParseChannel(db.channel) then
        AM.Print("Set a valid channel first: /autochan <say|yell|guild|party|raid|bg|w|1-10|name>")
        return false
    end
    AM.running = true
    AM.gen = AM.gen + 1
    AM.waiting = false
    AM.sent = 0
    AM.index = 1
    AM.warned = nil
    AM.join = nil
    AM.nextTick = GetTime()
    Trace("start")
    AM.Print("Started: every " .. db.interval .. "s to " .. db.channel .. ".")
    if AM.RefreshUI then AM.RefreshUI() end
    return true
end

function AM.Stop(reason)
    local was = AM.running
    AM.running = false
    AM.gen = AM.gen + 1
    AM.waiting = false
    AM.join = nil
    Trace("stop", reason)
    if was then
        AM.Print("Stopped" .. (reason and (": " .. reason) or ".") .. (reason and "." or ""))
    end
    if AM.RefreshUI then AM.RefreshUI() end
end

function AM.Toggle()
    if AM.running then AM.Stop() else AM.Start() end
end

function AM.StatusLine()
    local db = AutoMessageDB
    local parts = {}
    table.insert(parts, AM.running and "RUNNING" or "stopped")
    table.insert(parts, "channel " .. tostring(db.channel))
    table.insert(parts, "every " .. db.interval .. "s")
    table.insert(parts, table.getn(db.messages) .. " message(s)")
    local tr = "translate off"
    if db.translate then tr = AM.HasWoWTranslate() and "translate ON" or "translate ON (WoWTranslate missing)" end
    table.insert(parts, tr)
    if AM.running then
        table.insert(parts, "sent " .. AM.sent .. ((db.limit or 0) > 0 and ("/" .. db.limit) or ""))
        if not AM.waiting then
            local left = AM.nextTick - GetTime()
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
