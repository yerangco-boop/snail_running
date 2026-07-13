import 'package:flutter/material.dart';

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
  Color get onBackgroundMuted => onBackground.withValues(alpha: 0.55);

  Color get onRun =>
      runGradient[1].computeLuminance() > 0.3
          ? const Color(0xFF1A1A1A)
          : Colors.white;

  // ── 이력 화면 카드 전용 "무채색 카드" 구조 ──────────────────────────────────
  // surface(보석톤 채도색)를 그대로 카드 배경으로 쓰지 않고, 거의 검정에 가까운
  // 베이스에 아주 소량(4~10%)만 섞은 무채색 그라디언트로 대체 — 카드 자체는 무채색을
  // 유지하면서 테두리(cardBorder)로만 테마색을 드러내는 "중립 카드" 구조
  static Color _mix(Color tint, double t, Color base) => Color.fromRGBO(
        (tint.r * 255 * t + base.r * 255 * (1 - t)).round(),
        (tint.g * 255 * t + base.g * 255 * (1 - t)).round(),
        (tint.b * 255 * t + base.b * 255 * (1 - t)).round(),
        1.0,
      );

  List<Color> get cardGradient => [
        _mix(surface, 0.10, const Color(0xFF232328)),
        _mix(surface, 0.06, const Color(0xFF1A1A1E)),
        _mix(surface, 0.04, const Color(0xFF121214)),
      ];

  Color get cardBorder => surface.withValues(alpha: 0.55);
}

const kThemePresets = <ThemePreset>[
  // ── 1. 미드나잇 바이올렛 ─────────────────────────────────────────────────
  // 어두운 배경 + 자수정(amethyst) 보석톤 카드, 인디고→마젠타 그라디언트 포인트.
  ThemePreset(
    name: '미드나잇 바이올렛',
    subtitle: 'Midnight Violet · Amethyst',
    background: Color(0xFF655B78),
    surface:    Color(0xFFA279E9),
    accent:     Color(0xFF8B6EF5),
    accentGradientStart: Color(0xFF6D5EF2),
    accentGradientEnd:   Color(0xFFB46BF0),
    grey:       Color(0xFFCFBBF3),
    runGradient: [
      Color(0xFF2C2160),
      Color(0xFF6D5EF2),
      Color(0xFF1A1330),
    ],
  ),

  // ── 2. 아크틱 블루 ──────────────────────────────────────────────────────
  // 어두운 배경 + 사파이어 보석톤 카드, 블루→시안 그라디언트 포인트.
  ThemePreset(
    name: '아크틱 블루',
    subtitle: 'Arctic Blue · Sapphire',
    background: Color(0xFF54616F),
    surface:    Color(0xFF388BE9),
    accent:     Color(0xFF4BB4E6),
    accentGradientStart: Color(0xFF2F8FD8),
    accentGradientEnd:   Color(0xFF6FD0E8),
    grey:       Color(0xFF9CC6F3),
    runGradient: [
      Color(0xFF0F3A55),
      Color(0xFF2F8FD8),
      Color(0xFF0A1F30),
    ],
  ),

  // ── 3. 에메랄드 나이트 ──────────────────────────────────────────────────
  // 어두운 배경 + 에메랄드 보석톤 카드, 그린→민트 그라디언트 포인트.
  ThemePreset(
    name: '에메랄드 나이트',
    subtitle: 'Emerald Night · Jade',
    background: Color(0xFF4D645B),
    surface:    Color(0xFF15945F),
    accent:     Color(0xFF34B78A),
    accentGradientStart: Color(0xFF1F9D76),
    accentGradientEnd:   Color(0xFF6BD9A8),
    grey:       Color(0xFF8CCBB1),
    runGradient: [
      Color(0xFF103B2C),
      Color(0xFF1F9D76),
      Color(0xFF0B1F18),
    ],
  ),

  // ── 4. 로즈 골드 ────────────────────────────────────────────────────────
  // 어두운 배경 + 가넷/루비 보석톤 카드, 로즈→골드 그라디언트 포인트.
  ThemePreset(
    name: '로즈 골드',
    subtitle: 'Rose Gold · Garnet',
    background: Color(0xFF6F5A5E),
    surface:    Color(0xFFE84661),
    accent:     Color(0xFFDD9D92),
    accentGradientStart: Color(0xFFD98A8F),
    accentGradientEnd:   Color(0xFFF0C199),
    grey:       Color(0xFFF2A3AE),
    runGradient: [
      Color(0xFF4A2226),
      Color(0xFFD98A8F),
      Color(0xFF23100F),
    ],
  ),

  // ── 5. 앰버 프레스티지 ──────────────────────────────────────────────────
  // 어두운 배경 + 위스키 앰버/토파즈 보석톤 카드, 앰버→골드 그라디언트 포인트.
  ThemePreset(
    name: '앰버 프레스티지',
    subtitle: 'Amber Prestige · Topaz',
    background: Color(0xFF695E4F),
    surface:    Color(0xFFC97C16),
    accent:     Color(0xFFDBA449),
    accentGradientStart: Color(0xFFC9862E),
    accentGradientEnd:   Color(0xFFF0C869),
    grey:       Color(0xFFE3BD8A),
    runGradient: [
      Color(0xFF402B0C),
      Color(0xFFC9862E),
      Color(0xFF1E1408),
    ],
  ),
];
