-- What the location camera sees across (main/location/camera.script): the original shows a
-- location through a 4:3 window whose pivot stays inside the location's `bounds`. In Wide
-- mode the canvas is wider, so the pivot's x range narrows by the extra ground the wider
-- view uncovers on each side, and a location may be drawn only as wide as its x range can
-- absorb: the wide view never shows ground the 4:3 view could not reach. The widest ground
-- is seen along the top screen row (the farthest), so that row decides.
local screen = require("main.screen")

local M = {}

M.PIVOT_HEIGHT = 30
M.PITCH = math.rad(-45)
-- `_fmovecameratoentity`: the pivot stops this far behind (towards the camera) the point it
-- moves to.
M.MOVE_TO_BEHIND = 20

-- Ground half-width seen along the top screen row per unit of aspect (the pivot is
-- PIVOT_HEIGHT above the ground at y = 0).
local function top_half_width_per_aspect()
	local half_fov = screen.FOV / 2
	local below_horizon = -M.PITCH - half_fov
	local depth = M.PIVOT_HEIGHT / math.sin(below_horizon) * math.cos(half_fov)
	return depth * math.tan(half_fov)
end

local K = top_half_width_per_aspect()

-- How far the pivot's x range narrows on each side at canvas `aspect`.
function M.extra_half_width(aspect)
	return math.max(0, (aspect - screen.ASPECT) * K)
end

-- The pivot's x limits for `bounds` ({x_min, x_max, ...}) at canvas `aspect`.
function M.x_limits(bounds, aspect)
	local extra = M.extra_half_width(aspect)
	local lo, hi = bounds.x_min + extra, bounds.x_max - extra
	if lo > hi then
		lo = (bounds.x_min + bounds.x_max) / 2
		hi = lo
	end
	return lo, hi
end

-- The widest canvas aspect (at most `limit`) whose extra ground the x range absorbs.
function M.max_aspect(bounds, limit)
	return math.max(screen.ASPECT, math.min(limit, screen.ASPECT + (bounds.x_max - bounds.x_min) / (2 * K)))
end

return M
