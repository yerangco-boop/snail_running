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
  // ── 1. 미드나잇 바이올렛 ─────────────────────────────────────────────────
  // 보라빛 은하수. 블랙 배경 + 다크 스틸블루 카드 + 바이올렛 포인트.
  ThemePreset(
    name: '미드나잇 바이올렛',
    subtitle: 'Dark Space · Violet',
    background: Color(0xFF0E0A20),   // 확실한 인디고 틴트
    surface:    Color(0xFF1A2840),   // 뚜렷한 스틸블루
    accent:     Color(0xFF8B5CF6),
    grey:       Color(0xFF8A8AB0),
    runGradient: [
      Color(0xFF080215),
      Color(0xFF140535),
      Color(0xFF0E1035),
    ],
  ),

  // ── 2. 아크틱 블루 ──────────────────────────────────────────────────────
  // 극지방의 빙하. 다크 네이비 배경 + 딥오션 카드 + 하늘빛 포인트.
  ThemePreset(
    name: '아크틱 블루',
    subtitle: 'Deep Ocean · Cyan',
    background: Color(0xFF071828),   // 확실한 딥네이비 틴트
    surface:    Color(0xFF0C2E50),   // 뚜렷한 딥오션 블루
    accent:     Color(0xFF22D3EE),
    grey:       Color(0xFF6A8FA8),
    runGradient: [
      Color(0xFF020810),
      Color(0xFF051C30),
      Color(0xFF041528),
    ],
  ),

  // ── 3. 에메랄드 나이트 ──────────────────────────────────────────────────
  // 밤의 숲. 거의 검은 배경 + 다크 포레스트 카드 + 에메랄드 포인트.
  ThemePreset(
    name: '에메랄드 나이트',
    subtitle: 'Forest Black · Emerald',
    background: Color(0xFF081C0C),   // 확실한 포레스트 틴트
    surface:    Color(0xFF0C2A18),   // 뚜렷한 포레스트그린
    accent:     Color(0xFF10B981),
    grey:       Color(0xFF5A8A70),
    runGradient: [
      Color(0xFF020A04),
      Color(0xFF051508),
      Color(0xFF04130E),
    ],
  ),

  // ── 4. 로즈 골드 ────────────────────────────────────────────────────────
  // 딥 크림슨 럭셔리. 다크 와인 배경 + 크림슨 카드 + 로즈 포인트.
  ThemePreset(
    name: '로즈 골드',
    subtitle: 'Dark Crimson · Rose',
    background: Color(0xFF1E080E),   // 확실한 딥크림슨 틴트
    surface:    Color(0xFF2C0E18),   // 뚜렷한 다크크림슨
    accent:     Color(0xFFF43F5E),
    grey:       Color(0xFF8A6A72),
    runGradient: [
      Color(0xFF0A0205),
      Color(0xFF1A0510),
      Color(0xFF160315),
    ],
  ),

  // ── 5. 앰버 프레스티지 ──────────────────────────────────────────────────
  // 위스키 & 월넛. 다크 앰버 배경 + 월넛 카드 + 골드 포인트.
  ThemePreset(
    name: '앰버 프레스티지',
    subtitle: 'Dark Walnut · Gold',
    background: Color(0xFF1A0E00),   // 확실한 월넛 틴트
    surface:    Color(0xFF281500),   // 뚜렷한 월넛브라운
    accent:     Color(0xFFFBBF24),
    grey:       Color(0xFF8A7A50),
    runGradient: [
      Color(0xFF060300),
      Color(0xFF140900),
      Color(0xFF1C0C00),
    ],
  ),
];
