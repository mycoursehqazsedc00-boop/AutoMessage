-- AutoMessage slash commands. The 1.0 commands keep working; the rest are newer.
--
-- Slots: AutoMessage has several independent slots, each with its own message(s), channel,
-- interval, whisper target, translation switch and limit. The settings commands edit the
-- CURRENT slot (/autoslot <n> selects it) or the slot given in front of the arguments: @2

local AM = AutoMessage

local function Register(id, commands, desc, func)
    if Satellite and Satellite.registerSlashCommand then
        Satellite.registerSlashCommand({ id = id, commands = commands, onExecute = func, helpText = desc })
    else
        SlashCmdList[id] = func
        for i = 1, table.getn(commands) do
            setglobal("SLASH_" .. id .. i, commands[i])
        end
    end
end

-- "@2 rest" -> 2, "rest";  "rest" -> current slot, "rest";  bad slot -> nil
local function SlotArg(msg)
    local text = AM.Trim(msg or "")
    local s, e, num = string.find(text, "^@(%d+)%s*")
    if s then
        local n = tonumber(num)
        if n < 1 or n > AM.MAX_SLOTS then
            AM.Print("The slot must be a number from 1 to " .. AM.MAX_SLOTS .. ".")
            return nil
        end
        return n, string.sub(text, e + 1)
    end
    return AM.current, text
end

local function Help()
    AM.Print("v" .. AM.VERSION .. " - please don't spam!")
    AM.Print("/auto - open the configuration window")
    AM.Print("/autostart, /autostop, /autotoggle - start or stop sending (all enabled slots; /autostart @2 starts only slot 2)")
    AM.Print("/automsg <text> - set the message; separate several with ;;   (/automsg list, /automsg clear)")
    AM.Print("/autochan <channel> - say, yell, guild, officer, party, raid, rw, bg, emote, w (whisper), de (emote command), rs (script), a number 1-10, or a channel NAME (joined automatically)")
    AM.Print("/autotick <seconds> - time between messages (minimum 5)")
    AM.Print("/autochar <name> - whisper target for channel w")
    AM.Print("/autotranslate [on|off] - translate messages with WoWTranslate")
    AM.Print("/autolimit <n> - stop after n messages (0 = no limit)")
    AM.Print("Several slots: /autoslot lists them, /autoslot <n> selects one, /autoslot <n> on|off enables or disables it.")
    AM.Print("Any setting command can name its slot: /automsg @2 WTS herbs   /autochan @2 World")
    AM.Print("/autobutton [show|hide|reset] - the on/off button")
    AM.Print("/autostatus - show the settings of all slots")
    AM.Print("/autodebug, /autolog [n] - trace what the addon does")
    AM.Print("Variables in messages: {zone} {subzone} {name} {level} {class}")
end

Register("AUTOMESSAGEHELP", { "/autohelp" }, "AutoMessage commands", function(msg) Help() end)

Register("AUTOMESSAGESTART", { "/autostart" }, "Start AutoMessage", function(msg)
    local n, rest = SlotArg(msg)
    if not n then return end
    if string.find(AM.Trim(msg or ""), "^@") then
        AM.SetEnabled(true, n)
        if not AM.state[n].running then AM.StartSlot(n) end
    else
        AM.Start()
    end
end)

Register("AUTOMESSAGESTOP", { "/autostop" }, "Stop AutoMessage", function(msg)
    local n, rest = SlotArg(msg)
    if not n then return end
    if string.find(AM.Trim(msg or ""), "^@") then
        AM.StopSlot(n)
    else
        AM.Stop()
    end
end)

Register("AUTOMESSAGETOGGLE", { "/autotoggle" }, "Start or stop AutoMessage", function(msg) AM.Toggle() end)

Register("AUTOMESSAGETICK", { "/autotick" }, "Seconds between messages", function(msg)
    local n, value = SlotArg(msg)
    if not n then return end
    if AM.SetInterval(value, n) then AM.Print(AM.Tag(n) .. "Interval: " .. AM.Slot(n).interval .. " seconds.") end
end)

Register("AUTOMESSAGECHAN", { "/autochan" }, "Channel to send to", function(msg)
    local n, value = SlotArg(msg)
    if not n then return end
    if AM.SetChannel(value, n) then
        local channel = AM.Slot(n).channel
        local spec = AM.ParseChannel(channel)
        if not spec then
            AM.Print(AM.Tag(n) .. "'" .. channel .. "' is not a valid channel number (1-10).")
        elseif spec.name then
            AM.Print(AM.Tag(n) .. "Channel: '" .. spec.name .. "' (joined automatically if needed).")
        else
            AM.Print(AM.Tag(n) .. "Channel: " .. channel .. ".")
        end
    else
        AM.Print("Usage: /autochan [@slot] <say|yell|guild|party|raid|bg|w|1-10|channel name>")
    end
end)

