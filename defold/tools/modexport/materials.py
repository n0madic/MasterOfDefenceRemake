"""Defold materials emulating the Blitz3D fixed-function brush: up to two texture layers
combined per `TextureBlend`, spherical environment maps, EntityFX flags, EntityColor /
EntityAlpha / PositionTexture as per-component constants, skinning and MD2 morph targets.
"""
from __future__ import annotations

from blitzconv import ADDITIVE_ALPHA_EXPONENT

# Blitz3D brush blend modes (`BrushBlend`), EntityFX flags, texture flags, TextureBlend.
BLEND_ALPHA, BLEND_MULTIPLY, BLEND_ADD = 1, 2, 3
FX_FULLBRIGHT, FX_VERTEX_COLORS, FX_NO_CULL, FX_FORCE_ALPHA = 1, 2, 16, 32
TEX_FLAG_ALPHA, TEX_FLAG_MASKED, TEX_FLAG_SPHERE = 2, 4, 64
TEX_BLEND_ALPHA, TEX_BLEND_MULTIPLY, TEX_BLEND_ADD, TEX_BLEND_MULTIPLY2 = 1, 2, 3, 5
MAX_LAYERS = 2
MASK_THRESHOLD = 0.5
# Only the fully-solid texels of a base decal write depth (its soft blended copy on top hides
# this hard cut); matches the Godot port's SOLID_ALPHA.
GROUND_BASE_SOLID_ALPHA = 0.99
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


