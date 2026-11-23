# Beacon

Beacon is a free, lightweight addon for **World of Warcraft: Forever** that lets you @mention Discord roles and people from guild chat. It works with Blizzard's official guild Discord bridge.

## Features

- **@mentions from guild chat**: Type friendly aliases like `@raid`, `@tanks` or `@Kaerpow`. Beacon turns them into real Discord role and person mentions just before your message is sent.
- **Autocomplete**: Start typing `@` to see the matching aliases.
- **Readable chat**: Your chat window shows friendly names, and Discord gets the working mention.
- **Officer-managed guild list**: Officers keep one shared list of members and roles, and Beacon syncs it to every guild member who has the addon. Nobody has to look up Discord IDs or set up aliases themselves.
- **Personal list**: Everyone can also keep their own aliases, which only they use.
- **Mass import**: Paste many aliases at once, for example straight from a spreadsheet.
- **Minimap button**: One click opens your lists.
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

Click the Beacon minimap button, or type `/beacon`, to open your lists. Drag the button to move it around the minimap. Type `/beacon minimap` to hide or show it.

## Your two lists

The window has two tabs:

- **Guild**: the shared list your officers keep. Everyone else can see it but not change it.
- **Personal**: your own aliases. You can add, change and delete them, and they're never sent to anyone. If a personal alias has the same name as a guild alias, your personal one is used. Your personal list is shared by all your characters on this account.

Each list holds up to 500 entries.

To add an alias, fill in the **Alias** (what you type after `@`), a **Display name**, choose **Role** or **Person**, paste the **Discord ID**, and choose **Save**. Click an alias in the list to change or delete it.

## Mass import

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

## For officers

Officers are the **Guild Master rank and the rank directly below it**. Only they can edit and import into the guild list, and Beacon only accepts guild lists sent by them.

After editing or importing on the **Guild** tab, choose **Send to Guild** to share your changes with everyone online who has Beacon. Guild members who log in later get the newest list automatically from any officer who is online.

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
