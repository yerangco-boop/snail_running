import 'package:flutter/material.dart';
import '../models/app_settings.dart';

class SettingsScreen extends StatefulWidget {
  final AppSettings settings;
  final VoidCallback onChanged;

  const SettingsScreen({
    super.key,
    required this.settings,
    required this.onChanged,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  AppSettings get _s => widget.settings;
  Color get _accent => _s.accent;
  Color get _surface => _s.preset.surface;

  void _update(VoidCallback fn) {
    setState(fn);
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 28, 16, 32),
          children: [
            const Padding(
              padding: EdgeInsets.only(left: 8, bottom: 24),
              child: Text(
                "설정",
                style: TextStyle(
                    fontSize: 30, fontWeight: FontWeight.bold, color: Colors.white),
              ),
            ),

            // ── 세션 설정 ─────────────────────────────────────────────────────
            _sectionHeader("세션 설정"),
            const SizedBox(height: 8),

            _settingCard(
              icon: Icons.music_note_outlined,
              label: "메트로놈 BPM",
              trailing: Text("${_s.bpm} BPM",
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.bold)),
              onTap: _showBpmPicker,
            ),
            const SizedBox(height: 8),

            _settingCard(
              icon: Icons.flag_outlined,
              label: "목표 거리",
              trailing: Text("${_s.targetDistanceKm.toStringAsFixed(1)} km",
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.bold)),
              onTap: _showDistancePicker,
            ),
            const SizedBox(height: 8),

            _settingCard(
              icon: Icons.speed_outlined,
              label: "목표 페이스",
              trailing: Text(
                "${_s.paceMinutes}:${_s.paceSeconds.toString().padLeft(2, '0')} /km",
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.bold),
              ),
              onTap: _showPacePicker,
            ),

            const SizedBox(height: 28),

            // ── 오디오 설정 ───────────────────────────────────────────────────
            _sectionHeader("오디오 설정"),
            const SizedBox(height: 8),

