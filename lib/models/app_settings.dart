import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'theme_preset.dart';

export 'theme_preset.dart';

enum GoalType { distance, time }

// 메트로놈 음량 하한. 슬라이더를 스크롤하다 실수로 왼쪽 끝을 건드리면 값이 0이 되어
// "메트로놈은 켜져 있는데 아무 소리도 안 나고, BPM을 바꾸든 껐다 켜든 반응이 없는"
// 상태가 됨(2026-09-05 실측 로그의 vol=0.0). 무음이 필요하면 메트로놈 스위치를 끄면
// 되므로, 음량 자체는 0까지 내려가지 않게 막는다.
const double kMinMetronomeVolume = 0.15;

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
  // 메트로놈 재생 여부 — 러닝 화면에서 즉시 껐다 켤 수 있고 그 값이 그대로 유지됨
  bool metronomeEnabled;
  // 메트로놈 음량 0.0~1.0 (설정 화면 슬라이더는 0~100%로 표시)
  double metronomeVolume;
  double weightKg;
  // 러닝 중 화면이 꺼지면 OS가 위치/센서 콜백을 억제해 거리가 유실되므로 기본 ON
  bool keepScreenOn;
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
    this.metronomeEnabled = true,
    this.metronomeVolume = 1.0,
    this.weightKg = 70.0,
    this.keepScreenOn = true,
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
  static const _kMetronomeEnabled = 'metronomeEnabled';
  static const _kMetronomeVolume = 'metronomeVolume';
  static const _kWeightKg = 'weightKg';
  static const _kPresetName = 'presetName';
  static const _kKeepScreenOn = 'keepScreenOn';

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
    metronomeEnabled = prefs.getBool(_kMetronomeEnabled) ?? metronomeEnabled;
    // 예전 버전에서 0으로 저장된 값이 남아 있어도 하한으로 끌어올림
    metronomeVolume =
        (prefs.getDouble(_kMetronomeVolume) ?? metronomeVolume).clamp(kMinMetronomeVolume, 1.0);
    weightKg = prefs.getDouble(_kWeightKg) ?? weightKg;
    keepScreenOn = prefs.getBool(_kKeepScreenOn) ?? keepScreenOn;
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
    await prefs.setBool(_kMetronomeEnabled, metronomeEnabled);
    await prefs.setDouble(_kMetronomeVolume, metronomeVolume);
    await prefs.setDouble(_kWeightKg, weightKg);
    await prefs.setBool(_kKeepScreenOn, keepScreenOn);
    await prefs.setString(_kPresetName, preset.name);
  }
}
