#pragma once

#include <string>
#include <vector>

enum PresetSection {
    PRESET_SECTION_SETTINGS,
    PRESET_SECTION_ENHANCEMENTS,
    PRESET_SECTION_AUDIO,
    PRESET_SECTION_COSMETICS,
    PRESET_SECTION_RANDOMIZER,
    PRESET_SECTION_TRACKERS,
    PRESET_SECTION_NETWORK,
    PRESET_SECTION_MAX,
};

void DrawPresetSelector(std::vector<PresetSection> includeSections, std::string currentIndex, bool disabled);
void applyPreset(std::string presetName, std::vector<PresetSection> includeSections = {});
// CRT: expose the loaded preset names (map order = alphabetical) for the simple menu.
std::vector<std::string> GetPresetNames();
// CRT: true if the preset's enhancements block still matches current CVars.
bool DoesPresetMatchCurrent(const std::string& presetName);
