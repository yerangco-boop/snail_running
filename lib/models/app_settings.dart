import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'theme_preset.dart';

export 'theme_preset.dart';

enum GoalType { distance, time }

class AppSettings {
  int bpm;
  double targetDistanceKm;
  int targetTimeMinutes;
  int paceMinutes;
  int paceSeconds;
  GoalType goalType;
  // getVoices에서 반환되는 음성 이름 그대로 저장 (null이면 자동 선택 — Google 계열 우선,
  // 없으면 첫 한국어 음성). 예전 male/female 이름 매칭 방식은 안드로이드에서 이름에
  // 성별이 표기되지 않아 작동하지 않아 폐기하고, 사용자가 직접 듣고 고르는 방식으로 대체
  String? ttsVoiceName;
  bool mixWithOtherAudio;
  double weightKg;
  ThemePreset preset;

  AppSettings({
    this.bpm = 150,
    this.targetDistanceKm = 5.0,
    this.targetTimeMinutes = 30,
    this.paceMinutes = 8,
    this.paceSeconds = 0,
    this.goalType = GoalType.distance,
    this.ttsVoiceName,
    this.mixWithOtherAudio = true,
    this.weightKg = 60.0,
    ThemePreset? preset,
  }) : preset = preset ?? kThemePresets.first;

  Color get accent => preset.accent;

  // ── 영속 저장 (shared_preferences) ─────────────────────────────────────────
  static const _kBpm = 'bpm';
  static const _kTargetDistanceKm = 'targetDistanceKm';
  static const _kTargetTimeMinutes = 'targetTimeMinutes';
  static const _kPaceMinutes = 'paceMinutes';
  static const _kPaceSeconds = 'paceSeconds';
  static const _kGoalType = 'goalType';
  static const _kTtsVoiceName = 'ttsVoiceName';
  static const _kMixWithOtherAudio = 'mixWithOtherAudio';
  static const _kWeightKg = 'weightKg';
  static const _kPresetName = 'presetName';

  // 저장된 값이 있으면 그 값으로 필드를 덮어씀 (없으면 생성자 기본값 그대로 유지)
  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    bpm = prefs.getInt(_kBpm) ?? bpm;
    targetDistanceKm = prefs.getDouble(_kTargetDistanceKm) ?? targetDistanceKm;
    targetTimeMinutes = prefs.getInt(_kTargetTimeMinutes) ?? targetTimeMinutes;
    paceMinutes = prefs.getInt(_kPaceMinutes) ?? paceMinutes;
    paceSeconds = prefs.getInt(_kPaceSeconds) ?? paceSeconds;
    final goalTypeIndex = prefs.getInt(_kGoalType);
    if (goalTypeIndex != null && goalTypeIndex >= 0 && goalTypeIndex < GoalType.values.length) {
      goalType = GoalType.values[goalTypeIndex];
    }
    ttsVoiceName = prefs.getString(_kTtsVoiceName) ?? ttsVoiceName;
    mixWithOtherAudio = prefs.getBool(_kMixWithOtherAudio) ?? mixWithOtherAudio;
    weightKg = prefs.getDouble(_kWeightKg) ?? weightKg;
    final presetName = prefs.getString(_kPresetName);
    if (presetName != null) {
      preset = kThemePresets.firstWhere(
        (p) => p.name == presetName,
        orElse: () => preset,
      );
    }
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kBpm, bpm);
    await prefs.setDouble(_kTargetDistanceKm, targetDistanceKm);
    await prefs.setInt(_kTargetTimeMinutes, targetTimeMinutes);
    await prefs.setInt(_kPaceMinutes, paceMinutes);
    await prefs.setInt(_kPaceSeconds, paceSeconds);
    await prefs.setInt(_kGoalType, goalType.index);
    if (ttsVoiceName != null) {
      await prefs.setString(_kTtsVoiceName, ttsVoiceName!);
    } else {
      await prefs.remove(_kTtsVoiceName);
    }
    await prefs.setBool(_kMixWithOtherAudio, mixWithOtherAudio);
    await prefs.setDouble(_kWeightKg, weightKg);
    await prefs.setString(_kPresetName, preset.name);
  }
}
