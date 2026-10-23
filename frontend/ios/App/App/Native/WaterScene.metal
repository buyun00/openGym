// Inferno Water.metal (Paul Hudson et al., MIT) refraction adaptation.
// SwiftUIShaders underwater-caustics (Kris Puckett, MIT) cellular-light adaptation.
// Exact upstream revisions and complete licenses: WaterThirdPartyNotices.txt.
#include <metal_stdlib>
using namespace metal;

// Adapted from Inferno: keep coordinates in float and wrap the phase.
static float2 waterRefraction(float2 uv, float time) {
    float phase = fmod(time * 0.7f, 6.28318530718f);
    uv.x += fast::sin(12.0f * uv.x + phase) * 0.012f;
    uv.y += fast::cos(12.0f * uv.y + phase) * 0.012f;
    return uv;
}

static float2 waterHash(float2 cell) {
    return fract(sin(float2(dot(cell, float2(127.1f, 311.7f)), dot(cell, float2(269.5f, 183.3f)))) * 43758.5453f);
}

// The upstream's two cellular layers are adapted to nearest-cell edge distance,
// giving connected refracted light filaments rather than isolated bright dots.
static float causticNet(float2 uv, float time) {
    // Refracted domain warping curves the cell edges; a rigid Voronoi grid looks like tiles.
    uv += 0.58f * float2(sin(uv.y * 1.8f + sin(uv.x * 1.4f) + time * 0.3f),
                        cos(uv.x * 1.7f + sin(uv.y * 1.3f) - time * 0.2f));
    uv += 0.16f * float2(sin(uv.y * 3.7f - time * 0.5f), cos(uv.x * 3.1f + time * 0.4f));
    float2 cell = floor(uv);
    float2 f = fract(uv);
    float nearest = 8.0f, second = 8.0f;
    for (int y = -1; y <= 1; ++y) {
        for (int x = -1; x <= 1; ++x) {
            float2 neighbor = float2(x, y);
            float2 seed = waterHash(cell + neighbor);
            float2 point = 0.5f + 0.32f * sin(6.2831853f * seed + float2(time * 0.4f, -time * 0.3f));
            float2 delta = neighbor + point - f;
            float d = dot(delta, delta);
            if (d < nearest) { second = nearest; nearest = d; }
            else { second = min(second, d); }
        }
    }
    float edge = sqrt(second) - sqrt(nearest);
    return exp(-edge * 23.0f) * 0.8f + exp(-edge * 5.0f) * 0.2f;
}

static float sampleWaterField(float x, device const float *values, int count) {
    if (count <= 0) { return 0.0f; }
    float index = clamp(x * float(count) - 0.5f, 0.0f, float(count - 1));
    int left = int(index);
    int right = min(count - 1, left + 1);
    return mix(values[left], values[right], index - float(left));
}

// floatArray arguments arrive as a device pointer followed by its element count.
[[ stitchable ]] half4 opengymWater(float2 position, half4 source, float2 size, float time,
                                   device const float *depths, int depthCount,
                                   device const float *velocities, int velocityCount,
                                   device const float *foam, int foamCount,
                                   float ripple, float fill, float dark) {
    float2 uv = position / max(size, float2(1.0f));
    float x = uv.x;
    // Must match WaterSurface.waterline(at:). Each column has its own water
    // depth: crests propagate and fall instead of rotating around screen center.
    float surface = 1.0f - sampleWaterField(x, depths, depthCount)
        + ripple * (cos(4.0f * M_PI_F * x) * sin(time * 1.7f)
                  + 0.4f * cos(8.0f * M_PI_F * x) * sin(time * 1.1f));
    if (fill <= 0.0f) { surface = 2.0f; }
    if (fill >= 1.0f) { surface = -1.0f; }
    float depth = uv.y - surface;
    float antialias = 1.0f / max(size.y, 1.0f);
    float submerged = smoothstep(-antialias, antialias, depth);
    float3 air = mix(float3(0.97f, 0.985f, 0.99f), float3(0.88f, 0.95f, 0.97f), uv.y);
    air = mix(air, mix(float3(0.035f, 0.07f, 0.11f), float3(0.05f, 0.15f, 0.20f), uv.y), dark);
    if (submerged <= 0.0f) { return half4(half3(air), 1.0h); }

    float d = max(0.0f, depth);
    float3 shallow = mix(float3(0.36f, 0.80f, 0.89f), float3(0.035f, 0.36f, 0.44f), dark);
    float3 deep = mix(float3(0.035f, 0.58f, 0.70f), float3(0.015f, 0.15f, 0.24f), dark);
    float3 water = mix(shallow, deep, 1.0f - exp(-d * 1.9f));

    float flow = sampleWaterField(x, velocities, velocityCount);
    float froth = sampleWaterField(x, foam, foamCount);
    float2 refracted = waterRefraction(float2(uv.x + flow * 0.025f, uv.y), time);
    float aspect = size.x / max(size.y, 1.0f);
    float2 lightUV = float2(refracted.x * 5.0f, refracted.y * 5.0f / max(aspect, 0.3f));
    // A second, faint layer adds depth without refracting text or controls.
    float net = causticNet(lightUV, time);
    float fine = causticNet(lightUV * 1.63f + 8.0f, -time);
    float focus = (net * 0.52f + fine * 0.16f + fine * net * 0.50f) * (0.25f + 0.35f * min(d, 1.0f));
    water += float3(0.66f, 0.95f, 1.0f) * focus * mix(0.62f, 0.25f, dark);
    float shafts = pow(0.5f + 0.5f * sin(uv.x * 19.0f + d * 4.0f + time * 0.2f), 6.0f);
    water += float3(0.08f, 0.16f, 0.18f) * shafts * exp(-d * 3.5f) * mix(1.0f, 0.3f, dark);

    // Meniscus, Fresnel highlight and a refracted underside, all attached to the physical surface.
    float band = exp(-d * size.y / 9.0f);
    float crest = exp(-abs(depth) * size.y / 1.4f);
    float underside = exp(-pow((d * size.y - 8.0f) / 3.0f, 2.0f));
    float glint = 0.65f + 0.35f * sin(uv.x * 31.0f + time * 0.8f);
    water += band * float3(0.10f, 0.19f, 0.20f) + crest * glint * float3(0.55f, 0.63f, 0.63f);
    float surfaceRipples = pow(0.5f + 0.5f * sin(d * size.y * 0.75f + sin(uv.x * 24.0f + time * 1.2f) * 2.5f), 8.0f);
    water += surfaceRipples * band * float3(0.12f, 0.20f, 0.22f);
    // Compression and wall impacts create foam that fades with the simulated flow.
    float foamGrain = 0.65f + 0.35f * sin(uv.x * 140.0f - time * 2.0f + flow * 6.0f);
    water = mix(water, float3(0.90f, 0.98f, 1.0f), clamp(froth * band * foamGrain * 0.8f, 0.0f, 0.7f));
    water -= underside * float3(0.06f, 0.08f, 0.06f);
    return half4(half3(mix(air, clamp(water, 0.0f, 1.0f), submerged)), 1.0h) * source.a;
}
