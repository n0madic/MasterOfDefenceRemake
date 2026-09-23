-- Blitz text layout helpers (main/blitz_text.lua).
local text_layout = require("main.blitz_text")

return function(h)
	local check = h.check
	check(text_layout.utf8_length("Иван") == 4, "UTF-8 length counts characters")
	check(text_layout.utf8_head("Иван", 3) == "Ива", "a Cyrillic name loses whole characters")
	check(text_layout.utf8_head("abc", 0) == "" and text_layout.utf8_head("Иван", 10) == "Иван", "head bounds")
	-- A sequence cut in the middle (a byte-wise edit) shows one unknown glyph, no error.
	local ok, layout = pcall(text_layout.layout, "Ив" .. string.char(0xD0), 1, 5, 0, 0)
	check(ok, "a cut UTF-8 sequence lays out: " .. tostring(layout))
end