            _settingCard(
              icon: Icons.record_voice_over_outlined,
              label: "TTS 음성",
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _genderChip("여성", 'female'),
                  const SizedBox(width: 8),
                  _genderChip("남성", 'male'),
                ],
              ),
            ),
            const SizedBox(height: 8),

            _settingCard(
              icon: Icons.headphones_outlined,
              label: "다른 오디오와 함께 재생",
              trailing: Switch(
                value: _s.mixWithOtherAudio,
                activeThumbColor: _accent,
                onChanged: (v) => _update(() => _s.mixWithOtherAudio = v),
              ),
            ),

            const SizedBox(height: 28),

            // ── 테마 선택 ─────────────────────────────────────────────────────
            _sectionHeader("테마"),
            const SizedBox(height: 8),

            _buildPresetGrid(),
          ],
        ),
      ),
    );
  }

  // ── 테마 프리셋 2열 그리드 ─────────────────────────────────────────────────
  Widget _buildPresetGrid() {
    const presets = kThemePresets;
    final rows = <Widget>[];
    for (var i = 0; i < presets.length; i += 2) {
      rows.add(
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: _presetCard(presets[i])),
              const SizedBox(width: 12),
              if (i + 1 < presets.length)
                Expanded(child: _presetCard(presets[i + 1]))
              else
                const Expanded(child: SizedBox()),
            ],
          ),
        ),
      );
      if (i + 2 < presets.length) rows.add(const SizedBox(height: 12));
    }
    return Column(children: rows);
  }

  // ── 테마 프리셋 카드 ───────────────────────────────────────────────────────
  Widget _presetCard(ThemePreset preset) {
    final isSelected = identical(_s.preset, preset);
    final accent = preset.accent;

    return GestureDetector(
      onTap: () => _update(() => _s.preset = preset),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        height: 100,
        decoration: BoxDecoration(
          color: preset.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isSelected ? accent : Colors.white.withValues(alpha: 0.07),
            width: isSelected ? 2 : 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: accent.withValues(alpha: 0.35),
                    blurRadius: 16,
                    spreadRadius: 0,
                    offset: const Offset(0, 4),
                  )
                ]
              : null,
        ),
        child: Stack(
          children: [
            // 대각선 그라디언트 (테마 분위기)
            Positioned.fill(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(17),
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topRight,
                      end: Alignment.bottomLeft,
                      colors: [
                        accent.withValues(alpha: 0.18),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
            ),

            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // 상단: 색상 점 + 체크
                  Row(
                    children: [
                      _dot(preset.background, 11),
                      const SizedBox(width: 4),
                      _dot(preset.surface.withValues(alpha: 0.5), 11,
                          border: Colors.white.withValues(alpha: 0.25)),
                      const SizedBox(width: 4),
                      _dot(accent, 11),
                      const Spacer(),
                      if (isSelected)
                        Container(
                          width: 20,
                          height: 20,
                          decoration: BoxDecoration(
                            color: accent,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.check_rounded,
                              color: Colors.white, size: 13),
                        ),
                    ],
                  ),

                  // 하단: 테마 이름
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        preset.name,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: isSelected ? accent : Colors.white,
                          height: 1.2,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        preset.subtitle,
                        style: TextStyle(
                          fontSize: 10,
                          color: preset.grey,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dot(Color color, double size, {Color? border}) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: border != null ? Border.all(color: border, width: 1) : null,
        ),
      );

  // ── 공통 위젯 ──────────────────────────────────────────────────────────────

  Widget _sectionHeader(String text) => Padding(
        padding: const EdgeInsets.only(left: 8, bottom: 4),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 12,
            color: _s.preset.grey,
            letterSpacing: 1.2,
            fontWeight: FontWeight.w600,
          ),
        ),
      );

  Widget _settingCard({
    required IconData icon,
    required String label,
    required Widget trailing,
    VoidCallback? onTap,
  }) =>
      InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          decoration:
              BoxDecoration(color: _surface, borderRadius: BorderRadius.circular(16)),
          child: Row(
            children: [
              Icon(icon, color: _accent, size: 22),
              const SizedBox(width: 16),
              Expanded(child: Text(label, style: const TextStyle(fontSize: 16))),
              trailing,
              if (onTap != null) ...[
                const SizedBox(width: 8),
                Icon(Icons.chevron_right, color: _s.preset.grey, size: 18),
              ],
            ],
          ),
        ),
      );

  Widget _genderChip(String label, String value) {
    final selected = _s.ttsVoiceGender == value;
    return GestureDetector(
      onTap: () => _update(() => _s.ttsVoiceGender = value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? _accent : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? _accent : _s.preset.grey),
        ),
        child: Text(
          label,
          style: TextStyle(
              color: selected ? Colors.white : _s.preset.grey, fontSize: 13),
        ),
      ),
    );
  }

  // ── 다이얼로그 ──────────────────────────────────────────────────────────────

  void _showBpmPicker() {
    const bpms = [140, 150, 160, 170, 180, 190, 200];
    showDialog(
      context: context,
      builder: (_) => SimpleDialog(
        backgroundColor: _surface,
        title: const Text("BPM 선택"),
        children: bpms
            .map((b) => SimpleDialogOption(
                  onPressed: () {
                    _update(() => _s.bpm = b);
                    Navigator.pop(context);
                  },
                  child: Text(
                    "$b BPM",
                    style: TextStyle(
                      fontWeight:
                          b == _s.bpm ? FontWeight.bold : FontWeight.normal,
                      color: b == _s.bpm ? _accent : Colors.white,
                      fontSize: 16,
                    ),
                  ),
                ))
            .toList(),
      ),
    );
  }

  void _showDistancePicker() {
    final ctrl =
        TextEditingController(text: _s.targetDistanceKm.toStringAsFixed(1));
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: _surface,
        title: const Text("목표 거리 (km)"),
        content: TextField(
          controller: ctrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () {
              final v = double.tryParse(ctrl.text);
              if (v != null && v > 0) _update(() => _s.targetDistanceKm = v);
              Navigator.pop(context);
            },
            child: Text("확인", style: TextStyle(color: _accent)),
          ),
        ],
      ),
    );
  }

  void _showPacePicker() {
    final mCtrl = TextEditingController(text: '${_s.paceMinutes}');
    final sCtrl =
        TextEditingController(text: _s.paceSeconds.toString().padLeft(2, '0'));
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: _surface,
        title: const Text("페이스 설정 (분:초 /km)"),
        content: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 64,
              child: TextField(
                controller: mCtrl,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                decoration: const InputDecoration(labelText: "분"),
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: Text(":", style: TextStyle(fontSize: 28)),
            ),
            SizedBox(
              width: 64,
              child: TextField(
                controller: sCtrl,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                decoration: const InputDecoration(labelText: "초"),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              final m =
                  (int.tryParse(mCtrl.text) ?? _s.paceMinutes).clamp(4, 20);
              final s =
                  (int.tryParse(sCtrl.text) ?? _s.paceSeconds).clamp(0, 59);
              _update(() {
                _s.paceMinutes = m;
                _s.paceSeconds = s;
              });
              Navigator.pop(context);
            },
            child: Text("확인", style: TextStyle(color: _accent)),
          ),
        ],
      ),
    );
  }
}
