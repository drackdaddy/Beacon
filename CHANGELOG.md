# Changelog

## 1.0.0 - First release

Beacon lets you @mention Discord roles and people from World of Warcraft: Forever guild chat, through Blizzard's official guild Discord bridge.

### Mentions

- Type aliases like `@raid`, `@tanks` or `@Elara` in **Guild** or **Guild Discord** chat. Beacon turns them into real Discord role and person mentions just before the message is sent.
- Your chat window shows friendly names such as `@Raid Team`, while Discord receives the working mention.
- **Autocomplete:** typing `@` shows matching aliases above the chat box. **Tab** inserts one, **Shift+Tab** moves the highlight, **Click** picks one, and **Enter** sends with the highlighted alias filled in.
- `@everyone` and `@here` are always blocked, so nobody pings the whole server by accident.
- Beacon only changes text you're already sending in guild chat. It never posts on its own.

### Lists

- **Personal list:** your own aliases. Only you use them, and they're shared by all your characters on the account. A personal alias wins over a guild alias with the same name.
- **Guild list:** one shared list kept by officers (the Guild Master rank and the rank directly below it). Everyone else sees it read-only.
- Up to 500 entries in each list.
- **Search** by alias or display name, and filter to **All**, **Roles** or **People**.
- **Import:** paste many aliases at once, including tab-separated text from a spreadsheet. Existing aliases are updated and new ones added.
- **Export:** copy any list as text in the same format, for backups or for pasting into another list or character.

### Automatic guild sync

- Officer edits and imports reach every guild member who has Beacon about 10 seconds after the last change. There's no button to press.
- Guildmates who log in with an older copy get the newest list from an online officer. An officer who logs in with a newer copy updates the guildmates who are online.
- Updates, renames and deletions all arrive, because each update carries the whole list.
- Lists are accepted only from officers, so members can't change the guild list.
- An officer who logs in with an older list than the guildmates online is warned not to edit until another officer comes online.
- The list is sent in small pieces about one second apart, to keep addon traffic light.

### Officers' log

- A **Log** view, for officers only, shows the last sync and a history of edits, imports, shares and received lists.
- Each entry shows who sent the list and which aliases were added, changed or removed.
- Keeps the last 200 events for each guild.

### Discord companion tool

- A Windows tool in the `Companion` folder reads your Discord server's members and roles with your own Discord bot.
- It asks for the bot token on first run and keeps it in Windows Credential Manager, never in a file.
- The export can go straight into Beacon (type `/reload` in game), be posted in a Discord channel, or both.
- Importing matches by Discord ID:
  - New people and roles are added.
  - Nickname changes update display names, and everyone keeps their alias.
  - People who left the server, and deleted roles, are removed.
- Names are cleaned up so they can be typed in game. Accents and fancy letters become plain letters, and emoji are dropped.

### Interface

- Lives in the game's **Options → AddOns → Beacon**, styled like other Options pages.
- Minimap button with the Beacon logo. Click to open, drag to move. `/beacon minimap` hides or shows it.
- Commands:
  - `/beacon` opens Beacon in Options.
  - `/beacon discord` offers the latest Discord export again.
- During combat, Options opens as soon as combat ends.

### Notes

- Built for World of Warcraft: Forever.
- Free. Beacon is not affiliated with Discord or Blizzard Entertainment.
- Made with the assistance of AI.
