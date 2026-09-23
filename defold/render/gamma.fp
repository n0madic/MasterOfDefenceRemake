#version 140

// `_fsetgammaintensity`: SetGamma i -> i + intensity for every level (0..255), clamped --
// the whole frame's channels are offset by `gamma_offset` (intensity / 255).
in mediump vec2 var_uv;

out vec4 out_fragColor;

uniform mediump sampler2D frame;

uniform fs_uniforms
{
    mediump vec4 gamma_offset;
};

void main()
{
    vec3 c = texture(frame, var_uv).rgb;
    out_fragColor = vec4(clamp(c + gamma_offset.xyz, 0.0, 1.0), 1.0);
}
