-- A Blitz menu sheet (`Menu/*.b3d`, docs/09): a bone-posed model hanging 10 units in front
-- of the camera (drawn by the render script's fixed overlay camera), with named item
-- meshes ("punkts") picked by the mouse (`_fcreatepunkt` / `_fhandlepunkts`). The sheet is
-- seeked like Blitz's `Animate` / `SetAnimTime`; items are hidden through their joint's
-- pose, and the `sel` cursor is laid onto the hovered item with the original's brightness
-- ramp. The owning screen script ticks it and forwards clicks.
local model = require("main.views.model")
local picking = require("main.picking")
local menus = require("generated.menus")
local messages = require("main.messages")
local screen = require("main.screen")

local M = {}
M.__index = M

M.ANIM_NONE, M.ANIM_LOOP, M.ANIM_ONESHOT = 0, 1, 3
M.SHEET_OFFSET = vmath.vector3(0, 0, -10)  -- `EntityParent(sheet, camera)` + `MoveEntity 0, 0, 10`

local SEL_MODEL = "Menu/sel"
local SEL_SPEED, SEL_FIRST, SEL_LAST = 0.2, 3.0, 13.0
local SEL_BRIGHT_STEP, SEL_BRIGHT_MAX = 0.2, 0.9
local SEL_FADE_STEP, SEL_FADE_MIN = 0.05, 0.1
local CURSOR_TURN = vmath.quat_rotation_x(-math.pi / 2)  -- Blitz `TurnEntity sel, 90, 0, 0`

-- The pick ray of box point (x, y) (y down) from the overlay camera at the origin.
function M.overlay_ray(x, y)
	return picking.ray(vmath.vector3(), vmath.quat(), x, screen.HEIGHT - y, screen.WIDTH, screen.HEIGHT)
end

-- Rotation quaternion of an orthonormal basis given by columns.
local function quat_from_basis(x, y, z)
	local trace = x.x + y.y + z.z
	if trace > 0 then
		local s = math.sqrt(trace + 1) * 2
		return vmath.quat((y.z - z.y) / s, (z.x - x.z) / s, (x.y - y.x) / s, 0.25 * s)
	elseif x.x > y.y and x.x > z.z then
		local s = math.sqrt(1 + x.x - y.y - z.z) * 2
		return vmath.quat(0.25 * s, (y.x + x.y) / s, (z.x + x.z) / s, (y.z - z.y) / s)
	elseif y.y > z.z then
		local s = math.sqrt(1 + y.y - x.x - z.z) * 2
		return vmath.quat((y.x + x.y) / s, 0.25 * s, (z.y + y.z) / s, (z.x - x.z) / s)
	end
	local s = math.sqrt(1 + z.z - x.x - y.y) * 2
	return vmath.quat((z.x + x.z) / s, (z.y + y.z) / s, 0.25 * s, (x.y - y.x) / s)
end

-- Position, rotation and scale of a matrix (its basis normalized for the rotation).
function M.decompose(m)
	local x = vmath.vector3(m.c0.x, m.c0.y, m.c0.z)
	local y = vmath.vector3(m.c1.x, m.c1.y, m.c1.z)
	local z = vmath.vector3(m.c2.x, m.c2.y, m.c2.z)
	local scale = vmath.vector3(vmath.length(x), vmath.length(y), vmath.length(z))
	return vmath.vector3(m.c3.x, m.c3.y, m.c3.z), quat_from_basis(vmath.normalize(x), vmath.normalize(y), vmath.normalize(z)), scale
end

-- Box point (y down) of world point `p` seen by the overlay camera, or nil behind it.
function M.project_overlay(p)
	if p.z >= 0 then
		return nil
	end
	local t = math.tan(screen.FOV / 2)
	local nx = p.x / -p.z / (t * screen.ASPECT)
	local ny = p.y / -p.z / t
	return (nx + 1) / 2 * screen.WIDTH, (1 - ny) / 2 * screen.HEIGHT
end

-- `id`: the sheet's game object (instanced in the screen's collection); `key`: its model;
-- `items`: names of the pickable item nodes; `cursor_id`: the `sel` object, or nil.
function M.new(id, key, items, cursor_id)
	local self = setmetatable({}, M)
	self.obj = model.attach(id, key)
	self.pick_data = assert(menus[key], "no menu data for " .. key).pick
	self.items = {}
	for _, name in ipairs(items or {}) do
		assert(self.pick_data[name], key .. ": no item " .. name)
		self.items[name] = true
	end
	self.hidden = {}     -- joint index -> true (the node or an ancestor is hidden)
	self.hidden_nodes = {}  -- joint index -> true (hidden itself)
	self.offsets = {}       -- joint index -> vector3: the node (and its children) moved
	self.disabled = {}   -- item -> true (`EntityPickMode 0`: visible, not pickable)
	self.passive = {}    -- item -> true (pickable, never hovered or clicked: slider backs)
	self.time, self.speed, self.mode = 0, 0, M.ANIM_NONE
	self.first, self.last = 0, self.obj.meta.frames
	self.enabled = true  -- takes hover and clicks
	self.visible = true
	self.hovered = nil
	if cursor_id then
		self.cursor = {obj = model.attach(cursor_id, SEL_MODEL), time = SEL_FIRST, brightness = 0, shown = false}
		model.set_enabled(self.cursor.obj, false)
	end
	self:pose()
	return self