Register("AUTOMESSAGEMSG", { "/automsg" }, "Message to send", function(msg)
    local n, text = SlotArg(msg)
    if not n then return end
    local lower = string.lower(text)
    if lower == "list" then
        local list = AM.Slot(n).messages
        if table.getn(list) == 0 then
            AM.Print(AM.Tag(n) .. "No message set.")
        else
            for i = 1, table.getn(list) do AM.Print(AM.Tag(n) .. i .. ". " .. list[i]) end
        end
    elseif lower == "clear" then
        AM.SetMessages("", n)
        AM.Print(AM.Tag(n) .. "Messages cleared.")
    elseif text == "" then
        AM.Print("Usage: /automsg [@slot] <text>  (separate several messages with ;;)")
    else
        local count = AM.SetMessages(text, n)
        AM.Print(AM.Tag(n) .. count .. " message(s) saved.")
    end
end)

Register("AUTOMESSAGECHAR", { "/autochar" }, "Whisper target", function(msg)
    local n, value = SlotArg(msg)
    if not n then return end
    AM.SetWhisperTarget(value, n)
    AM.Print(AM.Tag(n) .. "Whisper target: " .. AM.Slot(n).whisperTarget)
end)

Register("AUTOMESSAGETRANSLATE", { "/autotranslate" }, "Translate with WoWTranslate", function(msg)
    local n, value = SlotArg(msg)
    if not n then return end
    local a = string.lower(value)
    local want
    if a == "on" or a == "1" then want = true
    elseif a == "off" or a == "0" then want = false
    else want = not AM.Slot(n).translate end
    local result = AM.SetTranslate(want, n)
    AM.Print(AM.Tag(n) .. "Translation with WoWTranslate: " .. (result and "ON" or "OFF") .. ".")
end)

Register("AUTOMESSAGELIMIT", { "/autolimit" }, "Stop after n messages", function(msg)
    local n, value = SlotArg(msg)
    if not n then return end
    if AM.SetLimit(value, n) then
        local limit = AM.Slot(n).limit
        AM.Print(AM.Tag(n) .. (limit == 0 and "No limit." or ("Stops after " .. limit .. " messages.")))
    end
end)

Register("AUTOMESSAGESLOT", { "/autoslot" }, "Select, enable or disable a slot", function(msg)
    local text = AM.Trim(msg or "")
    local s, e, num, rest = string.find(text, "^@?(%d+)%s*(.*)$")
    if not s then
        for n = 1, AM.MAX_SLOTS do
            AM.Print((n == AM.current and "> " or "  ") .. "Slot " .. n .. ": " .. AM.StatusLine(n))
        end
        return
    end
    local n = tonumber(num)
    if n < 1 or n > AM.MAX_SLOTS then
        AM.Print("The slot must be a number from 1 to " .. AM.MAX_SLOTS .. ".")
        return
    end
    rest = string.lower(rest or "")
    if rest == "on" then
        AM.SetEnabled(true, n)
        AM.Print("Slot " .. n .. " enabled.")
    elseif rest == "off" then
        AM.SetEnabled(false, n)
        AM.Print("Slot " .. n .. " disabled.")
    end
    AM.SelectSlot(n)
    AM.Print("Editing slot " .. n .. ": " .. AM.StatusLine(n))
end)

Register("AUTOMESSAGEBUTTON", { "/autobutton" }, "On/off button", function(msg)
    local a = string.lower(AM.Trim(msg or ""))
    if a == "hide" then
        AM.ShowButton(false)
    elseif a == "reset" then
        AM.ResetButton()
        AM.Print("Button moved back to the default position.")
    else
        AM.ShowButton(true)
    end
end)

Register("AUTOMESSAGESTATUS", { "/autostatus" }, "Show settings", function(msg)
    for n = 1, AM.MAX_SLOTS do
        local s = AM.Slot(n)
        if s.enabled or AM.state[n].running or n == 1 then
            AM.Print("Slot " .. n .. ": " .. AM.StatusLine(n))
            if s.whisperTarget ~= "" then AM.Print("  whisper target: " .. s.whisperTarget) end
        end
    end
    AM.Print("WoWTranslate: " .. (AM.HasWoWTranslate() and "found" or "not found"))
end)

Register("AUTOMESSAGEDEBUG", { "/autodebug" }, "Toggle tracing", function(msg)
    AutoMessageDB.debug = not AutoMessageDB.debug
    AM.Print("Tracing " .. (AutoMessageDB.debug and "ON (see /autolog)." or "OFF."))
end)

Register("AUTOMESSAGELOG", { "/autolog" }, "Show the trace", function(msg)
    local n = tonumber(msg) or 20
    local total = table.getn(AM.log)
    if total == 0 then
        AM.Print("The trace is empty. Turn it on with /autodebug.")
        return
    end
    local from = total - n + 1
    if from < 1 then from = 1 end
    for i = from, total do DEFAULT_CHAT_FRAME:AddMessage("  " .. AM.log[i]) end
end)

Register("AUTOMESSAGECONFIG", { "/auto" }, "Open the configuration window", function(msg)
    if AM.ShowConfig then AM.ShowConfig() end
end)
