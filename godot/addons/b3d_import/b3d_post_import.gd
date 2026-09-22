## EditorScenePostImport for the .glb files produced by tools/b3d2gltf.py / md2togltf.py.
##
## Reads the sidecar `<Name>.b3d.json` next to the source and applies the Blitz3D state
## that glTF cannot express to the imported StandardMaterial3D / nodes:
## brush blend ADD/MULTIPLY, vertex colours, lightmap layers on UV2, texture clamping,
## entity order (transparent pass with render priority and no depth write; negative orders
## also drop the depth test) and billboards.
## Brushes with a spherical environment-mapped layer (texture flag 64, the additive glows
## of towers, bullets, effects and the death animation) become a ShaderMaterial that
## samples the layer by the view-space normal exactly like Blitz (`gxscene.cpp`
## `CANVAS_TEX_SPHERE`: `CAMERASPACENORMAL` through `sphere_mat` 0.5/-0.5 + 0.5).
## Node metadata `blitz_order`, `blitz_billboard` and `blitz_tag` are kept for the runtime.
##
## Attached to every scene import through project.godot `[importer_defaults]`.
@tool
extends EditorScenePostImport

const BLEND_ADD := 3
const BLEND_MULTIPLY := 2
const TEX_BLEND_ADD := 3
const RENDER_PRIORITY_MIN := -128
const RENDER_PRIORITY_MAX := 127
const ZONE_NODES := ["grass", "grass01", "road", "noparking", "rocks"]
const FX_FULLBRIGHT := 1
const FX_NO_CULL := 16
const FX_FORCE_ALPHA := 32
const TEX_FLAG_ALPHA := 2
const TEX_FLAG_MASKED := 4
const TEX_FLAG_SPHERE := 64
## Blitz `TextureBlend` values combined per layer in the sphere shader.
const TEX_BLEND_ALPHA := 1
const TEX_BLEND_MULTIPLY := 2
const TEX_BLEND_MULTIPLY2 := 5
const MAX_LAYERS := 2
## Alpha from which a texel of an alpha-textured brush counts as solid and writes depth
## (`solid_pass`); the same threshold Forward+'s depth pre-pass uses for such materials.
const SOLID_ALPHA := 0.99

## Shader objects by variant key so identical materials share the compiled code.
var shaders: Dictionary = {}


func _post_import(scene: Node) -> Object:
	var source := get_source_file()
	var sidecar_path := source.get_basename() + ".b3d.json"
	if not FileAccess.file_exists(sidecar_path):
		return scene
	var f := FileAccess.open(sidecar_path, FileAccess.READ)
	var sidecar: Variant = JSON.parse_string(f.get_as_text())
	if sidecar == null:
		push_warning("b3d_post_import: invalid sidecar " + sidecar_path)
		return scene
	var materials: Dictionary = sidecar.get("materials", {})
	var nodes: Dictionary = sidecar.get("nodes", {})
	var fixed: Dictionary = {}
	_walk(scene, materials, nodes, fixed, source.get_base_dir())
	return scene


