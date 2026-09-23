-- Blitz `EText3D` strings in a gui scene (docs/13): one box node per 16x16 glyph of the
-- gui.png font (atlas images `g<code>`), placed and coloured per glyph so the `<colR=...>`
-- tags and the per-letter fades of the original work. Coordinates are the 800x600 box with
-- y down. Needs the `hud` atlas as texture `hud` of the gui scene.
local text_layout = require("main.blitz_text")
local screen = require("main.screen")

local M = {}

M.TEXTURE = "hud"

-- A box node of atlas image `image` at box point (x, y) (top-left pivot).
function M.box(x, y, w, h, image, layer)
	local node = gui.new_box_node(vmath.vector3(x, screen.HEIGHT - y, 0), vmath.vector3(w, h, 0))
	gui.set_pivot(node, gui.PIVOT_NW)
	gui.set_texture(node, M.TEXTURE)
	gui.play_flipbook(node, image)
	if layer then
		gui.set_layer(node, layer)
	end
	return node
end

function M.place(node, x, y, w, h)
	gui.set_position(node, vmath.vector3(x, screen.HEIGHT - y, 0))
	if w then
		gui.set_size(node, vmath.vector3(w, h, 0))
	end
end

-- Whether `obj` holds the glyphs of `spec`'s text laid out the same way.
local function same_layout(obj, spec)
	return obj.text == spec.text and obj.scale == spec.scale and obj.spacing == spec.spacing
		and obj.cx == spec.cx and obj.cy == spec.cy
end

-- Whether `obj`'s glyphs already stand where `spec` puts them, in its colour.
local function same_placement(obj, spec, a)
	local p, c = obj.placed, spec.color
	return p ~= nil and p.x == spec.x and p.y == spec.y and p.a == a and p.r == c[1] and p.g == c[2] and p.b == c[3]
end

function M.delete(obj)
	if obj then
		for _, n in ipairs(obj.nodes) do
			gui.delete_node(n)
		end
	end
end

-- Create or update the glyph nodes of text `spec` ({text, x, y, color, alpha, scale,
-- spacing, cx, cy, letter_alpha}); `letter_alpha[i]` multiplies glyph i's alpha (the
-- storyline's letter-by-letter reveal). Returns the object to keep for the next call.
function M.sync(obj, spec, layer)
	if not obj or not same_layout(obj, spec) then
		M.delete(obj)
		obj = {text = spec.text, scale = spec.scale, spacing = spec.spacing, cx = spec.cx, cy = spec.cy, nodes = {},
			layout = text_layout.layout(spec.text, spec.scale, spec.spacing, spec.cx, spec.cy)}
		for _, g in ipairs(obj.layout.glyphs) do
			obj.nodes[#obj.nodes + 1] = M.box(0, 0, obj.layout.size, obj.layout.size, "g" .. g.code, layer)
		end
	end
	local c = spec.color
	local a = spec.alpha or 1
	local letters = spec.letter_alpha
	-- The screens sync their texts every frame: unchanged ones are left alone (a letter
	-- reveal animates, so it is always applied).
	if not letters and same_placement(obj, spec, a) then
		return obj
	end
	for i, g in ipairs(obj.layout.glyphs) do
		local n = obj.nodes[i]
		M.place(n, spec.x + g.x, spec.y + g.y)
		gui.set_color(n, vmath.vector4(c[1] * g.r, c[2] * g.g, c[3] * g.b, letters and a * (letters[i] or 0) or a))
	end
	obj.placed = not letters and {x = spec.x, y = spec.y, a = a, r = c[1], g = c[2], b = c[3]} or nil
	return obj
end

-- A letter-by-letter fade-in of `text` (the storyline, the tutorial pages): every glyph
-- gets a random rate in [min_rate, max_rate] per step. `alpha` is the `letter_alpha` list.
function M.new_reveal(text, scale, spacing, min_rate, max_rate)
	local reveal = {alpha = {}, rates = {}}
	for i = 1, M.glyph_count(text, scale, spacing) do
		reveal.alpha[i] = 0
		reveal.rates[i] = min_rate + math.random() * (max_rate - min_rate)
	end
	return reveal
end

-- `steps` steps of a fade-in.
function M.step_reveal(reveal, steps)
	local alpha = reveal.alpha
	for i, rate in ipairs(reveal.rates) do
		alpha[i] = math.min(1, alpha[i] + rate * steps)
	end
end

-- Number of drawn glyphs of `text` (the length of a `letter_alpha` list).
function M.glyph_count(text, scale, spacing)
	return #text_layout.layout(text, scale, spacing).glyphs
end

-- Width of `text` laid out with `scale` / `spacing` (for right-aligned labels).
function M.width(text, scale, spacing)
	return text_layout.layout(text, scale, spacing).width
end

return M
