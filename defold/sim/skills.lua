-- Experience skills ("Magic and skills" window, docs/06). Multipliers accumulate in
-- float32 like the original: the level caps are `upgrader < 1.05f` / `< 1.06f` tests.
local blitz = require("sim.blitz")
local data = require("sim.data")

local f32 = blitz.f32

local M = {}
M.__index = M

M.DAMAGE, M.SPEED, M.GOLD, M.RANGE, M.SELL = 1, 2, 3, 4, 5
M.COLD, M.FIRE, M.POISON, M.RESISTANCE, M.FIRE6 = 6, 7, 8, 9, 10
M.KIND_RANGE, M.KIND_SPEED, M.KIND_DAMAGE = 1, 2, 3

M.PRICES = {[1] = 50, [2] = 80, [3] = 35, [4] = 50, [5] = 30, [6] = 100, [7] = 100, [8] = 100, [9] = 80, [10] = 200}
local RANGE_MAX, RANGE_INC = 1.06, 0.005
local SPEED_INC, SPEED_MAX_LEVEL = 0.02, 5
local DAMAGE_MAX, DAMAGE_INC = 1.05, 0.005
local GOLD_INC, GOLD_MAX_LEVEL = 0.02, 20
local SELL_INC, SELL_MAX, SELL_MAX_LEVEL = 0.05, 1.0, 5
local MAGIC_MAX_LEVEL = 5

function M.new()
	local self = setmetatable({}, M)
	self:reset()
	return self
end

function M:reset()
	self.range_upgrader, self.range_level = 1.0, 0
	self.speed_upgrader, self.speed_level = 1.0, 0
	self.damage_upgrader, self.damage_level = 1.0, 0
	self.gold_rate, self.gold_level = f32(0.6), 0
	self.sell_rate, self.sell_level = 0.75, 0
	self.cold_magic, self.fire_magic, self.poison_magic, self.ppl_resistance = 0, 0, 0, 0
	self.query = {}  -- operations since the window opened: {id, downgrade}
end

-- `_fhandlegui`: the fire button sends id 7 up to level 5 and id 10 at level 5 / 6.
function M:button_id(id, downgrade)
	if id == M.FIRE and self.fire_magic == (downgrade and MAGIC_MAX_LEVEL + 1 or MAGIC_MAX_LEVEL) then
		return M.FIRE6
	end
	return id
end

function M:price_of(id)
	return M.PRICES[id]
end

function M:can_buy(id, experience)
	if experience < self:price_of(id) then
		return false
	end
	if id == M.DAMAGE then return self.damage_upgrader < f32(DAMAGE_MAX)
	elseif id == M.SPEED then return self.speed_level < SPEED_MAX_LEVEL
	elseif id == M.GOLD then return self.gold_level < GOLD_MAX_LEVEL
	elseif id == M.RANGE then return self.range_upgrader < f32(RANGE_MAX)
	elseif id == M.SELL then return self.sell_level < SELL_MAX_LEVEL
	elseif id == M.COLD then return self.cold_magic < MAGIC_MAX_LEVEL
	elseif id == M.FIRE then return self.fire_magic < MAGIC_MAX_LEVEL
	elseif id == M.FIRE6 then return self.fire_magic == MAGIC_MAX_LEVEL
	elseif id == M.POISON then return self.poison_magic < MAGIC_MAX_LEVEL
	elseif id == M.RESISTANCE then return self.ppl_resistance < MAGIC_MAX_LEVEL
	end
	return false
end

function M:can_downgrade(id)
	if id == M.DAMAGE then return self.damage_upgrader > 1.0
	elseif id == M.SPEED then return self.speed_level > 0
	elseif id == M.GOLD then return self.gold_level > 0
	elseif id == M.RANGE then return self.range_upgrader > 1.0
	elseif id == M.SELL then return self.sell_level > 0
	elseif id == M.COLD then return self.cold_magic > 0
	elseif id == M.FIRE then return self.fire_magic >= 1 and self.fire_magic <= 5
	elseif id == M.FIRE6 then return self.fire_magic == 6
	elseif id == M.POISON then return self.poison_magic > 0
	elseif id == M.RESISTANCE then return self.ppl_resistance > 0
	end
	return false
end

function M:level_of(id)
	if id == M.DAMAGE then return self.damage_level
	elseif id == M.SPEED then return self.speed_level
	elseif id == M.GOLD then return self.gold_level
	elseif id == M.RANGE then return self.range_level
	elseif id == M.SELL then return self.sell_level
	elseif id == M.COLD then return self.cold_magic
	elseif id == M.FIRE or id == M.FIRE6 then return self.fire_magic
	elseif id == M.POISON then return self.poison_magic
	elseif id == M.RESISTANCE then return self.ppl_resistance
	end
	return 0
