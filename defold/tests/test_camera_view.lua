-- Wide mode camera limits (main/location/camera_view.lua).
local camera_view = require("main.location.camera_view")
local screen = require("main.screen")

local EPS = 1e-6

local function near(a, b)
	return math.abs(a - b) < EPS
end

return function(h)
	local check = h.check
	local l1 = {x_min = 50, x_max = 70, z_min = -40, z_max = 0}
	local l2 = {x_min = 10, x_max = 110, z_min = -100, z_max = 0}

	-- 4:3 keeps the original range.
	local x_lo, x_hi, z_lo, z_hi = camera_view.limits(l1, screen.ASPECT)
	check(near(x_lo, 50) and near(x_hi, 70) and near(z_lo, -40) and near(z_hi, 0), "4:3 keeps the original range")

	-- Wider: only x narrows, by the extra ground along the top row.
	local min2, max2 = camera_view.aspect_limits(l2)
	check(max2 > 2.5, "a wide location is not capped at the menu's 1.8")
	local aspect = 2
	x_lo, x_hi, z_lo, z_hi = camera_view.limits(l2, aspect)
	local dx = camera_view.frame(aspect).half_w - camera_view.frame(screen.ASPECT).half_w
	check(dx > 0 and near(x_lo, 10 + dx) and near(x_hi, 110 - dx), "a wider canvas narrows x by the extra ground")
	check(near(z_lo, -100) and near(z_hi, 0), "a wider canvas keeps the z range")

	-- The max aspect pins x to the centre.
	local min1, max1 = camera_view.aspect_limits(l1)
	check(max1 > screen.ASPECT and max1 < max2, "location 1's narrow x range caps Wide early")
	x_lo, x_hi = camera_view.limits(l1, max1)
	check(near(x_lo, 60) and near(x_hi, 60), "at the max aspect the pivot is pinned to the centre in x")

	-- Taller: the far edge and the width at it grow, so both ranges narrow.
	check(min1 < screen.ASPECT and min2 < screen.ASPECT, "a location may be drawn taller than 4:3")
	aspect = (min2 + screen.ASPECT) / 2
	x_lo, x_hi, z_lo, z_hi = camera_view.limits(l2, aspect)
	check(x_lo > 10 and x_hi < 110 and x_lo < x_hi, "a taller canvas narrows x")
	check(z_lo > -100 and z_hi < 0 and z_lo < z_hi, "a taller canvas narrows z")
	x_lo, x_hi, z_lo, z_hi = camera_view.limits(l2, min2 * 0.99)
	check(near(x_lo, x_hi) or near(z_lo, z_hi), "beyond the min aspect a range collapses")

	-- A taller canvas keeps the horizontal field of view.
	local t43 = screen.tan_half_fov(screen.ASPECT)
	check(near(screen.tan_half_fov(1), t43 * screen.ASPECT), "a taller canvas keeps the horizontal fov")
	check(near(screen.tan_half_fov(2), t43), "a wider canvas keeps the vertical fov")

	-- The canvas follows the window within the screen's range; 4:3 mode letterboxes.
	local layouts = {
		{wide = false, win = {1600, 600}, canvas = {800, 600}, box = {800, 600}},
		{wide = false, win = {600, 1000}, canvas = {600, 450}, box = {600, 450}},
		{wide = true, win = {1600, 600}, canvas = {1500, 600}, box = {800, 600}},  -- capped at 2.5
		{wide = true, win = {1200, 600}, canvas = {1200, 600}, box = {800, 600}},
		{wide = true, win = {600, 1000}, canvas = {600, 750}, box = {600, 450}},   -- capped at 0.8
		{wide = true, win = {600, 700}, canvas = {600, 700}, box = {600, 450}},
	}
	screen.min_aspect, screen.max_aspect = 0.8, 2.5
	for _, c in ipairs(layouts) do
		screen.wide = c.wide
		local canvas, box = screen.layout(c.win[1], c.win[2])
		local what = string.format("%s %dx%d", c.wide and "wide" or "4:3", c.win[1], c.win[2])
		check(canvas.w == c.canvas[1] and canvas.h == c.canvas[2], what .. ": canvas")
		check(box.w == c.box[1] and box.h == c.box[2], what .. ": box")
		check(box.x == math.floor((c.win[1] - box.w) / 2) and box.y == math.floor((c.win[2] - box.h) / 2), what .. ": box centred")
	end
	screen.wide, screen.min_aspect, screen.max_aspect = false, screen.ASPECT, screen.ASPECT
end
