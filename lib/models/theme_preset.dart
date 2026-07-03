import 'package:flutter/material.dart';

class ThemePreset {
  final String name;
  final String subtitle;
  final Color background;  // Scaffold 배경 (가장 어두움)
  final Color surface;     // 카드/패널 배경 (background보다 밝음)
  final Color accent;      // 포인트 컬러 (버튼, 아이콘, 하이라이트)
  final Color grey;        // 보조 텍스트/아이콘
  final List<Color> runGradient; // 주행 화면 3단계 그라디언트

  const ThemePreset({
    required this.name,
    required this.subtitle,
    required this.background,
    required this.surface,
    required this.accent,
    required this.grey,
    required this.runGradient,
  });

  // 바텀시트 배경 (background와 surface의 중간)
  Color get sheetBg => Color.fromRGBO(
        ((background.r * 0.5 + surface.r * 0.5) * 255).round(),
        ((background.g * 0.5 + surface.g * 0.5) * 255).round(),
        ((background.b * 0.5 + surface.b * 0.5) * 255).round(),
        1.0,
      );

  // 주행/메트릭 구분선
  Color get divider => accent.withValues(alpha: 0.2);

  // 배경 밝기에 따른 텍스트 색 (밝은 배경 → 어두운 글자, 어두운 배경 → 흰 글자)
  Color get onBackground =>
      background.computeLuminance() > 0.3 ? const Color(0xFF1A1A1A) : Colors.white;

  Color get onRun =>
      runGradient[1].computeLuminance() > 0.3
          ? const Color(0xFF1A1A1A)
          : Colors.white;
}

const kThemePresets = <ThemePreset>[
  // ── 1. 코랄 선샤인 ──────────────────────────────────────────────────────
  // 흰 배경 + 발랄한 코랄 포인트.
  ThemePreset(
    name: '코랄 선샤인',
    subtitle: 'Bright Coral · Sunny',
    background: Color(0xFFAB6A63),   // luminance ~20%
    surface:    Color(0xFFFFF1EE),
    accent:     Color(0xFFFF5A5F),
    grey:       Color(0xFFA69691),
    runGradient: [
      Color(0xFFFFDAD1),
      Color(0xFFFF7A59),
      Color(0xFFFFB199),
    ],
  ),

  // ── 2. 스카이 민트 ──────────────────────────────────────────────────────
  // 흰 배경 + 상쾌한 민트/시안 포인트.
  ThemePreset(
    name: '스카이 민트',
    subtitle: 'Fresh Mint · Cyan',
    background: Color(0xFF3D8878),   // luminance ~20%
    surface:    Color(0xFFE8FBF7),
    accent:     Color(0xFF00BFA6),
    grey:       Color(0xFF8FADAA),
    runGradient: [
      Color(0xFFCFF7EE),
      Color(0xFF00BFA6),
      Color(0xFF7FE0CF),
    ],
  ),

  // ── 3. 레몬 스퀴즈 ──────────────────────────────────────────────────────
  // 흰 배경 + 상큼한 레몬/라임 포인트.
  ThemePreset(
    name: '레몬 스퀴즈',
    subtitle: 'Zesty Lemon · Lime',
    background: Color(0xFF877C44),   // luminance ~20%
    surface:    Color(0xFFFFFBEA),
    accent:     Color(0xFFFFC933),
    grey:       Color(0xFFABA383),
    runGradient: [
      Color(0xFFFFF3C4),
      Color(0xFFFFC933),
      Color(0xFFFFE28A),
    ],
  ),

  // ── 4. 퍼플 팝 ──────────────────────────────────────────────────────────
  // 흰 배경 + 발랄한 바이올렛 포인트.
  ThemePreset(
    name: '퍼플 팝',
    subtitle: 'Playful Grape · Violet',
    background: Color(0xFF8869D1),   // luminance ~20%
    surface:    Color(0xFFF3EEFF),
    accent:     Color(0xFF8B5CF6),
    grey:       Color(0xFFA297B3),
    runGradient: [
      Color(0xFFE9DCFF),
      Color(0xFF8B5CF6),
      Color(0xFFC4A8FF),
    ],
  ),

  // ── 5. 핫핑크 버스트 ────────────────────────────────────────────────────
  // 흰 배경 + 에너지 넘치는 핫핑크 포인트.
  ThemePreset(
    name: '핫핑크 버스트',
    subtitle: 'Vivid Pink · Energy',
    background: Color(0xFFC25784),   // luminance ~20%
    surface:    Color(0xFFFFEFF5),
    accent:     Color(0xFFFF3D81),
    grey:       Color(0xFFB090A0),
    runGradient: [
      Color(0xFFFFDCEA),
      Color(0xFFFF3D81),
      Color(0xFFFF8FBB),
    ],
  ),
];
