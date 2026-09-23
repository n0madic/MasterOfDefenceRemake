-- Static game tables (godot/data/*.json copied to /data by the exporter). `load(read)`
-- takes a reader `function(path) -> string` so the module works headless as well.
local M = {}

M.TOWER_LAND = 1
M.TOWER_MAGIC = 2
M.TOWER_PLANT = 3
M.TOWER_ICEROCK = 4
M.TOWER_FLAME = 5
M.TOWER_TYPES = 5
M.TOWER_LEVELS = 11
M.TOWER_KEYS = {"land", "magic", "plant", "freeze", "fire"}
M.LOCATIONS = 6
M.CAMPAIGN_RAIDS = 180

-- A shallow copy of table `t`.
function M.copy(t)
	local out = {}
	for k, v in pairs(t) do
		out[k] = v
	end
	return out
end
local copy = M.copy

-- `decode` is a JSON decoder (`json.decode` in the engine); `read(path)` returns the text.
function M.load(read, decode, dir)
	dir = dir or "/data"
	local function json(name)
		return decode(read(dir .. "/" .. name))
	end
	local d = {}
	d.units = {}
	for _, u in ipairs(json("units.json")) do
		d.units[u.id] = u
	end
	local towers = json("towers.json")
	d.tower_protos = {}
	d.tower_models = {}
	for type_id = 1, M.TOWER_TYPES do
		local entry = towers[M.TOWER_KEYS[type_id]]
		local levels = {}
		for _, lv in ipairs(entry.levels) do
			lv.max_upgrades = entry.max_upgrades
			lv.type_id = type_id
			levels[lv.level] = lv
		end
		d.tower_protos[type_id] = levels
		local fire_keys = {}
		if entry.fire1.keys then
			for _, k in ipairs(entry.fire1.keys) do
				fire_keys[#fire_keys + 1] = {x = k[1], y = k[2], z = k[3]}
			end
		else
			local k = entry.fire1["static"]
			fire_keys[1] = {x = k[1], y = k[2], z = k[3]}
		end
		d.tower_models[type_id] = {
			model = entry.model, place_model = entry.place_model, effect_model = entry.effect_model,
			anim_frames = entry.anim_frames, fire1 = fire_keys,
		}
	end
	local raids = json("raids.json")
	d.raids = raids.campaign  -- raids[n], n = raid number
	d.survival = raids.survival  -- survival[n]: life, speed, armor, gold of raid n
	d.location_first_raid = {}
	for L = 1, M.LOCATIONS do
		d.location_first_raid[L] = raids.location_first_raid[tostring(L)]
	end
	local locs = json("locations.json")
	d.locations = {}
	for L = 1, M.LOCATIONS do
		d.locations[L] = locs[tostring(L)]
	end
	local paths = json("paths.json")
	d.paths = {}
	for L = 1, M.LOCATIONS do
		local entry = paths[tostring(L)]
		local pos, rot = {}, {}
		for i, k in ipairs(entry.keys) do
			pos[i] = {x = k.pos[1], y = k.pos[2], z = k.pos[3]}
			if k.rot_wxyz then
				rot[i] = {w = k.rot_wxyz[1], x = k.rot_wxyz[2], y = k.rot_wxyz[3], z = k.rot_wxyz[4]}
			end
		end
		d.paths[L] = {frames = entry.anim_frames, pos = pos, rot = rot}
	end
	d.texts = json("texts.json")
	setmetatable(d, {__index = M})
	return d
end

-- gametext[k] = line k+1 of Texts.txt.
function M.text(d, k)
	return d.texts.texts[k + 1] or ""
end

-- `Storyline.txt` text of location L (the map screen).
function M.storyline(d, L)
	return d.texts.storyline[L] or ""
end

-- Tutorial.txt line of tutorial page `page`.
function M.tutorial_text(d, page)
	return d.texts.tutorial[page + 1] or ""
end

function M.help(d, k)
	return d.texts.helps[k + 1] or ""
end

function M.unit(d, id)
	return d.units[id]
end

-- A fresh copy of the level-`level` prototype of tower `type_id` (`_floadtowerprototipesdata`).
function M.proto_copy(d, type_id, level)
	return copy(d.tower_protos[type_id][level])
end

-- The CSV prototype itself (read only).
function M.proto(d, type_id, level)
	return d.tower_protos[type_id][level]
end

function M.tower_model(d, type_id)
	return d.tower_models[type_id]
end

function M.raid(d, n)
	return d.raids[n]
end

function M.location(d, L)
	return d.locations[L]
end

return M