func _walk(node: Node, materials: Dictionary, nodes: Dictionary, fixed: Dictionary, base_dir: String) -> void:
	var info: Dictionary = nodes.get(node.name, {})
	if info.has("order"):
		node.set_meta("blitz_order", int(info["order"]))
	if info.get("billboard", false):
		node.set_meta("blitz_billboard", true)
	if info.has("tag"):
		node.set_meta("blitz_tag", str(info["tag"]))
	if info.has("animmap_material"):
		node.set_meta("blitz_animmap_material", str(info["animmap_material"]))
	if info.has("animbrush_material"):
		node.set_meta("blitz_animbrush_material", str(info["animbrush_material"]))
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		# Blitz draws transparent models back to front by the distance from the camera to
		# the entity's origin (world.cpp `TransComp`), never by its bounds: Location6's rocks
		# (origin far below the top) go before a tower base standing on them. Godot's
		# default AABB centre would flip that order with the camera angle.
		mi.sorting_use_aabb_center = false
		var mesh := mi.mesh
		if mesh != null:
			var negative_order: bool = info.has("order") and int(info["order"]) < 0 and not node.name in ZONE_NODES
			for i in mesh.get_surface_count():
				var mat := mesh.surface_get_material(i)
				if not (mat is StandardMaterial3D or mat is ShaderMaterial):
					continue
				var mat_info: Dictionary = materials.get(mat.resource_name, {})
				if not fixed.has(mat):
					# Multi-layer brushes need Blitz's per-layer combine (the second layer's
					# alpha masks the first: Location5 `noparking`, the `transp*` ground
					# patches), which StandardMaterial3D's detail layer cannot express.
					if mat is StandardMaterial3D and (_has_sphere_layer(mat_info) or mat_info.get("layers", []).size() > 1 or _clamps_one_axis(mat_info)):
						var replacement := _sphere_material(mat as StandardMaterial3D, mat_info, base_dir, false, false)
						mesh.surface_set_material(i, replacement)
						mat = replacement
					elif mat is StandardMaterial3D:
						_fix_material(mat as StandardMaterial3D, mat_info, base_dir)
					fixed[mat] = true
				if info.has("order") or info.get("billboard", false):
					# Per-node state: give the node its own copy of the material.
					var own: Material
					var positive_order: bool = info.has("order") and int(info["order"]) > 0
					if mat is ShaderMaterial or positive_order:
						# Blitz draws ordered entities with the z-buffer disabled (world.cpp
						# `ZMODE_DISABLE`): positive orders before everything else, highest
						# first (the stacked ground layers of the locations), negative orders
						# after everything. Godot cannot draw before the opaque pass, so a
						# positive order becomes a shader that writes the far-plane depth and
						# never stores it: it passes only where nothing has been drawn yet,
						# and render_priority orders the layers among themselves.
						own = _sphere_material(mat, mat_info, base_dir, negative_order, info.get("billboard", false), positive_order)
					else:
						var sm := (mat as StandardMaterial3D).duplicate() as StandardMaterial3D
						if sm.next_pass != null:
							sm.next_pass = sm.next_pass.duplicate()
						if negative_order:
							# Negative orders go to the transparent pass without the depth test.
							# Location zones (Location6 `noparking` has order -1) keep the
							# depth test so towers and enemies stay in front of the ground.
							sm.no_depth_test = true
							sm.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_OPAQUE_ONLY
							sm.next_pass = null  # nothing to occlude without a depth test
							if sm.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED:
								sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
						if info.get("billboard", false):
							sm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
							if sm.next_pass is StandardMaterial3D:
								(sm.next_pass as StandardMaterial3D).billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
						own = sm
					if info.has("order"):
						own.render_priority = clampi(-int(info["order"]), RENDER_PRIORITY_MIN, RENDER_PRIORITY_MAX)
					mi.set_surface_override_material(i, own)
	for c in node.get_children():
		_walk(c, materials, nodes, fixed, base_dir)


func _fix_material(sm: StandardMaterial3D, info: Dictionary, base_dir: String) -> void:
	sm.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	if info.is_empty():
		return
	var blend := int(info.get("blend", 1))
	if blend == BLEND_ADD:
		sm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	elif blend == BLEND_MULTIPLY:
		sm.blend_mode = BaseMaterial3D.BLEND_MODE_MUL
		sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if info.get("vertex_colors", false):
		# EntityFX 2: vertex colours replace the brush colour (the brush alpha still applies).
		sm.vertex_color_use_as_albedo = true
		sm.albedo_color = Color(1, 1, 1, sm.albedo_color.a)
	var layers: Array = info.get("layers", [])
	if not layers.is_empty() and layers[0].get("clamp_u", false) and layers[0].get("clamp_v", false):
		sm.texture_repeat = false
	var detail: Dictionary = info.get("detail", {})
	if not detail.is_empty() and detail.get("uri") != null:
		var tex_path := base_dir.path_join(str(detail["uri"])).simplify_path()
		if ResourceLoader.exists(tex_path):
			sm.detail_enabled = true
			sm.detail_albedo = load(tex_path)
			sm.detail_uv_layer = BaseMaterial3D.DETAIL_UV_2 if detail.get("uv2", false) else BaseMaterial3D.DETAIL_UV_1
			sm.detail_blend_mode = BaseMaterial3D.BLEND_MODE_ADD if int(detail.get("blend", 2)) == TEX_BLEND_ADD else BaseMaterial3D.BLEND_MODE_MUL
	if info.get("modulate2x", false):
		# Blitz `TextureBlend 5` (D3DTOP_MODULATE2X): brush colour x texture x 2.
		sm.albedo_color = Color(sm.albedo_color.r * 2.0, sm.albedo_color.g * 2.0, sm.albedo_color.b * 2.0, sm.albedo_color.a)
	if int(info.get("fx", 0)) & 1:
		sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.set_meta("blitz_blend", blend)
	sm.set_meta("blitz_fx", int(info.get("fx", 0)))
	if sm.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS and blend == 1 and sm.albedo_color.a >= 1.0:
		sm.next_pass = solid_pass(sm)


