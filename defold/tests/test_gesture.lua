-- Touch gestures (main/input/gesture.lua).
local Gesture = require("main.input.gesture")

return function(h)
	local check = h.check
	local g = Gesture.new()
	g:press(100, 100, 0)
	check(g:move(105, 104) == nil, "a small wander is no drag")
	check(g:release(200) == "tap", "a short press is a tap")
	g:press(100, 100, 0)
	check(g:release(Gesture.LONG_PRESS_MS) == "long_press", "a long still press is the right click")
	g:press(100, 100, 0)
	local dx, dy = g:move(130, 100)
	check(dx == 30 and dy == 0, "past the threshold the press drags")
	dx, dy = g:move(135, 90)
	check(dx == 5 and dy == -10, "drag deltas since the last move")
	check(g:release(2000) == "drag", "a drag ends as a drag, never a click")
	check(g:release(0) == nil, "no release without a press")
end
