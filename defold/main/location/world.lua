-- The 3D side of a location: turns simulation events into views and syncs the views to
-- the simulation after every frame's ticks. Views are keyed by the simulation object
-- itself: `_fdeleteenemy` / `_fdeletebullet` clear the object's `id` right after emitting
-- the event, and the events are drained after the tick loop.
local model = require("main.views.model")
local enemy_view = require("main.views.enemy")
local tower_view = require("main.views.tower")
local effects = require("main.views.effects")
local common = require("generated.common")
local data = require("sim.data")
local Game = require("sim.game")

local M = {}
M.__index = M

local PANEL_OFFSET = vmath.vector3(0, 0, -10)  -- Blitz MoveEntity(env, 0, 0, 10)
local WORKER_PORTRAIT_FRAME = 30.99
local PREVIEW_TOWER_TYPES = {data.TOWER_ICEROCK, data.TOWER_FLAME}
local BALLOON_MODEL, HERE_MODEL, BOMB_MODEL = "Towers/Balloon", "Towers/here", "Towers/military3"
local BALLOON_ANIM_SPEED = 0.03
local HERE_ANIM_SPEED = 0.5
local BALLOON_SHADOW_Y = 0.01
local BOMB_BLAST_SCALE = 1.2  -- `landExpl` scaled 1.2
local ENEMY_SELECTION_MODEL = "Towers/selmonster"
local HIDDEN_POSITION = vmath.vector3(0, -100, 0)

-- `location`: generated/locations entry; `ground_texture`: the tower base texture.
function M.new(game_data, location, ground_texture)
	local self = setmetatable({}, M)
	self.data = game_data
	self.location = location
	self.ground_texture = ground_texture
	self.enemies, self.towers, self.bullets, self.one_shots, self.bombs = {}, {}, {}, {}, {}
	self.preview_anim_time = 0
	self.enemies_hidden = false
	-- The HUD panel and the monster portrait: fixed overlays at a fixed world position,
	-- drawn by the render script's fixed HUD camera so they never move with the world.
	self.env = model.spawn("Env", PANEL_OFFSET, vmath.quat(), 1)
	for _, group in ipairs({"window", "updates"}) do
		if self.env.meta.groups[group] then
			msg.post(msg.url(nil, self.env.id, group), "disable")
		end
	end
	self.faces = model.spawn("faces", PANEL_OFFSET, vmath.quat(), 1)
	model.set_enabled(self.faces, false)
	-- `_vselectionmonstermesh`: the ring under the selected monster.
	self.enemy_selection = {obj = model.spawn(ENEMY_SELECTION_MODEL, HIDDEN_POSITION, vmath.quat(), 1), rotation = vmath.quat()}
	model.set_enabled(self.enemy_selection.obj, false)
	-- The location's own scene (instance `scene` of the location collection) and the frame
	-- clocks of its animated textures (`_fupdatelocation`: river and border).
	self.scene = model.attach(go.get_id("scene"), "Location" .. location.location)
	self.atlas_frames = {}
	for _, atlas in ipairs(self.scene.meta.frame_atlases or {}) do
		self.atlas_frames[atlas] = 0
		model.set_atlas_frame(self.scene, atlas, 0)
	end
	return self
end

-- `_fcreateballoon`: the balloon, its shadow on the ground (not on location 6) and the
-- destination marker.
function M:create_balloon(balloon)
	local p = model.vec(balloon.position)
	local view = {balloon = balloon, time = 0, here_time = nil, here_for = nil}
	view.model = model.spawn(BALLOON_MODEL, p, vmath.quat(), 1)
	if self.location.shadows then
		view.shadow = model.spawn(enemy_view.SHADOW_MODEL, vmath.vector3(p.x, BALLOON_SHADOW_Y, p.z), vmath.quat(), 1)
	end
	view.here = model.spawn(HERE_MODEL, p, vmath.quat(), 1)
	model.set_enabled(view.here, false)
	self.balloon = view
end

