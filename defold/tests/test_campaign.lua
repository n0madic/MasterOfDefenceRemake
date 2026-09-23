-- Campaign progression (`_fnextlocation`, the high score), save / load and the profile
-- rules.
local savegame = require("sim.savegame")
local profile = require("sim.profile")

return function(h)
	local check, Game, Skills, d = h.check, h.Game, h.Skills, h.data

	-- Difficulty start values (`_finitbalancedata`).
	for titul, expected in pairs({[0] = {200, 100}, [1] = {200, 25}, [2] = {500, 1}}) do
		local g = Game.new(d, 1)
		g:start_campaign(titul)
		check(g.gold == expected[1] and g.lifes == expected[2] and g.location == 1 and g.curlevel == 1,
			"difficulty " .. titul .. " start: gold " .. g.gold .. ", lifes " .. g.lifes)
	end

	-- `_fnextlocation`: gold above 200 hires inhabitants, gold resets to 200 + 20 L
	-- (250 + 20 L on location 5), experience + 10 L, the first raid of the next location.
	do
		local g = Game.new(d, 1)
		g:start_campaign(0)
		g.gold, g.experience = 455, 100
		check(g:next_location() == false, "location 1 -> 2 continues the campaign")
		check(g.location == 2 and g.max_location == 2 and g.curlevel == d.location_first_raid[2], "entered location 2")
		check(g.extra_lifes == 3 and g.gold == 240 and g.experience == 120, "gold to inhabitants: extra " .. g.extra_lifes .. ", gold " .. g.gold)
		g.gold = 150
		g:next_location()
		check(g.extra_lifes == 3 and g.gold == 260, "no hiring at 200 gold or less")
		g:next_location()
		g:next_location()
		check(g.location == 5 and g.gold == 350, "location 5 starts with 350 gold, got " .. g.gold)
		g:next_location()
		check(g.location == 6 and g.gold == 320 and g.experience == 120 + 30 + 40 + 50 + 60, "location 6 values")
		g.gold, g.lifes, g.extra_lifes = 430, 50, 4
		check(g:next_location() == true, "location 6 finishes the campaign")
		check(g.lifes == 50 + 3 + 4, "remaining gold and inhabitants become lives: " .. g.lifes)
		check(g:highscore() == 57 + 3, "the score converts the gold above 200 once more: " .. g.lifes)
	end

	-- Save round trip: towers (free, with their cost), skills replayed on fresh prototypes,
	-- raid state.
	do
		local g = Game.new(d, 5)
		g:start_campaign(1)
		g.experience = 1000
		g.skills:operate(g, Skills.RANGE, false)
		g.skills:operate(g, Skills.RANGE, false)
		g.skills:operate(g, Skills.DAMAGE, false)
		g.skills:operate(g, Skills.SPEED, false)
		g.skills:operate(g, Skills.COLD, false)
		g.skills:commit()
		local keys = d.paths[1].pos
		local t1 = g:build_tower(h.data_module.TOWER_LAND, {x = keys[6].x + 4, y = 0, z = keys[6].z + 4}, 3)
		local t2 = g:build_tower(h.data_module.TOWER_PLANT, {x = keys[9].x - 4, y = 0, z = keys[9].z - 4})
		t2.stopped = true
		g.gold, g.curlevel, g.missed[3] = 321, 7, 2
		local save = savegame.serialize(g)
		check(savegame.is_valid(save), "a fresh save is valid")
		check(not savegame.is_valid({version = savegame.VERSION + 1}), "a newer save is rejected")

		local r = Game.new(d, 9)
		savegame.restore(r, save)
		check(r.titul == 1 and r.gold == 321 and r.curlevel == 7 and r.location == 1 and r.missed[3] == 2, "game fields restored")
		check(#r.towers == 2 and r.towers[1].level == 3, "towers rebuilt")
		check(not r.towers[2].stopped, "a tower's stop is not saved (the original's record has none)")
		local spent = 0
		for level = 0, 3 do
			spent = spent + d:proto(h.data_module.TOWER_LAND, level).price
		end
		check(r.towers[1].spent == spent, "tower cost recomputed: " .. r.towers[1].spent .. " vs " .. spent)
		check(r.skills.range_level == 2 and r.skills.cold_magic == 1, "skill levels restored")
		local same = true
		for type_id = 1, h.data_module.TOWER_TYPES do
			for level = 0, h.data_module.TOWER_LEVELS - 1 do
				local a, b = g.protos[type_id][level], r.protos[type_id][level]
				same = same and a.range == b.range and a.land_damage == b.land_damage and a.rate_of_fire_ms == b.rate_of_fire_ms
			end
		end
		check(same, "prototypes replayed from the skill levels match the ones bought in play")
		check(r.towers[1].range == t1.range and r.towers[1].land_damage == t1.land_damage and r.towers[2].rate_of_fire_ms == t2.rate_of_fire_ms,
			"towers carry the replayed skills")
	end

	-- Profile rules.
	do
		local s = profile.with_defaults({MusicVol = 0.2, Bogus = 1, CurrentTitul = "x"})
		check(s.MusicVol == 0.2 and s.Bogus == nil and s.CurrentTitul == 0, "settings keep known keys of the right type")
		profile.finish_campaign(s, 0)
		check(s.CurrentTitul == 1 and s.MenusOpened == 1 and s.MasterFlag == 0, "first campaign unlocks Hero")
		profile.finish_campaign(s, 0)
		check(s.MenusOpened == 1 and s.MasterFlag == 0, "normal again unlocks nothing more")
		profile.finish_campaign(s, 1)
		check(s.CurrentTitul == 2 and s.MenusOpened == 2 and s.MasterFlag == 0, "Hero finished unlocks Legend")
		profile.finish_campaign(s, 0)
		check(s.MasterFlag == 0, "a normal campaign after the unlocks sets no master flag")
		profile.finish_campaign(s, 2)
		check(s.CurrentTitul == 2 and s.MenusOpened == 2 and s.MasterFlag == 1, "Legend finished sets the master flag")

		-- One rule per save kind (the key and the panel button may differ).
		local g = {titul = 0, survival_mode = false, level_finished = true, create_enemies_mode = false,
			enemies_amount = 0, is_game_over = false}
		check(profile.can_quick_save(g, false) and profile.can_quick_save(g, true), "between raids both save")
		g.create_enemies_mode = true
		check(not profile.can_quick_save(g, false) and not profile.can_quick_save(g, true), "no save while a raid spawns")
		g.create_enemies_mode, g.survival_mode = false, true
		check(not profile.can_quick_save(g, false) and profile.can_quick_save(g, true), "survival saves by the button only")
		check(not profile.can_quick_load(g, false) and profile.can_quick_load(g, true), "survival loads by the button only")
		check(not profile.can_autosave(g), "survival writes no automatic save")
		g.survival_mode, g.titul = false, 2
		check(not profile.can_quick_save(g, true) and not profile.can_quick_load(g, false), "Legend neither saves nor loads")
		g.titul, g.is_game_over = 0, true
		check(not profile.can_autosave(g), "a lost game writes no automatic save")
		local cleared = profile.saves_cleared_on_menu()
		check(#cleared == 6 and cleared[1] == "Location1" and cleared[6] == "Automatic", "saves cleared on the way to the menu")

		local tables = profile.new_highscores()
		for i = 1, 12 do
			profile.add_highscore(tables, false, i % 2 == 0 and "  " or "Ann", i * 10, "2026-09-22")
		end
		profile.add_highscore(tables, true, "Bob", 42)
		local rows = tables.campaign
		check(#rows == 10 and rows[1].score == 120 and rows[10].score == 30, "top 10 kept, highest first")
		check(rows[1].name == "Player" and rows[2].name == "Ann", "blank names become the default player")
		check(#tables.survival == 1 and tables.survival[1].name == "Bob", "survival table separate")

		local g = Game.new(d, 1)
		g:start_campaign(2)
		check(not profile.can_quick_save(g), "no quick save on Legend")
		g:start_campaign(0)
		check(profile.can_quick_save(g) and profile.quick_save_name(g) == "Save", "quick save between raids")
	end
end
