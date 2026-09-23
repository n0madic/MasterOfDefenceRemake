-- The balloon of locations 4-6 (`tballoont`, docs/07). Moving it is the `_fflux_translate`
-- tween: `Round(10 * dist)` ticks with cosine easing (the distance from the XZ coordinates
-- rounded to integers), the height kept. Now and then it turns to a random yaw
-- (`_fflux_rotate` over Rnd(2000, 5000) ms, draws from the game's Blitz RNG like the
-- original). Bombs: see sim/game.lua `handle_balloon` / `handle_bombs`.
local blitz = require("sim.blitz")

local M = {}
M.__index = M

M.HEIGHT = 10.0
M.BOMB_INTERVAL_TICKS = 200
M.BOMB_TRIGGER_DISTANCE = 15.0
M.TICKS_PER_UNIT = 10.0
local TURN_MS_MIN, TURN_MS_MAX = 2000, 5000
local TURN_YAW = 360
local TICK_MS = 16

-- A balloon at the centre of `bounds` (`_fcreateballoon`).
function M.new(bounds)
	local self = setmetatable({}, M)
	self.position = {x = (bounds.x_min + bounds.x_max) / 2, y = M.HEIGHT, z = (bounds.z_min + bounds.z_max) / 2}
	self.enabled = true
	self.timer = 0
	self.yaw = 0
	self.here = nil       -- the destination marker (`here.b3d`) while it is shown
	self.move = nil       -- {from, to, duration, elapsed}
	self.turn = nil       -- {from, to, duration, elapsed}
	return self
end

-- `_fmoveballoonto`: head for road point `dest`.
function M:move_to(dest)
	local p = self.position
	local dx = blitz.round_int(dest.x) - blitz.round_int(p.x)
	local dz = blitz.round_int(dest.z) - blitz.round_int(p.z)
	self.move = {from = {x = p.x, y = p.y, z = p.z}, to = {x = dest.x, y = p.y, z = dest.z},
		duration = blitz.round_int(M.TICKS_PER_UNIT * math.sqrt(dx * dx + dz * dz)), elapsed = -1}
	self.here = {x = dest.x, y = dest.y, z = dest.z}
end

function M:moving()
	return self.move ~= nil
end

local function eased(tween)
	if tween.elapsed == -1 then
		tween.elapsed = 0
	else
		tween.elapsed = tween.elapsed + 1
	end
	local t = tween.duration > 0 and math.min(tween.elapsed, tween.duration) / tween.duration or 1
	return (1 - math.cos(t * math.pi)) / 2, tween.elapsed >= tween.duration
end

-- `_fflux_update(1)`: one tick of the motions; `rng` is the game's Blitz generator.
function M:update(rng)
	if self.move then
		local a, done = eased(self.move)
		local f, t = self.move.from, self.move.to
		self.position = {x = f.x + (t.x - f.x) * a, y = f.y + (t.y - f.y) * a, z = f.z + (t.z - f.z) * a}
		if done then
			self.move = nil
		end
	end
	if not self.turn then
		local ms = blitz.round_int(rng:rnd(TURN_MS_MIN, TURN_MS_MAX))
		local yaw = rng:rnd(-TURN_YAW, TURN_YAW)
		self.turn = {from = self.yaw, to = yaw, duration = math.max(1, blitz.round_int(ms / TICK_MS)), elapsed = -1}
	end
	local a, done = eased(self.turn)
	self.yaw = self.turn.from + (self.turn.to - self.turn.from) * a
	if done then
		self.turn = nil
	end
end

return M
