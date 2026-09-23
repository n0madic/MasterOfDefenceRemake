-- Model objects spawned from the generated factories (generated/models.lua) and seeked to
-- the simulation's frames every frame like Blitz did: the game never plays animations, it
-- sets AnimTime. The other view modules build on these primitives.
local models = require("generated.models")

local M = {}

-- Game object holding the factories (main/location/location.collection), relative to the
-- screen's scripts.
M.ENTITIES = "entities"
M.MD2_LAST_FRAME = 10
M.NO_TINT = vmath.vector4(1, 1, 1, 0)

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

-- A view of an object that is part of a collection rather than spawned (a location's
-- scene): `id` is its instance id.
function M.attach(id, key)
	local meta = assert(models[key], "unknown model " .. tostring(key))
	return {id = id, key = key, meta = meta, urls = group_urls(id, meta)}
end

-- Blitz `EntityTexture(entity, anim_texture, frame)` for the model's animated-texture
-- groups (generated `frame_atlases`): show frame `frame` (0-based) of `atlas`.
function M.set_atlas_frame(obj, atlas, frame)
	local col = frame % atlas.columns
	local row = math.floor(frame / atlas.columns)
	local w, h = 1 / atlas.columns, 1 / atlas.rows
	-- Blitz numbers the frames from the image's top-left; Defold's texture origin is its
	-- bottom-left.
	go.set(msg.url(nil, obj.id, atlas.group), "frame_atlas", vmath.vector4(col * w, 1 - (row + 1) * h, w, h))
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

-- Frame `t` through Defold's animation cursor (a skinned model; see `M.set_frame`).
local function seek(obj, t)
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

local ZERO = vmath.matrix4()
ZERO.c0, ZERO.c1, ZERO.c2, ZERO.c3 = vmath.vector4(), vmath.vector4(), vmath.vector4(), vmath.vector4()
-- The `go.set` options addressing `bone_matrices[j]`, built once per joint index.
local JOINT_INDEX = setmetatable({}, {__index = function(t, j)
	local options = {index = j}
	rawset(t, j, options)
	return options
end})

-- The model-space matrix of joint `j` (1-based) of a bone-posed model at frame `t`, the two
-- nearest baked frames lerped.
function M.joint_matrix(obj, t, j)
	local c = obj.bones or load_bones(obj.meta, obj.key)
	obj.bones = c
	local maxf = c.frames - 1
	local f = math.max(0, math.min(maxf, t))
	local f0 = math.floor(f)
	local f1 = math.min(f0 + 1, maxf)
	local a = f - f0
	local m0 = c.mats[f0][j]
	if a == 0 or f0 == f1 then
		return m0
	end
	local m1 = c.mats[f1][j]
	local mat = vmath.matrix4()
	mat.c0 = vmath.lerp(a, m0.c0, m1.c0)
	mat.c1 = vmath.lerp(a, m0.c1, m1.c1)
	mat.c2 = vmath.lerp(a, m0.c2, m1.c2)
	mat.c3 = vmath.lerp(a, m0.c3, m1.c3)
	return mat
end

-- Upload the joint poses at frame `t` to every group's `bone_matrices`; the array index is
-- the joint index the vertices carry (0-based in the shader). Joints in `hidden` (a set of
-- 1-based indices) collapse to a zero matrix: Blitz `HideEntity` of that node; `offsets`
-- (joint -> vector3) move a joint in the model's space.
function M.pose(obj, t, hidden, offsets)
	-- A plain pose at the frame already uploaded changes nothing (a tower idling at a
	-- frame, a view synced twice between ticks).
	if hidden or offsets then
		obj.posed_t = nil
	elseif obj.posed_t == t then
		return
	else
		obj.posed_t = t
	end
	local c = obj.bones or load_bones(obj.meta, obj.key)
	obj.bones = c
	for j = 1, c.count do
		local mat = (hidden and hidden[j]) and ZERO or M.joint_matrix(obj, t, j)
		local offset = offsets and offsets[j]
		if offset and mat ~= ZERO then
			mat = vmath.matrix4_translation(offset) * mat
		end
		-- `index` is 1-based here; the shader reads the 0-based bone_matrices[joint].
		for _, url in ipairs(obj.urls) do
			go.set(url, "bone_matrices", mat, JOINT_INDEX[j])
		end
	end
end

-- Blitz `SetAnimTime`: frame `t` of the model's animation, whichever way the exporter posed
-- it: baked bone matrices (a bone-posed model -- e.g. the death soul, whose flat frost
-- planes Defold's SRT skinning cannot invert -- has no Defold animation to seek) or the
-- animation cursor. A static model has neither.
function M.set_frame(obj, t)
	if obj.meta.bones then
		M.pose(obj, t)
	else
		seek(obj, t)
	end
end

function M.set_constant(obj, name, value)
	for _, url in ipairs(obj.urls) do
		go.set(url, name, value)
	end
end

-- A keyframed pose (`{pos = {x, y, z}, rot = {x, y, z, w}}` per frame, the exporter's
-- camera flight and bird path) at frame `t`: lerped position, slerped rotation. Past the
-- last frame `wrap` loops to the first, else the last holds.
function M.sample_pose(frames, t, wrap)
	local f0 = math.floor(t)
	local f1
	if wrap then
		f0 = f0 % #frames
		f1 = (f0 + 1) % #frames
	else
		f0 = math.max(0, math.min(#frames - 1, f0))
		f1 = math.min(f0 + 1, #frames - 1)
	end
	local a = t - math.floor(t)
	local p0, p1 = frames[f0 + 1].pos, frames[f1 + 1].pos
	local r0, r1 = frames[f0 + 1].rot, frames[f1 + 1].rot
	return vmath.lerp(a, vmath.vector3(p0[1], p0[2], p0[3]), vmath.vector3(p1[1], p1[2], p1[3])),
		vmath.slerp(a, vmath.quat(r0[1], r0[2], r0[3], r0[4]), vmath.quat(r1[1], r1[2], r1[3], r1[4]))
end

-- `go.set` of a material property of model group `group` and of its depth companion
-- (`<group>_solid`, the exporter's alpha-scissor copy, which must cut the same texels).
function M.set_group(obj, group, property, value)
	for _, g in ipairs({group, group .. "_solid"}) do
		if obj.meta.groups[g] then
			go.set(msg.url(nil, obj.id, g), property, value)
		end
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
		obj.map_urls = obj.map_urls or {}
		local url = obj.map_urls[map.group]
		if not url then
			url = msg.url(nil, obj.id, map.group)
			obj.map_urls[map.group] = url
		end
		go.set(url, "uv_offset", vmath.vector4(u, v, 0, 0))
	end
end

-- Blitz `AnimateMD2` display: frame a = floor(t), b = a + 1 wrapping to 0 at `last` (the
-- monsters' 10 by default); morph target k is frame k + 1 (frame 0 is the base mesh).
function M.md2_frame(obj, t, last)
	local count = obj.meta.morph_targets
	if count == 0 then
		return
	end
	local a = math.floor(t)
	local b = a + 1
	if b >= (last or M.MD2_LAST_FRAME) then
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

-- Model key of a data table's resource path: "res://assets/models/Monsters/Crawl.glb" ->
-- "Monsters/Crawl".
function M.key_of(res_path)
	return res_path:match("res://assets/models/(.-)%.glb$")
end

function M.exists(key)
	return models[key] ~= nil
end

return M
