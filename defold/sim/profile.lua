-- The player's profile rules, engine independent: settings defaults (the original's
-- Settings.vdd "Options" section), the difficulty unlocks of a finished campaign, which
-- saves exist for what, and the local high score tables. main/storage.lua persists the
-- tables this module builds.
local M = {}

M.SAVE_AUTOMATIC = "Automatic"
M.SAVE_QUICK = "Save"
M.SAVE_SURVIVAL = "Survival"
M.HIGHSCORES_KEEP = 10
M.DEFAULT_PLAYER = "Player"
M.TITUL_MAX = 2

function M.location_save(L)
	return "Location" .. L
end

-- Settings defaults. `CurrentTitul`: the difficulty the menu title shows (0..2);
-- `MenusOpened`: the highest difficulty unlocked; `MasterFlag`: Legend finished.
function M.default_settings()
	return {
		SoundVol = 0.5, MusicVol = 0.5, GammaIntensity = 0, WideScreen = 0, Windowed = 1,
		PlayerName = "", ShowHelp = 1, TutorialDisable = 0,
		CurrentTitul = 0, MenusOpened = 0, MasterFlag = 0,
	}
end

-- `settings` completed with the defaults for missing keys.
function M.with_defaults(settings)
	local out = M.default_settings()
	for k, v in pairs(settings or {}) do
		if out[k] ~= nil and type(out[k]) == type(v) then
			out[k] = v
		end
	end
	return out
end

-- `_fshowmenu`: picking a difficulty (or survival, `_finitsurvival`: 0) makes it the
-- current one. Mutates and returns `settings`.
function M.select_titul(settings, titul)
	settings.CurrentTitul = titul
	return settings
end

-- `_floadfinaltitres`: finishing a campaign on difficulty `titul` unlocks the next one;
-- finishing it at the top one sets the master flag. Mutates and returns `settings`.
function M.finish_campaign(settings, titul)
	M.select_titul(settings, titul)
	if settings.CurrentTitul < M.TITUL_MAX then
		settings.CurrentTitul = settings.CurrentTitul + 1
		settings.MenusOpened = math.max(settings.MenusOpened, settings.CurrentTitul)
	else
		settings.MasterFlag = 1
	end
	return settings
end

-- `_fclearlocationsaves` (going back to the menu): Location1..5 and Automatic. Location6
-- and the quick save are kept, as in the original.
function M.saves_cleared_on_menu()
	local names = {}
	for L = 1, 5 do
		names[#names + 1] = M.location_save(L)
	end
	names[#names + 1] = M.SAVE_AUTOMATIC
	return names
end

-- The quick save (`_fhandlelevels` shows the panel's Save button, `_fmainloop` takes F5):
-- between raids (not while one spawns) on the normal and Hero difficulties. The key saves
-- a campaign with no monster alive; in survival only the button saves (Survival.sav).
function M.can_quick_save(game, from_button)
	if game.titul >= M.TITUL_MAX or not game.level_finished or game.create_enemies_mode then
		return false
	end
	if game.survival_mode then
		return from_button
	end
	return game.enemies_amount == 0
end

-- The quick load (the panel's Load button, F9 in a campaign), not on the top difficulty.
function M.can_quick_load(game, from_button)
	return game.titul < M.TITUL_MAX and (from_button or not game.survival_mode)
end

-- The automatic save (`_fnextlevel`, leaving through the in-game menu, the window losing
-- focus): a campaign with no raid on and not lost (the raid's last monster can take the
-- last life in the tick that ends the raid).
function M.can_autosave(game)
	return not game.survival_mode and not game.create_enemies_mode and game.enemies_amount == 0
		and not game.is_game_over
end

-- The quick save slot of the current mode.
function M.quick_save_name(game)
	return game.survival_mode and M.SAVE_SURVIVAL or M.SAVE_QUICK
end

-- An empty pair of high score tables.
function M.new_highscores()
	return {campaign = {}, survival = {}}
end

-- Insert a score into the campaign or survival table (top 10, highest first; a tie keeps
-- the older entry first). Mutates and returns `tables`.
function M.add_highscore(tables, survival, name, score, date)
	local rows = tables[survival and "survival" or "campaign"]
	name = (name or ""):match("^%s*(.-)%s*$")
	local entry = {name = name ~= "" and name or M.DEFAULT_PLAYER, score = score, date = date or ""}
	local at = #rows + 1
	for i, row in ipairs(rows) do
		if score > row.score then
			at = i
			break
		end
	end
	table.insert(rows, at, entry)
	while #rows > M.HIGHSCORES_KEEP do
		table.remove(rows)
	end
	return tables
end

return M
