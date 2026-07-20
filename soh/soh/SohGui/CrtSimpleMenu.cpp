#include "CrtSimpleMenu.h"

#include "soh/OTRGlobals.h"
#include "soh/Enhancements/enhancementTypes.h"
#include "soh/Enhancements/randomizer/randomizerEnums/RandomizerOptions.h"
#include "soh/Enhancements/randomizer/settings.h"
#include "soh/ShipInit.hpp"
#include "soh/cvar_prefixes.h"
#include <libultraship/bridge.h>
#include <ship/Context.h>
#include <ship/window/gui/ConsoleWindow.h>
#include <ship/controller/controldeck/ControlDeck.h>
#include <ship/controller/controldevice/controller/Controller.h>
#include <ship/controller/controldevice/controller/ControllerButton.h>
#include <ship/controller/physicaldevice/ConnectedPhysicalDeviceManager.h>
#include <libultraship/libultra/controller.h>
#include <fast/Fast3dGui.h>
#include <climits>
#include <cstdio>
#include <string>
#include <utility>

extern "C" {
#include "z64.h"
#include "include/z64audio.h"
#include "variables.h"
}

namespace Ship {

// CRT: draw a "label ............ [Apply]" row with the Apply button right-aligned.
// Presets UI temporarily disabled -- kept here for when we re-enable it.
/*
static void DrawCrtPresetRow(const std::string& presetName) {
    std::string label = presetName;
    const std::string prefix = "Enhancements - ";
    if (label.rfind(prefix, 0) == 0) {
        label = label.substr(prefix.size());
    }

    ImGui::AlignTextToFramePadding();
    ImGui::TextUnformatted(label.c_str());
    ImGui::SameLine();

    float buttonWidth = ImGui::CalcTextSize("Apply").x + ImGui::GetStyle().FramePadding.x * 2.0f;
    float avail = ImGui::GetContentRegionAvail().x;
    if (avail > buttonWidth) {
        ImGui::SetCursorPosX(ImGui::GetCursorPosX() + (avail - buttonWidth));
    }
    if (ImGui::Button(("Apply##" + presetName).c_str())) {
        applyPreset(presetName);
    }
}
*/

// CRT: bulk QoL/fixes pack toggled from the Enhancements tab.
static const std::pair<const char*, int> kCrtEnhancedModeCVars[] = {
    { CVAR_ENHANCEMENT("AssignableTunicsAndBoots"), 1 },
    { CVAR_ENHANCEMENT("Autosave"), 1 },
    { CVAR_ENHANCEMENT("BetterOwl"), 1 },
    { CVAR_ENHANCEMENT("CreditsFix"), 1 },
    { CVAR_ENHANCEMENT("CustomizeFrogsOcarinaGame"), 1 },
    { CVAR_ENHANCEMENT("DekuNutUpgradeFix"), 1 },
    { CVAR_ENHANCEMENT("DisableLOD"), 1 },
    { CVAR_ENHANCEMENT("DpadEquips"), 1 },
    { CVAR_ENHANCEMENT("DpadNoDropOcarinaInput"), 1 },
    { CVAR_ENHANCEMENT("DynamicWalletIcon"), 1 },
    { CVAR_ENHANCEMENT("EnemySpawnsOverWaterboxes"), 1 },
    { CVAR_ENHANCEMENT("FasterRupeeAccumulator"), 1 },
    { CVAR_ENHANCEMENT("FixBrokenGiantsKnife"), 1 },
    { CVAR_ENHANCEMENT("FixDampeGoingBackwards"), 1 },
    { CVAR_ENHANCEMENT("FixDaruniaDanceSpeed"), 1 },
    { CVAR_ENHANCEMENT("FixDungeonMinimapIcon"), 1 },
    { CVAR_ENHANCEMENT("FixEyesOpenWhileSleeping"), 1 },
    { CVAR_ENHANCEMENT("FixFloorSwitches"), 1 },
    { CVAR_ENHANCEMENT("FixHammerHand"), 1 },
    { CVAR_ENHANCEMENT("FixKokiriForestQuestStage"), 1 },
    { CVAR_ENHANCEMENT("FixMenuLR"), 1 },
    { CVAR_ENHANCEMENT("FixSawSoftlock"), 1 },
    { CVAR_ENHANCEMENT("FixTexturesOOB"), 1 },
    { CVAR_ENHANCEMENT("FixVineFall"), 1 },
    { CVAR_ENHANCEMENT("FixZoraHintDialogue"), 1 },
    { CVAR_ENHANCEMENT("FrogsModifyFailTime"), 2 },
    { CVAR_ENHANCEMENT("GerudoWarriorClothingFix"), 1 },
    { CVAR_ENHANCEMENT("GravediggingTourFix"), 1 },
    { CVAR_ENHANCEMENT("InjectItemCounts.GoldSkulltula"), 1 },
    { CVAR_ENHANCEMENT("InjectItemCounts.HeartContainer"), 1 },
    { CVAR_ENHANCEMENT("InjectItemCounts.HeartPiece"), 1 },
    { CVAR_ENHANCEMENT("NaviTextFix"), 1 },
    { CVAR_ENHANCEMENT("PauseMenuAnimatedLink"), 1 },
    { CVAR_ENHANCEMENT("PulsateBossIcon"), 1 },
    { CVAR_ENHANCEMENT("RedGanonBlood"), 1 },
    { CVAR_ENHANCEMENT("RememberMapToggleState"), 1 },
    { CVAR_ENHANCEMENT("SceneSpecificDirtPathFix"), 1 },
    { CVAR_ENHANCEMENT("SilverRupeeJingleExtend"), 1 },
    { CVAR_ENHANCEMENT("SkipSaveConfirmation"), 1 },
    { CVAR_ENHANCEMENT("SkipText"), 1 },
    { CVAR_ENHANCEMENT("TextSpeed"), 5 },
    { CVAR_ENHANCEMENT("TimeFlowFileSelect"), 1 },
    { CVAR_ENHANCEMENT("TwoHandedIdle"), 1 },
    { CVAR_ENHANCEMENT("VisualAgony"), 1 },
    { CVAR_ENHANCEMENT("WidescreenActorCulling"), 1 },
};

static bool IsCrtEnhancedModeOn() {
    for (const auto& [name, value] : kCrtEnhancedModeCVars) {
        if (CVarGetInteger(name, 0) != value) {
            return false;
        }
    }
    return true;
}

// On: write pack values. Off: clear only pack keys (leave Mirror/Hyper/Damage etc alone).
static void SetCrtEnhancedMode(bool enable) {
    if (enable) {
        for (const auto& [name, value] : kCrtEnhancedModeCVars) {
            CVarSetInteger(name, value);
        }
    } else {
        for (const auto& [name, value] : kCrtEnhancedModeCVars) {
            CVarClear(name);
        }
    }
    CVarSave();
    ShipInit::InitAll();
}

static void CrtEnhCheckbox(const char* label, const char* cvar) {
    bool value = CVarGetInteger(cvar, 0) != 0;
    if (ImGui::Checkbox(label, &value)) {
        CVarSetInteger(cvar, value ? 1 : 0);
        CVarSave();
        ShipInit::Init(cvar);
    }
}

// Fixed-width label column so sliders/combos share one horizontal start edge.
static void CrtControlLabel(const char* label, const char* widest = "Menu Opacity") {
    const float colW = ImGui::CalcTextSize(widest).x + ImGui::GetStyle().ItemSpacing.x;
    ImGui::AlignTextToFramePadding();
    ImGui::TextUnformatted(label);
    ImGui::SameLine(0.0f, 0.0f);
    ImGui::SetCursorPosX(ImGui::GetWindowContentRegionMin().x + colW);
}

static void CrtDrawSettingsTab() {
    const float sliderW = 120.0f;

    ImGui::TextUnformatted("Graphics");
    ImGui::Separator();

    uint32_t refreshHz = Ship::Context::GetRawInstance()->GetWindow()->GetCurrentRefreshRate();
    int fpsMax = refreshHz > 20 ? static_cast<int>(refreshHz) : 20;
    bool matchRefresh = CVarGetInteger(CVAR_SETTING("MatchRefreshRate"), 0) != 0;
    int fps = CVarGetInteger(CVAR_SETTING("InterpolationFPS"), 20);
    if (fps < 20) {
        fps = 20;
    }
    if (fps > fpsMax) {
        fps = fpsMax;
    }
    ImGui::BeginDisabled(matchRefresh);
    CrtControlLabel("FPS");
    ImGui::SetNextItemWidth(sliderW);
    if (ImGui::SliderInt("##CrtFps", &fps, 20, fpsMax)) {
        CVarSetInteger(CVAR_SETTING("InterpolationFPS"), fps);
        CVarSave();
    }
    ImGui::EndDisabled();

    if (ImGui::Checkbox("Match Refresh Rate", &matchRefresh)) {
        CVarSetInteger(CVAR_SETTING("MatchRefreshRate"), matchRefresh ? 1 : 0);
        CVarSave();
    }

    ImGui::Spacing();
    ImGui::TextUnformatted("Audio");
    ImGui::Separator();

    int masterVol = CVarGetInteger(CVAR_SETTING("Volume.Master"), 40);
    CrtControlLabel("Master");
    ImGui::SetNextItemWidth(sliderW);
    if (ImGui::SliderInt("##CrtMasterVol", &masterVol, 0, 100)) {
        CVarSetInteger(CVAR_SETTING("Volume.Master"), masterVol);
        CVarSave();
    }

    int musicVol = CVarGetInteger(CVAR_SETTING("Volume.MainMusic"), 100);
    CrtControlLabel("Music");
    ImGui::SetNextItemWidth(sliderW);
    if (ImGui::SliderInt("##CrtMusicVol", &musicVol, 0, 100)) {
        CVarSetInteger(CVAR_SETTING("Volume.MainMusic"), musicVol);
        CVarSave();
        Audio_SetGameVolume(SEQ_PLAYER_BGM_MAIN, musicVol / 100.0f);
    }

    int sfxVol = CVarGetInteger(CVAR_SETTING("Volume.SFX"), 100);
    CrtControlLabel("SFX");
    ImGui::SetNextItemWidth(sliderW);
    if (ImGui::SliderInt("##CrtSfxVol", &sfxVol, 0, 100)) {
        CVarSetInteger(CVAR_SETTING("Volume.SFX"), sfxVol);
        CVarSave();
        Audio_SetGameVolume(SEQ_PLAYER_SFX, sfxVol / 100.0f);
    }

    ImGui::Spacing();
    ImGui::TextUnformatted("General");
    ImGui::Separator();

    static const int kBootValues[] = { BOOTSEQUENCE_DEFAULT, BOOTSEQUENCE_AUTHENTIC, BOOTSEQUENCE_FILESELECT,
                                       BOOTSEQUENCE_DEBUGWARPSCREEN, BOOTSEQUENCE_WARPPOINT };
    static const char* kBootLabels[] = { "Default", "Authentic", "File Select", "Debug Warp", "Warp Point" };
    int boot = CVarGetInteger(CVAR_SETTING("BootSequence"), BOOTSEQUENCE_DEFAULT);
    int bootIdx = 0;
    for (int i = 0; i < 5; i++) {
        if (kBootValues[i] == boot) {
            bootIdx = i;
            break;
        }
    }
    CrtControlLabel("Boot");
    ImGui::SetNextItemWidth(sliderW);
    if (ImGui::Combo("##CrtBoot", &bootIdx, kBootLabels, 5)) {
        CVarSetInteger(CVAR_SETTING("BootSequence"), kBootValues[bootIdx]);
        CVarSave();
        ShipInit::Init(CVAR_SETTING("BootSequence"));
    }

    bool disableIdleCam = CVarGetInteger(CVAR_SETTING("A11yDisableIdleCam"), 0) != 0;
    if (ImGui::Checkbox("Disable Idle Camera", &disableIdleCam)) {
        CVarSetInteger(CVAR_SETTING("A11yDisableIdleCam"), disableIdleCam ? 1 : 0);
        CVarSave();
    }

    float opacity = CVarGetFloat(CVAR_SETTING("Menu.BackgroundOpacity"), 0.85f);
    CrtControlLabel("Menu Opacity");
    ImGui::SetNextItemWidth(sliderW);
    if (ImGui::SliderFloat("##CrtMenuOpacity", &opacity, 0.0f, 1.0f, "%.2f")) {
        CVarSetFloat(CVAR_SETTING("Menu.BackgroundOpacity"), opacity);
        CVarSave();
    }
}

static void CrtDrawEnhancementsTab() {
    const float sliderW = 120.0f;

    // Pack master toggle, then the individual CVars it also sets (its "children").
    bool qolPack = IsCrtEnhancedModeOn();
    if (ImGui::Checkbox("QoL Enhancements Pack", &qolPack)) {
        SetCrtEnhancedMode(qolPack);
    }
    ImGui::Separator();

    int textSpeed = CVarGetInteger(CVAR_ENHANCEMENT("TextSpeed"), 1);
    if (textSpeed < 1) {
        textSpeed = 1;
    }
    if (textSpeed > 6) {
        textSpeed = 6;
    }
    CrtControlLabel("Text Speed");
    ImGui::SetNextItemWidth(sliderW);
    const char* textSpeedFmt = textSpeed >= 6 ? "Instant" : "%dx";
    if (ImGui::SliderInt("##CrtTextSpeed", &textSpeed, 1, 6, textSpeedFmt)) {
        CVarSetInteger(CVAR_ENHANCEMENT("TextSpeed"), textSpeed);
        CVarSave();
        ShipInit::Init(CVAR_ENHANCEMENT("TextSpeed"));
    }

    CrtEnhCheckbox("Skip Text", CVAR_ENHANCEMENT("SkipText"));
    CrtEnhCheckbox("D-Pad Equips", CVAR_ENHANCEMENT("DpadEquips"));
    CrtEnhCheckbox("Autosave", CVAR_ENHANCEMENT("Autosave"));
    CrtEnhCheckbox("Disable LOD", CVAR_ENHANCEMENT("DisableLOD"));
    CrtEnhCheckbox("Visual Stone of Agony", CVAR_ENHANCEMENT("VisualAgony"));

    // Independent extras (not driven by the QoL pack).
    ImGui::Separator();

    bool mirroredWorld =
        CVarGetInteger(CVAR_ENHANCEMENT("MirroredWorldMode"), MIRRORED_WORLD_OFF) == MIRRORED_WORLD_ALWAYS;
    if (ImGui::Checkbox("Mirrored World", &mirroredWorld)) {
        CVarSetInteger(CVAR_ENHANCEMENT("MirroredWorldMode"),
                       mirroredWorld ? MIRRORED_WORLD_ALWAYS : MIRRORED_WORLD_OFF);
        CVarSave();
        ShipInit::Init(CVAR_ENHANCEMENT("MirroredWorldMode"));
    }

    ImGui::TextUnformatted("Damage Multiplier");
    int damageMult = CVarGetInteger(CVAR_ENHANCEMENT("DamageMult"), DAMAGE_VANILLA);
    bool damageChanged = false;
    damageChanged |= ImGui::RadioButton("1x", &damageMult, DAMAGE_VANILLA);
    ImGui::SameLine();
    damageChanged |= ImGui::RadioButton("2x", &damageMult, DAMAGE_DOUBLE);
    ImGui::SameLine();
    damageChanged |= ImGui::RadioButton("4x", &damageMult, DAMAGE_QUADRUPLE);
    ImGui::SameLine();
    damageChanged |= ImGui::RadioButton("8x", &damageMult, DAMAGE_OCTUPLE);
    if (damageChanged) {
        CVarSetInteger(CVAR_ENHANCEMENT("DamageMult"), damageMult);
        CVarSetInteger(CVAR_ENHANCEMENT("FallDamageMult"), damageMult);
        CVarSetInteger(CVAR_ENHANCEMENT("VoidDamageMult"), damageMult);
        CVarSave();
        ShipInit::Init(CVAR_ENHANCEMENT("DamageMult"));
        ShipInit::Init(CVAR_ENHANCEMENT("FallDamageMult"));
        ShipInit::Init(CVAR_ENHANCEMENT("VoidDamageMult"));
    }

    CrtEnhCheckbox("Hyper Bosses", CVAR_ENHANCEMENT("HyperBosses"));
    CrtEnhCheckbox("Hyper Enemies", CVAR_ENHANCEMENT("HyperEnemies"));
    CrtEnhCheckbox("Instant Putaway", CVAR_ENHANCEMENT("InstantPutaway"));

    int climbSpeed = CVarGetInteger(CVAR_ENHANCEMENT("ClimbSpeed"), 0);
    if (climbSpeed < 0) {
        climbSpeed = 0;
    }
    if (climbSpeed > 12) {
        climbSpeed = 12;
    }
    CrtControlLabel("Climb Speed");
    ImGui::SetNextItemWidth(sliderW);
    if (ImGui::SliderInt("##CrtClimbSpeed", &climbSpeed, 0, 12, "+%d")) {
        CVarSetInteger(CVAR_ENHANCEMENT("ClimbSpeed"), climbSpeed);
        CVarSave();
        ShipInit::Init(CVAR_ENHANCEMENT("ClimbSpeed"));
    }

    CrtEnhCheckbox("Instant Scarecrow", CVAR_ENHANCEMENT("InstantScarecrow"));
}

#define CRT_CONTROLLER_INPUT_BLOCK_ID 95237930

static int32_t sCrtMappingInputBlockTimer = INT32_MAX;
static bool sCrtMappingPopupOpen = false;

static std::string CrtFirstConnectedGamepadName() {
    auto names = Ship::Context::GetRawInstance()
                     ->GetControlDeck()
                     ->GetConnectedPhysicalDeviceManager()
                     ->GetConnectedSDLGamepadNames();
    if (names.empty()) {
        return {};
    }
    return names.begin()->second;
}

static std::string CrtGamepadBindingLabel(CONTROLLERBUTTONS_T bitmask) {
    auto button = Ship::Context::GetRawInstance()->GetControlDeck()->GetControllerByPort(0)->GetButton(bitmask);
    for (const auto& [id, mapping] : button->GetAllButtonMappings()) {
        if (mapping != nullptr && mapping->GetPhysicalDeviceType() == Ship::PhysicalDeviceType::SDLGamepad) {
            return mapping->GetPhysicalInputName();
        }
    }
    return "-";
}

static void CrtDrawControllerButtonRow(const char* label, CONTROLLERBUTTONS_T bitmask) {
    ImGui::PushID(static_cast<int>(bitmask));
    ImGui::TextUnformatted(label);
    ImGui::SameLine(52.0f);
    ImGui::TextUnformatted(CrtGamepadBindingLabel(bitmask).c_str());
    ImGui::SameLine(120.0f);
    if (ImGui::SmallButton("Set")) {
        ImGui::OpenPopup("CrtBindPopup");
        sCrtMappingInputBlockTimer = static_cast<int32_t>(ImGui::GetIO().Framerate / 3.0f);
        if (sCrtMappingInputBlockTimer < 1) {
            sCrtMappingInputBlockTimer = 1;
        }
    }
    ImGui::SameLine();
    if (ImGui::SmallButton("Clear")) {
        Ship::Context::GetRawInstance()
            ->GetControlDeck()
            ->GetControllerByPort(0)
            ->GetButton(bitmask)
            ->ClearAllButtonMappingsForDeviceType(Ship::PhysicalDeviceType::SDLGamepad);
    }

    if (ImGui::BeginPopup("CrtBindPopup")) {
        sCrtMappingPopupOpen = true;
        ImGui::TextUnformatted("Press a button...");
        if (ImGui::Button("Cancel")) {
            sCrtMappingPopupOpen = false;
            ImGui::CloseCurrentPopup();
        }
        if (sCrtMappingInputBlockTimer == INT32_MAX && Ship::Context::GetRawInstance()
                                                           ->GetControlDeck()
                                                           ->GetControllerByPort(0)
                                                           ->GetButton(bitmask)
                                                           ->AddOrEditButtonMappingFromRawPress(bitmask, "")) {
            sCrtMappingPopupOpen = false;
            ImGui::CloseCurrentPopup();
        }
        ImGui::EndPopup();
    }
    ImGui::PopID();
}

static void CrtUpdateControllerMappingGuards() {
    auto* ctx = Ship::Context::GetRawInstance();
    auto deck = ctx->GetControlDeck();
    auto gui = ctx->GetWindow()->GetGui();

    if (sCrtMappingPopupOpen && ImGui::IsPopupOpen("", ImGuiPopupFlags_AnyPopupId)) {
        deck->BlockGameInput(CRT_CONTROLLER_INPUT_BLOCK_ID);
        gui->BlockGamepadNavigation();
        if (sCrtMappingInputBlockTimer != INT32_MAX) {
            sCrtMappingInputBlockTimer--;
            if (sCrtMappingInputBlockTimer <= 0) {
                sCrtMappingInputBlockTimer = INT32_MAX;
            }
        }
    } else {
        sCrtMappingPopupOpen = false;
        deck->UnblockGameInput(CRT_CONTROLLER_INPUT_BLOCK_ID);
        gui->UnblockGamepadNavigation();
    }
}

static void CrtDrawControllerTab() {
    const std::string padName = CrtFirstConnectedGamepadName();
    if (padName.empty()) {
        ImGui::TextUnformatted("No controller");
        ImGui::Separator();
        ImGui::TextWrapped("Connect a gamepad to map buttons.");
        return;
    }

    ImGui::TextWrapped("%s", padName.c_str());
    ImGui::Separator();

    static const std::pair<const char*, CONTROLLERBUTTONS_T> kCrtButtons[] = {
        { "A", BTN_A },         { "B", BTN_B },         { "Start", BTN_START }, { "Z", BTN_Z },
        { "L", BTN_L },         { "R", BTN_R },         { "C-Up", BTN_CUP },    { "C-Dn", BTN_CDOWN },
        { "C-Lt", BTN_CLEFT },  { "C-Rt", BTN_CRIGHT }, { "D-Up", BTN_DUP },    { "D-Dn", BTN_DDOWN },
        { "D-Lt", BTN_DLEFT },  { "D-Rt", BTN_DRIGHT },
    };
    for (const auto& [label, mask] : kCrtButtons) {
        CrtDrawControllerButtonRow(label, mask);
    }

    ImGui::Separator();
    ImGui::TextUnformatted("Speed Modifier");
    CrtDrawControllerButtonRow("Spd", BTN_CUSTOM_MODIFIER1);

    const bool speedMapped = CrtGamepadBindingLabel(BTN_CUSTOM_MODIFIER1) != "-";
    if (speedMapped &&
        CVarGetInteger(CVAR_CHEAT("SpeedModifier.Btn"), BTN_CUSTOM_MODIFIER1) !=
            static_cast<int>(BTN_CUSTOM_MODIFIER1)) {
        CVarSetInteger(CVAR_CHEAT("SpeedModifier.Btn"), BTN_CUSTOM_MODIFIER1);
        CVarSave();
    }

    ImGui::BeginDisabled(!speedMapped);
    float speedPct = CVarGetFloat(CVAR_CHEAT("SpeedModifier.Value"), 1.0f) * 100.0f;
    CrtControlLabel("Multiplier");
    ImGui::SetNextItemWidth(120.0f);
    if (ImGui::SliderFloat("##CrtSpeedMult", &speedPct, 1.0f, 500.0f, "%.0f%%")) {
        CVarSetFloat(CVAR_CHEAT("SpeedModifier.Value"), speedPct / 100.0f);
        CVarSave();
        ShipInit::Init(CVAR_CHEAT("SpeedModifier.Value"));
    }

    bool speedToggle = CVarGetInteger(CVAR_CHEAT("SpeedModifier.SpeedToggle"), 0) != 0;
    if (ImGui::Checkbox("Toggle instead of hold", &speedToggle)) {
        CVarSetInteger(CVAR_CHEAT("SpeedModifier.SpeedToggle"), speedToggle ? 1 : 0);
        CVarSave();
    }
    ImGui::EndDisabled();

    ImGui::Separator();
    if (ImGui::Button("Reset Defaults")) {
        auto controller = Ship::Context::GetRawInstance()->GetControlDeck()->GetControllerByPort(0);
        controller->ClearAllMappingsForDeviceType(Ship::PhysicalDeviceType::SDLGamepad);
        controller->AddDefaultMappings(Ship::PhysicalDeviceType::SDLGamepad);
    }
}

static int CrtBridgeEnumToIndex(int bridge) {
    switch (bridge) {
        case RO_BRIDGE_VANILLA:
            return 0;
        case RO_BRIDGE_ALWAYS_OPEN:
            return 1;
        case RO_BRIDGE_MEDALLIONS:
            return 2;
        case RO_BRIDGE_GREG:
            return 3;
        default:
            return 3;
    }
}

static int CrtBridgeIndexToEnum(int index) {
    switch (index) {
        case 0:
            return RO_BRIDGE_VANILLA;
        case 1:
            return RO_BRIDGE_ALWAYS_OPEN;
        case 2:
            return RO_BRIDGE_MEDALLIONS;
        default:
            return RO_BRIDGE_GREG;
    }
}

static void CrtSaveRandoSetting() {
    CVarSave();
    Rando::Settings::GetInstance()->UpdateAllOptions();
}

static void CrtDrawRandomizerTab() {
    // Seed generation stays in-game (File Select). These CVars feed that Generate flow.
    constexpr const char* kRandoLabelCol = "Ganon's Trials";
    const float comboW = ImMin(95.0f, ImGui::GetContentRegionAvail().x);

    int forest = CVarGetInteger(CVAR_RANDOMIZER_SETTING("ClosedForest"), RO_CLOSED_FOREST_OFF);
    if (forest < RO_CLOSED_FOREST_ON || forest > RO_CLOSED_FOREST_OFF) {
        forest = RO_CLOSED_FOREST_OFF;
    }
    CrtControlLabel("Forest", kRandoLabelCol);
    ImGui::SetNextItemWidth(comboW);
    if (ImGui::Combo("##CrtForest", &forest, "On\0Deku Only\0Off\0")) {
        CVarSetInteger(CVAR_RANDOMIZER_SETTING("ClosedForest"), forest);
        CrtSaveRandoSetting();
    }

    int doorOfTime = CVarGetInteger(CVAR_RANDOMIZER_SETTING("DoorOfTime"), RO_DOOROFTIME_OPEN);
    if (doorOfTime < RO_DOOROFTIME_CLOSED || doorOfTime > RO_DOOROFTIME_OPEN) {
        doorOfTime = RO_DOOROFTIME_OPEN;
    }
    CrtControlLabel("Door of Time", kRandoLabelCol);
    ImGui::SetNextItemWidth(comboW);
    if (ImGui::Combo("##CrtDoorOfTime", &doorOfTime, "Closed\0Song only\0Open\0")) {
        CVarSetInteger(CVAR_RANDOMIZER_SETTING("DoorOfTime"), doorOfTime);
        CrtSaveRandoSetting();
    }

    bool skipChildZelda =
        CVarGetInteger(CVAR_RANDOMIZER_SETTING("ShuffleWeirdEgg"), RO_WEIRD_EGG_SKIP_TALON) == RO_WEIRD_EGG_SKIP_TALON;
    if (ImGui::Checkbox("Skip Child Zelda", &skipChildZelda)) {
        CVarSetInteger(CVAR_RANDOMIZER_SETTING("ShuffleWeirdEgg"),
                       skipChildZelda ? RO_WEIRD_EGG_SKIP_TALON : RO_WEIRD_EGG_VANILLA);
        CrtSaveRandoSetting();
    }

    int bridgeIdx = CrtBridgeEnumToIndex(CVarGetInteger(CVAR_RANDOMIZER_SETTING("RainbowBridge"), RO_BRIDGE_GREG));
    CrtControlLabel("Rainbow Bridge", kRandoLabelCol);
    ImGui::SetNextItemWidth(comboW);
    if (ImGui::Combo("##CrtBridge", &bridgeIdx, "Vanilla\0Always open\0Medallions\0Greg\0")) {
        CVarSetInteger(CVAR_RANDOMIZER_SETTING("RainbowBridge"), CrtBridgeIndexToEnum(bridgeIdx));
        CrtSaveRandoSetting();
    }

    int ganonTrial = CVarGetInteger(CVAR_RANDOMIZER_SETTING("GanonTrial"), RO_GANONS_TRIALS_SKIP);
    int trialsIdx = (ganonTrial == RO_GANONS_TRIALS_SKIP) ? 0 : 1;
    CrtControlLabel("Ganon's Trials", kRandoLabelCol);
    ImGui::SetNextItemWidth(comboW);
    if (ImGui::Combo("##CrtTrials", &trialsIdx, "Skip\0"
                                                "6 trials\0")) {
        if (trialsIdx == 0) {
            CVarSetInteger(CVAR_RANDOMIZER_SETTING("GanonTrial"), RO_GANONS_TRIALS_SKIP);
            CVarSetInteger(CVAR_RANDOMIZER_SETTING("GanonTrialCount"), 0);
        } else {
            CVarSetInteger(CVAR_RANDOMIZER_SETTING("GanonTrial"), RO_GANONS_TRIALS_SET_NUMBER);
            CVarSetInteger(CVAR_RANDOMIZER_SETTING("GanonTrialCount"), 6);
        }
        CrtSaveRandoSetting();
    }
}

static std::shared_ptr<Fast::Fast3dGui> CrtGetFast3dGui() {
    return std::dynamic_pointer_cast<Fast::Fast3dGui>(Ship::Context::GetRawInstance()->GetWindow()->GetGui());
}

static void CrtEnsureTabIconsLoaded() {
    auto gui = CrtGetFast3dGui();
    if (gui == nullptr) {
        return;
    }
    static const struct {
        const char* name;
        const char* path;
    } icons[] = {
        { "CrtTab-Settings", "textures/crt/settings_icon.png" },
        { "CrtTab-Enhancements", "textures/crt/enhancements_icon.png" },
        { "CrtTab-Controller", "textures/crt/controller_icon.png" },
        { "CrtTab-Randomizer", "textures/crt/randomizer_icon.png" },
    };
    for (const auto& icon : icons) {
        if (!gui->HasTextureByName(icon.name)) {
            gui->LoadTextureFromRawImage(icon.name, icon.path);
        }
    }
}

// Icon tabs; SetNextItemWidth + FramePadding size the hit target, icon stays centered.
static constexpr float kCrtTabHeight = 22.0f;
static constexpr float kCrtTabWidth = 34.0f; // 8px wider than tall
static constexpr float kCrtTabIcon = 16.0f;

static bool CrtBeginIconTabItem(const char* id, const char* tooltip, const char* textureName) {
    char label[64];
    std::snprintf(label, sizeof(label), "###%s", id);
    ImGui::SetNextItemWidth(kCrtTabWidth);
    const bool open = ImGui::BeginTabItem(label);
    auto gui = CrtGetFast3dGui();
    if (gui != nullptr && gui->HasTextureByName(textureName)) {
        const ImVec2 rmin = ImGui::GetItemRectMin();
        const ImVec2 rmax = ImGui::GetItemRectMax();
        const ImVec2 p0((rmin.x + rmax.x - kCrtTabIcon) * 0.5f, (rmin.y + rmax.y - kCrtTabIcon) * 0.5f);
        ImGui::GetWindowDrawList()->AddImage(gui->GetTextureByName(textureName), p0,
                                             ImVec2(p0.x + kCrtTabIcon, p0.y + kCrtTabIcon));
    }
    if (ImGui::IsItemHovered(ImGuiHoveredFlags_ForTooltip)) {
        ImGui::SetTooltip("%s", tooltip);
    }
    return open;
}

// CRT: icon-tab modal sized for small CRT displays. Quit/Reset stay pinned under a scrollable body.
void DrawCrtSimpleMenu() {
    ImGuiViewport* vp = ImGui::GetMainViewport();
    ImGui::SetNextWindowPos(vp->GetCenter(), ImGuiCond_Always, ImVec2(0.5f, 0.5f));
    ImGui::SetNextWindowSize(ImVec2(250.0f, 180.0f), ImGuiCond_Always);
    ImGuiWindowFlags flags = ImGuiWindowFlags_NoTitleBar | ImGuiWindowFlags_NoResize | ImGuiWindowFlags_NoCollapse |
                             ImGuiWindowFlags_NoMove | ImGuiWindowFlags_NoSavedSettings;
    const float opacity = CVarGetFloat(CVAR_SETTING("Menu.BackgroundOpacity"), 0.85f);
    ImGui::PushStyleColor(ImGuiCol_WindowBg, ImVec4(0.0f, 0.0f, 0.0f, opacity));
    ImGui::PushStyleColor(ImGuiCol_ChildBg, ImVec4(0.0f, 0.0f, 0.0f, 0.0f));
    if (ImGui::Begin("CRT Menu", nullptr, flags)) {
        const float footerH = ImGui::GetFrameHeightWithSpacing() + ImGui::GetStyle().ItemSpacing.y;
        CrtEnsureTabIconsLoaded();

        // BeginTabBar locks BarRect height from FramePadding — keep tab padding for the bar/headers,
        // and only switch to compact padding inside selected tab content.
        constexpr ImVec2 kCrtWidgetPad(4.0f, 2.0f);
        const float tabPadY = ImMax(0.0f, (kCrtTabHeight - ImGui::GetFontSize()) * 0.5f);
        ImGui::PushStyleVar(ImGuiStyleVar_FramePadding, ImVec2(4.0f, tabPadY));
        if (ImGui::BeginTabBar("CrtTabs", ImGuiTabBarFlags_NoTooltip)) {
            if (CrtBeginIconTabItem("Settings", "Settings", "CrtTab-Settings")) {
                ImGui::PushStyleVar(ImGuiStyleVar_FramePadding, kCrtWidgetPad);
                ImGui::BeginChild("CrtSettingsBody", ImVec2(0.0f, -footerH), false);
                CrtDrawSettingsTab();
                ImGui::EndChild();
                ImGui::PopStyleVar();
                ImGui::EndTabItem();
            }
            if (CrtBeginIconTabItem("Enhancements", "Enhancements", "CrtTab-Enhancements")) {
                ImGui::PushStyleVar(ImGuiStyleVar_FramePadding, kCrtWidgetPad);
                ImGui::BeginChild("CrtEnhancementsBody", ImVec2(0.0f, -footerH), false);
                CrtDrawEnhancementsTab();
                ImGui::EndChild();
                ImGui::PopStyleVar();
                ImGui::EndTabItem();
            }
            if (CrtBeginIconTabItem("Controller", "Controller", "CrtTab-Controller")) {
                ImGui::PushStyleVar(ImGuiStyleVar_FramePadding, kCrtWidgetPad);
                ImGui::BeginChild("CrtControllerBody", ImVec2(0.0f, -footerH), false);
                CrtDrawControllerTab();
                ImGui::EndChild();
                ImGui::PopStyleVar();
                ImGui::EndTabItem();
            }
            if (CrtBeginIconTabItem("Randomizer", "Randomizer", "CrtTab-Randomizer")) {
                ImGui::PushStyleVar(ImGuiStyleVar_FramePadding, kCrtWidgetPad);
                ImGui::BeginChild("CrtRandomizerBody", ImVec2(0.0f, -footerH), false);
                CrtDrawRandomizerTab();
                ImGui::EndChild();
                ImGui::PopStyleVar();
                ImGui::EndTabItem();
            }
            ImGui::EndTabBar();
        }
        ImGui::PopStyleVar();

        CrtUpdateControllerMappingGuards();

        if (ImGui::Button("Quit")) {
            Ship::Context::GetRawInstance()->GetWindow()->Close();
        }
        ImGui::SameLine();
        if (ImGui::Button("Reset")) {
            auto consoleWindow = std::reinterpret_pointer_cast<Ship::ConsoleWindow>(
                Ship::Context::GetRawInstance()->GetWindow()->GetGui()->GetGuiWindow("Console"));
            if (consoleWindow) {
                consoleWindow->Dispatch("reset");
            }
        }
    }
    ImGui::End();
    ImGui::PopStyleColor(2);
}

} // namespace Ship
