# Changelog

## 0.7.0

- New **Discord companion tool** in the `Companion` folder. It reads your server's members and roles with your own Discord bot.
  - It asks for the bot token on first run and keeps it in Windows Credential Manager.
  - It sends the export straight into Beacon (type `/reload`), posts it in a Discord channel, or both.
- Importing a Discord export matches by Discord ID: new people and roles are added, nickname changes update display names, and people or roles no longer in the server are removed.
- After `/reload`, Beacon offers to import a new export into **Personal** or, for officers, **Guild**. `/beacon discord` offers it again.
- The import window now also reports removals.

Made with the assistance of AI.

## 0.6.0

- New officers-only **Log** view: shows the last sync, then a history of edits, imports, shares and received lists, including which aliases were added, changed or removed and who sent each list. It keeps the last 200 events for each guild.

Made with the assistance of AI.

## 0.5.0

- Guild sync is now automatic, and the **Send to Guild** button is gone:
  - Officer edits and imports go out about 10 seconds after the last change.
  - Guildmates who log in with an older copy get the newest list from an online officer.
  - An officer who logs in with a newer list updates the guildmates who are online.
- Updates, renames and deletions all reach everyone, because each update carries the whole list and replaces the old one.
- An officer who logs in with an older list than the guildmates online is warned not to edit until another officer comes online.
- When two officers are online, only one of them answers a guildmate who logs in.

Made with the assistance of AI.

## 0.4.0

- Beacon's lists now live in the game's **Options → AddOns → Beacon** instead of a separate window. The minimap button and `/beacon` open Options straight to that page; during combat it opens as soon as combat ends.
- **Personal** and **Guild** are now buttons at the top of the page instead of tabs.
- Fixed an error when switching between the Personal and Guild lists (0.3.2 and 0.3.3).

Made with the assistance of AI.

## 0.3.3

- The **All / Roles / People** filter and the editor's **Role / Person** choice are now full-size buttons instead of small radio buttons, so they're easier to click. The chosen button stays lit.

Made with the assistance of AI.

## 0.3.2

- New **Show: All / Roles / People** filter under the search box on each tab.

Made with the assistance of AI.

## 0.3.1

- New **Search** box above each list: shows only aliases or display names containing the typed text.

Made with the assistance of AI.

## 0.3.0

- New **Export...** button on both tabs: shows the list as text in the import format, selected and ready to copy.
- **Import...**, **Export...** and **Send to Guild** now sit together on the window's bottom bar.

Made with the assistance of AI.

## 0.2.1

- The lists window now opens on the **Personal** tab, which is also the first tab.

Made with the assistance of AI.

## 0.2.0

- New **Personal** list: everyone can keep their own aliases next to the guild list. The window now has **Guild** and **Personal** tabs. Personal aliases win over guild aliases with the same name.
- New **Import...** window: paste many aliases at once (`alias, Role or Person, Discord ID, display name`), including tab-separated text from a spreadsheet. Officers can import into the guild list; anyone can import into their personal list.
- New minimap button with the Beacon logo. Click to open the lists, drag to move. `/beacon minimap` hides or shows it.
- New Beacon logo, also used for the window portrait and the addon list icon.
- Each list now holds up to 500 entries (was 200).

Made with the assistance of AI.

## 0.1.0

First release.

- Guild and Guild Discord chat turn `@alias` into Discord role and person mentions just before sending.
- `@` autocomplete above the chat box (Tab, Shift+Tab, click, Enter).
- The chat window shows friendly names instead of raw Discord IDs.
- `@everyone` and `@here` are always blocked.
- `/beacon` window: officers edit the shared guild list and send it to the guild; members see a read-only copy.
- The list syncs over the hidden guild addon channel. Only lists from officer ranks are accepted.

Made with the assistance of AI.