local function sync_balloon(view, ticks)
	local b = view.balloon
	local rot = vmath.quat_rotation_y(math.rad(b.yaw))
	local p = model.vec(b.position)
	go.set_position(p, view.model.id)
	go.set_rotation(rot, view.model.id)
	if view.shadow then
		go.set_position(vmath.vector3(p.x, BALLOON_SHADOW_Y, p.z), view.shadow.id)
		go.set_rotation(rot, view.shadow.id)
	end
	view.time = (view.time + BALLOON_ANIM_SPEED * ticks) % math.max(view.model.meta.frames, 1)
	model.set_frame(view.model, view.time)
	-- The marker plays once where the player sent the balloon.
	if b.here and b.here ~= view.here_for then
		view.here_for, view.here_time = b.here, 0
		go.set_position(vmath.vector3(b.here.x, b.here.y + 0.01, b.here.z), view.here.id)
		model.set_enabled(view.here, true)
	end
	if view.here_time then
		view.here_time = view.here_time + HERE_ANIM_SPEED * ticks
		if view.here_time >= view.here.meta.frames then
			view.here_time = nil
			model.set_enabled(view.here, false)
		else
			model.set_frame(view.here, view.here_time)
		end
	end
end

-- `_fupdatelocation`, once per tick: the river steps a frame (63 shown), the border half a
-- frame (8 shown).
function M:sync_scene(ticks)
	for atlas, frame in pairs(self.atlas_frames) do
		local next_frame = (frame + atlas.step * ticks) % atlas.frames
		self.atlas_frames[atlas] = next_frame
		if math.floor(next_frame) ~= math.floor(frame) then
			model.set_atlas_frame(self.scene, atlas, math.floor(next_frame))
		end
	end
end

-- Mirror every live simulation object (after simulating without views).
function M:rebuild(game)
	for _, t in ipairs(game.towers) do
		self:on_event({type = "tower_built", tower = t})
	end
	for _, e in ipairs(game.enemies) do
		self:on_event({type = "enemy_spawned", enemy = e})
	end
	for _, b in ipairs(game.bullets) do
		self:on_event({type = "bullet_created", bullet = b})
	end
end

local function remove(set, key, delete)
	local v = set[key]
	if v then
		set[key] = nil
		delete(v)
	end
end

