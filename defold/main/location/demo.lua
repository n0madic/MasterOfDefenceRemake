-- Debug scenarios for checking the views without input (main/config.lua options):
-- `demo=1` builds a scripted defense next to the path (towers of several types and
-- levels, health bars on) and keeps upgrading it; `demo_ticks=N` simulates N ticks before
-- the first frame so a screenshot shows a raid in progress; `demo_skills=1` opens the
-- skills window; `pivot_x` / `pivot_z` point the camera; `auto_advance=1` leaves the end
-- screen by itself.
local config = require("main.config")
local data = require("sim.data")
local Game = require("sim.game")

local M = {}

function M.requested()
	return config.get_flag("demo")
end

function M.ticks()
	return config.get_int("demo_ticks", 0)
end

-- `pivot_x` / `pivot_z`: look at that point of the location (for screenshots), or nil. The
-- camera keeps to the location's scroll range like any camera move, so a point beyond it
-- (the path's start behind the gate) shows the range's nearest edge.
function M.pivot()
	local x, z = config.get_int("pivot_x", nil), config.get_int("pivot_z", nil)
	if x and z then
		return {x = x, z = z}
	end
	return nil
end

-- `auto_advance=1`: leave the end screen by itself (walks the campaign unattended).
function M.auto_advance()
	return config.get_flag("auto_advance")
end

-- `demo_menu=1`: open the in-game menu.
function M.open_menu()
	return config.get_flag("demo_menu")
end

function M.open_skills()
	return config.get_flag("demo_skills")
end

-- Build the scripted defense; returns the path key the camera should look at.
function M.build(game, location)
	local keys = game.data.paths[location].pos
	game.gold = 400
	game.show_units_life = true
	local first
	for i = 6, 18, 3 do
		local k = keys[i]
		first = first or game:build_tower(data.TOWER_LAND, {x = k.x + 4, y = 0, z = k.z + 4})
		game:build_tower(data.TOWER_PLANT, {x = k.x - 4, y = 0, z = k.z - 4})
	end
	game:build_tower(data.TOWER_MAGIC, {x = keys[9].x, y = 0, z = keys[9].z + 5})
	-- A level-10 Land tower next to the level-0 one: its guns differ per level, which shows
	-- whether the animation cursor seeks the skinned model.
	game:build_tower(data.TOWER_LAND, {x = keys[9].x + 10, y = 0, z = keys[9].z + 5}, 10)
	-- A level-10 Plant tower: it is posed by `bone_matrices` (manual skinning), so a clean
	-- shape here proves the sheared-model path holds up at maximum upgrades.
	game:build_tower(data.TOWER_PLANT, {x = keys[9].x + 10, y = 0, z = keys[9].z - 6}, 10)
	-- A level-5 Magic tower: its crown ring is a Blitz billboard (`B3D_BB_1_`) that only
	-- shows at the top levels; it must hover centred over the tower top.
	local gold = game.gold
	game.gold = math.huge  -- a showcase tower, paid for outside the demo's economy
	game:build_tower(data.TOWER_MAGIC, {x = keys[9].x - 6, y = 0, z = keys[9].z - 3}, 5)
	-- An Icerock: its base is the plain `dno1.png` ground layer, not the location's texture.
	game:build_tower(data.TOWER_ICEROCK, {x = keys[9].x - 6, y = 0, z = keys[9].z + 9})
	-- A Flame tower near the path's start, before the others kill the monsters: its hits set
	-- them on fire, under the bone-posed `MagicEff` model.
	game:build_tower(data.TOWER_FLAME, {x = keys[3].x + 4, y = 0, z = keys[3].z})
	game.gold = gold
	if first then
		game:select_tower(first)
	end
	return keys[9]
end

-- Keep upgrading: the first tower that can start an upgrade gets it.
function M.upgrade(game)
	if game.gold <= 100 then
		return
	end
	for _, t in ipairs(game.towers) do
		if t.level < t.max_upgrades and not Game.tower_is_upgrading(t) and not t.upgrade_pending then
			game:select_tower(t)
			if game:upgrade_selected_tower() then
				return
			end
		end
	end
end

return M
