local addonName, ns = ...

-- Guild rank indexes that count as officers: 0 is the Guild Master, 1 is the rank
-- directly below. Every client reads ranks from the same roster, so senders and
-- receivers always agree on who may edit and push the guild list.
ns.OFFICER_MAX_RANK = 1
ns.MAX_ENTRIES = 500
ns.LOGO = "Interface\\AddOns\\Beacon\\Beacon-Logo.png"

---------------------------------------------------------------------------
-- Event dispatch
-- One frame for the whole addon. Features register handlers with ns.On(), so
-- several features can listen to the same event.
-- Events: whatever features register.
---------------------------------------------------------------------------
local dispatcher = CreateFrame("Frame")
local handlers = {}

-- Runs fn(...) with the event arguments whenever event fires.
function ns.On(event, fn)
	if not handlers[event] then
		handlers[event] = {}
		dispatcher:RegisterEvent(event)
	end
	table.insert(handlers[event], fn)
end

dispatcher:SetScript("OnEvent", function(_, event, ...)
	for _, fn in ipairs(handlers[event]) do
		fn(...)
	end
end)

-- Prints a message in the default chat frame with a gold "Beacon:" prefix.
function ns.Print(message)
	DEFAULT_CHAT_FRAME:AddMessage(NORMAL_FONT_COLOR:WrapTextInColorCode("Beacon: ") .. message)
end

---------------------------------------------------------------------------
-- Saved data
-- Sets every SavedVariables default in one place.
-- Events: ADDON_LOADED
-- SavedVariables:
--   BeaconDB.guilds[guildKey] = { rev, editor, entries, log }  -- shared guild list, one per guild
--     rev = server time of the last edit (higher wins on sync), editor = "Name-Realm"
--     log = { { time, text, sync }, ... } newest first; officers' record of syncs and changes
--   BeaconDB.personal = { entries }                       -- the player's own list, account-wide
--   BeaconDB.minimap = { angle, hide }                     -- minimap button position and visibility
--   BeaconDB.discordHandled = time                         -- last Discord export imported or dismissed (nil at first)
--   entries = { { alias = "raid", name = "Raid", kind = "role" | "user", id = "123..." }, ... }
---------------------------------------------------------------------------
ns.On("ADDON_LOADED", function(name)
	if name ~= addonName then
		return
	end
	BeaconDB = BeaconDB or {}
	BeaconDB.guilds = BeaconDB.guilds or {}
	for _, data in pairs(BeaconDB.guilds) do
		data.log = data.log or {}
	end
	BeaconDB.personal = BeaconDB.personal or { entries = {} }
	BeaconDB.minimap = BeaconDB.minimap or { angle = 225, hide = false }
end)

---------------------------------------------------------------------------
-- Players and guild ranks
---------------------------------------------------------------------------

-- Returns "Name-Realm" with the player's realm added when it is missing.
function ns.FullName(name)
	if name:find("-", 1, true) then
		return name
	end
	return name .. "-" .. GetNormalizedRealmName()
end

function ns.PlayerName()
	return ns.FullName(UnitName("player"))
end

-- Returns a stable key for the player's current guild, or nil when not in one.
function ns.GetGuildKey()
	local guildName, _, _, guildRealm = GetGuildInfo("player")
	if not guildName then
		return nil
	end
	return guildName .. "-" .. (guildRealm or GetNormalizedRealmName())
end

-- Returns true if fullName (or the player, when nil) holds an officer rank.
-- Other players are looked up in the guild roster, so it must be loaded.
function ns.IsOfficer(fullName)
	if not fullName then
		local _, _, rankIndex = GetGuildInfo("player")
		return rankIndex ~= nil and rankIndex <= ns.OFFICER_MAX_RANK
	end
	for i = 1, GetNumGuildMembers() do
		local memberName, _, rankIndex = GetGuildRosterInfo(i)
		if memberName and ns.FullName(memberName) == fullName then
			return rankIndex <= ns.OFFICER_MAX_RANK
		end
	end
	return false
end

