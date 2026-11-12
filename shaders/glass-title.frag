#version 440

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 effectSize;
    float shimmer;
} ubuf;
layout(binding = 1) uniform sampler2D glyphMask;
layout(binding = 2) uniform sampler2D backdrop;

float maskAt(vec2 uv) { return texture(glyphMask, uv).a; }

void main()
{
    vec2 uv = qt_TexCoord0;
    vec2 px = 1.0 / max(ubuf.effectSize, vec2(1.0));
    float mask = maskAt(uv);
    // Broad polished bevel, with a sharper rim along the actual letter outline.
    vec2 bevel = px * 1.3;
    float left = maskAt(uv - vec2(bevel.x, 0.0));
    float right = maskAt(uv + vec2(bevel.x, 0.0));
    float top = maskAt(uv - vec2(0.0, bevel.y));
    float bottom = maskAt(uv + vec2(0.0, bevel.y));
    vec2 normal = vec2(left - right, top - bottom);
    float rim = clamp(1.0 - min(min(left, right), min(top, bottom)), 0.0, 1.0);
    float rounding = 0.0;
    vec2 broadNormal = vec2(0.0);
    for (int i = 1; i <= 12; ++i) {
        vec2 radius = px * float(i) * 1.2;
        float l = maskAt(uv - vec2(radius.x, 0.0));
        float r = maskAt(uv + vec2(radius.x, 0.0));
        float t = maskAt(uv - vec2(0.0, radius.y));
        float b = maskAt(uv + vec2(0.0, radius.y));
        rounding += (4.0 - l - r - t - b) / 48.0;
        broadNormal += vec2(l - r, t - b) / 12.0;
    }
    vec2 refracted = clamp(uv + broadNormal * px * 12.0
                           + vec2(0.008 * sin(uv.y * 9.0), -0.012), 0.0, 1.0);
    vec3 scene = texture(backdrop, refracted).rgb;
    // Pastel surroundings remain visible in the reflective, translucent body.
    vec3 frost = (scene * 2.0 + texture(backdrop, refracted + px * 2.0).rgb
                  + texture(backdrop, refracted - px * 2.0).rgb) * 0.25;
    float light = dot(normal, normalize(vec2(-0.55, -0.85)));
    float sheen = exp(-pow((uv.x * 0.68 + uv.y * 0.32 - ubuf.shimmer) * 9.0, 2.0));
    // Crisp triangular reflection planes create the angular mirror finish.
    float facet = abs(fract(uv.x * 3.4 + 0.08) * 2.0 - 1.0);
    float horizon = 0.54 + (facet - 0.5) * 0.11;
    float split = smoothstep(horizon - 0.004, horizon + 0.004, uv.y);
    float reflection = exp(-pow((uv.y - horizon + 0.13) * 7.0, 2.0));
    float caps = pow(abs(uv.y - 0.57) * 1.8, 1.7);
    vec3 tint = mix(vec3(0.24, 0.89, 1.0), vec3(0.76, 0.63, 0.98), uv.x);
    vec3 glass = mix(frost, tint, split * 0.36);
    float pearl = clamp(rounding * 1.8 + caps * 0.72 + reflection * 0.32 + sheen * 0.08, 0.0, 0.90);
    glass = mix(glass, vec3(1.0), pearl);
    glass += max(light, 0.0) * 0.55;
    glass -= vec3(0.17, 0.11, 0.02) * max(-light, 0.0) * 0.35;
    glass -= vec3(0.08, 0.015, 0.0) * broadNormal.y * 0.18;
    float alpha = mask * clamp(0.52 + rounding * 0.65 + rim * 0.22 + caps * 0.20, 0.0, 0.98);
    fragColor = vec4(clamp(glass, 0.0, 1.0) * alpha, alpha) * ubuf.qt_Opacity;
}
