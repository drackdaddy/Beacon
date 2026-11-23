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
--   BeaconDB.guilds[guildKey] = { rev, editor, entries }  -- shared guild list, one per guild
--     rev = server time of the last edit (higher wins on sync), editor = "Name-Realm"
--   BeaconDB.personal = { entries }                       -- the player's own list, account-wide
--   BeaconDB.minimap = { angle, hide }                     -- minimap button position and visibility
--   entries = { { alias = "raid", name = "Raid", kind = "role" | "user", id = "123..." }, ... }
---------------------------------------------------------------------------
ns.On("ADDON_LOADED", function(name)
	if name ~= addonName then
		return
	end
	BeaconDB = BeaconDB or {}
	BeaconDB.guilds = BeaconDB.guilds or {}
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
		data = { rev = 0, entries = {} }
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

-- Records an edit. Guild edits are stamped so they win over older copies on sync.
local function Touch(which, list)
	if which == "guild" then
		list.rev = math.max(GetServerTime(), list.rev + 1)
		list.editor = ns.PlayerName()
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
	if not existing then
		if #list.entries >= ns.MAX_ENTRIES then
			return nil, "This list is full (" .. ns.MAX_ENTRIES .. " entries)."
		end
		existing = {}
		table.insert(list.entries, existing)
	end
	existing.alias, existing.name, existing.kind, existing.id = fields.alias, fields.name, fields.kind, fields.id
	Touch(which, list)
	return existing
end

-- Removes entry from a list the player may edit.
function ns.DeleteEntry(which, entry)
	local list = ns.GetList(which)
	if not list or not ns.CanEdit(which) then
		return
	end
	tDeleteItem(list.entries, entry)
	Touch(which, list)
end

local KINDS = { role = "role", r = "role", person = "user", user = "user", p = "user", u = "user" }

-- Adds or updates many entries at once from pasted text, one per line:
--   alias, Role|Person, Discord ID[, display name]
-- Commas or tabs (spreadsheet copy) separate fields; a leading @ on the alias,
-- blank lines and lines starting with # are ignored. Existing aliases are updated.
-- Returns added, updated and a list of skipped line numbers, or nil and a message.
function ns.ImportEntries(which, text)
	if not ns.CanEdit(which) then
		return nil, "Only officers can edit the guild list."
	end
	local list = ns.GetList(which, true)
	local byAlias = {}
	for _, entry in ipairs(list.entries) do
		byAlias[entry.alias] = entry
	end

	local added, updated, skipped = 0, 0, {}
	local lineNumber = 0
	for line in (text .. "\n"):gmatch("([^\n]*)\n") do
		lineNumber = lineNumber + 1
		line = strtrim(line)
		if line ~= "" and line:sub(1, 1) ~= "#" then
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
			}
			local existing = byAlias[entry.alias]
			if #fields > 4 or not ns.ValidateEntry(entry) or (not existing and #list.entries >= ns.MAX_ENTRIES) then
				skipped[#skipped + 1] = lineNumber
			elseif existing then
				existing.name, existing.kind, existing.id = entry.name, entry.kind, entry.id
				updated = updated + 1
			else
				table.insert(list.entries, entry)
				byAlias[entry.alias] = entry
				added = added + 1
			end
		end
	end
	if added + updated > 0 then
		Touch(which, list)
	end
	return added, updated, skipped
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
-- Slash command
-- /beacon opens Beacon in Options > AddOns; /beacon minimap shows or hides the minimap button.
---------------------------------------------------------------------------
SLASH_BEACON1 = "/beacon"
SlashCmdList.BEACON = function(input)
	if strtrim(input):lower() == "minimap" then
		ns.ToggleMinimapButton()
	else
		ns.OpenManager()
	end
end
