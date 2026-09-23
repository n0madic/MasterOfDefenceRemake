"""Defold materials emulating the Blitz3D fixed-function brush: up to two texture layers
combined per `TextureBlend`, spherical environment maps, EntityFX flags, EntityColor /
EntityAlpha / PositionTexture as per-component constants, skinning and MD2 morph targets.
"""
from __future__ import annotations

from b3d2gltf import KNOWN_MISSING
from blitzconv import ADDITIVE_ALPHA_EXPONENT

# Blitz3D brush blend modes (`BrushBlend`), EntityFX flags, texture flags, TextureBlend.
BLEND_ALPHA, BLEND_MULTIPLY, BLEND_ADD = 1, 2, 3
FX_FULLBRIGHT, FX_VERTEX_COLORS, FX_NO_CULL, FX_FORCE_ALPHA = 1, 2, 16, 32
TEX_FLAG_ALPHA, TEX_FLAG_MASKED, TEX_FLAG_SPHERE = 2, 4, 64
TEX_BLEND_ALPHA, TEX_BLEND_MULTIPLY, TEX_BLEND_ADD, TEX_BLEND_MULTIPLY2 = 1, 2, 3, 5
MAX_LAYERS = 2
MASK_THRESHOLD = 0.5
# Only the fully-solid texels of a depth companion write depth (the soft blended brush on top
# hides this hard cut); matches the Godot port's SOLID_ALPHA.
SOLID_ALPHA = 0.99
MORPH_WEIGHTS_PER_VEC4 = 4


def linear_to_srgb(c: float) -> float:
    c = max(0.0, min(1.0, c))
    if c <= 0.0031308:
        return c * 12.92
    return 1.055 * c ** (1.0 / 2.4) - 0.055


def gltf_color_to_blitz(rgba: list[float], additive: bool) -> list[float]:
    """Inverse of `blitzconv.blitz_color_to_gltf`: back to gamma space (Defold, like
    Blitz3D, shades in gamma space), the additive alpha compensation undone."""
    rgb = [linear_to_srgb(c) for c in rgba[:3]]
    alpha = float(rgba[3]) if len(rgba) > 3 else 1.0
    if additive:
        alpha = max(0.0, min(1.0, alpha)) ** (1.0 / ADDITIVE_ALPHA_EXPONENT)
    return rgb + [alpha]


def fmt(v: float) -> str:
    return f"{v:.6f}"



# Lit materials' light constants: filled every frame by render/blitz.render_script in the
# view space of the screen's camera (so the overlay sheets, which hang on that camera, see
# the scene's lights where the original's did); these defaults (full ambient, no
# directional light) only show if the render script failed to pass them.
# `light_dir`: the directional light's direction; `point_light<i>`: a point light's
# position and range (w = 0: no light), `point_color<i>`: its RGB.
NEUTRAL_LIGHT = {"light_dir": [0.0, -1.0, 0.0, 0.0], "light_color": [0.0, 0.0, 0.0, 1.0], "ambient": [1.0, 1.0, 1.0, 1.0],
                 "point_light0": [0.0, 0.0, 0.0, 0.0], "point_color0": [0.0, 0.0, 0.0, 1.0],
                 "point_light1": [0.0, 0.0, 0.0, 0.0], "point_color1": [0.0, 0.0, 0.0, 1.0]}

# A Blitz point light (gxlight.cpp): Direct3D 7 with no range cut-off and the attenuation
# 1 / (d / range) of `LightRange` (1000 by default), Lambert only.
POINT_LIGHT_FUNCTION = [
    "vec3 point_light(vec4 light, vec4 color, vec3 p, vec3 n)",
    "{",
    "    if (light.w <= 0.0) return vec3(0.0);",
    "    vec3 d = light.xyz - p;",
    "    float dist = max(length(d), 0.0001);",
    "    return color.rgb * (light.w / dist) * max(dot(n, d / dist), 0.0);",
    "}",
]



