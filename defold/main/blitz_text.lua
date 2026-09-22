-- Layout of Blitz `EText3D` strings (docs/13): 16x16 glyphs of gui.png, glyph = 16*scale
-- square, advance = (16 - spacing)*scale, the first glyph one advance right of the origin,
-- `\n` moves down 0.8*16*scale, `<colR=nnn><colG=nnn><colB=nnn>` tags change the colour.
local M = {}

M.GLYPH = 16
M.LINE_FACTOR = 0.8
local TAG_LENGTH = 10  -- "<colR=nnn>"

-- UTF-8 string -> list of cp1251 byte codes (-1 = newline) with colours.
local function parse(text)
	local glyphs, lines, line_len = {}, {}, 0
	local r, g, b = 1, 1, 1
	local i, n = 1, #text
	while i <= n do
		local c = text:byte(i)
		if c == 60 and i + TAG_LENGTH - 1 <= n and text:sub(i, i + 3) == "<col" and text:sub(i + TAG_LENGTH - 1, i + TAG_LENGTH - 1) == ">" then
			local channel = text:sub(i + 4, i + 4)
			local v = (tonumber(text:sub(i + 6, i + 8)) or 0) / 255
			if channel == "R" then r = v elseif channel == "G" then g = v elseif channel == "B" then b = v end
			i = i + TAG_LENGTH
		elseif c == 10 then
			glyphs[#glyphs + 1] = {code = -1}
			lines[#lines + 1] = line_len
			line_len = 0
			i = i + 1
		else
			local code, size = c, 1
			if c >= 0xC0 then
				-- UTF-8 lead byte: decode the code point, map Cyrillic to cp1251.
				local cp
				if c >= 0xF0 then
					cp = ((c % 8) * 262144) + ((text:byte(i + 1) % 64) * 4096) + ((text:byte(i + 2) % 64) * 64) + (text:byte(i + 3) % 64)
					size = 4
				elseif c >= 0xE0 then
					cp = ((c % 16) * 4096) + ((text:byte(i + 1) % 64) * 64) + (text:byte(i + 2) % 64)
					size = 3
				else
					cp = ((c % 32) * 64) + (text:byte(i + 1) % 64)
					size = 2
				end
				if cp >= 0x410 and cp <= 0x44F then
					code = 0xC0 + (cp - 0x410)
				elseif cp == 0x401 then
					code = 0xA8
				elseif cp == 0x451 then
					code = 0xB8
				else
					code = 63
				end
			end
			glyphs[#glyphs + 1] = {code = code, r = r, g = g, b = b}
			line_len = line_len + 1
			i = i + size
		end
	end
	lines[#lines + 1] = line_len
	return glyphs, lines
end

-- Returns {glyphs = {{code, x, y, r, g, b}}, width, height, lines} with positions of the
-- glyph squares (top-left corners, y down) relative to the text origin.
function M.layout(text, scale, spacing, center_x, center_y)
	scale = scale or 1
	spacing = spacing or 5
	local glyphs, lines = parse(text)
	local step = (M.GLYPH - spacing) * scale
	local size = M.GLYPH * scale
	local line_h = M.LINE_FACTOR * size
	local longest = 0
	for _, n in ipairs(lines) do
		longest = math.max(longest, n)
	end
	local width = longest * step
	local ox, oy = 0, 0
	if center_x then
		ox = -width / 2
	end
	if center_y then
		oy = -size / 2
	end
	local out = {}
	local col, line = 0, 0
	for _, g in ipairs(glyphs) do
		if g.code == -1 then
			line = line + 1
			col = 0
		else
			col = col + 1  -- the cursor advances before the glyph is drawn (EText3D quirk)
			if g.code ~= 32 then
				out[#out + 1] = {code = g.code, x = ox + col * step, y = oy + line * line_h, r = g.r, g = g.g, b = g.b}
			end
		end
	end
	return {glyphs = out, width = width, height = size, lines = #lines, size = size}
end

function M.line_count(text)
	local n = 1
	for _ in text:gmatch("\n") do
		n = n + 1
	end
	return n
end

return M