end

function M:pose()
	-- Empty sets pose plainly: model.pose then skips an unchanged frame and resends only the
	-- animated joints.
	model.pose(self.obj, self.time, next(self.hidden) and self.hidden or nil, next(self.offsets) and self.offsets or nil)
end

-- Move node `name` and its children by `delta` in the sheet's space, through the whole
-- animation (the Godot port's `offset_item`).
function M:offset_node(name, delta)
	local j = self.obj.meta.joints[name]
	local parents = self.obj.meta.joint_parents
	local moved = {[j] = true}
	for k = 1, #parents do  -- parents precede their children
		if moved[k] or (parents[k] > 0 and moved[parents[k]]) then
			moved[k] = true
			self.offsets[k] = (self.offsets[k] or vmath.vector3()) + delta
		end
	end
	self:pose()
end

-- Blitz `Animate(sheet, mode, speed)` over the whole clip.
function M:animate(mode, speed)
	self:animate_range(mode, speed, 0, self.obj.meta.frames)
end

-- `Animate` of an extracted sequence `first..last`: a negative speed runs from `last` back
-- to `first` and stops there.
function M:animate_range(mode, speed, first, last)
	self.mode, self.speed, self.first, self.last = mode, speed, first, last
	self.time = speed >= 0 and first or last
	self:pose()
end

function M:seek(t)
	self.mode, self.time = M.ANIM_NONE, t
	self:pose()
end

function M:animating()
	return self.mode ~= M.ANIM_NONE
end

function M:set_visible(on)
	self.visible = on
	model.set_enabled(self.obj, on)
	if not on then
		-- The cursor goes with the sheet (it would otherwise stay frozen where it was).
		self:set_hovered(nil)
		if self.cursor then
			self.cursor.shown = false
			model.set_enabled(self.cursor.obj, false)
		end
	end
end

local function joint_of(self, name)
	return self.obj.meta.joints[name]
end

-- Blitz `HideEntity` / `ShowEntity` of node `name` (its children go with it).
function M:set_node_visible(name, on)
	local j = joint_of(self, name)
	if not j then
		return
	end
	self.hidden_nodes[j] = (not on) or nil
	local parents = self.obj.meta.joint_parents
	self.hidden = {}
	for k = 1, #parents do  -- parents precede their children
		local p = parents[k]
		self.hidden[k] = self.hidden_nodes[k] or (p > 0 and self.hidden[p]) or nil
	end
	self:pose()
end

-- The `titul` plank of the main menu and the map: hidden below difficulty tier 1, else
-- `Titul<tier>.png` (`textures[tier]`: the screen's texture resources).
function M:set_titul(tier, textures)
	if tier < 1 then
		self:set_node_visible("titul", false)
		return
	end
	model.set_group(self.obj, "titul", "texture0", textures[math.min(tier, #textures)])
end

-- `EntityPickMode 0` / `2`: a visible item that cannot / can be picked.
function M:set_item_enabled(name, on)
	self.disabled[name] = (not on) or nil
end

function M:set_item_passive(name)
	self.items[name] = true
	self.passive[name] = true
end

-- The node's model-to-world matrix at frame `t` (the current one by default).
function M:node_matrix(name, t)
	local sheet = go.get_world_transform(self.obj.id)
	local j = joint_of(self, name)
	local m = model.joint_matrix(self.obj, t or self.time, j)
	if self.offsets[j] then
		m = vmath.matrix4_translation(self.offsets[j]) * m
	end
	return sheet * m
end

-- Centre nodes `names` as a group on the sheet's axis (at the end of its animation).
function M:center_nodes(names)
	local sum = 0
	for _, name in ipairs(names) do
		sum = sum + model.joint_matrix(self.obj, self.obj.meta.frames, joint_of(self, name)).c3.x
	end
	local delta = vmath.vector3(-sum / #names, 0, 0)
	for _, name in ipairs(names) do
		self:offset_node(name, delta)
	end
end

-- Place the whole sheet like a child of another sheet's node (Blitz `EntityParent`).
function M:follow(matrix)
	local pos, rot, scale = M.decompose(matrix)
	go.set_position(pos, self.obj.id)
	go.set_rotation(rot, self.obj.id)
	go.set_scale(scale, self.obj.id)
end

-- Box point (y down) of item `name`'s origin seen by the overlay camera (at frame `t`, the
-- current one by default).
function M:screen_point(name, t)
	local m = self:node_matrix(name, t)
	return M.project_overlay(vmath.vector3(m.c3.x, m.c3.y, m.c3.z))
end

-- The item under box point (x, y), or nil (passive items included).
function M:pick(x, y)
	if not self.visible then
		return nil
	end
	local o, d = M.overlay_ray(x, y)
	local best, best_name
	for name in pairs(self.items) do
		local j = joint_of(self, name)
		if not self.disabled[name] and not self.hidden[j] then
			local inv = vmath.inv(self:node_matrix(name))
			local lo = inv * vmath.vector4(o.x, o.y, o.z, 1)
			local ld = inv * vmath.vector4(d.x, d.y, d.z, 0)
			local dist = picking.hit_triangles(self.pick_data[name].tris, vmath.vector3(lo.x, lo.y, lo.z), vmath.vector3(ld.x, ld.y, ld.z))
			if dist and (not best or dist < best) then
				best, best_name = dist, name
			end
		end
	end
	return best_name
end

-- Lay the cursor onto item `name` (`AlignEntity` + `OrientEntity`, then turned 90 degrees).
local function place_cursor(self, name)
	local pos, rot = M.decompose(self:node_matrix(name))
	go.set_position(pos, self.cursor.obj.id)
	go.set_rotation(rot * CURSOR_TURN, self.cursor.obj.id)
end

function M:set_hovered(name)
	if name == self.hovered then
		return
	end
	if name and self.cursor then
		if not self.hovered then
			msg.post(messages.AUDIO, messages.PLAY_SOUND, {name = "rebutton"})
		end
		place_cursor(self, name)
		self.cursor.shown = true
		self.cursor.brightness = 0
		model.set_enabled(self.cursor.obj, true)
	end
	self.hovered = name
end

-- One logic tick: the sheet's animation, hover under box point (x, y), the cursor ramp.
function M:tick(x, y)
	if self.mode ~= M.ANIM_NONE then
		self.time = self.time + self.speed
		if self.mode == M.ANIM_LOOP then
			self.time = self.first + (self.time - self.first) % (self.last - self.first)
		elseif self.speed < 0 and self.time <= self.first then
			self.time, self.mode = self.first, M.ANIM_NONE
		elseif self.speed > 0 and self.time >= self.last then
			self.time, self.mode = self.last, M.ANIM_NONE
		end
		self:pose()
	end
	local over = (self.enabled and x) and self:pick(x, y) or nil
	if over and self.passive[over] then
		over = nil
	end
	self:set_hovered(over)
	local c = self.cursor
	if not c or not c.shown then
		return
	end
	if self.hovered then
		-- Up by 0.2 a tick to 0.9, then to 1.0 (docs/09).
		if c.brightness < SEL_BRIGHT_MAX and c.brightness + SEL_BRIGHT_STEP >= SEL_BRIGHT_MAX then
			c.brightness = SEL_BRIGHT_MAX
		else
			c.brightness = math.min(c.brightness + SEL_BRIGHT_STEP, 1)
		end
		place_cursor(self, self.hovered)
	else
		c.brightness = c.brightness - SEL_FADE_STEP
		if c.brightness <= SEL_FADE_MIN then
			c.shown = false
			model.set_enabled(c.obj, false)
			return
		end
	end
	local b = c.brightness
	model.tint(c.obj, vmath.vector4(b, b, b, 1))
	c.time = c.time + SEL_SPEED
	if c.time >= SEL_LAST then
		c.time = SEL_FIRST
	end
	model.pose(c.obj, c.time)
	model.animmaps(c.obj, c.time)
end

-- The item clicked at box point (x, y), or nil; plays the click.
function M:click(x, y)
	if not self.enabled then
		return nil
	end
	local name = self:pick(x, y)
	if name and not self.passive[name] then
		msg.post(messages.AUDIO, messages.PLAY_SOUND, {name = "click"})
		return name
	end
	return nil
end

return M
