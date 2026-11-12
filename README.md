# AutoMessage

<p align="center">
  <strong>Repeating chat messages for World of Warcraft 1.12</strong><br>
  Channel by name with auto-join, optional WoWTranslate translation, a movable on/off button
</p>

<p align="center">
  <img src="https://img.shields.io/badge/WoW-1.12-blue" alt="WoW 1.12">
  <img src="https://img.shields.io/badge/version-2.0-green" alt="Version 2.0">
</p>

A fork of **AutoMessager V1.0** by The BOFH (Stewarta of Nordrassil). The original slash commands keep working. Please don't spam.

---

## Client mods and dependencies

| Component | Role | Notes |
|---|---|---|
| Client mods (DLLs) | **Not used** | AutoMessage calls no client-mod function. |
| [WoWTranslate](https://github.com/sanjaygbhat/wow-translate) 2.2 or newer | **Optional** | Needed only for the translation switch. It provides `WoWTranslate_PrepareOutgoing` and `WoWTranslate_SendRaw`, and it needs its own `WoWTranslate.dll`. Without it AutoMessage works as a plain auto-messager and the switch is disabled. |

---

## Features

| Feature | Description |
|---------|-------------|
| 🌐 **Translation switch** | One on/off switch decides whether WoWTranslate translates your auto-messages. ON: each distinct message is translated once and the result is re-sent from memory, so repeats cost no translation request and cause no "Translating..." chat lines. OFF: messages are sent exactly as typed, even if WoWTranslate is translating your normal chat. |
| 🔘 **Movable on/off button** | A small button (`OFF` / `ON`) starts and stops the messager. Drag it anywhere; its position is saved. Right-click opens the settings, Ctrl-click switches translation, and the tooltip shows the status. |
| 📡 **Channel by name, with auto-join** | Besides a channel number you can type a name such as `World`. If you have not joined it yet, AutoMessage joins it, waits for the server and then sends. A name matches case-insensitively, exactly or as a prefix (`trade` finds `Trade - City`). If the channel cannot be joined within 10 seconds the messager stops and says why. |
| 🔁 **Message rotation** | Several messages separated by `;;` are sent in turn. |
| 🧩 **Variables** | `{zone}` `{subzone}` `{name}` `{level}` `{class}` are filled in at send time. |
| 🛑 **Send limit** | Stop automatically after N messages. |
| ✅ **Target checks** | Party, raid, guild and whisper messages are skipped, with one note, while you are not in a party, raid or guild or have no whisper target. |
| 🛡️ **Safe interval** | At least 5 seconds between messages. |
| 🔎 **Tracing** | `/autodebug` records what the addon does; `/autolog` shows it. |
| ⚙️ **Settings window** | `/auto` opens a window for message, channel, interval, whisper target and the translation switch. |

---

## Usage

### Commands

| Command | Description |
|---------|-------------|
| `/auto` | Open the settings window |
| `/autohelp` | List the commands |
| `/autostart`, `/autostop`, `/autotoggle` | Start or stop sending |
| `/automsg <text>` | Set the message. Separate several messages with `;;`. `/automsg list` shows them, `/automsg clear` removes them |
| `/autochan <channel>` | `say`, `yell`, `guild`, `officer`, `party`, `raid`, `rw`, `bg`, `emote`, `w`, a number `1`-`10`, or a channel name |
| `/autotick <seconds>` | Time between messages (minimum 5) |
| `/autochar <name>` | Whisper target for channel `w` |
| `/autotranslate [on\|off]` | Translate messages with WoWTranslate (no argument toggles) |
| `/autobutton [show\|hide\|reset]` | Show, hide or reset the on/off button |
| `/autolimit <n>` | Stop after `n` messages (`0` = no limit) |
| `/autostatus` | Show the current settings |
| `/autodebug`, `/autolog [n]` | Switch tracing on or off, show the last `n` trace lines |

The short codes of version 1.0 still work: `s y g p r o e rw bg w`, `1`-`10`, `de` (run an emote command such as `DANCE`) and `rs` (run a script).

### Examples

```
/automsg LFM {zone} run, need healer ;; WTS cheap herbs, whisper me
/autochan World
/autotick 120
/autotranslate on
/autostart
```

### Translation

With the switch ON, the text is prepared by WoWTranslate exactly as for a normal outgoing message (item links stay clickable, outgoing glossary, prefix, 255 byte limit) but it does not depend on WoWTranslate's own outgoing channel settings. A message that already contains the target language is sent unchanged. If the translation fails, the original text is sent once and translation is paused for five minutes; if WoWTranslate does not answer within 30 seconds the original is sent. The stored translation is dropped when the message text, its variables, or WoWTranslate's target language or prefix change.

### Notes

- Auto-joined channels are not added to a chat frame, so you will not see replies in them until you add the channel to a window.
- Zone channels such as `General` or `Trade` cannot be joined by name; if you are not in one, AutoMessage reports that it could not join.
- AutoMessage never starts by itself after login.

---

## What changed compared to the original

| Area | Original (1.0) | This fork (2.0) |
|------|----------------|-----------------|
| Channel | Number `1`-`10` or a fixed set of letters; the default value `say` was not understood | Alias, word, number or channel **name**, with auto-join |
| Yell | Broken (`SendChatMessage(am == "YELL")` sent no chat type) | Works |
| Translation | None; WoWTranslate would translate each send through its hook, with a "Translating..." line every time | On/off switch; translated once, then re-sent from memory |
| Messages | One | Rotation with `;;` |
| Variables | None | `{zone}` `{subzone}` `{name}` `{level}` `{class}` |
| On/off | Slash commands and the window | Plus a movable button with tooltip |
| Interval | Stored as typed text, no checks | Number, minimum 5 seconds |
| Group/guild targets | Sent anyway, producing a game error | Skipped with one note |
| Limit | None | `/autolimit` |
| Tracing | None | `/autodebug`, `/autolog` |
| Code | Globals such as `timerproc`, `initproc`, `am`, `channame` | One `AutoMessage` table; the four old variables are imported once, then cleared |
| Settings window | Fixed XML window with four edit boxes | Built in Lua; adds the translation switch, Start/Stop, Apply and a status line |

Saved variables: `AutoMessageDB`. The four 1.0 variables (`am`, `ticktime`, `channame`, `charname`) are read once to carry your settings over.

---

## Testing

The `qa/` folder holds a regression suite that loads the real addon files into a small WoW 1.12 mock and runs them on a standard Lua interpreter (developed with Lua 5.4):

```
sh qa/run_automessage.sh AutoMessage [path/to/WoWTranslate] [path/to/original/AutoMessage] [lua]
```

With the WoWTranslate folder the translation suite runs against the real addon and a fake DLL. With the original AutoMessage folder the A/B suite compares both versions on the same inputs. `qa/REPORT.md` records the latest run. The mock does not replace testing inside the game client.

---

## Credits

- Original AutoMessager V1.0: The BOFH (Stewarta of Nordrassil).
- Translation: [WoWTranslate](https://github.com/sanjaygbhat/wow-translate).

## License

The original addon states no license. Keep the original credit and add a `LICENSE` file if the upstream repository has one.
