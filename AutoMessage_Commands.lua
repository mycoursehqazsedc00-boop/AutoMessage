-- AutoMessage slash commands. The 1.0 commands keep working; the rest are new in 2.0.

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

local function Help()
    AM.Print("v" .. AM.VERSION .. " - please don't spam!")
    AM.Print("/auto - open the configuration window")
    AM.Print("/autostart, /autostop, /autotoggle - start or stop sending")
    AM.Print("/automsg <text> - set the message; separate several with ;;   (/automsg list, /automsg clear)")
    AM.Print("/autochan <channel> - say, yell, guild, officer, party, raid, rw, bg, emote, w (whisper), de (emote command), rs (script), a number 1-10, or a channel NAME (joined automatically)")
    AM.Print("/autotick <seconds> - time between messages (minimum 5)")
    AM.Print("/autochar <name> - whisper target for channel w")
    AM.Print("/autotranslate [on|off] - translate messages with WoWTranslate")
    AM.Print("/autobutton [show|hide|reset] - the on/off button")
    AM.Print("/autolimit <n> - stop after n messages (0 = no limit)")
    AM.Print("/autostatus - show the current settings")
    AM.Print("/autodebug, /autolog [n] - trace what the addon does")
    AM.Print("Variables in messages: {zone} {subzone} {name} {level} {class}")
end

Register("AUTOMESSAGEHELP", { "/autohelp" }, "AutoMessage commands", function(msg) Help() end)

Register("AUTOMESSAGESTART", { "/autostart" }, "Start AutoMessage", function(msg) AM.Start() end)
Register("AUTOMESSAGESTOP", { "/autostop" }, "Stop AutoMessage", function(msg) AM.Stop() end)
Register("AUTOMESSAGETOGGLE", { "/autotoggle" }, "Start or stop AutoMessage", function(msg) AM.Toggle() end)

Register("AUTOMESSAGETICK", { "/autotick" }, "Seconds between messages", function(msg)
    if AM.SetInterval(msg) then AM.Print("Interval: " .. AutoMessageDB.interval .. " seconds.") end
end)

Register("AUTOMESSAGECHAN", { "/autochan" }, "Channel to send to", function(msg)
    if AM.SetChannel(msg) then
        local spec = AM.ParseChannel(AutoMessageDB.channel)
        if not spec then
            AM.Print("'" .. AutoMessageDB.channel .. "' is not a valid channel number (1-10).")
        elseif spec.name then
            AM.Print("Channel: '" .. spec.name .. "' (joined automatically if needed).")
        else
            AM.Print("Channel: " .. AutoMessageDB.channel .. ".")
        end
    else
        AM.Print("Usage: /autochan <say|yell|guild|party|raid|bg|w|1-10|channel name>")
    end
end)

Register("AUTOMESSAGEMSG", { "/automsg" }, "Message to send", function(msg)
    local text = AM.Trim(msg or "")
    local lower = string.lower(text)
    if lower == "list" then
        local list = AutoMessageDB.messages
        if table.getn(list) == 0 then
            AM.Print("No message set.")
        else
            for i = 1, table.getn(list) do AM.Print(i .. ". " .. list[i]) end
        end
    elseif lower == "clear" then
        AM.SetMessages("")
        AM.Print("Messages cleared.")
    elseif text == "" then
        AM.Print("Usage: /automsg <text>  (separate several messages with ;;)")
    else
        local n = AM.SetMessages(text)
        AM.Print(n .. " message(s) saved.")
    end
end)

Register("AUTOMESSAGECHAR", { "/autochar" }, "Whisper target", function(msg)
    AM.SetWhisperTarget(msg)
    AM.Print("Whisper target: " .. AutoMessageDB.whisperTarget)
end)

Register("AUTOMESSAGETRANSLATE", { "/autotranslate" }, "Translate with WoWTranslate", function(msg)
    local a = string.lower(AM.Trim(msg or ""))
    local want
    if a == "on" or a == "1" then want = true
    elseif a == "off" or a == "0" then want = false
    else want = not AutoMessageDB.translate end
    local result = AM.SetTranslate(want)
    AM.Print("Translation with WoWTranslate: " .. (result and "ON" or "OFF") .. ".")
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

Register("AUTOMESSAGELIMIT", { "/autolimit" }, "Stop after n messages", function(msg)
    if AM.SetLimit(msg) then
        local n = AutoMessageDB.limit
        AM.Print(n == 0 and "No limit." or ("Stops after " .. n .. " messages."))
    end
end)

Register("AUTOMESSAGESTATUS", { "/autostatus" }, "Show settings", function(msg)
    AM.Print(AM.StatusLine())
    if AutoMessageDB.whisperTarget ~= "" then AM.Print("Whisper target: " .. AutoMessageDB.whisperTarget) end
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
