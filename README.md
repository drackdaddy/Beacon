# Beacon

Beacon is a free, lightweight addon for **World of Warcraft: Forever** that lets you @mention Discord roles and people from guild chat. It works with Blizzard's official guild Discord bridge.

## Features

- **@mentions from guild chat**: Type friendly aliases like `@raid`, `@tanks` or `@Elara`. Beacon turns them into real Discord role and person mentions just before your message is sent.
- **Autocomplete**: Start typing `@` to see the matching aliases.
- **Readable chat**: Your chat window shows friendly names, and Discord gets the working mention.
- **Officer-managed guild list**: Officers keep one shared list of members and roles, and Beacon syncs it automatically to every guild member who has the addon. Nobody has to look up Discord IDs or set up aliases themselves.
- **Personal list**: Everyone can also keep their own aliases, which only they use.
- **Import and export**: Paste many aliases at once, for example straight from a spreadsheet, or export a list to back it up or copy it elsewhere.
- **Discord companion tool**: Fill your lists straight from your Discord server's members and roles, and keep them in step as people join and leave.
- **In the game's Options**: Your lists live under Options → AddOns → Beacon, and the minimap button opens them in one click.
- **Lightweight**: Beacon only changes text when you send a guild-chat message. It never posts on its own.

## Install

Put this repository's files in a folder named `Beacon` inside your Forever client's `Interface/AddOns` folder, so the path is `Interface/AddOns/Beacon/Beacon.toc`. Then log in or type `/reload`.

If you download the repository as a ZIP from GitHub, the folder inside is named `Beacon-main`. Rename it to `Beacon`, or the game won't load the addon.

Your guild's Discord connection must already be set up: each player turns on Discord in the game's Social options, and a guild leader or officer links the guild's Discord channel in the guild settings.

## Using Beacon

In **Guild** or **Guild Discord** chat, type `@` and pick an alias:

- **Tab** inserts the highlighted alias, and **Shift+Tab** moves the highlight.
- **Click** an alias to insert it.
- **Enter** sends your message with the highlighted alias filled in.

Your chat window shows `@Raid Team`, while Discord receives the real role or person mention.

`@everyone` and `@here` are always blocked. Beacon sends them as plain words so nobody pings the whole server by accident.

Beacon's lists live in the game's **Options → AddOns → Beacon**. Click the Beacon minimap button, or type `/beacon`, to open them there directly. Drag the minimap button to move it around the minimap. Type `/beacon minimap` to hide or show it. If you're in combat, Options opens as soon as combat ends.

## Your two lists

Use the **Personal** and **Guild** buttons at the top of Beacon's page to switch lists. It opens on **Personal**:

- **Personal**: your own aliases. You can add, change and delete them, and they're never sent to anyone. If a personal alias has the same name as a guild alias, your personal one is used. Your personal list is shared by all your characters on this account.
- **Guild**: the shared list your officers keep. Everyone else can see it but not change it.

Each list holds up to 500 entries. Type in the **Search** box above a list to show only aliases or display names that contain what you typed. Under the search box, use the **All**, **Roles** and **People** buttons to list everything, only role mentions or only person mentions. The filter and the search work together, and switching lists resets both.

To add an alias, fill in the **Alias** (what you type after `@`), a **Display name**, choose **Role** or **Person**, paste the **Discord ID**, and choose **Save**. Click an alias in the list to change or delete it.

## Import and export

Choose **Import...** on a list you can edit, paste your aliases, one per line, and choose **Import**:

```
alias, Role or Person, Discord ID, display name
raid, Role, 123456789012345678, Raid Team
elara, Person, 223456789012345678
```

- The display name is optional. Without one, the alias is used.
- Columns copied from a spreadsheet (separated by tabs) work too.
- A leading `@` on the alias is fine, and lines starting with `#` are ignored.
- Aliases already in the list are updated, and new ones are added.
- Lines that can't be read are skipped, and their line numbers are shown in chat.

Choose **Export...** on either list to get the list as text in the same format, already selected. Press **Ctrl+C** to copy it. You can keep it as a backup, share it, or paste it into **Import** on another list or character, for example to copy the guild list into your personal list.

## For officers

Officers are the **Guild Master rank and the rank directly below it**. Only they can edit and import into the guild list, and Beacon only accepts guild lists sent by them.

Sharing is automatic. There's no button to press:

- **When an officer edits or imports**, the guild list goes out to everyone online with Beacon about 10 seconds after the last change. Several quick edits are sent together.
- **When anyone logs in** with an older copy, an officer who is online sends them the newest list.
- **When an officer logs in** with a newer copy than the guildmates who are online, it's sent to them.
- **Updates, renames and deletions** all arrive, because every update carries the whole list and replaces the old copy.

