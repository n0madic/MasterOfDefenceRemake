-- Enemy movement along Path1 (docs/03, port of tools/simulate_path.py): the body chases
-- an animated marker; the marker advances only while the body is within 1 unit.
local vec3 = require("sim.vec3")

local M = {}
M.__index = M

M.CATCH_UP_DISTANCE = 1.0
M.MARKER_FRAMES_PER_SPEED = 0.25

function M.new(path, offset)
	local self = setmetatable({}, M)
	self.keys = path.pos
	self.rots = path.rot
	self.frames = path.frames
	self.offset = offset
	self.time = 0
	self.body = self:marker_position()
	self.facing = {x = 0, y = 0, z = -1}
	local q = path.rot[1]
	if q then
		-- Quaternion (w, x, y, z) applied to FORWARD (0, 0, -1).
		self.facing = vec3.normalized({
			x = -(2 * (q.x * q.z + q.w * q.y)),
			y = -(2 * (q.y * q.z - q.w * q.x)),
			z = -(1 - 2 * (q.x * q.x + q.y * q.y)),
		})
	end
	return self
end

function M:position_at(t)
	local keys = self.keys
	local i = math.floor(t)
	if i >= #keys - 1 then
		return keys[#keys]
	elseif i < 0 then
		return keys[1]
	end
	return vec3.lerp(keys[i + 1], keys[i + 2], t - i)
end

function M:marker_position()
	return vec3.add(self:position_at(self.time), self.offset)
end

-- One tick: `speed` is the body step, `marker_step` what AnimTime advances by.
function M:advance(speed, marker_step)
	local marker = self:marker_position()
	if vec3.distance(self.body, marker) < M.CATCH_UP_DISTANCE then
		self.time = (self.time + marker_step) % self.frames
		marker = self:marker_position()
	end
	local delta = vec3.sub(marker, self.body)
	local d = vec3.length(delta)
	if d > 0 then
		self.facing = vec3.scale(delta, 1 / d)
		self.body = vec3.add(self.body, vec3.scale(self.facing, speed))
	end
end

function M:finished()
	return self.time > self.frames - 1
end

return M
