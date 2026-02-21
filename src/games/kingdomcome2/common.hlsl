#include "shared.h"
#include "./macleod_boynton.hlsli"

const static float NIGHT_LUMINANCE = renodx::math::FLT32_MIN;
const static float DAY_LUMINANCE = 2.5f;
const static float NIGHT_EXPOSURE = 1.85f;  // Keep dark scenes well-lit
const static float DAY_EXPOSURE = 0.35f;    // Reduce bright scenes more (adjust to taste)

// Adaptive exposure based on scene luminance
// Higher luminance (bright scenes) = more exposure reduction
// Lower luminance (dark scenes) = less exposure reduction
// Luminance range: Night=0.009, Day=2.0

/* float CalculateExposure(float luminance) {
  if (!RENODX_TONE_MAP_TYPE) return 1.f;
  // For bright scenes (high luminance), we want low exposure
  // For dark scenes (low luminance), we want high exposure

  // Create smooth curve based on luminance
  float t = saturate((luminance - NIGHT_LUMINANCE) / (DAY_LUMINANCE - NIGHT_LUMINANCE));

  // Use smoothstep for natural transition
  float smoothT = smoothstep(0.0, 1.0, t);

  // Interpolate between night and day exposure
  return lerp(NIGHT_EXPOSURE, DAY_EXPOSURE, smoothT);
} */
float CalculateExposure(float luminance, float power = 1.f) {
  if (!RENODX_TONE_MAP_TYPE) return 1.f;
  return renodx::math::PowSafe(1.0 / (1.0 + luminance), power);
}

float Highlights(float x, float highlights, float mid_gray) {
  if (highlights == 1.f) return x;

  if (highlights > 1.f) {
    return max(x, lerp(x, mid_gray * pow(x / mid_gray, highlights), min(x, 1.f)));
  }

  x /= mid_gray;
  return lerp(x, pow(x, highlights), step(1.f, x)) * mid_gray;
}

float Shadows(float x, float shadows, float mid_gray) {
  if (shadows == 1.f) return x;

  const float ratio = max(renodx::math::DivideSafe(x, mid_gray, 0.f), 0.f);
  const float base_term = x * mid_gray;
  const float base_scale = renodx::math::DivideSafe(base_term, ratio, 0.f);

  if (shadows > 1.f) {
    float raised = x * (1.f + renodx::math::DivideSafe(base_term, pow(ratio, shadows), 0.f));
    float reference = x * (1.f + base_scale);
    return max(x, x + (raised - reference));
  }

  float lowered = x * (1.f - renodx::math::DivideSafe(base_term, pow(ratio, 2.f - shadows), 0.f));
  float reference = x * (1.f - base_scale);
  return clamp(x + (lowered - reference), 0.f, x);
}

float3 ApplyLuminosityGrading(float3 untonemapped_bt2020, float lum, renodx::color::grade::Config config,
                              float mid_gray = 0.18f) {
  if (config.exposure == 1.f &&
      config.shadows == 1.f &&
      config.highlights == 1.f &&
      config.contrast == 1.f &&
      config.flare == 0.f) {
    return untonemapped_bt2020;
  }

  float3 color = untonemapped_bt2020 * config.exposure;
  float lum_exposed = lum * config.exposure;

  const float lum_normalized = renodx::math::DivideSafe(max(lum_exposed, 0.f), mid_gray, 0.f);
  float flare = renodx::math::DivideSafe(lum_normalized + config.flare, lum_normalized, 1.f);
  float exponent = config.contrast * flare;
  const float lum_contrasted = pow(max(lum_normalized, 0.f), exponent) * mid_gray;

  float lum_highlighted = Highlights(lum_contrasted, config.highlights, mid_gray);
  float lum_shadowed = Shadows(lum_highlighted, config.shadows, mid_gray);

  float lum_scale = renodx::math::DivideSafe(lum_shadowed, max(lum_exposed, 0.f), 0.f);
  return max(color * lum_scale, 0.f);
}