-- Handle one simulation event; returns true if it was a view event.
function M:on_event(ev)
	local kind = ev.type
	if kind == "enemy_spawned" then
		local v = enemy_view.create(ev.enemy, self.data:unit(ev.enemy.unit_id), self.location.shadows)
		if self.enemies_hidden then
			enemy_view.set_hidden(v, true)
		end
		self.enemies[ev.enemy] = v
	elseif kind == "enemy_died" then
		remove(self.enemies, ev.enemy, enemy_view.delete)
		if ev.killed then
			self.one_shots[#self.one_shots + 1] = effects.one_shot(effects.DEATH_MODEL, model.vec(ev.enemy.path.body), 1, effects.ONE_SHOT_SPEED, effects.DEATH_FADE_FRAMES)
		end
	elseif kind == "tower_built" then
		self.towers[ev.tower] = tower_view.create(ev.tower, self.ground_texture, self.location.tower_tint, self.location.location)
	elseif kind == "tower_removed" then
		remove(self.towers, ev.tower, tower_view.delete)
	elseif kind == "bomb_dropped" then
		self.bombs[ev.bomb] = model.spawn(BOMB_MODEL, model.vec(ev.bomb.position), vmath.quat(), 1)
	elseif kind == "bomb_removed" then
		remove(self.bombs, ev.bomb, model.delete)
		if ev.exploded then
			self.one_shots[#self.one_shots + 1] = effects.one_shot(effects.effect_key(data.TOWER_LAND), model.vec(ev.bomb.position), BOMB_BLAST_SCALE, effects.ONE_SHOT_SPEED)
		end
	elseif kind == "bullet_created" then
		self.bullets[ev.bullet] = effects.bullet_create(ev.bullet)
	elseif kind == "bullet_removed" then
		remove(self.bullets, ev.bullet, effects.bullet_delete)
		local t = ev.bullet.tower
		if ev.exploded and t and t.type ~= data.TOWER_FLAME then
			local s = math.max(effects.EXPLOSION_MIN_SCALE, t.level / math.max(t.max_upgrades, 1) * effects.EXPLOSION_SCALE_FACTOR)
			self.one_shots[#self.one_shots + 1] = effects.one_shot(effects.effect_key(t.type), model.vec(ev.bullet.position), s, effects.ONE_SHOT_SPEED)
		end
	else
		return false
	end
	return true
end

-- `_fshowupgradeswindow` / `_fshowingamemenu` hide the monsters while they are up.
function M:set_enemies_hidden(hidden)
	self.enemies_hidden = hidden
	for _, v in pairs(self.enemies) do
		enemy_view.set_hidden(v, hidden)
	end
end

-- The skills sheet of the HUD panel (`updates`).
function M:set_skills_panel(shown)
	if self.env.meta.groups.updates then
		msg.post(msg.url(nil, self.env.id, "updates"), shown and "enable" or "disable")
	end
end

-- `_fselectenemy` moves the ring to the monster and parents it keeping its world transform
-- (`_fdeselectallenemies` unparents it the same way): from the pick on it follows the
-- monster's moves and turns. It is hidden with the monster it rides.
function M:sync_enemy_selection(game)
	local sel = self.enemy_selection
	local e = game.selected_enemy
	local v = e and self.enemies[e]
	model.set_enabled(sel.obj, v ~= nil and not v.hidden)
	if not v then
		sel.enemy = nil
		return
	end
	local rot = model.facing_rotation(e.path.facing)
	if sel.enemy ~= e then
		sel.enemy = e
		sel.local_rotation = vmath.conj(rot) * sel.rotation
	end
	sel.rotation = rot * sel.local_rotation
	go.set_position(model.vec(e.path.body), sel.obj.id)
	go.set_rotation(sel.rotation, sel.obj.id)
end

-- Sync every view to the simulation after `ticks` ticks; `cam_rot` turns the health bars.
function M:sync(game, ticks, cam_rot)
	self:sync_scene(ticks)
	for _, v in pairs(self.enemies) do
		enemy_view.sync(v, cam_rot, game.show_units_life, common.gradient, ticks)
	end
	self:sync_enemy_selection(game)
	-- `_fupdateextanims`: the shared texture of a tower type scrolls with its first tower;
	-- Icerock / Flame follow the hidden level-0 preview tower's idle loop.
	self.preview_anim_time = (self.preview_anim_time + Game.ANIM_SPEED * ticks) % Game.SEQ_FRAMES
	local uv_driver = {}
	for _, type_id in ipairs(PREVIEW_TOWER_TYPES) do
		uv_driver[type_id] = self.preview_anim_time
	end
	for _, t in ipairs(game.towers) do
		if not uv_driver[t.type] then
			uv_driver[t.type] = Game.tower_model_frame(t)
		end
	end
	for _, v in pairs(self.towers) do
		tower_view.sync(v, uv_driver[v.tower.type], ticks)
	end
	for _, v in pairs(self.bullets) do
		effects.bullet_sync(v)
	end
	for bomb, obj in pairs(self.bombs) do
		go.set_position(model.vec(bomb.position), obj.id)
	end
	if game.balloon and not self.balloon then
		self:create_balloon(game.balloon)
	end
	if self.balloon then
		sync_balloon(self.balloon, ticks)
	end
	for i = #self.one_shots, 1, -1 do
		if effects.one_shot_tick(self.one_shots[i], ticks) then
			table.remove(self.one_shots, i)
		end
	end
	-- Portrait of the selected monster.
	local e = game.selected_enemy
	model.set_enabled(self.faces, e ~= nil and not self.enemies_hidden)
	if e then
		local frame = e.worker and WORKER_PORTRAIT_FRAME or (e.unit_id - 1)
		model.set_frame(self.faces, frame)
		model.animmaps(self.faces, frame)
	end
end

return M
