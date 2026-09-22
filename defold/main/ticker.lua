-- Fixed-step game clock (`_fmainloop`): period_ms = 1000 \ (40 + slider), the remainder
-- of a frame carries over; a long stall replays at most MAX_TICKS_PER_FRAME ticks.
local blitz = require("sim.blitz")

local M = {}
M.__index = M

M.BASE_FPS = 40
M.DEFAULT_SLIDER = 20
M.FAST_SLIDER = 100
M.SLIDER_MAX = 100
M.MAX_TICKS_PER_FRAME = 250

function M.new()
	return setmetatable({slider = M.DEFAULT_SLIDER, paused = false, accumulator_ms = 0}, M)
end

function M:set_slider(v)
	self.slider = math.max(0, math.min(M.SLIDER_MAX, math.floor(v)))
end

function M:fps()
	return M.BASE_FPS + self.slider
end

function M:period_ms()
	return blitz.idiv(1000, self:fps())
end

function M:ticks_per_second()
	return 1000 / self:period_ms()
end

-- Number of ticks to run for a frame of `dt` seconds.
function M:advance(dt)
	if self.paused then
		self.accumulator_ms = 0
		return 0
	end
	self.accumulator_ms = self.accumulator_ms + dt * 1000
	local period = self:period_ms()
	local ticks = blitz.idiv(math.floor(self.accumulator_ms), period)
	self.accumulator_ms = self.accumulator_ms - ticks * period
	return math.min(ticks, M.MAX_TICKS_PER_FRAME)
end

return M
