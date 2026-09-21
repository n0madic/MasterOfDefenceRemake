## Text drawn with the 16x16 glyph grid of gui.png exactly like `EText3D` (docs/13):
## glyph = 16*scale square, advance = (16 - spacing)*scale, the first glyph is drawn one
## advance to the right of `position`, `\n` moves down by 0.8 * 16 * scale, and
## `<colR=nnn><colG=nnn><colB=nnn>` tags change the colour. `letter_alpha`, when set,
## gives each character its own alpha (the storyline/tutorial reveal effect).
class_name BlitzText
extends Control

const GLYPH := 16.0
const LINE_FACTOR := 0.8
const ATLAS_FONT_ORIGIN := Vector2(0, 256)
const TAG_LENGTH := 10  # "<colR=nnn>"

@export var text := "":
	set(v):
		if v == text:
			return  # the HUD re-assigns its texts every frame
		text = v
		_parse()
		queue_redraw()
@export var text_scale := 1.0:
	set(v):
		text_scale = v
		queue_redraw()
@export var spacing := 5.0:
	set(v):
		spacing = v
		queue_redraw()
@export var center_x := false:
	set(v):
		center_x = v
		queue_redraw()
@export var center_y := false:
	set(v):
		center_y = v
		queue_redraw()
@export var color := Color.WHITE:
	set(v):
		color = v
		queue_redraw()
var letter_alpha := PackedFloat32Array():
	set(v):
		letter_alpha = v
		queue_redraw()

# Parsed runs: [{"char": int (cp1251 byte, -1 for newline), "color": Color}]
var _glyphs: Array = []
var _line_lengths: Array[int] = []


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_parse()


func advance() -> float:
	return (GLYPH - spacing) * text_scale


## `TextWidth`: length of the longest line times the advance (tags excluded).
func text_width() -> float:
	var longest := 0
	for n in _line_lengths:
		longest = maxi(longest, n)
	return longest * advance()


func text_height() -> float:
	return GLYPH * text_scale


func _parse() -> void:
	_glyphs.clear()
	_line_lengths.clear()
	var c := Color.WHITE
	var i := 0
	var n := 0
	var s := text
	while i < s.length():
		var ch := s[i]
		if ch == "<" and i + TAG_LENGTH <= s.length() and s.substr(i, 5) in ["<colR", "<colG", "<colB"] and s[i + TAG_LENGTH - 1] == ">":
			var v := float(s.substr(i + 6, 3)) / 255.0
			match s[i + 4]:
				"R": c.r = v
				"G": c.g = v
				"B": c.b = v
			i += TAG_LENGTH
			continue
		if ch == "\n":
			_glyphs.append({"char": -1, "color": c})
			_line_lengths.append(n)
			n = 0
		else:
			_glyphs.append({"char": _cp1251(ch), "color": c})
			n += 1
		i += 1
	_line_lengths.append(n)


## Unicode character -> cp1251 byte (glyph index in the atlas).
static func _cp1251(ch: String) -> int:
	var code := ch.unicode_at(0)
	if code < 128:
		return code
	if code >= 0x410 and code <= 0x44F:
		return 0xC0 + (code - 0x410)
	if code == 0x401:
		return 0xA8
	if code == 0x451:
		return 0xB8
	return 63  # '?'


func _draw() -> void:
	var atlas := GuiAtlas.atlas()
	var step := advance()
	var size := GLYPH * text_scale
	var line_h := LINE_FACTOR * size
	var origin := Vector2.ZERO
	if center_x:
		origin.x -= text_width() / 2.0
	if center_y:
		origin.y -= text_height() / 2.0
	var col := 0
	var line := 0
	var index := 0
	for g in _glyphs:
		var code: int = g["char"]
		if code == -1:
			line += 1
			col = 0
			continue
		col += 1  # the cursor advances before the glyph is drawn (EText3D quirk)
		if code == 32:
			index += 1
			continue
		var c: Color = g["color"]
		var a := color.a
		if index < letter_alpha.size():
			a = letter_alpha[index]
		var tint := Color(color.r * c.r, color.g * c.g, color.b * c.b, a)
		var src := Rect2(ATLAS_FONT_ORIGIN + Vector2(GLYPH * (code % 16), GLYPH * (code / 16)), Vector2(GLYPH, GLYPH))
		var dst := Rect2(origin + Vector2(col * step, line * line_h), Vector2(size, size))
		draw_texture_rect_region(atlas, dst, src, tint)
		index += 1


## Number of characters that carry alpha (letters, spaces excluded from drawing but counted).
func letter_count() -> int:
	var n := 0
	for g in _glyphs:
		if g["char"] != -1:
			n += 1
	return n
