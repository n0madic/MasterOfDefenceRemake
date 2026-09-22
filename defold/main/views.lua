-- 3D views of the simulation objects: game objects spawned from the generated factories
-- (generated/models.lua), seeked to the simulation's frames every frame like Blitz did
-- (the game never plays animations, it sets AnimTime).
local models = require("generated.models")
local Game = require("sim.game")
local blitz = require("sim.blitz")

local M = {}

M.ENTITIES = "entities"
M.FIRE_EFFECT = "Towers/MagicEff"  -- `_vfireexplprototype` (FireEff.b3d is an empty stub)
M.POISON_EFFECT = "Towers/PoisonEff"
M.DEATH_MODEL = "Towers/death"
M.SHADOW_MODEL = "Towers/shadow"
M.HEALTH_MODEL = "health"
M.RANGE_MODEL = "Towers/range"
M.SELECTION_MODEL = "Towers/selection"
M.MD2_LAST_FRAME = 10
M.HEALTH_BAR_HEIGHT = 3.5
M.EFFECT_SPEED = 0.2
M.FADE_IN_FRAMES = 3
M.SELECTION_SPEED = 1.0
M.ONE_SHOT_SPEED = 0.2
M.DEATH_FADE_FRAMES = 10
M.EXPLOSION_SCALE_FACTOR = 0.7
M.EXPLOSION_MIN_SCALE = 0.1
M.ICEROCK_TINT = vmath.vector4(0, 110 / 255, 1, 1)
M.COLOR_OK = vmath.vector4(0, 250 / 255, 0, 1)
M.COLOR_BAD = vmath.vector4(250 / 255, 0, 0, 1)
M.NO_TINT = vmath.vector4(1, 1, 1, 0)

local UP = vmath.vector3(0, 1, 0)

function M.vec(v)
	return vmath.vector3(v.x, v.y, v.z)
end

-- Rotation whose -Z axis points along `f` (Godot `look_at`), Y kept up.
function M.facing_rotation(f)
	local horizontal = math.sqrt(f.x * f.x + f.z * f.z)
	local yaw = math.atan2(-f.x, -f.z)
	local pitch = (horizontal > 0.001) and math.atan2(f.y, horizontal) or 0
	return vmath.quat_rotation_y(yaw) * vmath.quat_rotation_x(pitch)
end

-- --- model objects ----------------------------------------------------------------------