float3 ApplyHueAndPurityGrading(
    float3 ungraded_bt2020,
    float3 reference_bt2020,
    float lum,
    renodx::color::grade::Config config,
    float curve_gamma = 1.f,
    float2 mb_white_override = float2(-1.f, -1.f),
    float t_min = 1e-7f) {
  float3 color_bt2020 = ungraded_bt2020;

  // First apply local purity scaling from the grading controls.
  float purity_scale = 1.f;
  if (config.dechroma != 0.f) {
    purity_scale *= lerp(1.f, 0.f, saturate(pow(lum / (10000.f / 100.f), (1.f - config.dechroma))));
  }

  if (config.blowout != 0.f) {
    float percent_max = saturate(lum * 100.f / 10000.f);
    float blowout_strength = 100.f;
    float blowout_change = pow(1.f - percent_max, blowout_strength * abs(config.blowout));
    if (config.blowout < 0.f) {
      blowout_change = 2.f - blowout_change;
    }
    purity_scale *= blowout_change;
  }

  purity_scale *= config.saturation;

  if (purity_scale != 1.f) {
    float base_purity01 =
        renodx_custom::color::macleod_boynton::ApplyBT2020(color_bt2020, 1.f, 1.f, mb_white_override, t_min)
            .purityCur01;
    float scaled_purity01 = saturate(base_purity01 * max(purity_scale, 0.f));
    color_bt2020 =
        renodx_custom::color::macleod_boynton::ApplyBT2020(
            color_bt2020, scaled_purity01, curve_gamma, mb_white_override, t_min)
            .rgbOut;
  }

  // Then emulate hue/purity from a reference color using split-strength MB logic.
  // Keep skin tones stable: bias hue/purity emulation toward brighter ranges.
  float hue_strength = saturate(RENODX_TONE_MAP_HUE_SHIFT);
  float purity_emulation_strength = saturate(RENODX_TONE_MAP_HUE_CORRECTION);
  if (hue_strength > 0.f || purity_emulation_strength > 0.f) {
    float3 color_bt709 = renodx::color::bt709::from::BT2020(color_bt2020);
    float3 reference_bt709 = renodx::color::bt709::from::BT2020(reference_bt2020);
    color_bt709 = CorrectHueAndPurityMBSplitStrength(
        color_bt709,
        reference_bt709,
        0.f,
        hue_strength,
        0.f,
        purity_emulation_strength,
        1.0f,
        2.0f,
        curve_gamma,
        mb_white_override,
        t_min);
    color_bt2020 = renodx::color::bt2020::from::BT709(color_bt709);
  }

  return max(color_bt2020, 0.f);
}

float3 ApplyInjectedColorGrading(float3 color) {
  if (!RENODX_TONE_MAP_TYPE) return color;

  renodx::color::grade::Config grade_config = renodx::color::grade::config::Create();
  grade_config.exposure = RENODX_TONE_MAP_EXPOSURE;
  grade_config.highlights = RENODX_TONE_MAP_HIGHLIGHTS;
  grade_config.shadows = RENODX_TONE_MAP_SHADOWS;
  grade_config.contrast = RENODX_TONE_MAP_CONTRAST;
  grade_config.flare = RENODX_TONE_MAP_FLARE;
  grade_config.saturation = RENODX_TONE_MAP_SATURATION;
  grade_config.dechroma = RENODX_TONE_MAP_BLOWOUT;
  grade_config.blowout = 1.f - RENODX_TONE_MAP_HIGHLIGHT_SATURATION;
  grade_config.hue_correction_strength = 0.f;

  float3 color_bt2020 = renodx::color::bt2020::from::BT709(max(color, 0.f));
  float lum = LuminosityFromBT2020LuminanceNormalized(color_bt2020);

  float3 graded_bt2020 = ApplyLuminosityGrading(color_bt2020, lum, grade_config, 0.18f);

  // Build a soft highlight reference; MB hue/purity emulation pushes toward this.
  float3 chrominance_hue_reference_bt2020 = renodx::tonemap::ReinhardPiecewise(graded_bt2020, 5.f, 1.5f);
  float graded_lum = LuminosityFromBT2020LuminanceNormalized(graded_bt2020);
  graded_bt2020 = ApplyHueAndPurityGrading(
      graded_bt2020, chrominance_hue_reference_bt2020, graded_lum, grade_config);

  return renodx::color::bt709::from::BT2020(graded_bt2020);
}

float3 ApplyBT2020GamutCompression(float3 color_bt709) {
  float3 color_bt2020 = renodx::color::bt2020::from::BT709(color_bt709);
  float grayscale = renodx::color::y::from::BT2020(color_bt2020);

  const float MID_GRAY_LINEAR = 1.f / (pow(10.f, 0.75f));                  // ~0.18f
  const float MID_GRAY_PERCENT = 0.5f;                                     // 50%
  const float MID_GRAY_GAMMA = log(MID_GRAY_LINEAR) / log(MID_GRAY_PERCENT);  // ~2.49f

  float3 encoded = renodx::color::gamma::EncodeSafe(color_bt2020, MID_GRAY_GAMMA);
  float encoded_gray = renodx::color::gamma::Encode(grayscale, MID_GRAY_GAMMA);

  float3 compressed = renodx::color::correct::GamutCompress(encoded, encoded_gray);
  float3 decoded = renodx::color::gamma::DecodeSafe(compressed, MID_GRAY_GAMMA);

  return renodx::color::bt709::from::BT2020(decoded);
}




