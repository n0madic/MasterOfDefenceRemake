-- Bullets and one-shot effects (explosions, the death ghost with its alpha fade).
local model = require("main.views.model")

local M = {}

M.DEATH_MODEL = "Towers/death"
M.ONE_SHOT_SPEED = 0.2
M.DEATH_FADE_FRAMES = 10
M.EXPLOSION_SCALE_FACTOR = 0.7
M.EXPLOSION_MIN_SCALE = 0.1
local EFFECT_KEYS = {"Towers/MilitaryEff", "Towers/MagicEff", "Towers/NatureEff", "Towers/FreezeEff", "Towers/MagicEff"}

function M.bullet_create(b)
	local key = model.key_of(b.model or "")
	local view = {bullet = b}
	if key and model.exists(key) then
		view.model = model.spawn(key, model.vec(b.position), model.facing_rotation(b.direction), 1)
	end
	return view
end

function M.bullet_sync(view)
	if view.model then
		local b = view.bullet
		go.set_position(model.vec(b.position), view.model.id)
		local d = b.direction
		if d.x * d.x + d.z * d.z > 1e-6 then
			go.set_rotation(model.facing_rotation(d), view.model.id)
		end
	end
end

function M.bullet_delete(view)
	model.delete(view.model)
end

function M.effect_key(tower_type)
	return EFFECT_KEYS[tower_type]
end

-- A one-shot Blitz animation (explosion, death ghost): the whole `b3d` animation at
-- `speed` frames per tick; `fade_frames` > 0 applies `_fupdatedeathanims`' alpha fade.
function M.one_shot(key, position, scale, speed, fade_frames)
	local obj = model.spawn(key, position, vmath.quat(), scale)
	local shot = {obj = obj, time = 0, speed = speed, length = obj.meta.frames, fade = fade_frames or 0}
	model.set_frame(obj, 0)
	model.animmaps(obj, 0)
	return shot
end

-- Advance `ticks`; returns true when finished (and deleted).
function M.one_shot_tick(shot, ticks)
	shot.time = shot.time + shot.speed * ticks
	local done = shot.time >= shot.length
	if done then
		shot.time = shot.length
	end
	model.set_frame(shot.obj, shot.time)
	model.animmaps(shot.obj, shot.time)
	if shot.fade > 0 then
		model.alpha(shot.obj, math.max(0, (shot.length - shot.time) / shot.fade))
	end
	if done then
		model.delete(shot.obj)
	end
	return done
end

return M
