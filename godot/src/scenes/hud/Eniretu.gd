## The 2D widgets of the original's "Eniretu" GUI library (`_feslider`, `_fecheckbox`,
## `_feradiobutton`, `_felabel`, `_fetextbox`; docs/13), drawn from `gui.png` at the
## original 800x600 coordinates.
class_name Eniretu
extends RefCounted

const TOGGLE_SIZE := Vector2(20, 20)
const TOGGLE_CAPTION_OFFSET := Vector2(18, 2)
const SLIDER_EDGE := 7
const SLIDER_HEIGHT := 16
const KNOB_SIZE := 32
const TEXTBOX_HEIGHT := 20
const TEXTBOX_CORNER := 6
const TEXTBOX_TEXT_OFFSET := 2.0
const CURSOR_BLINK_MS := 200
const KEYBOARD_MARGIN := 8.0  # canvas px kept between a lifted text box and the keyboard


## `ESlider`: atlas track with the 32x32 knob; `value` in `[min_value, max_value]`.
class AtlasSlider:
	extends Control

	signal value_changed(value: float)

	var input: HSlider
	var knob: TextureRect
	var value: float:
		get:
			return input.value
		set(v):
			input.value = v
	var min_value: float:
		get:
			return input.min_value
		set(v):
			input.min_value = v
	var max_value: float:
		get:
			return input.max_value
		set(v):
			input.max_value = v

	func _init(rect: Rect2, lo: float, hi: float, initial: float, step := 1.0) -> void:
		position = rect.position
		size = rect.size
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		var track := NinePatchRect.new()
		track.texture = GuiAtlas.slider_track()
		track.size = rect.size
		track.patch_margin_left = SLIDER_EDGE
		track.patch_margin_right = SLIDER_EDGE
		track.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(track)
		input = HSlider.new()
		input.size = rect.size
		input.min_value = lo
		input.max_value = hi
		input.step = step
		input.value = initial
		input.modulate.a = 0.0  # invisible, only handles input; the knob is drawn below
		input.value_changed.connect(func(v): _place_knob(); value_changed.emit(v))
		add_child(input)
		knob = TextureRect.new()
		knob.texture = GuiAtlas.slider_knob()
		knob.size = Vector2(KNOB_SIZE, KNOB_SIZE)
		knob.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(knob)
		_place_knob()

	func set_value_no_signal(v: float) -> void:
		input.set_value_no_signal(v)
		_place_knob()

	func _place_knob() -> void:
		var span := input.max_value - input.min_value
		var frac := (input.value - input.min_value) / span if span > 0.0 else 0.0
		var x := SLIDER_EDGE + frac * (size.x - 2 * SLIDER_EDGE) - KNOB_SIZE / 2.0
		knob.position = Vector2(x, (size.y - KNOB_SIZE) / 2.0 + 4)


