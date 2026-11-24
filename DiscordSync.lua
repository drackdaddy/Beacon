local _, ns = ...

---------------------------------------------------------------------------
-- Discord import prompt
-- The companion tool writes the server's members and roles into
-- DiscordExportData.lua as ns.discordExport = { time, server, members, roles,
-- text }. After the next login or /reload, Beacon asks once which list to
-- import it into: Personal, or (for officers) Guild. The import matches by
-- Discord ID and removes people and roles no longer in the export.
-- /beacon discord asks again.
-- Events: PLAYER_LOGIN
-- SavedVariables: BeaconDB.discordHandled (time of the last export imported or
--   dismissed, so the same export isn't offered twice)
---------------------------------------------------------------------------
local PROMPT_DELAY = 8 -- seconds after login, once guild rank information is in

local function Import(which)
	local export = ns.discordExport
	BeaconDB.discordHandled = export.time
	local added, updated, skipped, removed = ns.ImportEntries(which, export.text)
	if not added then
		ns.Print(updated)
		return
	end
	ns.Print(string.format("Discord export imported into your %s list. %s",
		which == "guild" and "guild" or "personal", ns.ImportSummary(which, added, updated, removed)))
	if #skipped > 0 then
		ns.Print(ns.SkippedText(skipped))
	end
end

-- Creates the popup definition, with a Guild button for officers.
local function MakeDialog(withGuild)
	return {
		text = "%s",
		button1 = "Personal",
		button2 = "Not now",
		button3 = withGuild and "Guild" or nil,
		OnAccept = function()
			Import("personal")
		end,
		OnAlt = function()
			Import("guild")
		end,
		OnCancel = function()
			BeaconDB.discordHandled = ns.discordExport.time
		end,
		timeout = 0,
		whileDead = true,
		hideOnEscape = true,
	}
end

StaticPopupDialogs.BEACON_DISCORD_IMPORT = MakeDialog(false)
StaticPopupDialogs.BEACON_DISCORD_IMPORT_OFFICER = MakeDialog(true)

-- Offers the Discord export waiting in DiscordExportData.lua, if there is one.
function ns.OfferDiscordImport()
	local export = ns.discordExport
	if not export then
		ns.Print("No Discord export found. Run the Beacon Discord Sync companion tool (github.com/drackdaddy/BeaconDiscordSync), then /reload.")
		return
	end
	local text = string.format("Beacon: Discord export from %s\n%d %s and %d %s, made %s.\n\n"
		.. "Import it into which list? People and roles no longer in Discord are removed from that list.",
		export.server, export.members, export.members == 1 and "person" or "people",
		export.roles, export.roles == 1 and "role" or "roles", date("%b %d %I:%M %p", export.time))
	StaticPopup_Show(ns.IsOfficer() and "BEACON_DISCORD_IMPORT_OFFICER" or "BEACON_DISCORD_IMPORT", text)
end

ns.On("PLAYER_LOGIN", function()
	if ns.discordExport and ns.discordExport.time ~= BeaconDB.discordHandled then
		C_Timer.After(PROMPT_DELAY, ns.OfferDiscordImport)
	end
end)
