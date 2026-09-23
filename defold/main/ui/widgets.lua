-- The 2D widgets of the original's "Eniretu" library (`_felabel`, `_fecheckbox`,
-- `_feradiobutton`, `_feslider`, `_fetextbox`; docs/13) for gui scripts, drawn from the
-- gui.png atlas at 800x600 box coordinates (y down). A panel holds widgets, draws them and
-- takes the input over them.
local glyph_text = require("main.ui.glyph_text")
local text_layout = require("main.blitz_text")

local M = {}
M.__index = M

local TOGGLE_SIZE = 20
local CAPTION_DX, CAPTION_DY = 18, 2
local SLIDER_EDGE, KNOB = 7, 32
local TEXTBOX_CORNER, TEXTBOX_TEXT_DX = 6, 2
local CURSOR_BLINK_MS = 200
local WHITE = {1, 1, 1}
local CLICK, TEXT, BACKSPACE = hash("click"), hash("text"), hash("key_backspace")

function M.new()
	return setmetatable({widgets = {}, visible = true}, M)
end

local function add(self, w)
	self.widgets[#self.widgets + 1] = w
	return w
end

local function text_spec(s, x, y)
	return {text = s, x = x, y = y, color = WHITE, scale = 1, spacing = 5}
end

function M:label(x, y, s)
	local w = add(self, {kind = "label"})
	w.text = glyph_text.sync(nil, text_spec(s, x, y))
	w.nodes = w.text.nodes
	return w
end

-- A checkbox, or with `group` a radio button of that group (one of them on).
function M:toggle(x, y, caption, on, group)
	local w = add(self, {kind = "toggle", x = x, y = y, w = TOGGLE_SIZE, h = TOGGLE_SIZE, on = on, group = group})
	w.node = glyph_text.box(x, y, TOGGLE_SIZE, TOGGLE_SIZE, "checkbox_off")
	w.nodes = {w.node}
	if caption then
		w.caption = glyph_text.sync(nil, text_spec(caption, x + CAPTION_DX, y + CAPTION_DY))
		for _, n in ipairs(w.caption.nodes) do
			w.nodes[#w.nodes + 1] = n
		end
	end
	self:refresh(w)
	return w
end

function M:slider(x, y, width, height, lo, hi, value)
	local w = add(self, {kind = "slider", x = x, y = y, w = width, h = height, lo = lo, hi = hi, value = value})
	w.track = glyph_text.box(x, y, width, height, "slider_track")
	gui.set_slice9(w.track, vmath.vector4(SLIDER_EDGE, 0, SLIDER_EDGE, 0))
	w.knob = glyph_text.box(x, y, KNOB, KNOB, "slider_knob")
	w.nodes = {w.track, w.knob}
	self:refresh(w)
	return w
end

function M:textbox(x, y, width, height, text, max_length)
	local w = add(self, {kind = "textbox", x = x, y = y, w = width, h = height, value = text, max_length = max_length or 20})
	w.block = glyph_text.box(x, y, width, height, "textbox")
	gui.set_slice9(w.block, vmath.vector4(TEXTBOX_CORNER, TEXTBOX_CORNER, TEXTBOX_CORNER, TEXTBOX_CORNER))
	w.nodes = {w.block}
	self:refresh(w)
	return w
end

function M:refresh(w)
	if w.kind == "toggle" then
		gui.play_flipbook(w.node, (w.group and "radio_" or "checkbox_") .. (w.on and "on" or "off"))
	elseif w.kind == "slider" then
		local frac = w.hi > w.lo and (w.value - w.lo) / (w.hi - w.lo) or 0
		glyph_text.place(w.knob, w.x + SLIDER_EDGE + frac * (w.w - 2 * SLIDER_EDGE) - KNOB / 2, w.y + (w.h - KNOB) / 2 + 4)
	elseif w.kind == "textbox" then
		local shown = w.value .. ((w.focused and w.cursor_on) and "_" or "")
		w.text = glyph_text.sync(w.text, text_spec(shown, w.x + TEXTBOX_TEXT_DX, w.y + w.h / 2 - 8))
		for _, n in ipairs(w.text.nodes) do
			gui.set_enabled(n, self.visible)
		end
	end
end

function M:set_visible(on)
	self.visible = on
	for _, w in ipairs(self.widgets) do
		for _, n in ipairs(w.nodes) do
			gui.set_enabled(n, on)
		end
		if w.text and w.kind == "textbox" then
			for _, n in ipairs(w.text.nodes) do
				gui.set_enabled(n, on)
			end
		end
		w.focused = false
	end
	self.dragging = nil
	if not on then
		gui.hide_keyboard()
	end
end

local function inside(w, x, y)
	return x >= w.x and x < w.x + w.w and y >= w.y and y < w.y + w.h
end

-- Slider `w` set from box x and redrawn; returns it.
local function slide(self, w, x)
	local frac = (x - w.x - SLIDER_EDGE) / (w.w - 2 * SLIDER_EDGE)
	w.value = math.floor(w.lo + math.max(0, math.min(1, frac)) * (w.hi - w.lo) + 0.5)
	self:refresh(w)
	return w
end

-- Input at box point (x, y); returns the widget that changed, nil otherwise.
function M:on_input(action_id, action, x, y)
	if not self.visible then
		return nil
	end
	if action_id == CLICK then
		if action.released then
			self.dragging = nil
			return nil
		end
		if not action.pressed then
			if self.dragging then
				return slide(self, self.dragging, x)
			end
			return nil
		end
		local hit
		for _, w in ipairs(self.widgets) do
			if w.kind == "textbox" then
				w.focused = inside(w, x, y)
				if w.focused then
					gui.show_keyboard(gui.KEYBOARD_TYPE_DEFAULT, false)
				end
				self:refresh(w)
			end
			if w.kind ~= "label" and inside(w, x, y) then
				hit = w
			end
		end
		if not hit then
			return nil
		end
		if hit.kind == "toggle" then
			if hit.group then
				for _, other in ipairs(self.widgets) do
					if other.group == hit.group then
						other.on = other == hit
						self:refresh(other)
					end
				end
			else
				hit.on = not hit.on
				self:refresh(hit)
			end
		elseif hit.kind == "slider" then
			self.dragging = hit
			slide(self, hit, x)
		end
		return hit
	elseif action_id == nil and self.dragging then
		return slide(self, self.dragging, x)
	elseif action_id == TEXT or (action_id == BACKSPACE and action.pressed) then
		for _, w in ipairs(self.widgets) do
			if w.kind == "textbox" and w.focused then
				if action_id == TEXT then
					w.value = text_layout.utf8_head(w.value .. action.text, w.max_length)
				else
					w.value = text_layout.utf8_head(w.value, text_layout.utf8_length(w.value) - 1)
				end
				self:refresh(w)
				return w
			end
		end
	end
	return nil
end

-- The text boxes' cursor blink.
function M:update()
	local now = socket.gettime() * 1000
	for _, w in ipairs(self.widgets) do
		if w.kind == "textbox" and w.focused and now > (w.blink_ms or 0) + CURSOR_BLINK_MS then
			w.cursor_on, w.blink_ms = not w.cursor_on, now
			self:refresh(w)
		end
	end
end

return M