## `ETextBox`: black block with the text and a blinking `_` cursor while focused.
class TextBox:
	extends Control

	signal text_changed(text: String)

	var text := ""
	var max_length := 20
	var label: BlitzText
	var focused := false
	var cursor_on := false
	var cursor_timer := 0
	var keyboard_seen := false  # the virtual keyboard came up for this focus
	var rest_position := Vector2.ZERO  # where the box sits when no keyboard lifts it
	# A platform capability, fixed for the process lifetime: read once instead of on every
	# focus change and every polling frame below.
	var has_virtual_keyboard := DisplayServer.has_feature(DisplayServer.FEATURE_VIRTUAL_KEYBOARD)

	func _init(rect: Rect2, initial: String) -> void:
		position = rect.position
		size = rect.size
		text = initial
		mouse_filter = Control.MOUSE_FILTER_STOP
		var block := NinePatchRect.new()
		block.texture = GuiAtlas.textbox_block()
		block.size = rect.size
		for side in ["left", "right", "top", "bottom"]:
			block.set("patch_margin_" + side, TEXTBOX_CORNER)
		block.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(block)
		label = BlitzText.new()
		label.position = Vector2(TEXTBOX_TEXT_OFFSET, rect.size.y / 2.0)
		label.center_y = true
		add_child(label)
		_refresh()

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed:
			set_focused(true)
			accept_event()

	func _unhandled_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed:
			set_focused(false)
		elif focused and event is InputEventKey and event.pressed:
			var key := event as InputEventKey
			if key.keycode == KEY_BACKSPACE:
				text = text.left(text.length() - 1)
			elif key.keycode == KEY_ENTER or key.keycode == KEY_ESCAPE:
				set_focused(false)
			elif key.unicode >= 32 and key.unicode < 127 and text.length() < max_length:
				text += char(key.unicode)
			_refresh()
			text_changed.emit(text)
			get_viewport().set_input_as_handled()

	## Focus shows the platform's virtual keyboard (skipped on desktop, which has none);
	## it is seeded with the text so backspace reaches into it. Its keys arrive as
	## InputEventKey above.
	func set_focused(on: bool) -> void:
		if on == focused:
			return
		focused = on
		keyboard_seen = false
		if on:
			rest_position = position
			if has_virtual_keyboard:
				DisplayServer.virtual_keyboard_show(text, Rect2(), DisplayServer.KEYBOARD_TYPE_DEFAULT, max_length)
		else:
			if has_virtual_keyboard:
				DisplayServer.virtual_keyboard_hide()
			position = rest_position
		_refresh()

	func _process(_delta: float) -> void:
		if not focused:
			return
		# The keyboard dismissed from its own side (Back on Android) ends the edit;
		# desktop has no virtual keyboard to poll (`get_height` would just warn there).
		if has_virtual_keyboard:
			var keyboard_height := DisplayServer.virtual_keyboard_get_height()
			if keyboard_height > 0:
				keyboard_seen = true
				_lift_above_keyboard(keyboard_height)
			elif keyboard_seen:
				set_focused(false)
				return
		var now := Time.get_ticks_msec()
		if now > cursor_timer + CURSOR_BLINK_MS:
			cursor_on = not cursor_on
			cursor_timer = now
			_refresh()

	## The game window is not resized by the keyboard (immersive mode): a box the keyboard
	## would cover moves up to sit just above it for the time of the edit.
	func _lift_above_keyboard(keyboard_px: int) -> void:
		var canvas_h := get_viewport().get_visible_rect().size.y
		var window_h := float(get_window().size.y)
		if window_h <= 0.0:
			return
		var keyboard_top := canvas_h - float(keyboard_px) * canvas_h / window_h
		var bottom := global_position.y - position.y + rest_position.y + size.y + KEYBOARD_MARGIN
		position.y = rest_position.y - maxf(0.0, bottom - keyboard_top)

	func _refresh() -> void:
		label.text = text + ("_" if focused and cursor_on else "")


static func label(pos: Vector2, text: String, color := Color.WHITE) -> BlitzText:
	var t := BlitzText.new()
	t.position = pos
	t.text = text
	t.color = color
	return t


## Checkbox (`radio = false`) or radio button: the 16x16 atlas icon drawn 20x20 with the
## caption 18 px to the right.
static func toggle(pos: Vector2, caption: String, on: bool, radio: bool) -> TextureButton:
	var b := TextureButton.new()
	b.toggle_mode = true
	b.texture_normal = GuiAtlas.radio(0, false) if radio else GuiAtlas.checkbox(0, false)
	b.texture_pressed = GuiAtlas.radio(0, true) if radio else GuiAtlas.checkbox(0, true)
	b.texture_hover = GuiAtlas.radio(1, false) if radio else GuiAtlas.checkbox(1, false)
	b.ignore_texture_size = true
	b.stretch_mode = TextureButton.STRETCH_SCALE
	b.size = TOGGLE_SIZE
	b.position = pos
	b.button_pressed = on
	if radio:
		# A radio button never un-presses itself; the group handler releases the others.
		b.toggled.connect(func(pressed): if not pressed: b.set_pressed_no_signal(true))
	if caption != "":
		var t := label(TOGGLE_CAPTION_OFFSET, caption)
		t.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(t)
	return b


static func slider(rect: Rect2, lo: float, hi: float, initial: float, step := 1.0) -> AtlasSlider:
	return AtlasSlider.new(rect, lo, hi, initial, step)


static func textbox(rect: Rect2, initial: String) -> TextBox:
	return TextBox.new(rect, initial)
