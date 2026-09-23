-- Wide mode camera limits (main/location/camera_view.lua).
local camera_view = require("main.location.camera_view")
local screen = require("main.screen")

return function(h)
	local check = h.check
	local l1 = {x_min = 50, x_max = 70, z_min = -40, z_max = 0}
	local lo, hi = camera_view.x_limits(l1, screen.ASPECT)
	check(lo == 50 and hi == 70, "4:3 keeps the original x range")
	local wide = camera_view.max_aspect(l1, 1.8)
	check(wide > screen.ASPECT and wide < 1.8, "location 1's narrow x range caps Wide below 1.8")
	lo, hi = camera_view.x_limits(l1, wide)
	check(math.abs(lo - 60) < 1e-9 and math.abs(hi - 60) < 1e-9, "at the cap the pivot is pinned to the centre")
	local l5 = {x_min = 10, x_max = 110, z_min = -100, z_max = 0}
	check(camera_view.max_aspect(l5, 1.8) == 1.8, "a wide x range allows the full 1.8")
	lo, hi = camera_view.x_limits(l5, 1.8)
	local extra = camera_view.extra_half_width(1.8)
	check(math.abs(lo - (10 + extra)) < 1e-9 and math.abs(hi - (110 - extra)) < 1e-9, "the range narrows by the extra ground")
end
