-- Monster views: the MD2 model (or the healer's node-animated one), its shadow, the
-- health bar and the fire / poison effect it carries.
local model = require("main.views.model")
local Game = require("sim.game")
local blitz = require("sim.blitz")

local M = {}

M.FIRE_EFFECT = "Towers/MagicEff"  -- `_vfireexplprototype` (FireEff.b3d is an empty stub)
M.POISON_EFFECT = "Towers/PoisonEff"
M.SHADOW_MODEL = "Towers/shadow"
M.HEALTH_MODEL = "health"
M.HEALTH_BAR_HEIGHT = 3.5
M.EFFECT_SPEED = 0.2
M.FADE_IN_FRAMES = 3

function M.create(e, unit, shadows)
	local pos = model.vec(e.path.body)
	local rot = model.facing_rotation(e.path.facing)
	local view = {enemy = e, faded_in = false, health_lost = -1, health_index = -1, effect_kind = 0, effect_time = 0}
	view.model = model.spawn(model.key_of(unit.model), pos, rot, e.scale)
	if e.healer ~= 0 then
		-- The healer model is oriented sideways: Blitz turns it 90 degrees every tick.
		view.healer_rot = vmath.quat_rotation_y(math.rad(-90))
	end
	if shadows then
		view.shadow = model.spawn(M.SHADOW_MODEL, pos, rot, e.scale)
	end
	-- Blitz parents the bar to the scaled entity: its height and size grow with it.
	view.health = model.spawn(M.HEALTH_MODEL, pos, rot, e.scale)
	view.health_offset = ((e.air and 1 or 0) + M.HEALTH_BAR_HEIGHT) * e.scale
	model.set_enabled(view.health, false)
	return view
end

-- `_fshowupgradeswindow` hides the monsters (and all they carry) while the window is open.
function M.set_hidden(view, hidden)
	view.hidden = hidden
	model.set_enabled(view.model, not hidden)
	model.set_enabled(view.shadow, not hidden)
	model.set_enabled(view.effect, not hidden)
	if hidden then
		model.set_enabled(view.health, false)
	end
end

function M.delete(view)
	model.delete(view.model)
	model.delete(view.shadow)
	model.delete(view.health)
	model.delete(view.effect)
end

function M.sync(view, cam_rot, show_life, gradient, ticks)
	local e = view.enemy
	local pos = model.vec(e.path.body)
	local rot = model.facing_rotation(e.path.facing)
	local model_rot = view.healer_rot and (rot * view.healer_rot) or rot
	go.set_position(pos, view.model.id)
	go.set_rotation(model_rot, view.model.id)
	if view.shadow then
		go.set_position(pos, view.shadow.id)
		go.set_rotation(rot, view.shadow.id)
	end
	if e.healer == 0 then
		model.md2_frame(view.model, e.md2_time)
	else
		model.set_frame(view.model, e.md2_time % 10)
	end
	-- Fade in while the path marker is within the first 3 frames.
	local t = e.path.time
	if t < M.FADE_IN_FRAMES then
		local v = math.floor(255 * (t / M.FADE_IN_FRAMES) + 0.5) / 255
		model.tint(view.model, vmath.vector4(v, v, v, 1))
		if view.shadow then
			model.tint(view.shadow, vmath.vector4(v, v, v, 1))
		end
		view.faded_in = false
	elseif not view.faded_in then
		model.tint(view.model, nil)
		if view.shadow then
			model.tint(view.shadow, nil)
		end
		view.faded_in = true
	end
	-- Health bar: faces the camera, seeked to the lost percentage, tinted by the gradient.
	show_life = show_life and not view.hidden
	model.set_enabled(view.health, show_life)
	if show_life then
		go.set_position(vmath.vector3(pos.x, pos.y + view.health_offset, pos.z), view.health.id)
		go.set_rotation(cam_rot, view.health.id)
		local percent = Game.enemy_life_percent(e)
		local lost = math.max(1, math.min(99, 100 - percent))
		if lost ~= view.health_lost then
			view.health_lost = lost
			model.set_frame(view.health, lost)
		end
		-- `gradient` is 1-based over the bitmap's pixels 0..99: pixel `idx` is `gradient[idx + 1]`.
		local idx = math.max(1, blitz.round_int(percent - 1))
		if idx ~= view.health_index then
			view.health_index = idx
			local c = gradient[math.min(#gradient, idx + 1)]
			model.tint(view.health, vmath.vector4(c[1], c[2], c[3], 1))
		end
	end
	-- Status effect (fire / poison), the view's own clock.
	if e.effect_kind ~= view.effect_kind then
		model.delete(view.effect)
		view.effect = nil
		view.effect_kind = e.effect_kind
		if e.effect_kind ~= 0 then
			local key = (e.effect_kind == Game.EFFECT_FIRE) and M.FIRE_EFFECT or M.POISON_EFFECT
			local s = math.max(0.2, math.min(0.8, e.effect_size)) * e.scale
			view.effect = model.spawn(key, pos, rot, s)
			view.effect_time = 0
			model.set_enabled(view.effect, not view.hidden)
		end
	end
	if view.effect then
		local offset = e.air and 3 or 0
		go.set_position(vmath.vector3(pos.x, pos.y + offset, pos.z), view.effect.id)
		view.effect_time = (view.effect_time + M.EFFECT_SPEED * ticks) % math.max(view.effect.meta.frames, 1)
		model.set_frame(view.effect, view.effect_time)
	end
end

return M
