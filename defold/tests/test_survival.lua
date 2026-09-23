-- Survival (`_finitsurvival`, RaidsData7, `_fnextlevel` survival branch).
local Survival = require("sim.survival")
local savegame = require("sim.savegame")

return function(h)
	local check, Game, d = h.check, h.Game, h.data
	local g = Game.new(d, 11)
	g:start_survival()
	check(g.survival_mode and g.location == 2 and g.curlevel == 1, "survival starts on location 2, raid 1")
	check(g.gold == 250 and g.lifes == 100 and g.experience == 100 and g.titul == 0, "survival start values")
	check(g.balloon == nil, "no balloon in survival")
	check(#g.survival_raids == 200, "200 raids drawn at the start")
	check(#g.survival_raids[1].monsters == 10 and #g.survival_raids[18].monsters == 11 and #g.survival_raids[200].monsters == 21,
		"raid n has n \\ 18 + 10 monsters")
	local ok = true
	for _, raid in ipairs(g.survival_raids) do
		for _, id in ipairs(raid.monsters) do
			ok = ok and id >= 1 and id <= 30
		end
	end
	check(ok, "monster ids 1..30")
	check(Survival.raid(g.survival_raids, 250) == g.survival_raids[200], "past the table the last raid repeats")
	check(g:current_raid().life == d.survival[1].life, "stats from the survival table")

	-- Flying monsters' armour times 0.8; the income is gold_rate x the people left.
	local air_id
	for id = 1, 30 do
		if d:unit(id).air then
			air_id = id
			break
		end
	end
	g.curlevel = 150
	local e = g:create_enemy(false, air_id)
	check(e.armor == h.blitz.round_int(d.survival[150].armor * 0.8), "air armour x0.8: " .. e.armor)
	g.curlevel, g.lifes, g.gold = 5, 60, 0
	g:next_level()
	check(g.curlevel == 6 and g.gold == h.blitz.round_int(g.skills.gold_rate * 60), "income by the people left: " .. g.gold)

	local r = Game.new(d, 12)
	savegame.restore(r, savegame.serialize(g))
	check(r.survival_mode and #r.survival_raids == 200 and r.curlevel == 6, "a survival save restores")
end
