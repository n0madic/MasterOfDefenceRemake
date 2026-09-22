-- Auto-balance of monster health (`_fhandlebalance`, docs/08).
local blitz = require("sim.blitz")

local M = {}

local FLOOR_NORMAL, FLOOR_HERO, FLOOR_LEGEND = 0.8, 0.95, 1.0
local CEILING_HERO_FACTOR, CEILING_LEGEND_FACTOR = 1.1, 1.2
local CLEAN_RAIDS_BONUS = 0.03
local MANY_LIFES, MANY_LIFES_MULTIPLIER = 201, 1.3
local FEW_LIFES, FEW_LIFES_MULTIPLIER = 20, 0.7

-- `missed[n]` is indexed by raid number, written under the already incremented curlevel.
function M.update(m, missed, curlevel, location, titul, lifes)
	local f32 = blitz.f32
	if (missed[curlevel] or 0) > 0 then
		m = f32(m - missed[curlevel] / 100)
	end
	if curlevel > 3 and (missed[curlevel] or 0) == 0 and (missed[curlevel - 1] or 0) == 0 and (missed[curlevel - 2] or 0) == 0 then
		m = f32(m + f32(CLEAN_RAIDS_BONUS))
	end
	local ceiling = f32(location / 10 + 1)
	local floor_value = FLOOR_NORMAL
	if titul == 1 then
		floor_value = FLOOR_HERO
		ceiling = f32(ceiling * f32(CEILING_HERO_FACTOR))
	elseif titul == 2 then
		floor_value = FLOOR_LEGEND
		ceiling = f32(ceiling * f32(CEILING_LEGEND_FACTOR))
	end
	if m > ceiling then
		m = ceiling
	end
	if m < floor_value then
		m = f32(floor_value)
	end
	if lifes >= MANY_LIFES then
		m = f32(MANY_LIFES_MULTIPLIER)
	elseif lifes < FEW_LIFES and titul == 0 then
		m = f32(FEW_LIFES_MULTIPLIER)
	end
	return m
end

return M