def order_tag(order: int, overlay: bool = False) -> str:
    """Render pass tag of an EntityOrder: `order_30`, `order_m5` for -5; the overlay layer
    (the HUD panel and the menu sheets, drawn by the fixed camera) has its own `hud_*`."""
    name = f"m{-order}" if order < 0 else str(order)
    if overlay:
        return "hud" if order == 0 else f"hud_{name}"
    return f"order_{name}"


def canvas_tag(order: int) -> str:
    """Render pass tag of a negative EntityOrder of an overlay sheet drawn across the whole
    canvas (`canvas_m5`) rather than the 4:3 box: the loading curtain covers Wide's sides."""
    return f"canvas_m{-order}"


# The tower bases' ground layer (Military's `dno` brush): the location's `dno<N>.png`,
# multiplied, relative to the tower models' folder (the converter's stand-in for the
# `dno.png` the original never ships).
GROUND_BASE_TEXTURE = "dno.png"
GROUND_BASE_LAYER = {"texture": GROUND_BASE_TEXTURE, "flags": 523, "blend": 2, "uv2": False, "sphere": False,
                     "uri": f"../../textures/{KNOWN_MISSING[GROUND_BASE_TEXTURE]}", "clamp_u": False, "clamp_v": False}

class MaterialVariant:
    """One generated Defold material: a Blitz brush of one model, drawn at a given
    EntityOrder, with the shader features the model needs (`skinned`, `morph_targets`)."""

    def __init__(self, base_name: str, gltf_material: dict, info: dict, *, order: int = 0, hud: bool = False,
                 skinned: bool = False, morph_targets: int = 0, animmap: bool = False, lit_default: bool = False,
                 bone_count: int = 0, ground_base: bool = False, solid_depth: bool = False,
                 billboard: bool = False, frame_atlas: bool = False, node_rank: int | None = None,
                 canvas: bool = False):
        self._gltf_material = gltf_material
        self._info = info
        self._kwargs = dict(order=order, hud=hud, skinned=skinned, morph_targets=morph_targets,
                            animmap=animmap, lit_default=lit_default, bone_count=bone_count, billboard=billboard,
                            frame_atlas=frame_atlas, node_rank=node_rank, canvas=canvas)
        self.base_name = base_name
        self.name = (gltf_material["name"] + (f"@order{order}" if order else "") + ("@base" if ground_base else "")
                     + ("@solid" if solid_depth else "") + ("@billboard" if billboard else "")
                     + (f"@r{node_rank}" if node_rank is not None else ""))
        # The name of the glb material slot this variant binds to (the solid companion's glb
        # holds the base decal's primitives, so it binds to the base variant's slot -- see
        # `solid_variant`).
        self.bind_name = self.name
        self.order = order
        self.hud = hud
        # An overlay sheet drawn across the whole canvas (see `canvas_tag`): only its negative
        # orders, drawn last without the z-buffer, can leave the box.
        if canvas and not (hud and order < 0):
            raise ValueError(f"{self.name}: a canvas-wide brush needs a negative overlay order")
        self.canvas = canvas
        # The tower base decal (`dno`) draws in its own pass between the opaque world and the
        # translucent tower bodies, so a translucent trunk cannot sort-flip with it; its
        # `solid_depth` companion writes the depth that occludes the tower's underground root.
        self.ground_base = ground_base
        self.solid_depth = solid_depth
        # `bone_count > 0`: manual skinning through a `bone_matrices[N]` array constant the
        # runtime fills with full pose matrices, for models Defold's SRT-bone skinning
        # distorts (a non-uniform-scale + rotation hierarchy carries shear, e.g. Nature).
        self.bone_count = bone_count
        self.skinned = skinned and bone_count == 0
        # Blitz `B3D_BB_1_` nodes (the Magic tower's crown ring) face the camera: the joint's
        # rotation is replaced by the camera basis, keeping its position and scale (as the
        # Godot port's billboard shader does). Needs joint-local vertices, i.e. `bone_count`.
        self.billboard = billboard and bone_count > 0
        self.morph_targets = morph_targets
        self.animmap = animmap
        # Blitz `LoadAnimTexture` + `EntityTexture(entity, tex, frame)` (the location's river
        # and border): the first layer samples one frame of an atlas image, tiled over the
        # brush's UVs; the runtime sets `frame_atlas` = (u, v, width, height) of the frame.
        self.frame_atlas = frame_atlas
        # The translucent nodes of a menu sheet or of the menu's world draw in depth layers
        # (0 = farthest): all their meshes share one origin, so Defold's per-object sort
        # cannot order them the way Blitz's per-entity sort did (set by the model exporter).
        # A static overlay (the HUD panel) is ranked node by node (`node_rank`) in layers of
        # its own, drawn before the sheets that open over it.
        self.layer_rank: int | None = node_rank
        self.rank_layer = "panel" if node_rank is not None else "hud" if hud else "world"
        self.blend = int(info.get("blend", BLEND_ALPHA))
        # Models without a sidecar (MD2 monsters) are lit, textured and opaque.
        self.fx = int(info.get("fx", 0 if lit_default else FX_FULLBRIGHT))
        self.vertex_colors = bool(info.get("vertex_colors", False))
        self.layers: list[dict] = list(info.get("layers", []))[:MAX_LAYERS]
        if not info and gltf_material.get("pbrMetallicRoughness", {}).get("baseColorTexture") is not None:
            self.layers = [{"flags": 0, "blend": TEX_BLEND_MULTIPLY, "sphere": False, "uri": None, "from_gltf": True}]
        if ground_base and not self.layers:
            # `_fpositiontower` paints every base with the location's ground; Icerock's base
            # brush is untextured, so it gets the ground layer the other towers' bases carry
            # (the runtime swaps the texture), else it would stay an opaque tinted square.
            self.layers = [dict(GROUND_BASE_LAYER)]
        factor = gltf_material.get("pbrMetallicRoughness", {}).get("baseColorFactor", [1.0, 1.0, 1.0, 1.0])
        self.color = gltf_color_to_blitz(factor, additive=self.blend == BLEND_ADD)
        self.double_sided = bool(gltf_material.get("doubleSided", False)) or bool(self.fx & FX_NO_CULL)
        layer_alpha = any(int(l.get("flags", 0)) & TEX_FLAG_ALPHA for l in self.layers)
        # An overlay sheet's alpha-textured plain brush (the menu sign's planks, posts and
        # captions) also writes the depth of its solid texels, as the Godot port's
        # `_add_solid_pass`: a caption the sheet's animation moves behind its plank (the
        # settings flight) is hidden, and the posts behind the planks stay behind them
        # although they share the planks' brush and so their draw pass.
        # Sheets drawn with a negative EntityOrder (no z-buffer) take no companion.
        # A base decal always takes one (see `solid_variant`).
        self.needs_solid = not solid_depth and (ground_base or (
            hud and bone_count > 0 and order == 0 and layer_alpha and self.blend == BLEND_ALPHA and self.color[3] >= 1.0))
        self.masked = any(int(l.get("flags", 0)) & TEX_FLAG_MASKED for l in self.layers)
        # Blitz draws a brush opaquely when nothing asks for blending; everything else goes
        # to a blended pass (see godot/addons/b3d_import `_sphere_material`).
        opaque = self.blend == BLEND_ALPHA and self.color[3] >= 1.0 and not layer_alpha and not (self.fx & FX_FORCE_ALPHA)
        if self.blend == BLEND_ADD:
            self.pass_class = "add"
        elif self.blend == BLEND_MULTIPLY:
            self.pass_class = "mul"
        elif opaque:
            self.pass_class = "opaque"
        else:
            self.pass_class = "blend"
        self.mask_threshold = MASK_THRESHOLD
        if self.solid_depth:
            # The depth companion of a base decal or an overlay brush (see `solid_variant`):
            # an alpha-scissor opaque brush that writes depth for the fully-solid texels (of
            # the dirt splat: the tower's underground root is occluded). Its hard cut sits
            # inside the brush and is covered by the soft blended brush drawn on top (as in
            # the Godot port's alpha-scissor depth pre-pass), so no hard edge shows. The
            # overlay's companions draw depth only (render_passes `color_write`).
            self.pass_class = "opaque"
            self.masked = True
            self.mask_threshold = SOLID_ALPHA
        self.invisible = self.color[3] <= 0.0 and not self.layers

    def solid_variant(self) -> "MaterialVariant":
        """The depth companion of this base decal or overlay brush (an alpha-scissor opaque
        brush drawing its solid texels)."""
        solid = MaterialVariant(self.base_name + "_solid", self._gltf_material, self._info,
                                ground_base=self.ground_base, solid_depth=True, **self._kwargs)
        solid.bind_name = self.name  # its glb holds this decal's primitives, named after this variant
        return solid

    @property
    def tags(self) -> list[str]:
        if self.ground_base:
            return ["base", self.pass_class]
        if self.solid_depth:
            return [f"{'hud' if self.hud else 'world'}_solid", self.pass_class]
        if self.layer_rank is not None and self.pass_class != "opaque" and self.order == 0:
            return [f"{self.rank_layer}_l{self.layer_rank}", self.pass_class]
        if self.canvas:
            return [canvas_tag(self.order), self.pass_class]
        return [order_tag(self.order, self.hud), self.pass_class]

    @property
    def lit(self) -> bool:
        return not (self.fx & FX_FULLBRIGHT)

    @property
    def sphere(self) -> bool:
        return any(bool(l.get("sphere")) for l in self.layers)

    @property
    def needs_normal(self) -> bool:
        return self.lit or self.sphere

    @property
    def needs_view(self) -> bool:
        return self.billboard

    def sampler_name(self, layer: int) -> str:
        return f"layer{layer}"

    # --- shader sources ------------------------------------------------------------------

    def vertex_program(self) -> str:
        two = len(self.layers) > 1
        lines = ["#version 140", "", "in highp vec4 position;", "in mediump vec3 normal;", "in mediump vec2 texcoord0;"]
        if two:
            lines.append("in mediump vec2 texcoord1;")
        if self.vertex_colors:
            lines.append("in mediump vec4 color;")
        if self.skinned:
            lines += ["in mediump vec4 bone_weights;", "in mediump vec4 bone_indices;"]
        if self.bone_count:
            lines.append("in mediump vec4 bone_indices;")
        lines += ["", "out mediump vec2 var_texcoord0;"]
        if two:
            lines.append("out mediump vec2 var_texcoord1;")
        if self.vertex_colors:
            lines.append("out mediump vec4 var_color;")
        if self.lit:
            lines.append("out mediump vec3 var_light;")
        if self.sphere:
            lines.append("out mediump vec2 var_sphere_uv;")
        lines += ["", "uniform vs_uniforms", "{", "    mediump mat4 mtx_worldview;", "    mediump mat4 mtx_proj;"]
        if self.needs_normal:
            lines.append("    mediump mat4 mtx_normal;")
        if self.needs_view:
            lines.append("    mediump mat4 mtx_view;")
        if self.lit:
            lines += ["    mediump vec4 light_dir;", "    mediump vec4 light_color;", "    mediump vec4 ambient;",
                      "    highp vec4 point_light0;", "    mediump vec4 point_color0;",
                      "    highp vec4 point_light1;", "    mediump vec4 point_color1;"]
        if self.animmap:
            lines.append("    mediump vec4 uv_offset;")
        if self.skinned:
            lines.append("    mediump vec4 animation_data;")
        if self.bone_count:
            lines.append(f"    mediump mat4 bone_matrices[{self.bone_count}];")
        if self.morph_targets:
            n = (self.morph_targets + MORPH_WEIGHTS_PER_VEC4 - 1) // MORPH_WEIGHTS_PER_VEC4
            lines.append(f"    mediump vec4 morph_targets_weights[{n}];")
        lines.append("};")
        if self.skinned:
            lines += ["", '#include "/builtins/materials/skinning.glsl"']
        if self.morph_targets:
            lines += ["", "uniform sampler2DArray morph_targets;", ""] + self._morph_functions()
        if self.lit:
            lines += [""] + POINT_LIGHT_FUNCTION
        lines += ["", "void main()", "{"]
        if self.skinned:
            lines += ["    vec4 p_local = get_skinned_position(position);", "    vec3 n_local = get_skinned_normal(normal);"]
        elif self.bone_count:
            lines.append("    mediump mat4 bone = bone_matrices[int(bone_indices.x + 0.5)];")
            lines.append("    vec4 p_local = bone * vec4(position.xyz, 1.0);")
            if self.needs_normal:
                # A non-uniform / sheared bone needs the inverse transpose for the normal;
                # `mat3(bone)` skews it (the flat base of the Nature tower went dark). Defold's
                # shader compiler has no mat3 `inverse`, so use the cofactor (cross-product)
                # form, which equals det * inverse-transpose and is corrected by the normalize.
                lines += [
                    "    mediump mat3 bone3 = mat3(bone);",
                    "    vec3 n_local = mat3(cross(bone3[1], bone3[2]), cross(bone3[2], bone3[0]), cross(bone3[0], bone3[1])) * normal;",
                ]
            else:
                lines.append("    vec3 n_local = normal;")
        elif self.morph_targets:
            lines += [
                "    vec3 position_delta;",
                "    vec3 normal_delta;",
                "    get_morph_target_data(gl_VertexIndex, position_delta, normal_delta);",
                "    vec4 p_local = vec4(position.xyz + position_delta, 1.0);",
                "    vec3 n_local = normalize(normal + normal_delta);",
            ]
        else:
            lines += ["    vec4 p_local = vec4(position.xyz, 1.0);", "    vec3 n_local = normal;"]
        if self.billboard:
            # `_fext_updatebillboards`: PointEntity(node, camera) -- the node's Blitz +Z (glTF
            # -Z, the converter mirrors Z) points at the camera *position*, no roll, world Y
            # up; the joint's position and scale are kept. In view space the camera is at the
            # origin. Aligning to the camera axes instead (as the Godot port did) is wrong
            # under perspective: the Magic crown ring sits 3.44 units along the node's Z, so
            # it slid sideways off the tower top instead of hovering over it.
            lines += [
                "    mediump mat4 mv = mtx_worldview * bone;",
                "    vec3 bb_scale = vec3(length(mv[0].xyz), length(mv[1].xyz), length(mv[2].xyz));",
                "    vec3 bb_z = normalize(mv[3].xyz);",
                "    vec3 bb_x = normalize(cross((mtx_view * vec4(0.0, 1.0, 0.0, 0.0)).xyz, bb_z));",
                "    vec3 bb_y = cross(bb_z, bb_x);",
                "    mat3 bb_basis = mat3(bb_x, bb_y, bb_z);",
                "    vec4 p = vec4(mv[3].xyz + bb_basis * (bb_scale * position.xyz), 1.0);",
            ]
        else:
            lines.append("    vec4 p = mtx_worldview * vec4(p_local.xyz, 1.0);")
        lines.append("    var_texcoord0 = texcoord0" + (" + uv_offset.xy" if self.animmap else "") + ";")
        if two:
            lines.append("    var_texcoord1 = texcoord1;")
        if self.vertex_colors:
            lines.append("    var_color = color;")
        if self.needs_normal:
            if self.billboard:
                lines.append("    vec3 n = normalize(bb_basis * (normal / bb_scale));")  # inverse-transpose of basis * diag(scale)
            else:
                lines.append("    vec3 n = normalize((mtx_normal * vec4(n_local, 0.0)).xyz);")
        if self.lit:
            # Direct3D 7 lights per vertex (Gouraud): ambient + Lambert of one directional
            # light (the locations) and up to two point lights (the menu), no specular
            # (Blitz never sets EntityShininess in this game).
            lines += [
                "    vec3 l = normalize(light_dir.xyz);",
                "    vec3 lit = ambient.rgb + light_color.rgb * max(dot(n, -l), 0.0);",
                "    lit += point_light(point_light0, point_color0, p.xyz, n) + point_light(point_light1, point_color1, p.xyz, n);",
                "    var_light = clamp(lit, 0.0, 1.0);",
            ]
        if self.sphere:
            # gxscene.cpp CANVAS_TEX_SPHERE: uv from the camera-space normal, per vertex.
            # Godot writes `0.5 - 0.5 * n.y` (glTF's top-left V origin). Defold flips the
            # V of every imported `texcoord0` to its bottom-left origin, but a UV computed
            # in the shader never passes through that flip, so the sign is inverted here
            # -- otherwise every sphere-mapped texture rendered upside down (the death
            # soul's `death.png` ghost showed point-up instead of point-down).
            lines.append("    var_sphere_uv = vec2(0.5 + 0.5 * n.x, 0.5 + 0.5 * n.y);")
        lines += ["    gl_Position = mtx_proj * p;", "}", ""]
        return "\n".join(lines)

    def _morph_functions(self) -> list[str]:
        """Morph target sampling from the engine's texture array (Defold model-animation
        manual): layer 3k = position delta, 3k + 1 = normal delta of target k."""
        n = self.morph_targets
        lines = [
            "vec2 get_morph_uv(int vertex_index, int width, int height)",
            "{",
            "    int x = vertex_index % width;",
            "    int y = vertex_index / width;",
            "    return vec2((float(x) + 0.5) / float(width), (float(y) + 0.5) / float(height));",
            "}",
            "",
            "void apply_morph_target(vec2 uv, float weight, int target, inout vec3 position_delta, inout vec3 normal_delta)",
            "{",
            "    if (weight == 0.0) {",
            "        return;",
            "    }",
            "    position_delta += weight * texture(morph_targets, vec3(uv, target * 3 + 0)).xyz;",
            "    normal_delta += weight * texture(morph_targets, vec3(uv, target * 3 + 1)).xyz;",
            "}",
            "",
            "void get_morph_target_data(int vertex_index, out vec3 position_delta, out vec3 normal_delta)",
            "{",
            "    position_delta = vec3(0.0);",
            "    normal_delta = vec3(0.0);",
            "#ifndef EDITOR",
            "    ivec3 texture_size = textureSize(morph_targets, 0);",
            "    vec2 uv = get_morph_uv(vertex_index, texture_size.x, texture_size.y);",
        ]
        for k in range(n):
            comp = "xyzw"[k % MORPH_WEIGHTS_PER_VEC4]
            lines.append(f"    apply_morph_target(uv, morph_targets_weights[{k // MORPH_WEIGHTS_PER_VEC4}].{comp}, {k}, position_delta, normal_delta);")
        lines += ["#endif", "}"]
        return lines

    def fragment_program(self) -> str:
        two = len(self.layers) > 1
        lines = ["#version 140", "", "in mediump vec2 var_texcoord0;"]
        if two:
            lines.append("in mediump vec2 var_texcoord1;")
        if self.vertex_colors:
            lines.append("in mediump vec4 var_color;")
        if self.lit:
            lines.append("in mediump vec3 var_light;")
        if self.sphere:
            lines.append("in mediump vec2 var_sphere_uv;")
        lines += ["", "out vec4 out_fragColor;", ""]
        for i in range(len(self.layers)):
            lines.append(f"uniform mediump sampler2D {self.sampler_name(i)};")
        lines += [
            "",
            "uniform fs_uniforms",
            "{",
            "    mediump vec4 tint;          // brush colour",
            "    mediump vec4 entity_color;  // Blitz EntityColor: replaces the brush RGB when w > 0",
            "    mediump vec4 entity_alpha;  // Blitz EntityAlpha: x multiplies the alpha",
        ] + (["    mediump vec4 frame_atlas;   // animated texture frame: uv offset (xy) and size (zw)"] if self.frame_atlas else []) + [
            "};",
            "",
            "// Blitz `TextureBlend` per layer, as in godot/addons/b3d_import (`combine`).",
            "vec4 combine_alpha(vec4 acc, vec4 tex) { return vec4(mix(acc.rgb, tex.rgb, tex.a), acc.a); }",
            "vec4 combine_add(vec4 acc, vec4 tex) { return vec4(acc.rgb + tex.rgb, acc.a * tex.a); }",
            "vec4 combine_multiply(vec4 acc, vec4 tex) { return acc * tex; }",
            "vec4 combine_multiply2(vec4 acc, vec4 tex) { return acc * tex * vec4(2.0, 2.0, 2.0, 1.0); }",
            "",
        ]
        if self.frame_atlas:
            # The frame repeats over the brush like a texture of its own. Hardware filtering
            # at the frame's edge would blend in a strip of the neighbouring atlas frame (another
            # phase of the animation: a flickering seam along every wrap line), so the frame is
            # filtered by hand -- trilinear, the four taps wrapped inside the frame. The mip
            # comes from the gradients of the unwrapped UVs; mips never mix frames, since the
            # frames sit on a power-of-two grid.
            lines += [
                "vec4 frame_bilinear(sampler2D tex, vec2 uv, int lod)",
                "{",
                "    vec2 atlas = vec2(textureSize(tex, lod));",
                "    ivec2 origin = ivec2(frame_atlas.xy * atlas + 0.5);",
                "    ivec2 size = max(ivec2(frame_atlas.zw * atlas + 0.5), ivec2(1));",
                "    vec2 p = fract(uv) * vec2(size) - 0.5;",
                "    vec2 f = fract(p);",
                "    ivec2 i0 = (ivec2(floor(p)) + size) % size;",
                "    ivec2 i1 = (i0 + 1) % size;",
                "    vec4 a = texelFetch(tex, origin + i0, lod);",
                "    vec4 b = texelFetch(tex, origin + ivec2(i1.x, i0.y), lod);",
                "    vec4 c = texelFetch(tex, origin + ivec2(i0.x, i1.y), lod);",
                "    vec4 d = texelFetch(tex, origin + i1, lod);",
                "    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);",
                "}",
                "",
                "vec4 sample_frame(sampler2D tex, vec2 uv)",
                "{",
                "    vec2 texels = frame_atlas.zw * vec2(textureSize(tex, 0));",
                "    vec2 dx = dFdx(uv) * texels;",
                "    vec2 dy = dFdy(uv) * texels;",
                "    float max_lod = log2(max(min(texels.x, texels.y), 1.0));",
                "    float lod = clamp(0.5 * log2(max(max(dot(dx, dx), dot(dy, dy)), 1e-8)), 0.0, max_lod);",
                "    int l0 = int(floor(lod));",
                "    int l1 = min(l0 + 1, int(max_lod));",
                "    return mix(frame_bilinear(tex, uv, l0), frame_bilinear(tex, uv, l1), lod - float(l0));",
                "}",
                "",
            ]
        lines += [
            "void main()",
            "{",
        ]
        if self.vertex_colors:
            # EntityFX 2: the vertex colour replaces the brush colour (D3DMCS_COLOR1), the
            # brush alpha still applies. (Blitz ignores EntityColor on such brushes; the
            # runtime never tints one, and referencing the constant keeps the uniform
            # block alive for `go.set`.)
            lines.append("    vec4 c = vec4(mix(var_color.rgb, entity_color.rgb, entity_color.w), tint.a * var_color.a);")
        else:
            lines.append("    vec4 c = vec4(mix(tint.rgb, entity_color.rgb, entity_color.w), tint.a);")
        if self.lit:
            lines.append("    c.rgb *= var_light;")
        for i, layer in enumerate(self.layers):
            uv = "var_sphere_uv" if layer.get("sphere") else ("var_texcoord1" if i > 0 else "var_texcoord0")
            fn = {TEX_BLEND_ALPHA: "combine_alpha", TEX_BLEND_ADD: "combine_add", TEX_BLEND_MULTIPLY2: "combine_multiply2"}.get(
                int(layer.get("blend", TEX_BLEND_MULTIPLY)), "combine_multiply")
            sample = f"sample_frame({self.sampler_name(i)}, {uv})" if (self.frame_atlas and i == 0) else f"texture({self.sampler_name(i)}, {uv})"
            lines.append(f"    c = {fn}(c, {sample});")
        lines.append("    c.a *= entity_alpha.x;")
        if self.pass_class == "opaque":
            if self.masked:
                lines.append(f"    if (c.a < {fmt(self.mask_threshold)}) discard;")
            lines.append("    out_fragColor = vec4(c.rgb, 1.0);")
        else:
            lines.append("    out_fragColor = c;")
        lines += ["}", ""]
        return "\n".join(lines)

    def material_file(self, materials_path: str) -> str:
        out = [f'name: "{self.base_name}"']
        for tag in self.tags:
            out.append(f'tags: "{tag}"')
        out += [
            f'vertex_program: "{materials_path}/{self.base_name}.vp"',
            f'fragment_program: "{materials_path}/{self.base_name}.fp"',
            "vertex_space: VERTEX_SPACE_LOCAL",
        ]
        matrices = [("mtx_worldview", "CONSTANT_TYPE_WORLDVIEW"), ("mtx_proj", "CONSTANT_TYPE_PROJECTION")]
        if self.needs_normal:
            matrices.append(("mtx_normal", "CONSTANT_TYPE_NORMAL"))
        if self.needs_view:
            matrices.append(("mtx_view", "CONSTANT_TYPE_VIEW"))
        for name, kind in matrices:
            out += ["vertex_constants {", f'  name: "{name}"', f"  type: {kind}", "}"]
        if self.bone_count:
            # The runtime fills `bone_matrices[i]` (go.set with `index`); Defold reads the
            # array size from the shader. Default value is the identity matrix.
            out += ["vertex_constants {", '  name: "bone_matrices"', "  type: CONSTANT_TYPE_USER_MATRIX4", "}"]
        user_vs: list[tuple[str, list[float]]] = []
        if self.lit:
            # The scene light is not baked: the render script passes the current scene's
            # light in a constant buffer (`LIGHT_CONSTANTS`), shared by every lit material.
            user_vs += [(name, value) for name, value in NEUTRAL_LIGHT.items()]
        if self.animmap:
            user_vs.append(("uv_offset", [0.0, 0.0, 0.0, 0.0]))
        for name, value in user_vs:
            out += ["vertex_constants {", f'  name: "{name}"', "  type: CONSTANT_TYPE_USER", "  value {",
                    f"    x: {fmt(value[0])}", f"    y: {fmt(value[1])}", f"    z: {fmt(value[2])}", f"    w: {fmt(value[3])}", "  }", "}"]
        fs_constants = [("tint", self.color), ("entity_color", [1.0, 1.0, 1.0, 0.0]), ("entity_alpha", [1.0, 0.0, 0.0, 0.0])]
        if self.frame_atlas:
            fs_constants.append(("frame_atlas", [0.0, 0.0, 1.0, 1.0]))
        for name, value in fs_constants:
            out += ["fragment_constants {", f'  name: "{name}"', "  type: CONSTANT_TYPE_USER", "  value {",
                    f"    x: {fmt(value[0])}", f"    y: {fmt(value[1])}", f"    z: {fmt(value[2])}", f"    w: {fmt(value[3])}", "  }", "}"]
        for i, layer in enumerate(self.layers):
            wrap_u = "WRAP_MODE_CLAMP_TO_EDGE" if layer.get("clamp_u") else "WRAP_MODE_REPEAT"
            wrap_v = "WRAP_MODE_CLAMP_TO_EDGE" if layer.get("clamp_v") else "WRAP_MODE_REPEAT"
            out += ["samplers {", f'  name: "{self.sampler_name(i)}"', f"  wrap_u: {wrap_u}", f"  wrap_v: {wrap_v}",
                    "  filter_min: FILTER_MODE_MIN_LINEAR_MIPMAP_LINEAR", "  filter_mag: FILTER_MODE_MAG_LINEAR", "  max_anisotropy: 1.0", "}"]
        out.append("max_page_count: 0")
        return "\n".join(out) + "\n"
