#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

/// Native God Rays — Paper Design–inspired look for Intake Settings.
/// Not a copy of @paper-design/shaders; stitchable SwiftUI Metal for macOS.

constant float GR_PI = 3.14159265359;
constant float GR_TWO_PI = 6.28318530718;

static float gr_hash11(float p) {
    p = fract(p * 0.1031);
    p *= p + 33.33;
    p *= p + p;
    return fract(p);
}

static float gr_hash21(float2 p) {
    float3 p3 = fract(float3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

static float gr_valueNoise(float2 st) {
    float2 i = floor(st);
    float2 f = fract(st);
    float a = gr_hash21(i);
    float b = gr_hash21(i + float2(1.0, 0.0));
    float c = gr_hash21(i + float2(0.0, 1.0));
    float d = gr_hash21(i + float2(1.0, 1.0));
    float2 u = f * f * (3.0 - 2.0 * f);
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

static float2 gr_rotate(float2 v, float angle) {
    float s = sin(angle);
    float c = cos(angle);
    return float2(c * v.x - s * v.y, s * v.x + c * v.y);
}

static float gr_raysShape(float2 uv, float r, float freq, float intensityPow) {
    float a = atan2(uv.y, uv.x);
    float2 left = float2(a * freq, r);
    float2 right = float2(fract(a / GR_TWO_PI) * GR_TWO_PI * freq, r);
    float nLeft = pow(gr_valueNoise(left), intensityPow);
    float nRight = pow(gr_valueNoise(right), intensityPow);
    return mix(nRight, nLeft, smoothstep(-0.15, 0.15, uv.x));
}

[[ stitchable ]] half4 intakeGodRays(
    float2 position,
    half4 currentColor,
    float2 size,
    float time,
    float intensity,
    float density,
    float spotty,
    float midSize,
    float midIntensity,
    float bloom,
    float scale,
    float offsetY,
    half4 color0,
    half4 color1,
    half4 colorBack,
    half4 colorBloom
) {
    float2 uv = (position / max(size, float2(1.0))) * 2.0 - 1.0;
    float aspect = size.x / max(size.y, 1.0);
    uv.x *= aspect;
    uv *= max(scale, 0.05);
    uv.y += offsetY;

    float t = 0.2 * time;
    float radius = length(uv);
    float spots = 6.5 * abs(spotty);
    float intensityPow = 4.0 - 3.0 * clamp(intensity, 0.0, 1.0);

    float mid = 10.0 * abs(midSize);
    float msLo = 0.02 * mid;
    float msHi = max(mid, 1e-6);
    float middleShape = pow(max(midIntensity, 0.0), 0.3) * (1.0 - smoothstep(msLo, msHi, 3.0 * radius));
    middleShape = pow(middleShape, 5.0);

    float3 accumColor = float3(0.0);
    float accumAlpha = 0.0;

    half4 colors[2] = { color0, color1 };
    for (int i = 0; i < 2; i++) {
        float2 rotatedUV = gr_rotate(uv, float(i) + 1.0);
        float r1 = radius * (1.0 + 0.4 * float(i)) - 3.0 * t;
        float r2 = 0.5 * radius * (1.0 + spots) - 2.0 * t;
        float dens = 6.0 * density + step(0.5, density) * pow(4.5 * (density - 0.5), 4.0);
        float f = mix(1.0, 3.0 + 0.5 * float(i), gr_hash11(float(i) * 15.0)) * dens;

        float ray = gr_raysShape(rotatedUV, r1, 5.0 * f, intensityPow);
        ray *= gr_raysShape(rotatedUV, r2, 4.0 * f, intensityPow);
        ray += (1.0 + 4.0 * ray) * middleShape;
        ray = clamp(ray, 0.0, 1.0);

        float srcAlpha = float(colors[i].a) * ray;
        float3 srcColor = float3(colors[i].rgb) * srcAlpha;

        float3 alphaBlendColor = accumColor + (1.0 - accumAlpha) * srcColor;
        float alphaBlendAlpha = accumAlpha + (1.0 - accumAlpha) * srcAlpha;
        float3 addBlendColor = accumColor + srcColor;
        float addBlendAlpha = accumAlpha + srcAlpha;

        accumColor = mix(alphaBlendColor, addBlendColor, bloom);
        accumAlpha = mix(alphaBlendAlpha, addBlendAlpha, bloom);
    }

    float3 overlayColor = float3(colorBloom.rgb) * float(colorBloom.a);
    float3 colorWithOverlay = accumColor + accumAlpha * overlayColor;
    accumColor = mix(accumColor, colorWithOverlay, bloom);

    float3 bgColor = float3(colorBack.rgb) * float(colorBack.a);
    float3 color = accumColor + (1.0 - accumAlpha) * bgColor;
    float opacity = accumAlpha + (1.0 - accumAlpha) * float(colorBack.a);
    color = clamp(color, 0.0, 1.0);
    opacity = clamp(opacity, 0.0, 1.0);

    // Preserve any existing content alpha when layered via colorEffect.
    half outA = half(opacity);
    return half4(half3(color), outA);
}
