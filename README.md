# Beacon

Beacon is a free, lightweight addon for **World of Warcraft: Forever** that lets you @mention Discord roles and people from guild chat. It works with Blizzard's official guild Discord bridge.

## Features

- **@mentions from guild chat**: Type friendly aliases like `@raid`, `@tanks` or `@Kaerpow`. Beacon turns them into real Discord role and person mentions just before your message is sent.
- **Autocomplete**: Start typing `@` to see the matching aliases.
- **Readable chat**: Your chat window shows friendly names, and Discord gets the working mention.
- **Officer-managed guild list**: Officers keep one shared list of members and roles, and Beacon syncs it automatically to every guild member who has the addon. Nobody has to look up Discord IDs or set up aliases themselves.
- **Personal list**: Everyone can also keep their own aliases, which only they use.
- **Import and export**: Paste many aliases at once, for example straight from a spreadsheet, or export a list to back it up or copy it elsewhere.
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
kaerpow, Person, 223456789012345678
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

The list is sent in small pieces about one second apart so it doesn't flood the guild's addon channel. A full 500-entry list takes about two minutes.

### Finding Discord IDs

1. In Discord, open **User Settings → Advanced** and turn on **Developer Mode**.
2. For a person, right-click their name and choose **Copy User ID**.
3. For a role, open **Server Settings → Roles**, right-click the role and choose **Copy Role ID**.

If a role mention reaches Discord but nobody is notified, turn on **Allow anyone to @mention this role** for that role in Discord.

## Limits

- A guild message can be at most 255 characters once mentions are added. If it's longer, Beacon sends your aliases as plain text and tells you to shorten the message.
- During restricted combat content, when the game locks chat for addons, Beacon leaves your messages unchanged.
- The **Guild & Communities** window may still show raw Discord IDs, because addons can't change the text in that window.

## Credits

Inspired by the Discord bridge idea in GuildPing by kaerpow. Beacon is a separate addon written from scratch and contains no GuildPing code. The Beacon logo is original artwork made for this addon.

Beacon is not affiliated with Discord or Blizzard Entertainment.

This addon was made with the assistance of AI.
