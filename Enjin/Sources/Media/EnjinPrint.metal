// "Enjin print": one look for every picture that enters a canvas, so real
// photos and generated illustrations feel like pages of the same sketchbook.
// A Core Image stitchable kernel, applied once at import (not per frame).
// Run it on sRGB-encoded values (see PrintStylizer): the palette below is sRGB.
#include <CoreImage/CoreImage.h>
using namespace metal;

namespace enjin {
    constant float3 kInk   = float3(0.043, 0.043, 0.047); // ENJIN ink (#0b0b0c)
    constant float3 kPaper = float3(0.980, 0.980, 0.976); // ENJIN paper (#fafaf9)
    constant float3 kLuma  = float3(0.299, 0.587, 0.114);

    float hash(float2 p) {
        p = fract(p * float2(123.34, 456.21));
        p += dot(p, p + 45.32);
        return fract(p.x * p.y);
    }

    // Posterize with soft steps, so bands read as print layers, not banding.
    float softBands(float v, float bands) {
        float x = v * bands;
        float f = fract(x);
        return (floor(x) + smoothstep(0.35, 0.65, f)) / bands;
    }
}

extern "C" [[stitchable]] float4 enjinPrint(coreimage::sampler src, float bands, float keepColor, float edgeAmount, float grain,
                             coreimage::destination dest) {
    using namespace enjin;
    float2 dc = dest.coord();
    float4 c = src.sample(src.transform(dc));
    float3 rgb = c.rgb;
    float l = dot(rgb, kLuma);

    // Color: posterize brightness only (print layers) and keep each pixel's
    // own chroma on top, so hues never shift. Expects sRGB-encoded input.
    float lc = clamp((l - 0.5) * 1.12 + 0.52, 0.0, 1.0);
    float lp = softBands(lc, bands);
    float3 hue = clamp(lp + (rgb - l) * keepColor, 0.0, 1.0);

    // Unify: a little of the shared ink->paper tone everywhere, ink in the deep
    // shadows, and bright skies/backgrounds melt into the card's paper color.
    float3 tone = mix(kInk, kPaper, softBands(l, bands));
    float3 col = mix(hue, tone, 0.18);
    col = mix(col, kInk, (1.0 - smoothstep(0.02, 0.22, l)) * 0.55);
    col = mix(col, kPaper, smoothstep(0.78, 0.93, l) * 0.85);

    // Ink lines: Sobel on luminance.
    float s[9];
    int k = 0;
    for (int y = -1; y <= 1; y++) {
        for (int x = -1; x <= 1; x++) {
            s[k++] = dot(src.sample(src.transform(dc + float2(x, y) * 1.5)).rgb, kLuma);
        }
    }
    float gx = -s[0] - 2.0 * s[3] - s[6] + s[2] + 2.0 * s[5] + s[8];
    float gy = -s[0] - 2.0 * s[1] - s[2] + s[6] + 2.0 * s[7] + s[8];
    float edge = smoothstep(0.18, 0.55, length(float2(gx, gy)));
    col = mix(col, kInk, edge * edgeAmount);

    // Paper: warm multiply and a little grain.
    col *= mix(float3(1.0), kPaper, 0.5);
    col += (hash(floor(dc)) - 0.5) * grain;

    return float4(clamp(col, 0.0, 1.0), c.a);
}
