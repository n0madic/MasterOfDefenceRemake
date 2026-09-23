-- The whole game simulation (`_fgamelogic` + `UpdateWorld(1)`): what the original kept in
-- `_v*` globals plus the enemy, tower and bullet lists. Nothing here touches the engine;
-- views read the state and drain `game.events` once per frame.
local blitz = require("sim.blitz")
local vec3 = require("sim.vec3")
local data = require("sim.data")
local PathFollower = require("sim.path_follower")
local Skills = require("sim.skills")
local balance = require("sim.balance")
local savegame = require("sim.savegame")
local profile = require("sim.profile")
local Balloon = require("sim.balloon")
local Survival = require("sim.survival")

local f32 = blitz.f32

local M = {}
M.__index = M

M.MSG_WHITE, M.MSG_RED, M.MSG_GOLD, M.MSG_GREEN = 1, 2, 3, 4
M.INGAME_TIME_STEP = 0.01
M.RAID_WAIT_TIME = 10.0
M.SPAWN_INTERVAL = 0.4
M.EXTRA_LIFE_TIME_MIN, M.EXTRA_LIFE_TIME_MAX = 6.0, 6.01
M.BOSS_RAID_MAX_MONSTERS = 4
M.RAID_EXPERIENCE = 20
M.CAMPAIGN_INCOME_BASE = 100.0
M.ENEMY_SCALE_PER_RAID = 250.0
M.BOSS_SCALE = 0.64
M.DEATH_SAVE_MESSAGE_RAIDS = {[10] = true, [34] = true, [58] = true}
M.HEALER_RANGE_FACTOR = 10.0
M.WORKER_IDS = {32, 33}
M.FLAME_RANGE_EFFECT = 0.3
M.POISON_EFFECT_SIZE = 0.8
M.EFFECT_FIRE, M.EFFECT_POISON = 1, 2
M.PLACE_MARKER_Y = 0.0

-- Tower animator (Blitz Animate/AnimSeq/AnimTime, docs/05 "Upgrading").
M.ANIM_NONE, M.ANIM_LOOP, M.ANIM_ONESHOT = 0, 1, 3
M.SEQ_FRAMES = 10
M.ANIM_SPEED = 0.1
M.TIMER_STEP_MS = 16
M.BULLET_SPEED = 0.4
M.MIN_DISTANCE_BETWEEN_TOWERS = 5.6
M.TOWER_PREVIEW_COUNT = 2

local BUILD_SOUNDS = {"military_build", "magic_build", "plant_build", "freeze_build", "fire_build"}

function M.new(game_data, seed)
	local self = setmetatable({}, M)
	self.data = game_data
	self.rng = blitz.Random(seed or os.time())
	self.cheats = false
	self.events = {}
	self.gold, self.lifes, self.experience = 0, 0, 0
	self.old_lifes, self.extra_lifes = 0, 0
	self.curlevel, self.location, self.titul = 1, 1, 0
	self.max_location = 1       -- the furthest location reached (`tvdet` +0x44)
	self.survival_mode = false
	self.ingame_time = 0
	self.create_enemies_mode = false
	self.level_finished = true
	self.enemies_created, self.enemies_amount = 0, 0
	self.show_units_life = false
	self.units_life_multiplier = 1.0
	self.monsters_killed_by_inhabitants = 0
	self.missed = {}
	self.skills = Skills.new()
	self.enemies, self.towers, self.bullets, self.bombs = {}, {}, {}, {}
	self.balloon = nil
	self.selected_tower, self.selected_enemy = nil, nil
	self.next_id = 1
	self.tick_count = 0
	self.is_game_over = false
	self.location_completed = false
	self:reset_protos()
	return self
end

