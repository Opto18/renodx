#include "./shared.h"

Texture2D<float4> Tx2Tx_Source : register(t0);
Texture2D<float4> UITex_Source : register(t1);

cbuffer PER_BATCH : register(b0, space2) {
  float4 HDRParams : packoffset(c000.x);
};

SamplerState Tx2Tx_Sampler : register(s2);

float3 ApplyLuminancePeakRolloff(float3 color_bt2020_rel) {
  float peak_rel = max(RENODX_PEAK_WHITE_NITS / RENODX_DIFFUSE_WHITE_NITS, 1.f);
  float knee_rel = max(peak_rel * 0.75f, 1e-4f);

  float luminance = renodx::color::y::from::BT2020(color_bt2020_rel);
  if (luminance <= knee_rel) return color_bt2020_rel;

  float rolled_luminance = renodx::tonemap::ExponentialRollOff(luminance, knee_rel, peak_rel);
  float scale = rolled_luminance / max(luminance, 1e-6f);
  return color_bt2020_rel * scale;
}

float4 main(
  noperspective float4 SV_Position : SV_Position,
  linear float2 TEXCOORD : TEXCOORD
) : SV_Target {
  float4 scene_sample = Tx2Tx_Source.Sample(Tx2Tx_Sampler, TEXCOORD);
  float4 ui_sample = UITex_Source.Sample(Tx2Tx_Sampler, TEXCOORD);

  // KCD2 scene is authored around 80-nit paper white. Remap to Reno diffuse-relative space.
  float3 scene_rel = max(scene_sample.rgb, 0.f) * (80.f / RENODX_DIFFUSE_WHITE_NITS);

  float ui_alpha = saturate(ui_sample.a);
  float3 ui_rel = renodx::color::srgb::DecodeSafe(saturate(ui_sample.rgb));
  ui_rel = min(ui_rel, 1.f);
  // Optional UI-vs-scene white control (defaults to 1.0 when both are 203).
  ui_rel *= (RENODX_GRAPHICS_WHITE_NITS / RENODX_DIFFUSE_WHITE_NITS);

  // Straight-alpha blend in one consistent relative-linear space.
  float3 blended_rel = lerp(scene_rel, ui_rel, ui_alpha);

  // HDR10 output: BT.709 -> BT.2020, apply soft peak rolloff, then PQ encode.
  float3 blended_bt2020_rel = renodx::color::bt2020::from::BT709(blended_rel);
  blended_bt2020_rel = ApplyLuminancePeakRolloff(blended_bt2020_rel);

  float4 out_color;
  out_color.rgb = renodx::color::pq::EncodeSafe(blended_bt2020_rel, RENODX_DIFFUSE_WHITE_NITS);
  out_color.a = scene_sample.a;
  return out_color;
}
