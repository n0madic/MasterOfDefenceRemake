-- Where the game is drawn in the window. The original is an 800x600 game: its HUD, sheets
-- and gui live in that 4:3 "box", centred in the window at full height (or full width in a
-- tall window). The 3D world fills the "canvas": the box itself, or in Wide mode (a
-- setting) the window up to `max_aspect` (the scene decides how wide it still looks
-- right). The canvas grows along the axis the window has room on: wider than 4:3 up to
-- `max_aspect`, taller down to `min_aspect`; the box stays centred in it. The render script
-- (the gui keeps its 800x600 coordinates, drawn into the box) and the mouse mapping all use
-- this module (`script.shared_state`).
--
-- The engine does not know about the box: `action.x` / `action.y` stretch the *whole*
-- window onto 800x600 (engine.cpp: `x = (x + 0.5) * display_width / window_width`), so
-- everything that consumes mouse positions converts them here.
local M = {}

M.WIDTH, M.HEIGHT = 800, 600
M.ASPECT = M.WIDTH / M.HEIGHT
-- The vertical field of view of every camera (the original's `_fsetfov 60`: 60 degrees
-- horizontal at 4:3); the location and menu camera.go files carry the same value.
M.FOV = 0.8173

M.wide = false                 -- the Wide setting
M.min_aspect = M.ASPECT        -- how tall the current screen may be drawn
M.max_aspect = M.ASPECT        -- how wide the current screen may be drawn

-- Tangent of the half vertical field of view for a canvas of `aspect`: the original 4:3
-- frame stays in view, so a wider canvas keeps the vertical fov and a taller one the
-- horizontal one.
function M.tan_half_fov(aspect)
	return math.tan(M.FOV / 2) * math.max(1, M.ASPECT / aspect)
end

-- The vertical field of view of the cameras for a canvas of `aspect`.
function M.fov(aspect)
	return 2 * math.atan(M.tan_half_fov(aspect))
end

-- The last layout (the render script, the camera and the mouse mapping ask every frame).
local last = {}

-- The canvas and the box in window pixels, {x, y, w, h} with y up (shared tables: do not
-- modify them).
function M.layout(win_w, win_h)
	if last.w == win_w and last.h == win_h and last.wide == M.wide and last.min_aspect == M.min_aspect
		and last.max_aspect == M.max_aspect then
		return last.canvas, last.box
	end
	local aspect = win_w / win_h
	local lo = M.wide and math.min(M.ASPECT, M.min_aspect) or M.ASPECT
	local hi = M.wide and math.max(M.ASPECT, M.max_aspect) or M.ASPECT
	local canvas_aspect = math.max(lo, math.min(hi, aspect))
	local cw, ch
	if aspect > canvas_aspect then
		ch = win_h
		cw = math.floor(win_h * canvas_aspect)
	else
		cw = win_w
		ch = math.floor(win_w / canvas_aspect)
	end
	local canvas = {x = math.floor((win_w - cw) / 2), y = math.floor((win_h - ch) / 2), w = cw, h = ch}
	local bw, bh = cw, ch
	if cw / ch > M.ASPECT then
		bw = math.floor(ch * M.ASPECT)
	else
		bh = math.floor(cw / M.ASPECT)
	end
	local box = {x = math.floor((win_w - bw) / 2), y = math.floor((win_h - bh) / 2), w = bw, h = bh}
	last = {w = win_w, h = win_h, wide = M.wide, min_aspect = M.min_aspect, max_aspect = M.max_aspect, canvas = canvas, box = box}
	return canvas, box
end

-- The window size in the units of `action.x` / `action.y` fractions.
local function window_rects()
	local w, h = window.get_size()
	if not w or w <= 0 or not h or h <= 0 then
		w, h = M.WIDTH, M.HEIGHT
	end
	local canvas, box = M.layout(w, h)
	return w, h, canvas, box
end

-- Window fraction (0..1, y down) of an input action; `inside` is false when the cursor
-- is outside the window altogether (the browser keeps sending page-wide moves).
local function fraction(action)
	local inside = action.x >= 0 and action.x <= M.WIDTH and action.y >= 0 and action.y <= M.HEIGHT
	return action.x / M.WIDTH, 1 - action.y / M.HEIGHT, inside
end

-- Mouse position of an input action in the 800x600 box with y pointing down (the HUD's
-- coordinates, docs/13), clamped to it; third result as `fraction`.
function M.mouse(action)
	local fx, fy, inside = fraction(action)
	local w, h, _, box = window_rects()
	local x = (fx * w - box.x) / box.w * M.WIDTH
	-- `box.y` counts from the bottom, fy from the top.
	local y = (fy * h - (h - box.y - box.h)) / box.h * M.HEIGHT
	return math.max(0, math.min(M.WIDTH, x)), math.max(0, math.min(M.HEIGHT, y)), inside
end

-- Box point (y down) of a canvas point given as NDC (-1..1, y up), e.g. a world point
-- projected by the screen's camera.
function M.box_of_canvas_ndc(nx, ny)
	local w, h, canvas, box = window_rects()
	local px = canvas.x + (nx + 1) / 2 * canvas.w
	local py = canvas.y + (ny + 1) / 2 * canvas.h
	return (px - box.x) / box.w * M.WIDTH, (1 - (py - box.y) / box.h) * M.HEIGHT
end

-- Mouse position in the canvas: (x, y) with y up, and the canvas size in the same units
-- (box pixels: the box is 800x600 in them), for rays through the world camera; fifth
-- result as `fraction`.
function M.canvas_mouse(action)
	local fx, fy, inside = fraction(action)
	local w, h, canvas, box = window_rects()
	local cw = M.WIDTH * canvas.w / box.w
	local ch = M.HEIGHT * canvas.h / box.h
	local x = (fx * w - canvas.x) / canvas.w * cw
	local y = (1 - (fy * h - (h - canvas.y - canvas.h)) / canvas.h) * ch
	return math.max(0, math.min(cw, x)), math.max(0, math.min(ch, y)), cw, ch, inside
end

return M
