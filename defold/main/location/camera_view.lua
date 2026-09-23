-- What the location camera sees across (main/location/camera.script): the original shows a
-- location through a 4:3 window whose pivot stays inside the location's `bounds`. In Wide
-- mode the canvas is wider or taller, so the pivot's range narrows by the extra ground the
-- bigger view uncovers on each side (godot CameraRig.fit_bounds), and a location may be
-- drawn only as wide / tall as its range can absorb: the wide view never shows ground the
-- 4:3 view could not reach.
local screen = require("main.screen")

local M = {}

M.PIVOT_HEIGHT = 30
M.PITCH = math.rad(-45)
-- `_fmovecameratoentity`: the pivot stops this far behind (towards the camera) the point it
-- moves to.
M.MOVE_TO_BEHIND = 20

-- Bisection steps of the tallest aspect (`aspect_limits`) and the canvas it starts from:
-- 800 wide and 4 times as high.
local MIN_ASPECT_STEPS = 40
local TALLEST_ASPECT = screen.ASPECT / 4

-- Ground footprint of the camera frame at canvas `aspect` (camera at rest on its pivot,
-- PIVOT_HEIGHT above the ground at y = 0): distance ahead of the camera of the far (top)
-- and near (bottom) screen edges and the half-width of the frame at the far edge, where
-- it is widest.
function M.frame(aspect)
	local tan_v = screen.tan_half_fov(aspect)
	local half_v = math.atan(tan_v)
	local pitch = -M.PITCH
	local top = pitch - half_v  -- angle of the top ray below the horizon
	local bottom = math.min(pitch + half_v, math.pi / 2)
	local far, depth_top = math.huge, math.huge
	if top > 0 then
		far = M.PIVOT_HEIGHT / math.tan(top)
		depth_top = M.PIVOT_HEIGHT / math.sin(top) * math.cos(half_v)
	end
	return {far = far, near = M.PIVOT_HEIGHT / math.tan(bottom), half_w = depth_top * tan_v * aspect}
end

local FRAME_4_3 = M.frame(screen.ASPECT)

-- The pivot's limits x_min, x_max, z_min, z_max for `bounds` ({x_min, x_max, z_min,
-- z_max}) at canvas `aspect`: shrunk by the growth of the frame footprint over the 4:3 one
-- (the far edge eats z_min, the camera looking along -Z), collapsed to the centre where the
-- frame outgrew them.
function M.limits(bounds, aspect)
	local f = M.frame(aspect)
	local dx = f.half_w - FRAME_4_3.half_w
	local x_lo, x_hi = bounds.x_min + dx, bounds.x_max - dx
	if x_lo > x_hi then
		x_lo = (bounds.x_min + bounds.x_max) / 2
		x_hi = x_lo
	end
	local z_lo, z_hi = bounds.z_min + (f.far - FRAME_4_3.far), bounds.z_max - (FRAME_4_3.near - f.near)
	if z_lo > z_hi then  -- also when the top ray clears the horizon (an infinite far edge)
		z_lo = (bounds.z_min + bounds.z_max) / 2
		z_hi = z_lo
	end
	return x_lo, x_hi, z_lo, z_hi
end

-- The canvas aspects (min, max) up to which `limits` still has room in `bounds`: the
-- frame's half-width grows linearly with a wider aspect; on the taller side both the far
-- edge and the width at it grow, the limit is found by bisection.
function M.aspect_limits(bounds)
	local max_aspect = screen.ASPECT * (1 + (bounds.x_max - bounds.x_min) / 2 / FRAME_4_3.half_w)
	local fits, outgrown = screen.ASPECT, TALLEST_ASPECT
	for _ = 1, MIN_ASPECT_STEPS do
		local mid = (fits + outgrown) / 2
		local x_lo, x_hi, z_lo, z_hi = M.limits(bounds, mid)
		if x_hi > x_lo and z_hi > z_lo then
			fits = mid
		else
			outgrown = mid
		end
	end
	return fits, max_aspect
end

return M
