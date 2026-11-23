local addonName, ns = ...

-- Guild rank indexes that count as officers: 0 is the Guild Master, 1 is the rank
-- directly below. Every client reads ranks from the same roster, so senders and
-- receivers always agree on who may edit and push the list.
ns.OFFICER_MAX_RANK = 1
ns.MAX_ENTRIES = 200

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
-- Saved data and the shared guild list
-- Holds one list per guild, so alts in other guilds keep separate lists.
-- Events: ADDON_LOADED
-- SavedVariables: BeaconDB.guilds[guildKey] = {
--   rev = number,        -- server time of the last edit; higher wins on sync
--   editor = "Name-Realm",
--   entries = { { alias = "raid", name = "Raid", kind = "role" | "user", id = "123..." }, ... },
-- }
---------------------------------------------------------------------------
ns.On("ADDON_LOADED", function(name)
	if name ~= addonName then
		return
	end
	BeaconDB = BeaconDB or {}
	BeaconDB.guilds = BeaconDB.guilds or {}
end)

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

-- Returns the saved list for the current guild. With create, makes an empty one.
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

-- Lookup tables for the current guild, rebuilt only when the list changes.
-- byAlias["raid"] = entry; byMention["&123"] = role entry; byMention["123"] = person entry.
local cache = {}

function ns.GetLookups()
	local data = ns.GetGuildData()
	if cache.data ~= data or not cache.byAlias then
		cache.data = data
		cache.byAlias, cache.byMention = {}, {}
		for _, entry in ipairs(data and data.entries or {}) do
			cache.byAlias[entry.alias] = entry
			cache.byMention[(entry.kind == "role" and "&" or "") .. entry.id] = entry
		end
	end
	return cache.byAlias, cache.byMention
end

-- Call after any change to the list: clears lookups and refreshes the open window.
function ns.ListChanged()
	cache.byAlias = nil
	if ns.RefreshManager then
		ns.RefreshManager()
	end
end

local RESERVED = { everyone = true, here = true }

-- Checks one entry's fields. Returns true, or nil and a message for the player.
-- Display names cannot contain , ; | or line breaks because sync uses them as separators.
function ns.ValidateEntry(entry)
	if not entry.alias:match("^[%w_]+$") or #entry.alias > 24 then
		return nil, "Alias must be 1-24 letters, numbers or underscores."
	end
	if RESERVED[entry.alias] then
		return nil, "@everyone and @here can't be used as aliases."
	end
	if #entry.name == 0 or #entry.name > 32 or entry.name:find("[,;|\n]") then
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

-- Marks the list as edited by this officer so it wins over older copies.
local function Touch(data)
	data.rev = math.max(GetServerTime(), data.rev + 1)
	data.editor = ns.PlayerName()
	ns.ListChanged()
end

-- Officer only. Adds fields as a new entry, or updates existing in place.
-- Returns the saved entry, or nil and a message for the player.
function ns.SaveEntry(fields, existing)
	if not ns.IsOfficer() then
		return nil, "Only officers can edit the guild list."
	end
	fields.alias = fields.alias:lower()
	local ok, err = ns.ValidateEntry(fields)
	if not ok then
		return nil, err
	end
	local data = ns.GetGuildData(true)
	for _, entry in ipairs(data.entries) do
		if entry ~= existing and entry.alias == fields.alias then
			return nil, "@" .. fields.alias .. " is already in the list."
		end
	end
	if not existing then
		if #data.entries >= ns.MAX_ENTRIES then
			return nil, "The guild list is full (" .. ns.MAX_ENTRIES .. " entries)."
		end
		existing = {}
		table.insert(data.entries, existing)
	end
	existing.alias, existing.name, existing.kind, existing.id = fields.alias, fields.name, fields.kind, fields.id
	Touch(data)
	return existing
end

-- Officer only. Removes entry from the current guild's list.
function ns.DeleteEntry(entry)
	local data = ns.GetGuildData()
	if not data or not ns.IsOfficer() then
		return
	end
	tDeleteItem(data.entries, entry)
	Touch(data)
end

---------------------------------------------------------------------------
-- Slash command
-- /beacon opens the guild list window.
---------------------------------------------------------------------------
SLASH_BEACON1 = "/beacon"
SlashCmdList.BEACON = function()
	ns.ToggleManager()
end
