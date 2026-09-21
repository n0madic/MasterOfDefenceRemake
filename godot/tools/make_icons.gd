## Derives the launcher bitmaps the exporters cannot make themselves from res://icons/icon_1024.png
## (rendered by render_icon.gd):
##   godot --headless --path godot -s res://tools/make_icons.gd
## Writes res://icons/ (a .gdignore keeps the PNGs out of the import pipeline; the exporters
## read them directly). The project icon (favicon, the smaller iOS sizes, the editor) is the
## 256 px copy, so the web page does not ship the 1024 px master as its favicon.
extends SceneTree

const ICON := "res://icons/icon_1024.png"
const OUT_DIR := "res://icons"
const PROJECT_ICON_SIZE := 256
const LEGACY_SIZE := 192
const ADAPTIVE_SIZE := 432
## Adaptive icons are masked to the inner ~66%: keep the art inside that safe zone.
const ADAPTIVE_ART_SIZE := 272
const APP_STORE_SIZE := 1024  # App Store icons must be opaque
const BACKGROUND := Color("#1d2a1a")  # dark forest green, the palette of the game's menu


func _init() -> void:
	var icon := Image.load_from_file(ProjectSettings.globalize_path(ICON))
	if icon == null or icon.is_empty():
		push_error("make_icons: cannot read " + ICON)
		quit(1)
		return
	icon.convert(Image.FORMAT_RGBA8)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	_save(_scaled(icon, PROJECT_ICON_SIZE), "icon_256.png")
	_save(_scaled(icon, LEGACY_SIZE), "android_main_192.png")

	var foreground := Image.create_empty(ADAPTIVE_SIZE, ADAPTIVE_SIZE, false, Image.FORMAT_RGBA8)
	var art := _scaled(icon, ADAPTIVE_ART_SIZE)
	var margin := (ADAPTIVE_SIZE - ADAPTIVE_ART_SIZE) / 2
	foreground.blit_rect(art, Rect2i(Vector2i.ZERO, art.get_size()), Vector2i(margin, margin))
	_save(foreground, "android_fg_432.png")

	var background := Image.create_empty(ADAPTIVE_SIZE, ADAPTIVE_SIZE, false, Image.FORMAT_RGBA8)
	background.fill(BACKGROUND)
	_save(background, "android_bg_432.png")

	# Themed (monochrome) icon: the silhouette in white, the alpha carries the shape.
	var mono := foreground.duplicate() as Image
	for y in mono.get_height():
		for x in mono.get_width():
			var a := mono.get_pixel(x, y).a
			mono.set_pixel(x, y, Color(1, 1, 1, a))
	_save(mono, "android_mono_432.png")

	var store := Image.create_empty(APP_STORE_SIZE, APP_STORE_SIZE, false, Image.FORMAT_RGBA8)
	store.fill(BACKGROUND)
	store.blend_rect(_scaled(icon, APP_STORE_SIZE), Rect2i(0, 0, APP_STORE_SIZE, APP_STORE_SIZE), Vector2i.ZERO)
	store.convert(Image.FORMAT_RGB8)
	_save(store, "ios_app_store_1024.png")
	quit()


func _scaled(icon: Image, size: int) -> Image:
	var img := icon.duplicate() as Image
	img.resize(size, size, Image.INTERPOLATE_LANCZOS)
	return img


func _save(img: Image, name: String) -> void:
	var path := OUT_DIR.path_join(name)
	var err := img.save_png(path)
	if err != OK:
		push_error("make_icons: cannot write %s (%d)" % [path, err])
		quit(1)
	print("%s %s" % [path, img.get_size()])