Only lists from officers are accepted, so members can't change the guild list. That means an officer who logs in with an old copy, while only members are online, can't get the newer list until another officer is online. Beacon warns that officer, in chat and in red on the **Guild** list, not to edit until then. Otherwise their older list would replace the newer one.

If two officers change the list at almost the same moment, the later change wins.

### Officers' log

Officers see a **Log** button next to **Personal** and **Guild**. It shows when the guild list was last synced, then a history, newest first, of:

- your own edits and imports
- each time you shared the list, or sent it to a guildmate who logged in with an older copy
- each list you received, who sent it, and exactly what changed (aliases added, changed or removed)

Hover over a line to see all of it. The log keeps the last 200 events for each guild and is only recorded and shown while you're an officer.

The list is sent in small pieces about one second apart so it doesn't flood the guild's addon channel. A full 500-entry list takes about two minutes.

### Finding Discord IDs

1. In Discord, open **User Settings → Advanced** and turn on **Developer Mode**.
2. For a person, right-click their name and choose **Copy User ID**.
3. For a role, open **Server Settings → Roles**, right-click the role and choose **Copy Role ID**.

If a role mention reaches Discord but nobody is notified, turn on **Allow anyone to @mention this role** for that role in Discord.

## Discord companion tool

The `Companion` folder has a small Windows tool that reads your Discord server's members and roles with your own Discord bot and turns them into Beacon aliases. The addon itself can't connect to Discord, so this runs outside the game.

When you import its export into a list, Beacon matches everyone by Discord ID:

- **New people and roles** are added. If an alias is already taken, a number is added, for example `@dark2`.
- **Nickname changes** update the display name. Everyone keeps the `@alias` they already use.
- **People who left the server, or roles that were deleted,** are removed from that list.

### Set up the bot (one time)

1. Go to <https://discord.com/developers/applications>, choose **New Application**, name it (for example `Beacon Export`) and choose **Create**.
2. Open **Bot**, choose **Reset Token** and copy the token. Treat it like a password.
3. On the same page, under **Privileged Gateway Intents**, turn on **Server Members Intent** and save.
4. Open **OAuth2 → URL Generator**, tick **bot**, then under **Bot Permissions** tick **View Channels** and **Send Messages**. Also tick **Send Messages in Threads** if you'll post to a forum post or thread. Open the generated link and add the bot to your server.

If you'll post to a private channel, also allow the bot **View Channel** and **Send Messages** there.

### Run it

Double-click `Companion\BeaconDiscordExport.bat`. The first time, it installs Python and the parts it needs if they're missing, then asks:

1. **Your bot token.** It's stored in Windows Credential Manager, never in a file.
2. **Where the export should go:**
   - **Straight into Beacon in game.** It writes `DiscordExportData.lua` into the Beacon folder. In game, type `/reload` and choose **Personal**, or **Guild** if you're an officer. The game can stay open.
   - **Post in a Discord channel**, as code blocks. Paste them into **Import...** in Beacon. For a big server, paste **all the parts together** so Beacon can also remove people who left.
   - **Both.**
3. **The channel link**, if you post to a channel. Right-click the channel and choose **Copy Link**.
4. **Whether to include Discord roles**, for aliases like `@raidteam`.

Later runs reuse your answers. Press **Enter** to export, or type **C** to change them. `/beacon discord` shows the import prompt again in game.

The first time you add this version of Beacon, restart the game once, so it loads the new files. After that, `/reload` is enough.

### How names become aliases

Names are cleaned up so they can be typed in game: accents and fancy letters become plain letters, and emoji and symbols are dropped. The alias is the cleaned name in lower case without spaces, for example **Dark Knight** becomes `@darkknight`. Names with no usable letters are skipped and listed when the tool finishes.

### Troubleshooting

| Message | Fix |
|---|---|
| `Discord rejected the bot token` | Reset the token in the Developer Portal and run the tool again to paste the new one. |
| `turn on 'Server Members Intent'` | Do step 3 of the bot setup. |
| `the bot can't see that server` | Add the bot to your server, or copy the channel link again. |
| `channel not found` / `can't see that channel` / `isn't allowed to post` | Copy the link again, or give the bot **View Channel** and **Send Messages** in that channel. |
| `Python was installed but could not be found` | Close the window and run the tool again. |

The export holds everyone's display name and Discord ID, so post it only where your members or officers can see it.

## Limits

- A guild message can be at most 255 characters once mentions are added. If it's longer, Beacon sends your aliases as plain text and tells you to shorten the message.
- During restricted combat content, when the game locks chat for addons, Beacon leaves your messages unchanged.
- The **Guild & Communities** window may still show raw Discord IDs, because addons can't change the text in that window.

## Credits

Beacon is written from scratch. The Beacon logo is original artwork made for this addon.

Beacon is not affiliated with Discord or Blizzard Entertainment.

This addon was made with the assistance of AI.
