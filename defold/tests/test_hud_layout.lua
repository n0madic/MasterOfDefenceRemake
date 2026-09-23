-- Wide-screen HUD anchors (main/screen.lua `anchor_shifts_for`, main/location/hud_model.lua).
local screen = require("main.screen")
local hud = require("main.location.hud_model")

local EPS = 1e-9

local function near(a, b)
	return math.abs(a - b) < EPS
end

return function(h)
	local check = h.check
	screen.wide, screen.min_aspect, screen.max_aspect = true, 0.8, 2.5

	-- A 1200x600 window: the box is 800 wide in the middle, 200 box pixels each side.
	local canvas, box = screen.layout(1200, 600)
	local l, t, r, b = screen.margins(canvas, box)
	check(near(l, 200) and near(r, 200) and near(t, 0) and near(b, 0), "margins of a wide canvas")
	l, t, r, b = screen.anchor_shifts_for(1200, 600, {})
	check(near(l, 200) and near(r, 200) and near(t, 0) and near(b, 0), "without a safe area the groups reach the canvas edges")
	-- A notch of 50 px on the left, a gesture bar of 30 px at the bottom (window pixels,
	-- here box pixels too): the groups stay inside the safe area.
	l, t, r, b = screen.anchor_shifts_for(1200, 600, {inset_left = 50, inset_top = 0, inset_right = 0, inset_bottom = 30})
	check(near(l, 150) and near(r, 200) and near(t, 0) and near(b, -30), "the safe area pulls the groups in")
	-- Letterbox bars already cover an inset: a 3000x600 window is capped at 2.5 (1500 wide),
	-- 750 px bars on each side cover a 50 px notch.
	l = screen.anchor_shifts_for(3000, 600, {inset_left = 50})
	check(near(l, 350), "a letterbox bar covers the inset")
	-- A tall window: the box margins are above and below.
	canvas, box = screen.layout(800, 800)
	l, t, r, b = screen.margins(canvas, box)
	check(near(l, 0) and near(r, 0) and near(t, 100) and near(b, 100), "margins of a tall canvas")

	-- The widgets move with their anchors; hit tests follow them.
	hud.set_anchor_shifts(200, 0, 200, 50)
	local dx, dy = hud.anchor_offset(hud.BOTTOM_LEFT)
	check(dx == -200 and dy == 50, "bottom-left offset")
	dx, dy = hud.anchor_offset(hud.TOP_RIGHT)
	check(dx == 200 and dy == 0, "top-right offset")
	dx, dy = hud.anchor_offset(nil)
	check(dx == 0 and dy == 0, "no anchor stays in the box")
	local sell = hud.by_name.sell
	local tower1 = hud.by_name.tower1
	hud.place_widgets()
	check(hud.widget_at(sell.x0 + 200 + 1, sell.y0 + 50 + 1) == sell, "the sell button is hit at its anchored place")
	check(hud.widget_at(tower1.x0 - 200 + 1, tower1.y0 + 50 + 1) == tower1, "the first tower button is hit at the left edge")
	check(hud.widget_at(sell.x0 + 1, sell.y0 + 1) ~= sell, "not at its box place")
	hud.set_anchor_shifts(0, 0, 0, 0)
	hud.place_widgets()
	screen.wide, screen.min_aspect, screen.max_aspect = false, screen.ASPECT, screen.ASPECT
end
