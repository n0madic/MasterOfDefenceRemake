## Blitz `LoadAnimTexture` emulation: the atlas is cut into frame textures (left to right,
## top to bottom) and the material's first layer is swapped per frame. Separate textures,
## not UV offsets, so meshes whose UVs run far outside 0..1 (the Location5 river repeats
## the water 15 times) tile within the frame instead of across the atlas.
class_name UvAtlasAnimator
extends RefCounted

var material: Material
var frames: Array[Texture2D] = []


func _init(mat: Material, texture: Texture2D, fw: int, fh: int) -> void:
	material = mat
	var atlas := texture.get_image()
	var columns := maxi(atlas.get_width() / fw, 1)
	var rows := maxi(atlas.get_height() / fh, 1)
	for row in rows:
		for col in columns:
			var frame := atlas.get_region(Rect2i(col * fw, row * fh, fw, fh))
			frame.generate_mipmaps()
			frames.append(ImageTexture.create_from_image(frame))
	set_frame(0)


func set_frame(frame: int) -> void:
	BlitzAnimator.set_material_texture(material, frames[frame % frames.size()])
