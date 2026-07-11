import 'package:flutter/material.dart';
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
}