---------------------------------------------------------------------------
-- Mention lists
-- Two lists: "guild" (shared, officers edit, synced by Sync.lua) and
-- "personal" (the player's own, never sent anywhere). When both have the same
-- alias, the personal one is used.
-- SavedVariables: BeaconDB.guilds, BeaconDB.personal
---------------------------------------------------------------------------

-- Returns the saved guild list for the current guild. With create, makes an empty one.
function ns.GetGuildData(create)
	local key = ns.GetGuildKey()
	if not key then
		return nil
	end
	local data = BeaconDB.guilds[key]
	if not data and create then
		data = { rev = 0, entries = {}, log = {} }
		BeaconDB.guilds[key] = data
	end
	return data
end

-- Returns the list table for which ("guild" or "personal"), or nil when not in a guild.
function ns.GetList(which, create)
	if which == "personal" then
		return BeaconDB.personal
	end
	return ns.GetGuildData(create)
end

-- Anyone may edit their personal list; only officers may edit the guild list.
function ns.CanEdit(which)
	return which == "personal" or (ns.GetGuildKey() ~= nil and ns.IsOfficer())
end

-- Lookup tables over both lists, rebuilt only when a list changes.
-- byAlias["raid"] = entry; byMention["&123"] = role entry; byMention["123"] = person entry.
local cache = {}

function ns.GetLookups()
	local guild = ns.GetGuildData()
	if cache.guild ~= guild or not cache.byAlias then
		cache.guild = guild
		cache.byAlias, cache.byMention = {}, {}
		for _, list in ipairs({ guild or { entries = {} }, BeaconDB.personal }) do
			for _, entry in ipairs(list.entries) do
				cache.byAlias[entry.alias] = entry
				cache.byMention[(entry.kind == "role" and "&" or "") .. entry.id] = entry
			end
		end
	end
	return cache.byAlias, cache.byMention
end

-- Call after any change to a list: clears lookups and refreshes the open window.
function ns.ListChanged()
	cache.byAlias = nil
	if ns.RefreshManager then
		ns.RefreshManager()
	end
end

local RESERVED = { everyone = true, here = true }

-- Checks one entry's fields. Returns true, or nil and a message for the player.
-- Display names cannot contain , ; | or line breaks because sync and import use them as separators.
function ns.ValidateEntry(entry)
	if not entry.alias:match("^[%w_]+$") or #entry.alias > 24 then
		return nil, "Alias must be 1-24 letters, numbers or underscores."
	end
	if RESERVED[entry.alias] then
		return nil, "@everyone and @here can't be used as aliases."
	end
	if #entry.name == 0 or #entry.name > 32 or entry.name:find("[,;|\n\t]") then
		return nil, "Display name must be 1-32 characters without , ; or |."
	end
	if entry.kind ~= "role" and entry.kind ~= "user" then
		return nil, "Choose Role or Person."
	end
	if not entry.id:match("^%d+$") or #entry.id < 17 or #entry.id > 20 then
		return nil, "Discord ID must be the 17-20 digit number copied from Discord."
	end
	return true
end

-- Records an edit. Guild edits are stamped so they win over older copies, are
-- shared with the guild automatically (see Sync.lua), and are written to the
-- officers' log as logText.
local function Touch(which, list, logText)
	if which == "guild" then
		list.rev = math.max(GetServerTime(), list.rev + 1)
		list.editor = ns.PlayerName()
		ns.QueueShare()
		ns.AddLog(logText)
	end
	ns.ListChanged()
end

-- Adds fields to a list as a new entry, or updates existing in place.
-- Returns the saved entry, or nil and a message for the player.
function ns.SaveEntry(which, fields, existing)
	if not ns.CanEdit(which) then
		return nil, "Only officers can edit the guild list."
	end
	fields.alias = fields.alias:lower()
	local ok, err = ns.ValidateEntry(fields)
	if not ok then
		return nil, err
	end
	local list = ns.GetList(which, true)
	for _, entry in ipairs(list.entries) do
		if entry ~= existing and entry.alias == fields.alias then
			return nil, "@" .. fields.alias .. " is already in this list."
		end
	end
	local logText = existing and ("You changed @" .. existing.alias) or ("You added @" .. fields.alias)
	if not existing then
		if #list.entries >= ns.MAX_ENTRIES then
			return nil, "This list is full (" .. ns.MAX_ENTRIES .. " entries)."
		end
		existing = {}
		table.insert(list.entries, existing)
	end
	existing.alias, existing.name, existing.kind, existing.id = fields.alias, fields.name, fields.kind, fields.id
	Touch(which, list, logText)
	return existing
end

-- Removes entry from a list the player may edit.
function ns.DeleteEntry(which, entry)
	local list = ns.GetList(which)
	if not list or not ns.CanEdit(which) then
		return
	end
	tDeleteItem(list.entries, entry)
	Touch(which, list, "You deleted @" .. entry.alias)
end

local KINDS = { role = "role", r = "role", person = "user", user = "user", p = "user", u = "user" }

-- Reads pasted import text, one entry per line:
--   alias, Role|Person, Discord ID[, display name]
-- Commas or tabs (spreadsheet copy) separate fields; a leading @ on the alias,
-- blank lines and lines starting with # are ignored, except the
--   # Beacon Discord export <stamp> part <i> of <n>
-- header the companion tool writes. Returns the valid entries (each with its
-- line number), the skipped line numbers, and whether the text holds every
-- part of one Discord export (true), only some parts ("partial") or none (nil).
local function ParseImport(text)
	local items, skipped = {}, {}
	local stamp, total, parts, mixed = nil, nil, {}, false
	local lineNumber = 0
	for line in (text .. "\n"):gmatch("([^\n]*)\n") do
		lineNumber = lineNumber + 1
		line = strtrim(line)
		local exportStamp, part, partCount = line:match("^#%s*Beacon Discord export (%d+) part (%d+) of (%d+)")
		if exportStamp then
			mixed = mixed or (stamp and (stamp ~= exportStamp or total ~= partCount))
			stamp, total = exportStamp, partCount
			parts[tonumber(part)] = true
		elseif line ~= "" and line:sub(1, 1) ~= "#" then
			local fields = {}
			for field in (line:gsub("\t", ",") .. ","):gmatch("([^,]*),") do
				fields[#fields + 1] = strtrim(field)
			end
			local alias = (fields[1] or ""):gsub("^@", "")
			local entry = {
				alias = alias:lower(),
				kind = KINDS[(fields[2] or ""):lower()] or "",
				id = fields[3] or "",
				name = (fields[4] and fields[4] ~= "") and fields[4] or alias,
				line = lineNumber,
			}
			if #fields > 4 or not ns.ValidateEntry(entry) then
				skipped[#skipped + 1] = lineNumber
			else
				items[#items + 1] = entry
			end
		end
	end

	local discord
	if stamp then
		discord = "partial"
		if not mixed then
			discord = true
			for i = 1, tonumber(total) do
				discord = discord and parts[i] == true
			end
			discord = discord or "partial"
		end
	end
	return items, skipped, discord
end

-- Returns base, or base with a number added (raid2, raid3...), so that it isn't
-- already used by another entry in byAlias. Returns nil if no free name is found.
local function FreeAlias(base, byAlias)
	if not byAlias[base] then
		return base
	end
	for n = 2, 99 do
		local candidate = base:sub(1, 24 - #tostring(n)) .. n
		if not byAlias[candidate] then
			return candidate
		end
	end
end

-- Copies a list's entries so later edits can be compared against them.
local function Snapshot(entries)
	local copy = {}
	for i, entry in ipairs(entries) do
		copy[i] = { alias = entry.alias, name = entry.name, kind = entry.kind, id = entry.id }
	end
	return copy
end

-- Applies a Discord export to list, matching entries by Discord ID: people and
-- roles already in the list keep their alias and get their current display
-- name; new ones are added (with a number added to the alias if it's taken).
-- With a complete export, entries whose ID isn't in it are removed: they've
-- left the server or the role was deleted.
-- Returns added, updated, removed; adds lines that didn't fit to skipped.
local function ApplyDiscordExport(list, items, complete, skipped)
	local inExport = {}
	for _, item in ipairs(items) do
		inExport[item.kind .. item.id] = true
	end
	-- Remove first, so a newcomer can take the alias of someone who left.
	local removed = 0
	if complete then
		for i = #list.entries, 1, -1 do
			local entry = list.entries[i]
			if not inExport[entry.kind .. entry.id] then
				table.remove(list.entries, i)
				removed = removed + 1
			end
		end
	end

	local byId, byAlias = {}, {}
	for _, entry in ipairs(list.entries) do
		byId[entry.kind .. entry.id] = entry
		byAlias[entry.alias] = entry
	end
	local added, updated = 0, 0
	for _, item in ipairs(items) do
		local key = item.kind .. item.id
		local existing = byId[key]
		local alias = not existing and FreeAlias(item.alias, byAlias)
		if existing then
			if existing.name ~= item.name then
				existing.name = item.name
				updated = updated + 1
			end
		elseif alias and #list.entries < ns.MAX_ENTRIES then
			local entry = { alias = alias, name = item.name, kind = item.kind, id = item.id }
			table.insert(list.entries, entry)
			byId[key], byAlias[alias] = entry, entry
			added = added + 1
		else
			skipped[#skipped + 1] = item.line
		end
	end
	return added, updated, removed
end

-- Adds or updates many entries at once from pasted text (see ParseImport).
-- Ordinary text is matched by alias: existing aliases are updated, the rest
-- added. A Discord export from the companion tool is matched by Discord ID and,
-- when every part of it is present, also removes entries missing from it.
-- Returns added, updated, skipped line numbers, removed and, when only some
-- parts of a Discord export were pasted, a note for the player; or nil and a message.
function ns.ImportEntries(which, text)
	if not ns.CanEdit(which) then
		return nil, "Only officers can edit the guild list."
	end
	local list = ns.GetList(which, true)
	local before = Snapshot(list.entries)
	local items, skipped, discord = ParseImport(text)
	local added, updated, removed, note = 0, 0, 0, nil

	if discord then
		added, updated, removed = ApplyDiscordExport(list, items, discord == true, skipped)
		if discord == "partial" then
			note = "Paste every part of the Discord export together to also remove people who have left."
		end
	else
		local byAlias = {}
		for _, entry in ipairs(list.entries) do
			byAlias[entry.alias] = entry
		end
		for _, item in ipairs(items) do
			local existing = byAlias[item.alias]
			if existing then
				existing.name, existing.kind, existing.id = item.name, item.kind, item.id
				updated = updated + 1
			elseif #list.entries < ns.MAX_ENTRIES then
				local entry = { alias = item.alias, name = item.name, kind = item.kind, id = item.id }
				table.insert(list.entries, entry)
				byAlias[entry.alias] = entry
				added = added + 1
			else
				skipped[#skipped + 1] = item.line
			end
		end
	end

	if added + updated + removed > 0 then
		local source = discord and "You synced from Discord: " or "You imported: "
		Touch(which, list, source .. (ns.DescribeChanges(before, list.entries) or "no changes"))
	end
	table.sort(skipped)
	return added, updated, skipped, removed, note
end

-- Returns a list as text in the format ns.ImportEntries reads, sorted by alias,
-- so an export can be pasted back into Import on any list or character.
function ns.ExportEntries(which)
	local list = ns.GetList(which)
	local entries = {}
	for i, entry in ipairs(list and list.entries or {}) do
		entries[i] = entry
	end
	table.sort(entries, function(a, b)
		return a.alias < b.alias
	end)
	local lines = { "# alias, Role or Person, Discord ID, display name" }
	for _, entry in ipairs(entries) do
		lines[#lines + 1] = table.concat({ entry.alias, entry.kind == "role" and "Role" or "Person", entry.id, entry.name }, ", ")
	end
	return table.concat(lines, "\n")
end

---------------------------------------------------------------------------
-- Officers' log
-- A record of guild list syncs and changes, kept per guild and shown only to
-- officers. Written only while the player is an officer.
-- SavedVariables: BeaconDB.guilds[guildKey].log
---------------------------------------------------------------------------
local MAX_LOG = 200
local MAX_NAMES = 6

-- Adds text to the current guild's log. sync marks entries that record a list
-- being sent or received, which the log page shows as the last sync.
function ns.AddLog(text, sync)
	if not ns.IsOfficer() then
		return
	end
	local log = ns.GetGuildData(true).log
	table.insert(log, 1, { time = GetServerTime(), text = text, sync = sync })
	for i = #log, MAX_LOG + 1, -1 do
		log[i] = nil
	end
	ns.RefreshManager()
end

-- Returns "@a, @b and 3 more" for a sorted list of aliases.
local function NameList(aliases)
	table.sort(aliases)
	local shown = {}
	for i = 1, math.min(#aliases, MAX_NAMES) do
		shown[i] = "@" .. aliases[i]
	end
	local text = table.concat(shown, ", ")
	if #aliases > MAX_NAMES then
		text = text .. string.format(" and %d more", #aliases - MAX_NAMES)
	end
	return text
end

-- Compares two versions of a list. Returns text such as
-- "added @a; changed @b; removed @c", or nil when nothing changed.
function ns.DescribeChanges(oldEntries, newEntries)
	local before, after = {}, {}
	for _, entry in ipairs(oldEntries) do
		before[entry.alias] = entry
	end
	local added, changed, removed = {}, {}, {}
	for _, entry in ipairs(newEntries) do
		after[entry.alias] = true
		local old = before[entry.alias]
		if not old then
			added[#added + 1] = entry.alias
		elseif old.name ~= entry.name or old.kind ~= entry.kind or old.id ~= entry.id then
			changed[#changed + 1] = entry.alias
		end
	end
	for alias in pairs(before) do
		if not after[alias] then
			removed[#removed + 1] = alias
		end
	end
	local parts = {}
	for _, group in ipairs({ { "added", added }, { "changed", changed }, { "removed", removed } }) do
		if #group[2] > 0 then
			parts[#parts + 1] = group[1] .. " " .. NameList(group[2])
		end
	end
	return #parts > 0 and table.concat(parts, "; ") or nil
end

---------------------------------------------------------------------------
-- Slash command
-- /beacon opens or closes the Beacon window; /beacon minimap shows or hides the
-- minimap button; /beacon discord offers the companion tool's latest export.
---------------------------------------------------------------------------
SLASH_BEACON1 = "/beacon"
SlashCmdList.BEACON = function(input)
	local command = strtrim(input):lower()
	if command == "minimap" then
		ns.ToggleMinimapButton()
	elseif command == "discord" then
		ns.OfferDiscordImport()
	else
		ns.ToggleManager()
	end
end