## Alpha-textured brushes with a plain blend (planks and posts of the menu sign, the HUD
## sheets, road patches, tower bases) rely on the depth pre-pass to occlude each other, but
## the Mobile renderer has none and sorts them by centre only (the posts came out over the
## planks). An extra opaque pass with an alpha scissor writes the depth of the solid texels
## on every renderer, the blended pass on top keeps the soft edges. Writing depth from the
## blended pass itself (`DEPTH_DRAW_ALWAYS`) is wrong: its transparent texels cut holes into
## blended geometry behind the quad (Location6's rocks under a tower base).
static func solid_pass(sm: StandardMaterial3D) -> StandardMaterial3D:
	var solid := sm.duplicate() as StandardMaterial3D
	solid.resource_name = sm.resource_name + " solid"
	solid.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	solid.alpha_scissor_threshold = SOLID_ALPHA
	solid.next_pass = null
	return solid


## Blitz clamps U and V separately (texture flags 16 / 32); StandardMaterial3D cannot, so
## such brushes (the scrolling `flame.jpg` of the menu fire and the Flame tower) get the
## generated shader, which wraps one axis and clamps the other.
func _clamps_one_axis(info: Dictionary) -> bool:
	for layer in info.get("layers", []):
		if layer.get("clamp_u", false) != layer.get("clamp_v", false):
			return true
	return false


## Per-layer (clamp U, clamp V) pairs of the brush, in layer order.
func _layer_clamps(layers: Array) -> Array:
	var out := []
	for layer in layers:
		out.append([bool(layer.get("clamp_u", false)), bool(layer.get("clamp_v", false))])
	return out


func _has_sphere_layer(info: Dictionary) -> bool:
	for layer in info.get("layers", []):
		if layer.get("sphere", false):
			return true
	return false


## ShaderMaterial for a brush with spherical layers. `source` supplies the brush colour
## (glTF baseColorFactor); layers are loaded from the sidecar URIs. Uniforms `albedo`
## and `uv1_offset` mirror the StandardMaterial3D properties the runtime animates.
func _sphere_material(source: Material, info: Dictionary, base_dir: String, no_depth: bool, billboard: bool, far_depth := false) -> ShaderMaterial:
	var blend := int(info.get("blend", 1))
	var fx := int(info.get("fx", 0))
	var layers: Array = info.get("layers", []).slice(0, MAX_LAYERS)
	var vertex_colors: bool = info.get("vertex_colors", false)
	# Brushes that Blitz draws opaque (blend 1, alpha 1, no alpha/masked layer, no force
	# alpha) must stay in the opaque pass: a shader that writes ALPHA goes to the
	# transparent pass and stops writing depth. Ordered layers need the transparent pass
	# for render_priority. Masked layers use the alpha-scissor instead.
	var color := Color.WHITE
	if source is StandardMaterial3D:
		color = (source as StandardMaterial3D).albedo_color
	elif source is ShaderMaterial:
		color = (source as ShaderMaterial).get_shader_parameter("albedo")
	var masked := false
	var layer_alpha := false
	for layer in layers:
		var flags := int(layer.get("flags", 0))
		masked = masked or (flags & TEX_FLAG_MASKED) != 0
		layer_alpha = layer_alpha or (flags & TEX_FLAG_ALPHA) != 0
	var opaque := blend == 1 and color.a >= 1.0 and not layer_alpha and not (fx & FX_FORCE_ALPHA) and not far_depth and not no_depth
	var alpha_mode := "opaque" if opaque else "blend"
	if opaque and masked:
		alpha_mode = "scissor"
	var clamps := _layer_clamps(layers)
	var key := "%d:%d:%d:%d:%s:%d:%d:%s" % [blend, fx, int(no_depth), int(billboard), str(clamps), int(vertex_colors), int(far_depth), alpha_mode]
	if not shaders.has(key):
		var sh := Shader.new()
		sh.code = _sphere_shader_code(blend, fx, no_depth, billboard, clamps, vertex_colors, far_depth, alpha_mode)
		shaders[key] = sh
	var m := ShaderMaterial.new()
	m.shader = shaders[key]
	m.resource_name = source.resource_name
	m.set_shader_parameter("albedo", color)
	m.set_shader_parameter("uv1_offset", Vector3.ZERO)
	for i in layers.size():
		var layer: Dictionary = layers[i]
		var tex_path := base_dir.path_join(str(layer.get("uri", ""))).simplify_path()
		if ResourceLoader.exists(tex_path):
			m.set_shader_parameter("layer%d" % i, load(tex_path))
		m.set_shader_parameter("sphere%d" % i, bool(layer.get("sphere", false)))
		m.set_shader_parameter("blend%d" % i, int(layer.get("blend", TEX_BLEND_MULTIPLY)))
	m.set_meta("blitz_blend", blend)
	m.set_meta("blitz_fx", fx)
	m.set_meta("blitz_sphere", _has_sphere_layer(info))
	return m


