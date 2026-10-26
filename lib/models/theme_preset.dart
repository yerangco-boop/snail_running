import 'package:flutter/material.dart';
import '../theme/tokens.dart';

class ThemePreset {
  final String name;
  final String subtitle;
  final Color background;          // 어두운 무채색에 가까운 배경 (--bg)
  final Color surface;             // 채도 높은 보석톤 카드 배경 (--surface)
  final Color accent;              // 단색 포인트 (아이콘, 작은 텍스트 — --accent-solid)
  final Color accentGradientStart; // 그라디언트 포인트 시작색 (--accent-1)
  final Color accentGradientEnd;   // 그라디언트 포인트 끝색 (--accent-2)
  final Color grey;                // 보조 텍스트/아이콘
  final List<Color> runGradient;   // 주행 화면 3단계 그라디언트 (--run-1/2/3)

  const ThemePreset({
    required this.name,
    required this.subtitle,
    required this.background,
    required this.surface,
    required this.accent,
    required this.accentGradientStart,
    required this.accentGradientEnd,
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

  // surface 배경 위에 올라가는 텍스트/아이콘 색 (surface와 background의 밝기가 다를 수 있으므로 별도 계산)
  Color get onSurface =>
      surface.computeLuminance() > 0.3 ? const Color(0xFF1A1A1A) : Colors.white;

  // background 위에서 보조 텍스트로 쓰는 흐린 색 (고정된 grey 대신 배경 밝기에 맞춰 자동 대비)
  Color get onBackgroundMuted => Tokens.inkMuted;

  Color get onRun =>
      runGradient[1].computeLuminance() > 0.3
          ? const Color(0xFF1A1A1A)
          : Colors.white;

  // 밝은 단일 룩: 흰 카드 + 은은한 그림자 (1번 시안)
  List<Color> get cardGradient => const [Tokens.card, Tokens.card, Color(0xFFFFFDFA)];

  Color get cardBorder => Tokens.ink.withValues(alpha: 0.06);

  List<BoxShadow> get cardShadow => [
        BoxShadow(
          color: const Color(0xFFB4694B).withValues(alpha: 0.12),
          blurRadius: 18,
          offset: const Offset(0, 6),
        ),
      ];
}

// 밝은 단일 룩 (2026-10-26 UI 개편). 저장된 예전 테마 이름은 AppSettings.load에서 기본값으로 대체됨.
const kThemePresets = <ThemePreset>[
  ThemePreset(
    name: '달팽이 코랄',
    subtitle: 'Snail Coral',
    background: Tokens.bg,
    surface:    Tokens.card,
    accent:     Tokens.coralDisplay,
    accentGradientStart: Tokens.coralFace,
    accentGradientEnd:   Tokens.coralDisplay,
    grey:       Tokens.inkMuted,
    runGradient: [
      Tokens.bg,
      Tokens.card,
      Tokens.bg,
    ],
  ),
];
