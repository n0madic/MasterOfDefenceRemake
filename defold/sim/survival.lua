-- Survival ("hardcore") mode (`_finitsurvival`, `_floaddata` with RaidsData7, docs/08): an
-- endless defense of location 2. `_floaddata` draws the monsters of all 200 raids at the
-- start: raid n has n \ 18 + 10 of random ids 1..30, its stats from the survival table.
local blitz = require("sim.blitz")

local M = {}

M.START_GOLD = 250
M.START_LIFES = 100
M.START_EXPERIENCE = 100
M.LOCATION = 2
M.RAIDS = 200
M.AIR_ARMOR_FACTOR = 0.8
local MONSTERS_PER_18_RAIDS, BASE_MONSTERS, MAX_UNIT_ID = 18, 10, 30

-- The 200 raids, drawing from `rng` (the game's Blitz generator).
function M.make_raids(data, rng)
	local raids = {}
	for n = 1, M.RAIDS do
		local row = data.survival[n]
		local monsters = {}
		for i = 1, blitz.idiv(n, MONSTERS_PER_18_RAIDS) + BASE_MONSTERS do
			monsters[i] = rng:rand(1, MAX_UNIT_ID)
		end
		raids[n] = {raid = n, monsters = monsters, life = row.life, speed = row.speed, armor = row.armor, gold = row.gold}
	end
	return raids
end

-- Raid `n`; past the table the original read beyond it, here the last raid repeats.
function M.raid(raids, n)
	return raids[math.min(n, #raids)]
end

return M
