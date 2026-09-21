## Slices of `gui.png` (docs/13): buttons, slider, progress bar, checkbox, 9-slice frame.
class_name GuiAtlas
extends RefCounted

const ATLAS_PATH := "res://assets/textures/gui.png"
const BIG := 64
const SMALL := 32
const STYLE_BIG := 0
const STYLE_SMALL1 := 1
const STYLE_SMALL2 := 2

static var _atlas: Texture2D = null


static func atlas() -> Texture2D:
	if _atlas == null:
		_atlas = load(ATLAS_PATH)
	return _atlas


static func region(x: int, y: int, w: int, h: int) -> AtlasTexture:
	var t := AtlasTexture.new()
	t.atlas = atlas()
	t.region = Rect2(x, y, w, h)
	return t


## Button icon `icon` in style `style`; `state` 0 normal, 1 hover, 2 pressed.
static func button(style: int, icon: int, state: int) -> AtlasTexture:
	match style:
		STYLE_BIG:
			return region(256 + BIG * state, BIG * (icon - 1), BIG, BIG)
		STYLE_SMALL1:
			return region(192 + SMALL * (icon - 1), 64 + SMALL * state, SMALL, SMALL)
		_:
			return region(128 + SMALL * (icon - 1), 160 + SMALL * state, SMALL, SMALL)


static func slider_track() -> AtlasTexture:
	return region(64, 128, 32, 16)


static func slider_knob() -> AtlasTexture:
	return region(64, 160, 32, 32)


static func progress_frame() -> AtlasTexture:
	return region(0, 128, 64, 32)


static func progress_fill() -> AtlasTexture:
	return region(0, 160, 64, 32)


## Checkbox: `held` state column (0 normal, 1 held, 2 pressed), `on` row.
static func checkbox(state: int, on: bool) -> AtlasTexture:
	return region(192 + 16 * state, 48 if on else 32, 16, 16)


## Radio button: the dotted circles above the checkboxes.
static func radio(state: int, on: bool) -> AtlasTexture:
	return region(192 + 16 * state, 16 if on else 0, 16, 16)


## `ETextBox` background (`_feblock` u 0.5..0.75 of 256, v 0.0625..0.125).
static func textbox_block() -> AtlasTexture:
	return region(128, 32, 64, 32)


## Tooltip / help block: `_feblock(..., u 0..0.0625, v 0.375..0.4375)` = 32x32 at (0, 192),
## a 50 % black square whose first row is transparent.
static func frame() -> AtlasTexture:
	return region(0, 192, 32, 32)


## A TextureButton with the three states of the atlas.
static func make_button(style: int, icon: int, size: Vector2) -> TextureButton:
	var b := TextureButton.new()
	b.texture_normal = button(style, icon, 0)
	b.texture_hover = button(style, icon, 1)
	b.texture_pressed = button(style, icon, 2)
	b.texture_disabled = button(style, icon, 0)
	b.ignore_texture_size = true
	b.stretch_mode = TextureButton.STRETCH_SCALE
	b.custom_minimum_size = size
	b.size = size
	return b
