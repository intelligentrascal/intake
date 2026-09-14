#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

/// Paper Design–inspired MeshGradient (native Metal). Not @paper-design/npm.
/// Captain refs: colors #343232/#000000, distortion 1, swirl 0.3, grainMixer 0.31,
/// grainOverlay 0, speed 0.26, scale 0.52, rotation 90°.

constant float PM_PI = 3.14159265359;

static float pm_hash21(float2 p) {
    float3 p3 = fract(float3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

static float pm_valueNoise(float2 st) {
    float2 i = floor(st);
    float2 f = fract(st);
    float a = pm_hash21(i);
    float b = pm_hash21(i + float2(1.0, 0.0));
    float c = pm_hash21(i + float2(0.0, 1.0));
    float d = pm_hash21(i + float2(1.0, 1.0));
    float2 u = f * f * (3.0 - 2.0 * f);
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

static float2 pm_rotate(float2 v, float angle) {
    float s = sin(angle);
    float c = cos(angle);
    return float2(c * v.x - s * v.y, s * v.x + c * v.y);
}

static float2 pm_getPosition(int i, float t) {
    float a = float(i) * 0.37;
    float b = 0.6 + fract(float(i) / 3.0) * 0.9;
    float c = 0.8 + fract(float(i + 1) / 4.0);
    float x = sin(t * b + a);
    float y = cos(t * c + a * 1.5);
    return 0.5 + 0.5 * float2(x, y);
}

[[ stitchable ]] half4 intakePaperMesh(
    float2 position,
    half4 currentColor,
    float2 size,
    float time,
    float distortion,
    float swirl,
    float grainMixer,
    float grainOverlay,
    float scale,
    float rotationDegrees,
    half4 color0,
    half4 color1
) {
    float2 uv = position / max(size, float2(1.0));
    // Center, apply scale + rotation (Paper sizing).
    uv -= 0.5;
    float rad = rotationDegrees * PM_PI / 180.0;
    uv = pm_rotate(uv, rad);
    uv /= max(scale, 0.01);
    uv += 0.5;

    float2 grainUV = uv * 1000.0;
    float mixerGrain = 0.0;
    if (grainMixer > 0.0) {
        mixerGrain = 0.4 * grainMixer * (pm_valueNoise(grainUV) - 0.5);
    }

    const float firstFrameOffset = 41.5;
    float t = 0.5 * (time + firstFrameOffset);

    float radius = smoothstep(0.0, 1.0, length(uv - 0.5));
    float center = 1.0 - radius;
    for (float i = 1.0; i <= 2.0; i += 1.0) {
        uv.x += distortion * center / i
            * sin(t + i * 0.4 * smoothstep(0.0, 1.0, uv.y))
            * cos(0.2 * t + i * 2.4 * smoothstep(0.0, 1.0, uv.y));
        uv.y += distortion * center / i
            * cos(t + i * 2.0 * smoothstep(0.0, 1.0, uv.x));
    }

    float2 uvRotated = uv - float2(0.5);
    float angle = 3.0 * swirl * radius;
    uvRotated = pm_rotate(uvRotated, -angle);
    uvRotated += float2(0.5);

    half4 colors[2] = { color0, color1 };
    float3 color = float3(0.0);
    float opacity = 0.0;
    float totalWeight = 0.0;

    for (int i = 0; i < 2; i++) {
        float2 pos = pm_getPosition(i, t) + mixerGrain;
        float3 colorFraction = float3(colors[i].rgb) * float(colors[i].a);
        float opacityFraction = float(colors[i].a);
        float dist = length(uvRotated - pos);
        dist = pow(dist, 3.5);
        float weight = 1.0 / (dist + 1e-3);
        color += colorFraction * weight;
        opacity += opacityFraction * weight;
        totalWeight += weight;
    }

    color /= max(1e-4, totalWeight);
    opacity /= max(1e-4, totalWeight);

    if (grainOverlay > 0.0) {
        float grain = pm_valueNoise(pm_rotate(grainUV, 1.0) + float2(3.0));
        grain = mix(grain, pm_valueNoise(pm_rotate(grainUV, 2.0) + float2(-1.0)), 0.5);
        grain = pow(grain, 1.3);
        float grainV = grain * 2.0 - 1.0;
        float3 grainColor = float3(step(0.0, grainV));
        float grainStrength = grainOverlay * abs(grainV);
        grainStrength = pow(grainStrength, 0.8);
        color = mix(color, grainColor, 0.35 * grainStrength);
        opacity += 0.5 * grainStrength;
    }

    opacity = clamp(opacity, 0.0, 1.0);
    color = clamp(color, 0.0, 1.0);
    return half4(half3(color), half(opacity));
}