class MaterialVariant:
    """One generated Defold material: a Blitz brush of one model, drawn at a given
    EntityOrder, with the shader features the model needs (`skinned`, `morph_targets`)."""

    def __init__(self, base_name: str, gltf_material: dict, info: dict, *, order: int = 0, hud: bool = False,
                 skinned: bool = False, morph_targets: int = 0, animmap: bool = False, lit_default: bool = False,
                 bone_count: int = 0, ground_base: bool = False, solid_depth: bool = False,
                 billboard: bool = False):
        self._gltf_material = gltf_material
        self._info = info
        self._kwargs = dict(order=order, hud=hud, skinned=skinned, morph_targets=morph_targets,
                            animmap=animmap, lit_default=lit_default, bone_count=bone_count, billboard=billboard)
        self.base_name = base_name
        self.name = (gltf_material["name"] + (f"@order{order}" if order else "") + ("@base" if ground_base else "")
                     + ("@solid" if solid_depth else "") + ("@billboard" if billboard else ""))
        # The name of the glb material slot this variant binds to (the solid companion reuses
        # the base decal's glb, so it binds to the base variant's slot -- see `solid_variant`).
        self.bind_name = self.name
        self.order = order
        self.hud = hud
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
        self.blend = int(info.get("blend", BLEND_ALPHA))
        # Models without a sidecar (MD2 monsters) are lit, textured and opaque.
        self.fx = int(info.get("fx", 0 if lit_default else FX_FULLBRIGHT))
        self.vertex_colors = bool(info.get("vertex_colors", False))
        self.layers: list[dict] = list(info.get("layers", []))[:MAX_LAYERS]
        if not info and gltf_material.get("pbrMetallicRoughness", {}).get("baseColorTexture") is not None:
            self.layers = [{"flags": 0, "blend": TEX_BLEND_MULTIPLY, "sphere": False, "uri": None, "from_gltf": True}]
        factor = gltf_material.get("pbrMetallicRoughness", {}).get("baseColorFactor", [1.0, 1.0, 1.0, 1.0])
        self.color = gltf_color_to_blitz(factor, additive=self.blend == BLEND_ADD)
        self.double_sided = bool(gltf_material.get("doubleSided", False)) or bool(self.fx & FX_NO_CULL)
        layer_alpha = any(int(l.get("flags", 0)) & TEX_FLAG_ALPHA for l in self.layers)
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
            # The depth-only companion of a base decal (see `solid_variant`): an alpha-scissor
            # opaque brush that writes depth for the fully-solid texels of the dirt splat, so
            # the tower's underground root is occluded. Its hard cut sits deep inside the
            # splat and is covered by the soft blended decal drawn on top (as in the Godot
            # port's alpha-scissor depth pre-pass), so no hard edge shows against the road.
            self.pass_class = "opaque"
            self.masked = True
            self.mask_threshold = GROUND_BASE_SOLID_ALPHA
        self.invisible = self.color[3] <= 0.0 and not self.layers

    def solid_variant(self) -> "MaterialVariant":
        """The depth-only companion of this base decal (an alpha-scissor opaque brush)."""
        solid = MaterialVariant(self.base_name + "_solid", self._gltf_material, self._info,
                                ground_base=True, solid_depth=True, **self._kwargs)
        solid.bind_name = self.name  # reuses this decal's glb, so binds to its material slot
        return solid

    @property
    def tags(self) -> list[str]:
        if self.hud:
            return ["hud", self.pass_class]
        if self.ground_base:
            return ["base", self.pass_class]
        return [f"order_{self.order}", self.pass_class]

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
        return self.lit or self.billboard

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
            lines += ["    mediump vec4 light_dir;", "    mediump vec4 light_color;", "    mediump vec4 ambient;"]
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
            # light, no specular (Blitz never sets EntityShininess in this game).
            lines += [
                "    vec3 l = normalize((mtx_view * vec4(light_dir.xyz, 0.0)).xyz);",
                "    var_light = clamp(ambient.rgb + light_color.rgb * max(dot(n, -l), 0.0), 0.0, 1.0);",
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
            "};",
            "",
            "// Blitz `TextureBlend` per layer, as in godot/addons/b3d_import (`combine`).",
            "vec4 combine_alpha(vec4 acc, vec4 tex) { return vec4(mix(acc.rgb, tex.rgb, tex.a), acc.a); }",
            "vec4 combine_add(vec4 acc, vec4 tex) { return vec4(acc.rgb + tex.rgb, acc.a * tex.a); }",
            "vec4 combine_multiply(vec4 acc, vec4 tex) { return acc * tex; }",
            "vec4 combine_multiply2(vec4 acc, vec4 tex) { return acc * tex * vec4(2.0, 2.0, 2.0, 1.0); }",
            "",
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
            lines.append(f"    c = {fn}(c, texture({self.sampler_name(i)}, {uv}));")
        lines.append("    c.a *= entity_alpha.x;")
        if self.pass_class == "opaque":
            if self.masked:
                lines.append(f"    if (c.a < {fmt(self.mask_threshold)}) discard;")
            lines.append("    out_fragColor = vec4(c.rgb, 1.0);")
        else:
            lines.append("    out_fragColor = c;")
        lines += ["}", ""]
        return "\n".join(lines)

    def material_file(self, light: dict, materials_path: str) -> str:
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
            user_vs += [("light_dir", light["direction"] + [0.0]), ("light_color", light["color"] + [1.0]), ("ambient", light["ambient"] + [1.0])]
        if self.animmap:
            user_vs.append(("uv_offset", [0.0, 0.0, 0.0, 0.0]))
        for name, value in user_vs:
            out += ["vertex_constants {", f'  name: "{name}"', "  type: CONSTANT_TYPE_USER", "  value {",
                    f"    x: {fmt(value[0])}", f"    y: {fmt(value[1])}", f"    z: {fmt(value[2])}", f"    w: {fmt(value[3])}", "  }", "}"]
        for name, value in (("tint", self.color), ("entity_color", [1.0, 1.0, 1.0, 0.0]), ("entity_alpha", [1.0, 0.0, 0.0, 0.0])):
            out += ["fragment_constants {", f'  name: "{name}"', "  type: CONSTANT_TYPE_USER", "  value {",
                    f"    x: {fmt(value[0])}", f"    y: {fmt(value[1])}", f"    z: {fmt(value[2])}", f"    w: {fmt(value[3])}", "  }", "}"]
        for i, layer in enumerate(self.layers):
            wrap_u = "WRAP_MODE_CLAMP_TO_EDGE" if layer.get("clamp_u") else "WRAP_MODE_REPEAT"
            wrap_v = "WRAP_MODE_CLAMP_TO_EDGE" if layer.get("clamp_v") else "WRAP_MODE_REPEAT"
            out += ["samplers {", f'  name: "{self.sampler_name(i)}"', f"  wrap_u: {wrap_u}", f"  wrap_v: {wrap_v}",
                    "  filter_min: FILTER_MODE_MIN_LINEAR_MIPMAP_LINEAR", "  filter_mag: FILTER_MODE_MAG_LINEAR", "  max_anisotropy: 1.0", "}"]
        out.append("max_page_count: 0")
        return "\n".join(out) + "\n"
