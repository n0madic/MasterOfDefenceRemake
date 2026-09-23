-- Fixed-step game clock (main/ticker.lua).
local Ticker = require("main.ticker")

return function(h)
	local check = h.check
	local t = Ticker.new()
	check(t:period_ms() == 16, "slider 20 -> 16 ms")
	t:set_slider(100)
	check(t:fps() == 140 and t:period_ms() == 7, "slider dragged to 100 -> fps 140, 7 ms")
	t:set_fast_speed()
	check(t:fps() == 120 and t:period_ms() == 8, "M -> fps 120, 8 ms")
	check(t.slider == 100, "M draws the slider at 100")
	t:set_normal_speed()
	check(t:fps() == 60 and t.slider == 20, "N -> fps 60, slider 20")
	check(t:advance(0.05) == 3, "50 ms at 16 ms per tick = 3 ticks")
	check(t:advance(0.015) == 1, "the 2 ms remainder carries over")
end
