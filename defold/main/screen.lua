-- The game is drawn in a fixed 800x600 box (the original's resolution) that keeps its 4:3
-- aspect inside the window: render/blitz.render_script letterboxes the world and the HUD
-- panel, and the gui nodes are adjusted the same way by the engine (ADJUST_FIT).
--
-- The engine does not know about that box: `action.x` / `action.y` stretch the *whole*
-- window onto 800x600 (engine.cpp: `x = (x + 0.5) * display_width / window_width`), so a
-- window that is not 4:3 shifts every hit test sideways. Everything that consumes mouse
-- positions converts them here instead.
local M = {}

M.WIDTH, M.HEIGHT = 800, 600

local ASPECT = M.WIDTH / M.HEIGHT

-- Fraction of the window covered by the game box, horizontally and vertically.
function M.fit()
	local w, h = window.get_size()
	if not w or w <= 0 or not h or h <= 0 then
		return 1, 1
	end
	local a = (w / h) / ASPECT
	if a > 1 then
		return 1 / a, 1
	end
	return 1, a
end

-- Mouse position of an input action in the 800x600 box with y pointing down (the HUD's
-- coordinates, docs/13). Positions outside the game box are clamped to it; the third
-- result is false when the cursor is outside the window altogether (the browser keeps
-- sending moves for the whole page), which stops the edge scrolling from latching on.
function M.mouse(action)
	local fx, fy = M.fit()
	local inside = action.x >= 0 and action.x <= M.WIDTH and action.y >= 0 and action.y <= M.HEIGHT
	local x = (action.x / M.WIDTH - (1 - fx) / 2) / fx * M.WIDTH
	local y = (action.y / M.HEIGHT - (1 - fy) / 2) / fy * M.HEIGHT
	x = math.max(0, math.min(M.WIDTH, x))
	y = math.max(0, math.min(M.HEIGHT, y))
	return x, M.HEIGHT - y, inside
end

return M
