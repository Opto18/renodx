/*
 * Copyright (C) 2023 Carlos Lopez
 * SPDX-License-Identifier: MIT
 */

#include <include/reshade_api_device.hpp>
#define ImTextureID ImU64

#define DEBUG_LEVEL_0

#include <embed/shaders.h>

#include <deps/imgui/imgui.h>
#include <include/reshade.hpp>

#include "../../mods/shader.hpp"
#define RENODX_MODS_SWAPCHAIN_VERSION 2
#include "../../mods/swapchain.hpp"
#include "../../templates/settings.hpp"
#include "../../utils/date.hpp"
#include "../../utils/settings.hpp"
#include "./shared.h"

namespace {

renodx::mods::shader::CustomShaders custom_shaders = {
    __ALL_CUSTOM_SHADERS};

ShaderInjectData shader_injection;
const std::string build_date = __DATE__;
const std::string build_time = __TIME__;

renodx::utils::settings::Settings settings = renodx::templates::settings::JoinSettings({
    renodx::templates::settings::CreateDefaultSettings({
        {"ToneMapType", &shader_injection.tone_map_type},
        {"ToneMapPeakNits", &shader_injection.peak_white_nits},
        {"ToneMapGameNits", &shader_injection.diffuse_white_nits},
        {"ToneMapUINits", &shader_injection.graphics_white_nits},
        {"ColorGradeExposure", &shader_injection.tone_map_exposure},
        {"ColorGradeHighlights", &shader_injection.tone_map_highlights},
        {"ColorGradeShadows", &shader_injection.tone_map_shadows},
        {"ColorGradeContrast", &shader_injection.tone_map_contrast},
        {"ColorGradeSaturation", &shader_injection.tone_map_saturation},
        {"ColorGradeHighlightSaturation", &shader_injection.tone_map_highlight_saturation},
        {"ColorGradeBlowout", &shader_injection.tone_map_blowout},
        {"ColorGradeFlare", &shader_injection.tone_map_flare},
        {"ToneMapHueCorrection", &shader_injection.tone_map_hue_correction},
        {"ToneMapHueShift", &shader_injection.tone_map_hue_shift},
        {"FxBloom", &shader_injection.fxBloom},
        {"FxVignette", &shader_injection.fxVignette},
    }),
    {
        new renodx::utils::settings::Setting{
            .value_type = renodx::utils::settings::SettingValueType::BUTTON,
            .label = "HDR Den Discord",
            .section = "Links",
            .group = "button-line-1",
            .tint = 0x5865F2,
            .on_change = []() {
              renodx::utils::platform::LaunchURL("https://discord.gg/XUhv", "tR54yc");
            },
        },
        new renodx::utils::settings::Setting{
            .value_type = renodx::utils::settings::SettingValueType::BUTTON,
            .label = "Github",
            .section = "Links",
            .group = "button-line-1",
            .on_change = []() {
              renodx::utils::platform::LaunchURL("https://github.com/clshortfuse/renodx");
            },
        },
        new renodx::utils::settings::Setting{
            .value_type = renodx::utils::settings::SettingValueType::BUTTON,
            .label = "Ritsu's Ko-Fi",
            .section = "Links",
            .group = "button-line-1",
            .tint = 0xFF5F5F,
            .on_change = []() {
              renodx::utils::platform::LaunchURL("https://ko-fi.com/ritsucecil");
            },
        },
        new renodx::utils::settings::Setting{
            .value_type = renodx::utils::settings::SettingValueType::BUTTON,
            .label = "ShortFuse's Ko-Fi",
            .section = "Links",
            .group = "button-line-1",
            .tint = 0xFF5F5F,
            .on_change = []() {
              renodx::utils::platform::LaunchURL("https://ko-fi.com/shortfuse");
            },
        },
        new renodx::utils::settings::Setting{
            .value_type = renodx::utils::settings::SettingValueType::BUTTON,
            .label = "HDR Den's Ko-Fi",
            .section = "Links",
            .group = "button-line-1",
            .tint = 0xFF5F5F,
            .on_change = []() {
              renodx::utils::platform::LaunchURL("https://ko-fi.com/hdrden");
            },
        },
        new renodx::utils::settings::Setting{
            .value_type = renodx::utils::settings::SettingValueType::TEXT,
            .label = "Game mod by Ritsu, Updated by Opto, RenoDX Framework by ShortFuse. Shout-out to Pumbo & Lilium for the support!",
            .section = "About",
        },
        new renodx::utils::settings::Setting{
            .value_type = renodx::utils::settings::SettingValueType::TEXT,
            .label = "This build was compiled on " + build_date + " at " + build_time + ".",
            .section = "About",
        },
    },
});

void ConfigureSettingsLabels() {
  for (auto* setting : settings) {
    if (setting->key == "ToneMapType") {
      setting->labels = {"Vanilla", "Neutwo"};
    } else if (setting->key == "ToneMapHueCorrection") {
      setting->default_value = 75.f;
      setting->can_reset = true;
    } else if (setting->key == "ToneMapHueShift") {
      setting->default_value = 30.f;
      setting->can_reset = true;
    }
  }
}

void OnPresetOff() {
  renodx::utils::settings::UpdateSettings({
      {"ToneMapGameNits", 203.f},
      {"ToneMapUINits", 203.f},
      {"ToneMapGammaCorrection", 0.f},
      {"ColorGradeExposure", 1.f},
      {"ColorGradeHighlights", 50.f},
      {"ColorGradeShadows", 50.f},
      {"ColorGradeContrast", 50.f},
      {"ColorGradeSaturation", 50.f},
      {"ColorGradeHighlightSaturation", 50.f},
      {"ColorGradeBlowout", 0.f},
      {"ColorGradeFlare", 0.f},
      {"ToneMapHueCorrection", 75.f},
      {"ToneMapHueShift", 30.f},
      {"FxBloom", 50.f},
      {"FxVignette", 50.f},
  });
}

bool fired_on_init_swapchain = false;

void OnInitSwapchain(reshade::api::swapchain* swapchain, bool resize) {
  if (fired_on_init_swapchain) return;
  fired_on_init_swapchain = true;
  auto peak = renodx::utils::swapchain::GetPeakNits(swapchain);
  if (peak.has_value()) {
    for (auto* setting : settings) {
      if (setting->key == "ToneMapPeakNits") {
        setting->default_value = peak.value();
        setting->can_reset = true;
        break;
      }
    }
  }
}

}  // namespace