function M:emit(event)
	self.events[#self.events + 1] = event
end

function M:sound(name, position)
	self:emit({type = "sound", name = name, position = position})
end

function M:message(text, kind, duration_ms)
	self:emit({type = "message", text = text, kind = kind, duration_ms = duration_ms})
end

-- Drain the event queue (the view calls this once per frame).
function M:take_events()
	local events = self.events
	self.events = {}
	return events
end

-- `_floadtowerprototipesdata`: fresh copies of the CSV values.
function M:reset_protos()
	self.protos = {}
	for type_id = 1, data.TOWER_TYPES do
		local levels = {}
		for level = 0, data.TOWER_LEVELS - 1 do
			levels[level] = self.data:proto_copy(type_id, level)
		end
		self.protos[type_id] = levels
	end
end

-- Start values per difficulty (`titul`): normal, Hero, Legend.
M.DIFFICULTY_START = {[0] = {gold = 200, lifes = 100}, [1] = {gold = 200, lifes = 25}, [2] = {gold = 500, lifes = 1}}

-- `_finitbalancedata`: start values for a campaign at difficulty `titul`.
function M:init_balance(titul)
	self.titul = titul or 0
	local start = M.DIFFICULTY_START[self.titul] or M.DIFFICULTY_START[0]
	self.curlevel = 1
	self.gold, self.lifes, self.old_lifes = start.gold, start.lifes, start.lifes
	self.skills:reset()
	self.experience, self.extra_lifes = 0, 0
	self.units_life_multiplier = 1.0
	self.missed = {}
	self.monsters_killed_by_inhabitants = 0
end

-- A new campaign at difficulty `titul`, from location `L` (1 unless debugging).
function M:start_campaign(titul, L)
	self:init_balance(titul)
	L = L or 1
	self.max_location = L
	self:enter_location(L)
end

-- `_finitsurvival` + `_frestartgame`: survival on location 2.
function M:start_survival()
	self:init_balance(0)
	self.survival_mode = true
	self.experience = Survival.START_EXPERIENCE
	self.gold = Survival.START_GOLD
	self.lifes, self.old_lifes = Survival.START_LIFES, Survival.START_LIFES
	self.survival_raids = Survival.make_raids(self.data, self.rng)
	self.max_location = Survival.LOCATION
	self:enter_location(Survival.LOCATION)
end

-- `_fnextlocation`, from the congratulations screen: move to the next location (gold
-- above 200 hires inhabitants, 100 gold each; the gold is reset; experience bonus).
-- After the last location the remaining gold and inhabitants become lives, and true is
-- returned: the campaign is finished. Otherwise also returns the gold spent on hiring and
-- the inhabitants hired (none: 0, 0) for the map's message.
function M:next_location()
	if self.location < data.LOCATIONS then
		local L = self.location + 1
		self.max_location = math.max(self.max_location, L)
		local spent, hired = 0, 0
		if self.gold > 200 then
			spent = self.gold - 100
			hired = blitz.idiv(spent, 100)
			self.extra_lifes = self.extra_lifes + hired
		end
		self.gold = (L == 5 and 250 or 200) + L * 20
		self.experience = self.experience + L * 10
		self:enter_location(L)
		return false, spent, hired
	end
	self.lifes = self.lifes + blitz.idiv(self.gold - 100, 100) + self.extra_lifes
	return true
end

-- `_fcreatehighscoresmenu`: the score submitted at the end of a campaign converts the gold
-- above 200 once more (lives). (Survival scores the raid reached.)
function M:highscore()
	if self.gold > 200 then
		self.lifes = self.lifes + blitz.idiv(self.gold - 100, 100)
	end
	return self.lifes
end

-- Load location L (`_floadlocation`): the balloon of the previous one is gone
-- (`_fdeleteballoon`), locations 4-6 get theirs at their centre (`_fenableballoon`).
function M:enter_location(L)
	self.location = L
	self.path = self.data.paths[L]
	self.balloon = nil
	self:restart_location()
	if self.data:location(L).balloon and not self.survival_mode then
		self:enable_balloon()
	end
end

function M:enable_balloon()
	if not self.balloon then
		self.balloon = Balloon.new(self.data:location(self.location).bounds)
	end
	self.balloon.enabled = true
end

function M:restart_location()
	self:deselect_all_towers()
	for i = #self.towers, 1, -1 do
		self:delete_tower(self.towers[i])
	end
	for i = #self.enemies, 1, -1 do
		self:delete_enemy(self.enemies[i], false, false)
	end
	for i = #self.bullets, 1, -1 do
		self:delete_bullet(self.bullets[i], false)
	end
	for _, bomb in ipairs(self.bombs) do
		self:emit({type = "bomb_removed", bomb = bomb})
	end
	self.bombs = {}
	self.curlevel = self.survival_mode and 1 or self.data.location_first_raid[self.location]
	self.ingame_time = 0
	self.create_enemies_mode = false
	self.level_finished = true
	self.enemies_created = 0
	self.units_life_multiplier = 1.0
	self.is_game_over = false
	self.location_completed = false
end

function M:current_raid()
	if self.survival_mode then
		return Survival.raid(self.survival_raids, self.curlevel)
	end
	return self.data:raid(self.curlevel)
end

function M:last_raid_of_location()
	if self.location < data.LOCATIONS then
		return self.data.location_first_raid[self.location + 1] - 1
	end
	return data.CAMPAIGN_RAIDS
end

function M:raid_index_in_location()
	return self.curlevel - self.data.location_first_raid[self.location] + 1
end

function M:raids_in_location()
	return self.data:location(self.location).raids
end

-- ---------------------------------------------------------------- tick

-- `_fgamelogic` followed by `UpdateWorld(1)`.
function M:tick()
	if self.is_game_over then
		return
	end
	self.tick_count = self.tick_count + 1
	if self.level_finished then
		self:handle_levels()
	end
	self:update_enemies()
	self:handle_towers()
	self:handle_balloon()
	self:update_bullets()
	self:handle_bombs()
	for _, t in ipairs(self.towers) do
		M.update_tower_anim(t)
	end
end

-- `_fhandlelevels`: raid wait timer and monster spawning.
function M:handle_levels()
	self.ingame_time = f32(self.ingame_time + f32(M.INGAME_TIME_STEP))
	if self.ingame_time >= M.RAID_WAIT_TIME then
		self.ingame_time = 0
		self.create_enemies_mode = true
	end
	if self.ingame_time >= M.EXTRA_LIFE_TIME_MIN and self.ingame_time < M.EXTRA_LIFE_TIME_MAX and self.extra_lifes > 0 then
		self.extra_lifes = self.extra_lifes - 1
		self:create_enemy(false, self.rng:rand(M.WORKER_IDS[1], M.WORKER_IDS[2]))
	end
	if self.create_enemies_mode and self.ingame_time >= M.SPAWN_INTERVAL then
		local monsters = self:current_raid().monsters
		if self.enemies_created < #monsters then
			local boss = #monsters < M.BOSS_RAID_MAX_MONSTERS
			self:create_enemy(boss, monsters[self.enemies_created + 1])
			if self.enemies_created == 0 then
				self:sound("start")
				self:emit({type = "raid_started", raid = self.curlevel})
			end
			self.enemies_created = self.enemies_created + 1
			self.ingame_time = 0
		else
			self.create_enemies_mode = false
			self.level_finished = false
			self.enemies_created = 0
		end
	end
end

-- `_fcreateenemy(boss, unitId)`.
function M:create_enemy(boss, unit_id)
	local raid = self:current_raid()
	local unit = self.data:unit(unit_id)
	local e = {}
	e.id = self.next_id
	self.next_id = self.next_id + 1
	-- Blitz MoveEntity(copy, Rnd(-1, 1), 0, Rnd(0, 1)): Blitz +z is Godot/Defold -z.
	local offset = {x = self.rng:rnd(-1, 1), y = 0, z = -self.rng:rnd(0, 1)}
	e.path = PathFollower.new(self.path, offset)
	e.speed = f32(raid.speed / 10)
	e.max_life = f32(self.units_life_multiplier * raid.life)
	e.armor = raid.armor
	if self.survival_mode and unit.air then
		e.armor = blitz.round_int(e.armor * Survival.AIR_ARMOR_FACTOR)
	end
	e.gold = raid.gold
	e.air = unit.air
	e.anim_speed = unit.anim_speed
	e.freeze = 0
	e.burn_time, e.burn_damage = 0, 0
	e.poison_time, e.poison_damage = 0, 0
	e.unit_id = unit_id
	e.boss = boss
	e.healer = unit.healer
	if e.healer ~= 0 then
		if not boss then
			e.max_life = e.max_life * 2
			e.gold = e.gold * 2
		else
			e.max_life = e.max_life / 2
			e.gold = blitz.idiv(e.gold, 10)
		end
	end
	e.life = e.max_life
	e.worker = unit.worker
	local s = self.curlevel / M.ENEMY_SCALE_PER_RAID
	if boss or s > M.BOSS_SCALE then
		s = M.BOSS_SCALE
	end
	e.scale = s + 1
	if e.healer == 0 then
		e.md2_speed = e.anim_speed * e.speed - s / 7.5
	else
		e.md2_speed = e.anim_speed * e.speed - s / 10
	end
	e.md2_time = 0
	e.effect_kind, e.effect_size = 0, 0
	e.selected = false
	if not e.worker then
		self.enemies_amount = self.enemies_amount + 1
	end
	self.enemies[#self.enemies + 1] = e
	self:emit({type = "enemy_spawned", enemy = e})
	return e
end

-- World point bullets aim at (air units are hit 3 above their road position).
function M.enemy_aim_point(e)
	local p = e.path.body
	if e.air then
		return {x = p.x, y = p.y + 3, z = p.z}
	end
	return p
end

function M.enemy_life_percent(e)
	return e.life * (100 / e.max_life)
end

local function snapshot(list)
	local out = {}
	for i, v in ipairs(list) do
		out[i] = v
	end
	return out
end

local function remove_value(list, value)
	for i, v in ipairs(list) do
		if v == value then
			table.remove(list, i)
			return
		end
	end
end

-- `_fupdateenemies`.
function M:update_enemies()
	for _, e in ipairs(snapshot(self.enemies)) do
		if e.id ~= 0 then
			if e.healer > 0 then
				for _, other in ipairs(self.enemies) do
					if other.id ~= 0 then
						local d = vec3.distance(other.path.body, e.path.body)
						if d < e.healer * 10 then
							local heal = e.healer / (d * M.HEALER_RANGE_FACTOR)
							if heal + other.life < other.max_life then
								other.life = other.life + heal
							end
						end
					end
				end
			end
			if e.freeze <= 0 then
				e.path:advance(e.speed, e.speed * PathFollower.MARKER_FRAMES_PER_SPEED)
			else
				local step = e.speed / e.freeze * 2
				e.path:advance(step, step * PathFollower.MARKER_FRAMES_PER_SPEED)
				e.freeze = e.freeze - 1
			end
			if e.burn_time > 0 then
				e.life = e.life - e.burn_damage
				e.burn_time = e.burn_time - 1
				if e.burn_time <= 0 then
					e.effect_kind = 0
				end
			end
			if e.poison_time > 0 then
				e.life = e.life - e.poison_damage
				e.poison_time = e.poison_time - 1
				if e.poison_time <= 0 then
					e.effect_kind = 0
				end
			end
			e.md2_time = blitz.fmod(e.md2_time + e.md2_speed, 10)
			if not e.path:finished() then
				if e.life <= 0 then
					self:delete_enemy(e, true, true)
				end
			else
				local lost = 0
				if not e.worker then
					lost = blitz.round_int(M.enemy_life_percent(e) / (self.skills.ppl_resistance * 3 + 33))
					if e.boss then
						lost = lost * 5
					end
					if not self.cheats then
						self.lifes = math.max(self.lifes - lost, 0)
					end
					if lost < 1 then
						self.monsters_killed_by_inhabitants = self.monsters_killed_by_inhabitants + 1
					else
						self:sound("kill" .. self.rng:rand(1, 4), e.path.body)
					end
				else
					self.lifes = self.lifes + 1
					self.old_lifes = self.lifes
				end
				self:emit({type = "enemy_reached_end", enemy = e, lost = lost})
				if self.lifes < 1 then
					self.is_game_over = true
					self:emit({type = "game_over"})
				end
				self:delete_enemy(e, false, true)
			end
		end
	end
end

-- `_fdeleteenemy(enemy, killed, checkLevel)`.
function M:delete_enemy(e, killed, check_level)
	if e.id == 0 then
		return
	end
	if killed then
		self.gold = self.gold + e.gold
		self:sound("death" .. self.rng:rand(1, 4), e.path.body)
		self:emit({type = "gold_popup", amount = e.gold, position = vec3.copy(e.path.body)})
	end
	if e.selected then
		e.selected = false
		self.selected_enemy = nil
	end
	for _, t in ipairs(self.towers) do
		if t.target == e then
			t.target = nil
		end
	end
	for _, b in ipairs(self.bullets) do
		if b.target == e then
			b.target = nil
		end
	end
	remove_value(self.enemies, e)
	self:emit({type = "enemy_died", enemy = e, killed = killed})
	e.id = 0
	if not e.worker then
		self.enemies_amount = self.enemies_amount - 1
		-- A lost game does not finish its raid (the game over sheet stops the game logic):
		-- no income, no automatic save, no completed location.
		if check_level and self.enemies_amount == 0 and not self.is_game_over then
			self:next_level()
		end
	end
end

-- `_fnextlevel`.
function M:next_level()
	local d = self.data
	local finished_raid = self.curlevel
	if self.survival_mode then
		self.curlevel = self.curlevel + 1
	else
		local hints = {[1] = 53, [3] = 51, [4] = 52}
		if hints[self.curlevel] then
			self:message(d:text(hints[self.curlevel]), M.MSG_WHITE, 3000)
		end
		if M.DEATH_SAVE_MESSAGE_RAIDS[self.curlevel] then
			self:message(d:text(50), M.MSG_WHITE, 3000)
		end
		if self.curlevel < self:last_raid_of_location() then
			self.curlevel = self.curlevel + 1
		else
			self.location_completed = true
			self:emit({type = "location_completed"})
		end
	end
	self.level_finished = true
	self.ingame_time = 0
	-- Survival pays by the people left, the campaign a fixed base.
	local base = self.survival_mode and self.lifes or M.CAMPAIGN_INCOME_BASE
	local income = blitz.round_int(self.skills.gold_rate * base)
	self.gold = self.gold + income
	self:message(string.format("%s %d %s", d:text(46), income, d:text(30)), M.MSG_GOLD, 3000)
	if self.lifes < self.old_lifes then
		self.missed[self.curlevel] = self.old_lifes - self.lifes
		self:message(string.format("%d %s", self.old_lifes - self.lifes, d:text(47)), M.MSG_WHITE, 2000)
		self.old_lifes = self.lifes
	end
	if self.monsters_killed_by_inhabitants > 0 then
		self:message(string.format("%d %s", self.monsters_killed_by_inhabitants, d:text(88)), M.MSG_WHITE, 1500)
		self:sound("nokills")
	end
	self.monsters_killed_by_inhabitants = 0
	if not self.survival_mode then
		self.units_life_multiplier = balance.update(self.units_life_multiplier, self.missed, self.curlevel, self.location, self.titul, self.lifes)
	end
	self.experience = self.experience + M.RAID_EXPERIENCE
	-- The automatic save of a campaign raid won with no monster left: the snapshot is taken
	-- here, at the original's moment, and written by the screen controller.
	if profile.can_autosave(self) then
		self:emit({type = "autosave", save = savegame.serialize(self)})
	end
	for _, t in ipairs(self.towers) do
		t.stopped = false
	end
	self:emit({type = "raid_finished", raid = finished_raid})
end

-- ---------------------------------------------------------------- towers

local function apply_proto(t, p)
	t.rate_of_fire_ms = p.rate_of_fire_ms
	t.land_damage = p.land_damage
	t.air_damage = p.air_damage
	t.range = p.range
	t.target_method = p.target_method
	t.freeze = p.freeze
	t.fire = p.fire
	t.place_on_road = p.place_on_road
	t.poison_coof = p.poison_coof
	t.poison_damage = p.poison_damage
	t.max_upgrades = p.max_upgrades
	t.bullet_model = p.bullet_model
end

function M.tower_idle_seq(t)
	return t.level * 2 + 1
end

function M.tower_upgrade_seq(t)
	return t.level * 2
end

function M.tower_is_upgrading(t)
	return t.anim_seq == M.tower_upgrade_seq(t)
end

-- Blitz `Animate(entity, mode, speed, seq)` with no transition.
function M.tower_animate(t, mode, seq)
	t.anim_mode, t.anim_seq, t.anim_time = mode, seq, 0
end

-- Blitz `UpdateWorld(1)` step of the animator.
function M.update_tower_anim(t)
	if t.anim_mode == M.ANIM_NONE then
		return
	end
	t.anim_time = f32(t.anim_time + f32(M.ANIM_SPEED))
	if t.anim_mode == M.ANIM_LOOP then
		t.anim_time = blitz.fmod(t.anim_time, M.SEQ_FRAMES)
	elseif t.anim_mode == M.ANIM_ONESHOT and t.anim_time >= M.SEQ_FRAMES then
		t.anim_time = M.SEQ_FRAMES
		t.anim_mode = M.ANIM_NONE
	end
end

-- Absolute frame inside the model's animation (`ExtractAnimSeq` numbers from 1).
function M.tower_model_frame(t)
	return (t.anim_seq - 1) * M.SEQ_FRAMES + t.anim_time
end

-- World position of `fire1` at the current frame, rotated by the tower's build yaw.
function M.tower_fire_point(t)
	local keys = t.fire_keys
	local local_pos
	if #keys == 1 then
		local_pos = keys[1]
	else
		local frame = M.tower_model_frame(t)
		local i = math.max(0, math.min(math.floor(frame), #keys - 1))
		if i >= #keys - 1 then
			local_pos = keys[#keys]
		else
			local_pos = vec3.lerp(keys[i + 1], keys[i + 2], frame - i)
		end
	end
	return vec3.add(t.position, vec3.rotate_y(local_pos, t.yaw_degrees))
end

function M.tower_can_hit(t, e)
	if e.air then
		return t.air_damage ~= 0
	end
	return t.land_damage ~= 0
end

function M:tower_price(type_id, level)
	return self.protos[type_id][level or 0].price
end

function M:can_afford_tower(type_id)
	return self.gold >= self:tower_price(type_id)
end

-- No other tower closer than 5.6.
function M:is_too_close_to_tower(pos)
	for _, t in ipairs(self.towers) do
		if vec3.distance(t.position, pos) < M.MIN_DISTANCE_BETWEEN_TOWERS then
			return true
		end
	end
	return false
end

-- `_fcreatetower` + `_fpositiontower`: a tower placed at `pos`; gold is charged here.
-- `_fbuildtower` / `_fcreatetower`: a tower of `type_id` at `level` (0) on `pos`;
-- `charge == false` builds it for free (restoring a save).
function M:build_tower(type_id, pos, level, charge)
	level = level or 0
	local p = self.protos[type_id][level]
	if charge ~= false and self.gold < p.price then
		self:sound("oops2")
		return nil
	end
	local t = {}
	t.id = self.next_id
	self.next_id = self.next_id + 1
	t.type = type_id
	t.level = level
	apply_proto(t, p)
	t.fire_keys = self.data:tower_model(type_id).fire1
	t.position = vec3.copy(pos)
	t.yaw_degrees = self.rng:rnd(0, 360)
	t.timer = 0
	t.target = nil
	t.upgrade_pending = false
	t.spent = p.price
	t.stopped = false
	t.selected = false
	M.tower_animate(t, M.ANIM_LOOP, M.tower_idle_seq(t))
	if charge ~= false and not self.cheats then
		self.gold = self.gold - p.price
	end
	self.towers[#self.towers + 1] = t
	self:sound(BUILD_SOUNDS[type_id], pos)
	self:emit({type = "tower_built", tower = t})
	return t
end

-- `_fupgradetower` for the selected tower. Returns true if the upgrade was started.
function M:upgrade_selected_tower()
	local t = self.selected_tower
	if t == nil then
		return false
	end
	if t.level + 1 <= t.max_upgrades and t.anim_seq == M.tower_idle_seq(t) then
		local price = self.protos[t.type][t.level + 1].price
		if self.gold < price then
			self:sound("oops2")
			return false
		end
		t.level = t.level + 1
		if not self.cheats then
			self.gold = self.gold - price
		end
		t.spent = t.spent + price
		t.upgrade_pending = true
		self:emit({type = "tower_upgrade_started", tower = t})
		return true
	end
	return false
end

function M:sell_value(t)
	return blitz.round_int(self.skills.sell_rate * t.spent)
end

-- `_fselltower` + `_freturngold` + `_fdeletetower` for the selected tower.
function M:sell_selected_tower()
	local t = self.selected_tower
	if t == nil then
		return false
	end
	self.gold = blitz.round_int(self.gold + self.skills.sell_rate * t.spent)
	self:delete_tower(t)
	return true
end

function M:delete_tower(t)
	if t.selected then
		t.selected = false
		self.selected_tower = nil
	end
	for _, b in ipairs(snapshot(self.bullets)) do
		if b.tower == t then
			self:delete_bullet(b, false)
		end
	end
	remove_value(self.towers, t)
	self:emit({type = "tower_removed", tower = t})
end

function M:select_tower(t)
	self:deselect_all_towers()
	t.selected = true
	self.selected_tower = t
end

function M:deselect_all_towers()
	for _, t in ipairs(self.towers) do
		t.selected = false
	end
	self.selected_tower = nil
end

-- `_fhandleenemyselection`: the picked monster becomes every tower's target.
function M:select_enemy(e)
	self:deselect_enemy()
	e.selected = true
	self.selected_enemy = e
	for _, t in ipairs(self.towers) do
		t.target = e
	end
end

function M:deselect_enemy()
	if self.selected_enemy then
		self.selected_enemy.selected = false
	end
	self.selected_enemy = nil
end

-- Tab: next tower after the selected one (`_fswitchtonexttower`).
function M:next_tower()
	local n = #self.towers
	if n + M.TOWER_PREVIEW_COUNT <= 3 then
		return nil
	end
	local idx = 0
	for i, t in ipairs(self.towers) do
		if t == self.selected_tower then
			idx = i
		end
	end
	local t = self.towers[idx % n + 1]
	self:select_tower(t)
	return t
end

-- `_fhandletowers` (simulation part; picking lives in the view).
-- `candidate` lives across the loop as in the original: a stopped tower keeps the one
-- found for the tower before it, `shoot` refuses it, and so its own target is cleared.
function M:handle_towers()
	local candidate = nil
	for _, t in ipairs(self.towers) do
		t.timer = t.timer + M.TIMER_STEP_MS
		if t.anim_seq == M.tower_upgrade_seq(t) and t.anim_mode == M.ANIM_NONE then
			M.tower_animate(t, M.ANIM_LOOP, M.tower_idle_seq(t))
			self:message(self.data:text(57), M.MSG_WHITE, 1500)
			apply_proto(t, self.protos[t.type][t.level])
			self:emit({type = "tower_upgraded", tower = t})
			self:sound("update", t.position)
		end
		if t.upgrade_pending and blitz.round_int(t.anim_time) == M.SEQ_FRAMES then
			M.tower_animate(t, M.ANIM_ONESHOT, M.tower_upgrade_seq(t))
			t.upgrade_pending = false
		end
		if not t.stopped then
			candidate = nil
			if t.target_method == 1 then
				local best = 100
				for _, e in ipairs(self.enemies) do
					if not e.worker and M.tower_can_hit(t, e) then
						local d = vec3.distance(t.position, e.path.body)
						if d < t.range then
							if e.selected then
								candidate = e
								break
							end
							if d < best then
								candidate, best = e, d
							end
						end
					end
				end
			elseif t.target_method == 2 then
				if t.target == nil or vec3.distance(t.position, t.target.path.body) >= t.range then
					for i = #self.enemies, 1, -1 do
						local e = self.enemies[i]
						if vec3.distance(t.position, e.path.body) < t.range and not e.worker and M.tower_can_hit(t, e) then
							candidate = e
							break
						end
					end
				else
					candidate = t.target
				end
			end
		end
		if candidate then
			if self:shoot(t, candidate) then
				t.target = candidate
			else
				t.target = nil
			end
		end
	end
end

-- ---------------------------------------------------------------- balloon

M.BOMB_DAMAGE = 350.0
M.BOMB_FREEZE_PER_COLD = 30
M.BOMB_FALL_SPEED = 0.2
M.BOMB_RADIUS = 7.0

-- The right click on the road moves the balloon (`_fhandleballoons` + `_fmoveballoonto`);
-- false when there is no balloon to move.
function M:move_balloon(dest)
	if not (self.balloon and self.balloon.enabled) then
		return false
	end
	self.balloon:move_to(dest)
	return true
end

-- `_fhandleballoons`: the balloon moves; a bomb drops when a monster is near and the
-- timer allows it.
function M:handle_balloon()
	local b = self.balloon
	if not (b and b.enabled) then
		return
	end
	b:update(self.rng)
	b.timer = b.timer + 1
	if b.timer <= Balloon.BOMB_INTERVAL_TICKS then
		return
	end
	for _, e in ipairs(self.enemies) do
		if not e.worker and vec3.distance(e.path.body, b.position) < Balloon.BOMB_TRIGGER_DISTANCE then
			local bomb = {id = self.next_id, position = {x = b.position.x, y = f32(b.position.y + 1), z = b.position.z},
				damage = M.BOMB_DAMAGE, freeze = M.BOMB_FREEZE_PER_COLD * self.skills.cold_magic}
			self.next_id = self.next_id + 1
			self.bombs[#self.bombs + 1] = bomb
			b.timer = 0
			self:emit({type = "bomb_dropped", bomb = bomb})
			return
		end
	end
end

-- `_fhandlebombs`: a bomb falls 0.2 a tick; on the ground it hits every monster within 7
-- (inhabitants too) for 350 ignoring armour and freezes them.
function M:handle_bombs()
	for i = #self.bombs, 1, -1 do
		local bomb = self.bombs[i]
		bomb.position.y = f32(bomb.position.y - f32(M.BOMB_FALL_SPEED))  -- Blitz positions are float32
		if bomb.position.y <= 0 then
			for _, e in ipairs(self.enemies) do
				if vec3.distance(e.path.body, bomb.position) < M.BOMB_RADIUS then
					e.life = e.life - bomb.damage
					e.freeze = bomb.freeze
				end
			end
			self:sound("exp1", bomb.position)
			table.remove(self.bombs, i)
			self:emit({type = "bomb_removed", bomb = bomb, exploded = true})
		end
	end
end

-- `_fcreateduration`: an enemy carries one visual effect at a time.
local function start_effect(e, kind, size)
	if e.effect_kind ~= 0 then
		return
	end
	e.effect_kind, e.effect_size = kind, size
end

-- `_fshoot(tower, enemy)`: false when the tower cannot attack this enemy.
function M:shoot(t, e)
	if (e.air and t.air_damage == 0) or (not e.air and t.land_damage == 0) or t.stopped then
		return false
	end
	if t.timer > t.rate_of_fire_ms then
		if t.type == data.TOWER_FLAME then
			local fm = math.min(self.skills.fire_magic, 5)
			e.burn_time = fm * t.fire
			start_effect(e, M.EFFECT_FIRE, (t.level + 1) * M.FLAME_RANGE_EFFECT)
			e.burn_damage = t.land_damage
			t.timer = 0
			self:emit({type = "flame_hit", tower = t, enemy = e})
			return true
		end
		local b = {}
		b.id = self.next_id
		self.next_id = self.next_id + 1
		b.position = M.tower_fire_point(t)
		b.direction = vec3.normalized(vec3.sub(e.path.body, b.position))
		b.target = e
		b.speed = M.BULLET_SPEED
		b.burn = 0
		if e.air then
			b.damage = t.air_damage
			if self.skills.fire_magic == 6 and t.type == data.TOWER_MAGIC then
				b.burn = b.damage * 5
			end
		else
			b.damage = t.land_damage
		end
		b.freeze = self.skills.cold_magic * t.freeze
		b.poison = t.poison_coof * self.skills.poison_magic
		t.timer = 0
		b.tower = t
		b.model = t.bullet_model
		self.bullets[#self.bullets + 1] = b
		if t.type == data.TOWER_LAND then
			self:sound("exp1", t.position)
		elseif t.type == data.TOWER_MAGIC or t.type == data.TOWER_ICEROCK then
			self:sound("exp2", t.position)
		end
		self:emit({type = "bullet_created", bullet = b})
	end
	return true
end

-- `_fupdatebullets`.
function M:update_bullets()
	for _, b in ipairs(snapshot(self.bullets)) do
		if b.id ~= 0 then
			if vec3.distance(b.position, b.tower.position) > b.tower.range then
				self:delete_bullet(b, true)
			else
				local hit = false
				local e = b.target
				if e then
					local aim = M.enemy_aim_point(e)
					local delta = vec3.sub(aim, b.position)
					if vec3.length(delta) > 0 then
						b.direction = vec3.normalized(delta)
					end
					if vec3.distance(b.position, aim) < 1 then
						if e.armor < b.damage then
							e.life = e.life - (b.damage - e.armor)
						end
						if b.freeze > 0 then
							e.freeze = b.freeze
						end
						if b.poison > 0 and e.poison_time < b.poison then
							e.poison_time = b.poison
							start_effect(e, M.EFFECT_POISON, M.POISON_EFFECT_SIZE)
							e.poison_damage = b.tower.poison_damage
						end
						if b.burn > 0 and e.burn_time < b.burn then
							e.burn_time = b.burn
							start_effect(e, M.EFFECT_FIRE, (b.tower.level + 1) * M.FLAME_RANGE_EFFECT)
							e.burn_damage = 1
						end
						self:delete_bullet(b, true)
						hit = true
					end
				end
				if not hit then
					b.position = vec3.add(b.position, vec3.scale(b.direction, b.speed))
				end
			end
		end
	end
end

function M:delete_bullet(b, exploded)
	if b.id == 0 then
		return
	end
	remove_value(self.bullets, b)
	self:emit({type = "bullet_removed", bullet = b, exploded = exploded})
	b.id = 0
end

return M
