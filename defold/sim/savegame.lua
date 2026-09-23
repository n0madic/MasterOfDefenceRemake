-- Save / load of the simulation (`_fsavegame` / `_floadgame`, docs/02): the fields of the
-- original's `tthegamet` record plus the tower list, as a plain Lua table (the storage
-- layer writes it with sys.save). The original saves between raids, so enemies and
-- bullets are not kept, nor a tower's "stop" (the original's tower record has no such field;
-- `_fnextlevel` starts every tower again after the raid anyway). Loading rebuilds the towers
-- without charging for them, recomputes what each one cost and replays the multiplier
-- skills on fresh prototypes.
local blitz = require("sim.blitz")
local Skills = require("sim.skills")
local Survival = require("sim.survival")
local data = require("sim.data")

local f32 = blitz.f32

local M = {}

M.VERSION = 1

-- Skill fields stored as they are.
local SKILL_FIELDS = {
	"range_upgrader", "speed_upgrader", "damage_upgrader", "gold_rate", "sell_rate",
	"range_level", "speed_level", "damage_level", "gold_level", "sell_level",
	"cold_magic", "fire_magic", "poison_magic", "ppl_resistance",
}
local FLOAT_SKILL_FIELDS = {range_upgrader = true, speed_upgrader = true, damage_upgrader = true, gold_rate = true, sell_rate = true}

-- Game fields stored as they are (`survival_mode`, `titul` are kept by the original in its
-- settings rather than the save).
local GAME_FIELDS = {
	"survival_mode", "titul", "gold", "lifes", "curlevel", "location", "enemies_created", "ingame_time",
	"show_units_life", "create_enemies_mode", "level_finished", "experience", "max_location", "old_lifes",
	"extra_lifes", "units_life_multiplier",
}


-- A save table of `game`.
function M.serialize(game)
	local save = {version = M.VERSION, skills = {}, towers = {}, missed = data.copy(game.missed)}
	for _, field in ipairs(GAME_FIELDS) do
		save[field] = game[field]
	end
	for _, field in ipairs(SKILL_FIELDS) do
		save.skills[field] = game.skills[field]
	end
	if game.balloon then
		local p = game.balloon.position
		save.balloon = {x = p.x, y = p.y, z = p.z}
	end
	for _, t in ipairs(game.towers) do
		if not t.hidden then
			local p = t.position
			save.towers[#save.towers + 1] = {type = t.type, level = t.level, x = p.x, y = p.y, z = p.z, yaw = t.yaw_degrees}
		end
	end
	return save
end

-- Whether `save` can be restored by this version.
function M.is_valid(save)
	return type(save) == "table" and save.version == M.VERSION and type(save.location) == "number"
		and type(save.skills) == "table" and type(save.towers) == "table"
end

-- Restore `game` (a fresh sim.game) from `save`.
function M.restore(game, save)
	assert(M.is_valid(save), "incompatible save")
	game.survival_mode = save.survival_mode or false
	if game.survival_mode then
		-- The original's load re-runs `_floaddata`: the raids are drawn anew.
		game.survival_raids = Survival.make_raids(game.data, game.rng)
	end
	game:enter_location(save.location)
	game:reset_protos()
	for _, field in ipairs(GAME_FIELDS) do
		if save[field] ~= nil then
			game[field] = save[field]
		end
	end
	game.ingame_time = f32(game.ingame_time)
	game.units_life_multiplier = f32(game.units_life_multiplier)
	local skills = game.skills
	skills:reset()
	for _, field in ipairs(SKILL_FIELDS) do
		local v = save.skills[field]
		if v ~= nil then
			skills[field] = FLOAT_SKILL_FIELDS[field] and f32(v) or v
		end
	end
	game.missed = data.copy(save.missed or {})
	if save.balloon then
		game:enable_balloon()
		game.balloon.position = {x = save.balloon.x, y = save.balloon.y, z = save.balloon.z}
	end
	for _, entry in ipairs(save.towers) do
		local t = game:build_tower(entry.type, {x = entry.x, y = entry.y, z = entry.z}, entry.level, false)
		t.yaw_degrees = entry.yaw or t.yaw_degrees
		t.spent = 0
		for level = 0, t.level do
			t.spent = t.spent + game.data:proto(t.type, level).price
		end
	end
	for _, kind in ipairs({Skills.KIND_RANGE, Skills.KIND_SPEED, Skills.KIND_DAMAGE}) do
		skills:reapply_from_levels(game, kind)
	end
	game:emit({type = "skills_changed"})
end

return M