## `clamps[i]` = [clamp U, clamp V] of layer i: both axes clamped is the sampler's
## `repeat_disable`; a single axis is clamped in the shader to the texel centres of that
## layer (a repeating sampler at exactly 0.0 / 1.0 would blend with the opposite edge).
func _sphere_shader_code(blend: int, fx: int, no_depth: bool, billboard: bool, clamps: Array, vertex_colors: bool, far_depth: bool, alpha_mode: String) -> String:
	var layer_count := clamps.size()
	# Blitz has no specular unless EntityShininess is set (never in this game).
	var modes := ["unshaded"] if fx & FX_FULLBRIGHT else ["diffuse_lambert", "specular_disabled"]
	if blend == BLEND_ADD:
		modes.append("blend_add")
	elif blend == BLEND_MULTIPLY:
		modes.append("blend_mul")
	else:
		modes.append("blend_mix")
	if far_depth or blend == BLEND_ADD or blend == BLEND_MULTIPLY:
		modes.append("depth_draw_never")
	if fx & FX_NO_CULL:
		modes.append("cull_disabled")
	if no_depth:
		modes.append("depth_test_disabled")
	var code := "shader_type spatial;\nrender_mode " + ", ".join(modes) + ";\n"
	code += "uniform vec4 albedo : source_color = vec4(1.0);\nuniform vec3 uv1_offset = vec3(0.0);\n"
	for i in layer_count:
		var repeat := "repeat_disable" if clamps[i][0] and clamps[i][1] else "repeat_enable"
		code += "uniform sampler2D layer%d : source_color, filter_linear_mipmap, %s;\n" % [i, repeat]
		code += "uniform bool sphere%d = false;\nuniform int blend%d = 2;\n" % [i, i]
	# Like the D3D fixed-function pipeline the sphere UV is computed per vertex from the
	# camera-space normal and interpolated across the triangle.
	code += "varying vec2 sphere_uv;\n"
	code += "void vertex() {\n"
	if billboard:
		# Blitz `B3D_BB_1_` nodes face the camera; keep the node's scale.
		code += "\tMODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0] * length(MODEL_MATRIX[0]), INV_VIEW_MATRIX[1] * length(MODEL_MATRIX[1]), INV_VIEW_MATRIX[2] * length(MODEL_MATRIX[2]), MODEL_MATRIX[3]);\n"
		code += "\tMODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);\n"
	code += "\tvec3 n = normalize(MODELVIEW_NORMAL_MATRIX * NORMAL);\n"
	code += "\tsphere_uv = vec2(0.5 + 0.5 * n.x, 0.5 - 0.5 * n.y);\n}\n"
	code += "vec4 combine(vec4 acc, vec4 tex, int mode) {\n"
	code += "\tif (mode == %d) { return vec4(mix(acc.rgb, tex.rgb, tex.a), acc.a); }\n" % TEX_BLEND_ALPHA
	code += "\tif (mode == %d) { return vec4(acc.rgb + tex.rgb, acc.a * tex.a); }\n" % TEX_BLEND_ADD
	code += "\tif (mode == %d) { return acc * tex * vec4(2.0, 2.0, 2.0, 1.0); }\n" % TEX_BLEND_MULTIPLY2
	code += "\treturn acc * tex;\n}\n"
	code += "float clamp_axis(float v, float size) {\n\treturn clamp(v, 0.5 / size, 1.0 - 0.5 / size);\n}\n"
	code += "void fragment() {\n"
	if far_depth:
		# Reverse-Z: 0.0 is the far plane, so the fragment survives only over cleared depth.
		code += "\tDEPTH = 0.0;\n"
	code += "\tvec2 plain_uv = UV + uv1_offset.xy;\n"
	code += "\tvec4 c = albedo;\n"
	if vertex_colors:
		# EntityFX 2: the vertex colour replaces the brush colour (D3DMCS_COLOR1); the brush
		# alpha is kept so EntityAlpha / ANIMBRUSH fades still apply.
		code += "\tc = vec4(COLOR.rgb, c.a * COLOR.a);\n"
	for i in layer_count:
		# tools/b3d2gltf.py writes the (baked) coordinates of the second layer to TEXCOORD_1.
		var uv := "UV2" if i > 0 else "plain_uv"
		if clamps[i][0] != clamps[i][1]:
			var axis := "x" if clamps[i][0] else "y"
			code += "\tvec2 uv%d = %s;\n\tuv%d.%s = clamp_axis(uv%d.%s, float(textureSize(layer%d, 0).%s));\n" % [i, uv, i, axis, i, axis, i, axis]
			uv = "uv%d" % i
		code += "\tc = combine(c, texture(layer%d, sphere%d ? sphere_uv : %s), blend%d);\n" % [i, i, uv, i]
	code += "\tALBEDO = c.rgb;\n"
	if alpha_mode == "blend":
		code += "\tALPHA = c.a;\n"
	elif alpha_mode == "scissor":
		code += "\tALPHA = c.a;\n\tALPHA_SCISSOR_THRESHOLD = 0.5;\n"
	code += "}\n"
	return code
