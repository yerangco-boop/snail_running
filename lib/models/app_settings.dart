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
  String ttsVoiceGender;
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
    this.ttsVoiceGender = 'female',
    this.mixWithOtherAudio = true,
    this.weightKg = 60.0,
    ThemePreset? preset,
  }) : preset = preset ?? kThemePresets.first;

  Color get accent => preset.accent;
}