local function group_urls(id, meta)
	local urls = {}
	for group in pairs(meta.groups) do
		urls[#urls + 1] = msg.url(nil, id, group)
	end
	return urls
end

-- Spawn `key` (a generated/models.lua entry); skinned models get their animation parked
-- at playback rate 0 so `cursor` seeks it.
function M.spawn(key, position, rotation, scale)
	local meta = assert(models[key], "unknown model " .. tostring(key))
	local id = factory.create(M.ENTITIES .. "#" .. meta.factory, position, rotation, nil, scale or 1)
	local obj = {id = id, key = key, meta = meta, urls = group_urls(id, meta)}
	if meta.skinned then
		for _, url in ipairs(obj.urls) do
			model.play_anim(url, "b3d", go.PLAYBACK_LOOP_FORWARD, {playback_rate = 0})
		end
	end
	return obj
end

function M.delete(obj)
	if obj then
		go.delete(obj.id, true)
	end
end

function M.set_enabled(obj, on)
	if obj and obj.enabled ~= on then
		obj.enabled = on
		msg.post(obj.id, on and "enable" or "disable")
	end
end

-- Blitz `SetAnimTime`: frame `t` of the model's animation.
function M.seek(obj, t)
	if not obj.meta.skinned or obj.meta.frames <= 0 then
		return
	end
	local cursor = math.max(0, math.min(1, t / obj.meta.frames))
	for _, url in ipairs(obj.urls) do
		go.set(url, "cursor", cursor)
	end
end

-- --- manual skinning (bone-posed models) ------------------------------------------------
-- Some models cannot be posed by Defold's SRT bones: Nature's hierarchy carries shear, and
-- the death soul's flat frost planes have a degenerate scale whose inverse-bind matrix is
-- near-singular (Defold rendered it as a flipped, blown-up ghost). For these the exporter
-- bakes each joint's full world matrix per frame (generated/bones/<slug>.bin) and the
-- shader skins the joint-local vertices through the `bone_matrices` constant we upload here.

local bone_cache = {}  -- model key -> {count, frames, mats = {[frame] = {[joint] = matrix4}}}

-- Decode one little-endian IEEE-754 float at byte offset `i` (LuaJIT has no string.unpack).
local function read_f32(blob, i)
	local b1, b2, b3, b4 = string.byte(blob, i, i + 3)
	local sign = (b4 >= 128) and -1 or 1
	local exp = (b4 % 128) * 2 + math.floor(b3 / 128)
	local mant = (b3 % 128) * 65536 + b2 * 256 + b1
	if exp == 0 then
		return sign * mant * 2 ^ -149
	elseif exp == 255 then
		return mant == 0 and sign * math.huge or 0 / 0
	end
	return sign * (1 + mant / 8388608) * 2 ^ (exp - 127)
end

local function load_bones(meta, key)
	if bone_cache[key] then
		return bone_cache[key]
	end
	local blob = assert(sys.load_resource(meta.bones.resource), "missing bones " .. meta.bones.resource)
	local count, frames = meta.bones.count, meta.bones.frames
	local mats, pos = {}, 1
	for f = 0, frames - 1 do
		local jm = {}
		for j = 1, count do
			local v = {}
			for k = 1, 16 do
				v[k] = read_f32(blob, pos)
				pos = pos + 4
			end
			-- The blob stores each pose matrix row-major; matrix4 takes columns.
			local m = vmath.matrix4()
			m.c0 = vmath.vector4(v[1], v[5], v[9], v[13])
			m.c1 = vmath.vector4(v[2], v[6], v[10], v[14])
			m.c2 = vmath.vector4(v[3], v[7], v[11], v[15])
			m.c3 = vmath.vector4(v[4], v[8], v[12], v[16])
			jm[j] = m
		end
		mats[f] = jm
	end
	bone_cache[key] = {count = count, frames = frames, mats = mats}
	return bone_cache[key]
end

-- Upload the joint poses at frame `t` (two nearest frames lerped) to every group's
-- `bone_matrices`; the array index is the joint index the vertices carry (0-based).
function M.pose(obj, t)
	local c = obj.bones or load_bones(obj.meta, obj.key)
	obj.bones = c
	local maxf = c.frames - 1
	local f = math.max(0, math.min(maxf, t))
	local f0 = math.floor(f)
	local f1 = math.min(f0 + 1, maxf)
	local a = f - f0
	local m0, m1 = c.mats[f0], c.mats[f1]
	for j = 1, c.count do
		local mat
		if a == 0 or f0 == f1 then
			mat = m0[j]
		else
			mat = vmath.matrix4()
			mat.c0 = vmath.lerp(a, m0[j].c0, m1[j].c0)
			mat.c1 = vmath.lerp(a, m0[j].c1, m1[j].c1)
			mat.c2 = vmath.lerp(a, m0[j].c2, m1[j].c2)
			mat.c3 = vmath.lerp(a, m0[j].c3, m1[j].c3)
		end
		-- `index` is 1-based here; the shader reads the 0-based bone_matrices[joint].
		for _, url in ipairs(obj.urls) do
			go.set(url, "bone_matrices", mat, {index = j})
		end
	end
end

function M.set_constant(obj, name, value)
	for _, url in ipairs(obj.urls) do
		go.set(url, name, value)
	end
end

-- Blitz `EntityColor`: `nil` restores the brush colours.
function M.tint(obj, color)
	M.set_constant(obj, "entity_color", color or M.NO_TINT)
end

-- Blitz `EntityAlpha`.
function M.alpha(obj, a)
	M.set_constant(obj, "entity_alpha", vmath.vector4(a, 0, 0, 0))
end

-- B3DEXT_ANIMMAP scroll of the model's brushes at `frame` (`PositionTexture`).
function M.animmaps(obj, frame)
	local maps = obj.meta.animmaps
	if not maps then
		return
	end
	for _, map in ipairs(maps) do
		local keys = map.keys
		local i = math.max(0, math.min(math.floor(frame), #keys - 1))
		local a = keys[i + 1]
		local b = keys[math.min(i + 2, #keys)]
		local f = frame - i
		local u, v = a[1] + (b[1] - a[1]) * f, a[2] + (b[2] - a[2]) * f
		go.set(msg.url(nil, obj.id, map.group), "uv_offset", vmath.vector4(u, v, 0, 0))
	end
end

-- Blitz `AnimateMD2` display: frame a = floor(t), b = a + 1 wrapping to 0 at the last
-- frame; morph target k is frame k + 1 (frame 0 is the base mesh).
function M.md2_frame(obj, t)
	local count = obj.meta.morph_targets
	if count == 0 then
		return
	end
	local a = math.floor(t)
	local b = a + 1
	if b >= M.MD2_LAST_FRAME then
		b = 0
	end
	local f = t - a
	local url = obj.urls[1]
	local weights = model.get_blend_weights(url)
	for k = 1, count do
		local frame = k
		local w = 0
		if frame == a then
			w = w + 1 - f
		end
		if frame == b then
			w = w + f
		end
		weights[k] = w
	end
	model.set_blend_weights(url, weights)
end

-- --- enemies ----------------------------------------------------------------------------

local function model_key(res_path)
	-- "res://assets/models/Monsters/Crawl.glb" -> "Monsters/Crawl"
	return res_path:match("res://assets/models/(.-)%.glb$")
end

function M.enemy_create(e, unit, shadows)
	local pos = M.vec(e.path.body)
	local rot = M.facing_rotation(e.path.facing)
	local view = {enemy = e, faded_in = false, health_lost = -1, health_index = -1, effect_kind = 0, effect_time = 0}
	view.model = M.spawn(model_key(unit.model), pos, rot, e.scale)
	if e.healer ~= 0 then
		-- The healer model is oriented sideways: Blitz turns it 90 degrees every tick.
		view.healer_rot = vmath.quat_rotation_y(math.rad(-90))
	end
	if shadows then
		view.shadow = M.spawn(M.SHADOW_MODEL, pos, rot, e.scale)
	end
	-- Blitz parents the bar to the scaled entity: its height and size grow with it.
	view.health = M.spawn(M.HEALTH_MODEL, pos, rot, e.scale)
	view.health_offset = ((e.air and 1 or 0) + M.HEALTH_BAR_HEIGHT) * e.scale
	M.set_enabled(view.health, false)
	return view
end

-- `_fshowupgradeswindow` hides the monsters (and all they carry) while the window is open.
function M.enemy_set_hidden(view, hidden)
	view.hidden = hidden
	M.set_enabled(view.model, not hidden)
	M.set_enabled(view.shadow, not hidden)
	M.set_enabled(view.effect, not hidden)
	if hidden then
		M.set_enabled(view.health, false)
	end
end

function M.enemy_delete(view)
	M.delete(view.model)
	M.delete(view.shadow)
	M.delete(view.health)
	M.delete(view.effect)
end

function M.enemy_sync(view, cam_rot, show_life, gradient, ticks)
	local e = view.enemy
	local pos = M.vec(e.path.body)
	local rot = M.facing_rotation(e.path.facing)
	local model_rot = view.healer_rot and (rot * view.healer_rot) or rot
	go.set_position(pos, view.model.id)
	go.set_rotation(model_rot, view.model.id)
	if view.shadow then
		go.set_position(pos, view.shadow.id)
		go.set_rotation(rot, view.shadow.id)
	end
	if e.healer == 0 then
		M.md2_frame(view.model, e.md2_time)
	else
		M.seek(view.model, e.md2_time % 10)
	end
	-- Fade in while the path marker is within the first 3 frames.
	local t = e.path.time
	if t < M.FADE_IN_FRAMES then
		local v = math.floor(255 * (t / M.FADE_IN_FRAMES) + 0.5) / 255
		M.tint(view.model, vmath.vector4(v, v, v, 1))
		if view.shadow then
			M.tint(view.shadow, vmath.vector4(v, v, v, 1))
		end
		view.faded_in = false
	elseif not view.faded_in then
		M.tint(view.model, nil)
		if view.shadow then
			M.tint(view.shadow, nil)
		end
		view.faded_in = true
	end
	-- Health bar: faces the camera, seeked to the lost percentage, tinted by the gradient.
	show_life = show_life and not view.hidden
	M.set_enabled(view.health, show_life)
	if show_life then
		go.set_position(vmath.vector3(pos.x, pos.y + view.health_offset, pos.z), view.health.id)
		go.set_rotation(cam_rot, view.health.id)
		local percent = Game.enemy_life_percent(e)
		local lost = math.max(1, math.min(99, 100 - percent))
		if lost ~= view.health_lost then
			view.health_lost = lost
			M.seek(view.health, lost)
		end
		-- `gradient` is 1-based over the bitmap's pixels 0..99: pixel `idx` is `gradient[idx + 1]`.
		local idx = math.max(1, blitz.round_int(percent - 1))
		if idx ~= view.health_index then
			view.health_index = idx
			local c = gradient[math.min(#gradient, idx + 1)]
			M.tint(view.health, vmath.vector4(c[1], c[2], c[3], 1))
		end
	end
	-- Status effect (fire / poison), the view's own clock.
	if e.effect_kind ~= view.effect_kind then
		M.delete(view.effect)
		view.effect = nil
		view.effect_kind = e.effect_kind
		if e.effect_kind ~= 0 then
			local key = (e.effect_kind == Game.EFFECT_FIRE) and M.FIRE_EFFECT or M.POISON_EFFECT
			local s = math.max(0.2, math.min(0.8, e.effect_size)) * e.scale
			view.effect = M.spawn(key, pos, rot, s)
			view.effect_time = 0
			M.set_enabled(view.effect, not view.hidden)
		end
	end
	if view.effect then
		local offset = e.air and 3 or 0
		go.set_position(vmath.vector3(pos.x, pos.y + offset, pos.z), view.effect.id)
		view.effect_time = (view.effect_time + M.EFFECT_SPEED * ticks) % math.max(view.effect.meta.frames, 1)
		M.seek(view.effect, view.effect_time)
	end
end

-- --- towers -----------------------------------------------------------------------------

local TOWER_KEYS = {"Towers/Military", "Towers/Magic", "Towers/Nature", "Towers/Freeze", "Towers/Fire"}
local PLACE_KEYS = {"Towers/MilitaryPlace", "Towers/MagicPlace", "Towers/NaturePlace", "Towers/FreezePlace", "Towers/FirePlace"}
local EFFECT_KEYS = {"Towers/MilitaryEff", "Towers/MagicEff", "Towers/NatureEff", "Towers/FreezeEff", "Towers/MagicEff"}

function M.tower_create(t, ground_texture, tint, location)
	local pos = M.vec(t.position)
	local rot = vmath.quat_rotation_y(math.rad(t.yaw_degrees))
	local view = {tower = t, selection_time = 0}
	view.model = M.spawn(TOWER_KEYS[t.type], pos, rot, 1)
	-- `_fpositiontower`: the base gets the location's ground texture and tint; Icerock
	-- outside location 3 is painted blue. `dno_solid` is the depth-writing copy of the base.
	if view.model.meta.groups.dno then
		local c = (t.type == 4 and location ~= 3) and M.ICEROCK_TINT or vmath.vector4(tint[1], tint[2], tint[3], 1)
		for _, group in ipairs({"dno", "dno_solid"}) do
			if view.model.meta.groups[group] then
				local url = msg.url(nil, view.model.id, group)
				go.set(url, "texture0", ground_texture)
				go.set(url, "entity_color", c)
			end
		end
	end
	view.range = M.spawn(M.RANGE_MODEL, pos, vmath.quat(), vmath.vector3(t.range * 2, 1, t.range * 2))
	M.set_enabled(view.range, false)
	view.selection = M.spawn(M.SELECTION_MODEL, pos, vmath.quat(), 1)
	M.set_enabled(view.selection, false)
	return view
end

function M.tower_delete(view)
	M.delete(view.model)
	M.delete(view.range)
	M.delete(view.selection)
end

-- `uv_frame`: the frame driving the type's shared texture scroll (`_fupdateextanims`
-- updates one tower per type), or nil for this tower's own frame.
function M.tower_sync(view, uv_frame, ticks)
	local t = view.tower
	local frame = Game.tower_model_frame(t)
	if view.model.meta.bones then
		M.pose(view.model, frame)
	else
		M.seek(view.model, frame)
	end
	M.animmaps(view.model, uv_frame or frame)
	M.set_enabled(view.range, t.selected)
	M.set_enabled(view.selection, t.selected)
	if t.selected then
		go.set_scale(vmath.vector3(t.range * 2, 1, t.range * 2), view.range.id)
		view.selection_time = (view.selection_time + M.SELECTION_SPEED * ticks) % math.max(view.selection.meta.frames, 1)
		M.seek(view.selection, view.selection_time)
	end
end

-- --- placement marker -------------------------------------------------------------------

function M.marker_create(type_id, range)
	local view = {allowed = nil}
	view.marker = M.spawn(PLACE_KEYS[type_id], vmath.vector3(0, -100, 0), vmath.quat(), 1)
	view.range = M.spawn(M.RANGE_MODEL, vmath.vector3(0, -100, 0), vmath.quat(), vmath.vector3(range * 2, 1, range * 2))
	M.marker_set(view, nil, false)
	return view
end

function M.marker_delete(view)
	M.delete(view.marker)
	M.delete(view.range)
end

-- `pos` nil hides the marker; the range circle shows only where building is allowed.
function M.marker_set(view, pos, allowed)
	M.set_enabled(view.marker, pos ~= nil)
	M.set_enabled(view.range, pos ~= nil and allowed)
	if pos then
		go.set_position(pos, view.marker.id)
		go.set_position(pos, view.range.id)
	end
	if allowed ~= view.allowed then
		view.allowed = allowed
		M.tint(view.marker, allowed and M.COLOR_OK or M.COLOR_BAD)
	end
end

-- --- bullets and one-shot effects -------------------------------------------------------

function M.bullet_create(b)
	local key = model_key(b.model or "")
	local view = {bullet = b}
	if key and models[key] then
		view.model = M.spawn(key, M.vec(b.position), M.facing_rotation(b.direction), 1)
	end
	return view
end

function M.bullet_sync(view)
	if view.model then
		local b = view.bullet
		go.set_position(M.vec(b.position), view.model.id)
		local d = b.direction
		if d.x * d.x + d.z * d.z > 1e-6 then
			go.set_rotation(M.facing_rotation(d), view.model.id)
		end
	end
end

function M.bullet_delete(view)
	M.delete(view.model)
end

function M.effect_key(tower_type)
	return EFFECT_KEYS[tower_type]
end

-- Pose a one-shot at frame `t`. A bone-posed model (the death soul: its flat frost planes
-- have a degenerate scale Defold's SRT skinning cannot invert) is driven by baked bone
-- matrices, not by Defold's animation cursor, so it needs M.pose rather than M.seek.
function M.one_shot_pose(obj, t)
	if obj.meta.bones then
		M.pose(obj, t)
	else
		M.seek(obj, t)
	end
end

-- A one-shot Blitz animation (explosion, death ghost): the whole `b3d` animation at
-- `speed` frames per tick; `fade_frames` > 0 applies `_fupdatedeathanims`' alpha fade.
function M.one_shot(key, position, scale, speed, fade_frames)
	local obj = M.spawn(key, position, vmath.quat(), scale)
	local shot = {obj = obj, time = 0, speed = speed, length = obj.meta.frames, fade = fade_frames or 0}
	M.one_shot_pose(obj, 0)
	M.animmaps(obj, 0)
	return shot
end

-- Advance `ticks`; returns true when finished (and deleted).
function M.one_shot_tick(shot, ticks)
	shot.time = shot.time + shot.speed * ticks
	local done = shot.time >= shot.length
	if done then
		shot.time = shot.length
	end
	M.one_shot_pose(shot.obj, shot.time)
	M.animmaps(shot.obj, shot.time)
	if shot.fade > 0 then
		M.alpha(shot.obj, math.max(0, (shot.length - shot.time) / shot.fade))
	end
	if done then
		M.delete(shot.obj)
	end
	return done
end

return M