extern "C" __declspec(dllexport) constexpr const char* NAME = "RenoDX";
extern "C" __declspec(dllexport) constexpr const char* DESCRIPTION = "RenoDX for Kingdom Come Deliverance 2";

BOOL APIENTRY DllMain(HMODULE h_module, DWORD fdw_reason, LPVOID lpv_reserved) {
  switch (fdw_reason) {
    case DLL_PROCESS_ATTACH:
      if (!reshade::register_addon(h_module)) return FALSE;
      reshade::register_event<reshade::addon_event::init_swapchain>(OnInitSwapchain);
      ConfigureSettingsLabels();

      // while (IsDebuggerPresent() == 0) Sleep(100);

      renodx::mods::shader::force_pipeline_cloning = true;

      renodx::mods::shader::expected_constant_buffer_space = 50;

      renodx::mods::shader::expected_constant_buffer_index = 13;

      renodx::mods::shader::allow_multiple_push_constants = true;
      renodx::mods::swapchain::SetUseHDR10(true);
      renodx::mods::swapchain::use_resource_cloning = false;


      break;
    case DLL_PROCESS_DETACH:
      reshade::unregister_event<reshade::addon_event::init_swapchain>(OnInitSwapchain);

      reshade::unregister_addon(h_module);
      break;
  }

  renodx::utils::settings::Use(fdw_reason, &settings, &OnPresetOff);

  renodx::utils::swapchain::Use(fdw_reason);
  renodx::mods::swapchain::Use(fdw_reason, &shader_injection);

  renodx::mods::shader::Use(fdw_reason, custom_shaders, &shader_injection);

  return TRUE;
}
