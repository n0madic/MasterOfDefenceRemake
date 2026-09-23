-- Touch gestures for the map on phones and tablets, engine independent: a tap is the left
-- click, a still press held long enough the right click (cancel, deselect, send the
-- balloon), a moving press drags the camera. Feed it the press, the moves and the release
-- (box coordinates, milliseconds); it answers what happened.
local M = {}
M.__index = M

M.DRAG_THRESHOLD = 12    -- box pixels a press may wander and still be a tap
M.LONG_PRESS_MS = 500

function M.new()
	return setmetatable({down = nil}, M)
end

function M:press(x, y, ms)
	self.down = {x = x, y = y, last_x = x, last_y = y, ms = ms, dragging = false}
end

-- A move while pressed: returns the drag delta since the last move, or nil.
function M:move(x, y)
	local d = self.down
	if not d then
		return nil
	end
	if not d.dragging and (x - d.x) ^ 2 + (y - d.y) ^ 2 > M.DRAG_THRESHOLD ^ 2 then
		d.dragging = true
	end
	if not d.dragging then
		return nil
	end
	local dx, dy = x - d.last_x, y - d.last_y
	d.last_x, d.last_y = x, y
	return dx, dy
end

-- The release: "tap", "long_press" or "drag" (nil without a press).
function M:release(ms)
	local d = self.down
	self.down = nil
	if not d then
		return nil
	end
	if d.dragging then
		return "drag"
	end
	return (ms - d.ms >= M.LONG_PRESS_MS) and "long_press" or "tap"
end

return M