end

-- `_fnewupgade(id, downgrade)`: queue the operation and apply it.
function M:operate(game, id, downgrade)
	self.query[#self.query + 1] = {id = id, downgrade = downgrade}
	self:_do(game, id, downgrade, false)
end

-- OK button.
function M:commit()
	self.query = {}
end

-- Cancel button (`_fcancelqueryupgrades`): undo the queue in reverse.
function M:cancel(game)
	for i = #self.query, 1, -1 do
		local op = self.query[i]
		self:_do(game, op.id, not op.downgrade, true)
	end
	self.query = {}
end

local function mul(x, m, divide)
	return divide and f32(x / m) or f32(x * m)
end

-- `_fupgradetowerbuildingskills` / `_fdowngradetowerbuildingskills`: scale every
-- prototype and built tower by the current upgrader of `kind`.
function M:_apply(game, kind, divide)
	local m
	if kind == M.KIND_RANGE then m = self.range_upgrader
	elseif kind == M.KIND_SPEED then m = self.speed_upgrader
	else m = self.damage_upgrader end
	local function scale(p)
		if kind == M.KIND_RANGE then
			p.range = mul(p.range, m, divide)
		elseif kind == M.KIND_SPEED then
			p.rate_of_fire_ms = blitz.round_int(mul(p.rate_of_fire_ms, m, divide))
		else
			p.land_damage = mul(p.land_damage, m, divide)
			p.air_damage = mul(p.air_damage, m, divide)
		end
	end
	for type_id = 1, data.TOWER_TYPES do
		for level = 0, data.TOWER_LEVELS - 1 do
			scale(game.protos[type_id][level])
		end
	end
	for _, t in ipairs(game.towers) do
		scale(t)  -- towers carry the same field names as the prototypes
	end
end

-- `_fdoupgrades(downgrade, cancel)`: cost price / (2 - (cancel ^ 1)) on purchase and
-- price / (2 - cancel) on downgrade.
function M:_do(game, id, downgrade, cancel)
	local price = game.cheats and 0 or self:price_of(id)
	local buy_cost = blitz.idiv(price, 2 - (cancel and 0 or 1))
	local refund = blitz.idiv(price, 2 - (cancel and 1 or 0))
	local up = not downgrade
	if id == M.DAMAGE then
		if up then
			self.damage_upgrader = f32(self.damage_upgrader + f32(DAMAGE_INC))
			self.damage_level = self.damage_level + 1
			self:_apply(game, M.KIND_DAMAGE, false)
		else
			self:_apply(game, M.KIND_DAMAGE, true)
			self.damage_upgrader = f32(self.damage_upgrader - f32(DAMAGE_INC))
			self.damage_level = self.damage_level - 1
		end
	elseif id == M.SPEED then
		if up then
			self.speed_upgrader = f32(self.speed_upgrader - f32(SPEED_INC))
			self.speed_level = self.speed_level + 1
			self:_apply(game, M.KIND_SPEED, false)
		else
			self:_apply(game, M.KIND_SPEED, true)
			self.speed_upgrader = f32(self.speed_upgrader + f32(SPEED_INC))
			self.speed_level = self.speed_level - 1
		end
	elseif id == M.GOLD then
		self.gold_rate = f32(self.gold_rate + (up and 1 or -1) * f32(GOLD_INC))
		self.gold_level = self.gold_level + (up and 1 or -1)
	elseif id == M.RANGE then
		if up then
			self.range_upgrader = f32(self.range_upgrader + f32(RANGE_INC))
			self.range_level = self.range_level + 1
			self:_apply(game, M.KIND_RANGE, false)
		else
			self:_apply(game, M.KIND_RANGE, true)
			self.range_upgrader = f32(self.range_upgrader - f32(RANGE_INC))
			self.range_level = self.range_level - 1
		end
	elseif id == M.SELL then
		self.sell_rate = math.min(f32(self.sell_rate + (up and 1 or -1) * f32(SELL_INC)), SELL_MAX)
		self.sell_level = self.sell_level + (up and 1 or -1)
	elseif id == M.COLD then
		self.cold_magic = self.cold_magic + (up and 1 or -1)
	elseif id == M.FIRE or id == M.FIRE6 then
		self.fire_magic = self.fire_magic + (up and 1 or -1)
	elseif id == M.POISON then
		self.poison_magic = self.poison_magic + (up and 1 or -1)
	elseif id == M.RESISTANCE then
		self.ppl_resistance = self.ppl_resistance + (up and 1 or -1)
	end
	if up then
		game.experience = game.experience - buy_cost
	else
		game.experience = game.experience + refund
	end
	game:emit({type = "skills_changed"})
end

return M
