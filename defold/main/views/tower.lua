-- Tower views: the tower with its ground base, the range ring and the selection mark,
-- and the placement marker of `_fplacetower`.
local model = require("main.views.model")
local Game = require("sim.game")
local data = require("sim.data")

local M = {}

M.RANGE_MODEL = "Towers/range"
M.SELECTION_MODEL = "Towers/selection"
M.SELECTION_SPEED = 1.0
M.ICEROCK_TINT = vmath.vector4(0, 110 / 255, 1, 1)
local ICEROCK_UNTINTED_LOCATION = 3  -- `_fpositiontower`: the ice cave keeps its ground
M.COLOR_OK = vmath.vector4(0, 250 / 255, 0, 1)
M.COLOR_BAD = vmath.vector4(250 / 255, 0, 0, 1)

local TOWER_KEYS = {"Towers/Military", "Towers/Magic", "Towers/Nature", "Towers/Freeze", "Towers/Fire"}
local PLACE_KEYS = {"Towers/MilitaryPlace", "Towers/MagicPlace", "Towers/NaturePlace", "Towers/FreezePlace", "Towers/FirePlace"}

function M.create(t, ground_texture, tint, location)
	local pos = model.vec(t.position)
	local rot = vmath.quat_rotation_y(math.rad(t.yaw_degrees))
	local view = {tower = t, selection_time = 0}
	view.model = model.spawn(TOWER_KEYS[t.type], pos, rot, 1)
	-- `_fpositiontower`: the base gets the location's ground texture and tint; Icerock
	-- outside location 3 is painted blue.
	if view.model.meta.groups.dno then
		local c = (t.type == data.TOWER_ICEROCK and location ~= ICEROCK_UNTINTED_LOCATION) and M.ICEROCK_TINT or vmath.vector4(tint[1], tint[2], tint[3], 1)
		model.set_group(view.model, "dno", "texture0", ground_texture)
		model.set_group(view.model, "dno", "entity_color", c)
	end
	view.range = model.spawn(M.RANGE_MODEL, pos, vmath.quat(), vmath.vector3(t.range * 2, 1, t.range * 2))
	model.set_enabled(view.range, false)
	view.selection = model.spawn(M.SELECTION_MODEL, pos, vmath.quat(), 1)
	model.set_enabled(view.selection, false)
	return view
end

function M.delete(view)
	model.delete(view.model)
	model.delete(view.range)
	model.delete(view.selection)
end

-- `uv_frame`: the frame driving the type's shared texture scroll (`_fupdateextanims`
-- updates one tower per type), or nil for this tower's own frame.
function M.sync(view, uv_frame, ticks)
	local t = view.tower
	local frame = Game.tower_model_frame(t)
	model.set_frame(view.model, frame)
	model.animmaps(view.model, uv_frame or frame)
	model.set_enabled(view.range, t.selected)
	model.set_enabled(view.selection, t.selected)
	if t.selected then
		go.set_scale(vmath.vector3(t.range * 2, 1, t.range * 2), view.range.id)
		view.selection_time = (view.selection_time + M.SELECTION_SPEED * ticks) % math.max(view.selection.meta.frames, 1)
		model.set_frame(view.selection, view.selection_time)
	end
end

-- --- placement marker -------------------------------------------------------------------

function M.marker_create(type_id, range)
	local view = {allowed = nil}
	view.marker = model.spawn(PLACE_KEYS[type_id], vmath.vector3(0, -100, 0), vmath.quat(), 1)
	view.range = model.spawn(M.RANGE_MODEL, vmath.vector3(0, -100, 0), vmath.quat(), vmath.vector3(range * 2, 1, range * 2))
	M.marker_set(view, nil, false)
	return view
end

function M.marker_delete(view)
	model.delete(view.marker)
	model.delete(view.range)
end

-- `pos` nil hides the marker; the range circle shows only where building is allowed.
function M.marker_set(view, pos, allowed)
	model.set_enabled(view.marker, pos ~= nil)
	model.set_enabled(view.range, pos ~= nil and allowed)
	if pos then
		go.set_position(pos, view.marker.id)
		go.set_position(pos, view.range.id)
	end
	if allowed ~= view.allowed then
		view.allowed = allowed
		model.tint(view.marker, allowed and M.COLOR_OK or M.COLOR_BAD)
	end
end

return M
