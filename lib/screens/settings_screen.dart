import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:share_plus/share_plus.dart';
import '../models/app_settings.dart';
import '../services/database_service.dart';
import '../services/file_logger.dart';

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

  // 슬로우 조깅 권장 케이던스 대역을 담을 수 있도록 5단위로 선택
  static const int _minBpm = 140;
  static const int _maxBpm = 200;
  static const int _bpmStep = 5;

  // 실기기에 실제로 설치된 앱 이름/versionName/versionCode 확인용 (하드코딩이 아니라
  // 빌드 시점 pubspec.yaml의 version: X.Y.Z+N에서 그대로 채워짐 — 매 빌드마다 자동 갱신)
  PackageInfo? _packageInfo;
  String? get _versionLabel => _packageInfo == null
      ? null
      : 'v${_packageInfo!.version} (${_packageInfo!.buildNumber})';

  // 지난 기록에서 계산한 실측 보폭(m) — "지금 내 보폭"을 권장값과 비교해 보여주는 용도.
  // BPM 제안 자체는 아래 슬로우 조깅 표준 보폭을 기준으로 함(실측 보폭을 쓰면 느리게
  // 뛸수록 BPM을 낮추라고 제안하게 되어 슬로우 조깅 원칙과 반대가 됨)
  double? _measuredStride;

  @override
  void initState() {
    super.initState();
    _loadVersion();
    _loadStride();
  }

  Future<void> _loadVersion() async {
    final info = await PackageInfo.fromPlatform();
    if (!mounted) return;
    setState(() => _packageInfo = info);
  }

  // 보폭 = 이동거리 / 걸음 수. 걸음 수가 저장되기 시작한 기록(v20+)만 대상으로
  // 최근 5개를 평균 — 한 세션만 쓰면 그날 컨디션에 좌우되기 쉬움
  Future<void> _loadStride() async {
    try {
      final records = await DatabaseService.instance.getWorkouts();
      final strides = records
          .map((r) => r.strideMeters)
          .whereType<double>()
          .take(5)
          .toList();
      if (strides.isEmpty || !mounted) return;
      final avg = strides.reduce((a, b) => a + b) / strides.length;
      setState(() => _measuredStride = avg);
    } catch (e) {
      debugPrint('[Settings] 보폭 계산 실패: $e');
    }
  }

  // ── 슬로우 조깅 표준 보폭 (페이스별) ──────────────────────────────────────
  // 슬로우 조깅은 "보폭을 짧게, 케이던스는 높게" 유지하는 방식이라, 느려질수록
  // 보폭이 짧아지고 케이던스는 높은 대역(대략 155~190spm)에 머문다.
  // 아래 앵커를 선형 보간해서 목표 페이스에 해당하는 표준 보폭을 구함.
  static const List<List<double>> _slowJogStrideAnchors = [
    [7.0, 0.75], [8.0, 0.68], [9.0, 0.62], [10.0, 0.57],
    [11.0, 0.52], [13.0, 0.47], [15.0, 0.43],
  ];

  double _slowJogStrideFor(double paceMinPerKm) {
    final a = _slowJogStrideAnchors;
    if (paceMinPerKm <= a.first[0]) return a.first[1];
    if (paceMinPerKm >= a.last[0]) return a.last[1];
    for (var i = 0; i < a.length - 1; i++) {
      final p0 = a[i][0], s0 = a[i][1], p1 = a[i + 1][0], s1 = a[i + 1][1];
      if (paceMinPerKm >= p0 && paceMinPerKm <= p1) {
        final t = (paceMinPerKm - p0) / (p1 - p0);
        return s0 + (s1 - s0) * t;
      }
    }
    return a.last[1];
  }

  double get _targetPaceMin => _s.paceMinutes + _s.paceSeconds / 60.0;

  // 속도(m/분) = 케이던스(spm) × 보폭(m). 목표 페이스를 슬로우 조깅 표준 보폭으로
  // 나눠 필요한 케이던스를 구한 뒤, 선택 가능한 5단위 값으로 반올림
  int? get _recommendedBpm {
    final pace = _targetPaceMin;
    if (pace <= 0) return null;
    final raw = (1000 / pace) / _slowJogStrideFor(pace);
    final rounded = (raw / 5).round() * 5;
    return rounded.clamp(_minBpm, _maxBpm);
  }

  void _update(VoidCallback fn) {
    setState(fn);
    widget.onChanged();
  }

  // 실외 테스트 진단 로그(GPS/케이던스/바퀴)를 USB 연결 없이도 확인할 수 있도록
  // 카톡/메일 등 아무 앱으로나 바로 공유
  Future<void> _shareDebugLog() async {
    await FileLogger.instance.flushNow();
    final path = FileLogger.instance.filePath;
    if (path == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('공유할 로그가 아직 없습니다. 운동을 한 번 진행한 뒤 다시 시도해주세요.')),
      );
      return;
    }
    await Share.shareXFiles(
      [XFile(path, mimeType: 'text/plain')],
      text: '달팽이 러닝 디버그 로그',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 28, 16, 32),
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 8, bottom: 24),
              child: Text(
                "설정",
                style: TextStyle(
                    fontSize: 30, fontWeight: FontWeight.bold, color: _s.preset.onBackground),
              ),
            ),

            // ── 세션 설정 ─────────────────────────────────────────────────────
            _sectionHeader("세션 설정"),
            const SizedBox(height: 8),

            _settingCard(
              icon: Icons.music_note_outlined,
              label: "메트로놈 BPM",
              trailing: Text("${_s.bpm} BPM",
                  style: TextStyle(color: _accent, fontWeight: FontWeight.bold)),
              onTap: _showBpmPicker,
            ),
            const SizedBox(height: 8),

            _settingCard(
              icon: Icons.flag_outlined,
              label: "목표 거리",
              trailing: Text("${_s.targetDistanceKm.toStringAsFixed(1)} km",
                  style: TextStyle(color: _accent, fontWeight: FontWeight.bold)),
              onTap: _showDistancePicker,
            ),
            const SizedBox(height: 8),

            _settingCard(
              icon: Icons.speed_outlined,
              label: "목표 페이스",
              trailing: Text(
                "${_s.paceMinutes}:${_s.paceSeconds.toString().padLeft(2, '0')} /km",
                style: TextStyle(color: _accent, fontWeight: FontWeight.bold),
              ),
              onTap: _showPacePicker,
            ),
            if (_recommendedBpm != null) ...[
              const SizedBox(height: 8),
              _buildBpmSuggestionCard(),
            ],
            const SizedBox(height: 8),

            _settingCard(
              icon: Icons.monitor_weight_outlined,
              label: "체중 (칼로리 계산용)",
              trailing: Text("${_s.weightKg.toStringAsFixed(1)} kg",
                  style: TextStyle(color: _accent, fontWeight: FontWeight.bold)),
              onTap: _showWeightPicker,
            ),
            const SizedBox(height: 8),

            _settingCard(
              icon: Icons.screen_lock_portrait_outlined,
              label: "러닝 중 화면 켜두기",
              trailing: Switch(
                value: _s.keepScreenOn,
                activeThumbColor: _accent,
                onChanged: (v) => _update(() => _s.keepScreenOn = v),
              ),
            ),

            const SizedBox(height: 28),

            // ── 오디오 설정 ───────────────────────────────────────────────────
            _sectionHeader("오디오 설정"),
            const SizedBox(height: 8),

            _settingCard(
              icon: Icons.record_voice_over_outlined,
              label: "TTS 음성",
              trailing: Text(
                _s.ttsVoiceName ?? "자동",
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: _accent, fontWeight: FontWeight.bold),
              ),
              onTap: _showVoicePicker,
            ),
            const SizedBox(height: 8),

            _settingCard(
              icon: Icons.music_note_outlined,
              label: "메트로놈 사용",
              trailing: Switch(
                value: _s.metronomeEnabled,
                activeThumbColor: _accent,
                onChanged: (v) => _update(() => _s.metronomeEnabled = v),
              ),
            ),
            const SizedBox(height: 8),

            _buildMetronomeVolumeCard(),
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

            const SizedBox(height: 28),

            // ── 디버그 ────────────────────────────────────────────────────────
            _sectionHeader("디버그"),
            const SizedBox(height: 8),
            _settingCard(
              icon: Icons.bug_report_outlined,
              label: "실외 테스트 로그 공유",
              trailing: Icon(Icons.ios_share, color: _s.preset.grey, size: 18),
              onTap: _shareDebugLog,
            ),

            const SizedBox(height: 28),

            // ── 정보 ──────────────────────────────────────────────────────────
            _sectionHeader("정보"),
            const SizedBox(height: 8),
            _buildAboutCard(),
          ],
        ),
      ),
    );
  }

  // 목표 페이스 → 슬로우 조깅 표준 보폭 → 권장 BPM.
  // 실측 보폭이 있으면 "지금 내 보폭"을 함께 보여줘 얼마나 줄여야 하는지 알 수 있게 함
  Widget _buildBpmSuggestionCard() {
    final bpm = _recommendedBpm!;
    final refStride = _slowJogStrideFor(_targetPaceMin);
    final mine = _measuredStride;
    final already = bpm == _s.bpm;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 14, 16, 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: _s.preset.cardGradient,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _accent.withValues(alpha: 0.45)),
        boxShadow: _s.preset.cardShadow,
      ),
      child: Row(
        children: [
          Icon(Icons.auto_awesome_outlined, color: _accent, size: 22),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  already ? '목표 페이스에 맞는 BPM입니다' : '이 페이스엔 $bpm BPM 권장',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: _s.preset.onBackground,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  mine == null
                      ? '슬로우 조깅 보폭 ${(refStride * 100).round()}cm 기준'
                      : '보폭 ${(refStride * 100).round()}cm로 잔발 '
                          '(지난 러닝 ${(mine * 100).round()}cm)',
                  style: TextStyle(fontSize: 12, color: _s.preset.grey),
                ),
              ],
            ),
          ),
          if (!already)
            TextButton(
              onPressed: () => _update(() => _s.bpm = bpm),
              child: Text('적용',
                  style: TextStyle(color: _accent, fontWeight: FontWeight.bold)),
            ),
        ],
      ),
    );
  }

  // 메트로놈 음량 슬라이더 — 스피커로만 들을 때 음량이 부족한 경우를 위해 노출.
  // 값은 SoundPool의 leftVolume/rightVolume(안드로이드), Web Audio gain(웹)으로 전달됨
  Widget _buildMetronomeVolumeCard() {
    final percent = (_s.metronomeVolume * 100).round();
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 6),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: _s.preset.cardGradient,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _s.preset.cardBorder),
        boxShadow: _s.preset.cardShadow,
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(Icons.volume_up_outlined, color: _accent, size: 22),
              const SizedBox(width: 16),
              Expanded(
                child: Text("메트로놈 음량",
                    style: TextStyle(fontSize: 16, color: _s.preset.onBackground)),
              ),
              Text("$percent%",
                  style: TextStyle(color: _accent, fontWeight: FontWeight.bold)),
            ],
          ),
          Slider(
            value: _s.metronomeVolume.clamp(0.0, 1.0),
            activeColor: _accent,
            onChanged: (v) => _update(() => _s.metronomeVolume = v),
          ),
        ],
      ),
    );
  }

  // 앱 아이콘 + 앱 이름 + 버전 + 제작자 표시
  Widget _buildAboutCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: _s.preset.cardGradient,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _s.preset.cardBorder),
        boxShadow: _s.preset.cardShadow,
      ),
      child: Column(
        children: [
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Image.asset('assets/icon/icon.png', width: 48, height: 48),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("달팽이 러닝",
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: _s.preset.onBackground)),
                    const SizedBox(height: 2),
                    Text(
                      _versionLabel ?? '버전 확인 중...',
                      style: TextStyle(fontSize: 13, color: _s.preset.grey),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Divider(color: _s.preset.cardBorder, height: 1),
          const SizedBox(height: 14),
          Text(
            "© 2026 홍정표 · Made by 홍정표",
            style: TextStyle(fontSize: 12, color: _s.preset.grey),
          ),
        ],
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
            color: isSelected ? accent : preset.onSurface.withValues(alpha: 0.07),
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
                          border: preset.onSurface.withValues(alpha: 0.25)),
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
                          color: isSelected ? accent : preset.onSurface,
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
            color: _s.preset.onBackgroundMuted,
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
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topRight,
              end: Alignment.bottomLeft,
              colors: _s.preset.cardGradient,
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _s.preset.cardBorder),
            boxShadow: _s.preset.cardShadow,
          ),
          child: Row(
            children: [
              Icon(icon, color: _accent, size: 22),
              const SizedBox(width: 16),
              Expanded(
                  child: Text(label,
                      style: TextStyle(fontSize: 16, color: _s.preset.onBackground))),
              trailing,
              if (onTap != null) ...[
                const SizedBox(width: 8),
                Icon(Icons.chevron_right, color: _s.preset.grey, size: 18),
              ],
            ],
          ),
        ),
      );

  // 한국어 음성 목록을 피커로 보여주고, 각 항목의 미리듣기 버튼으로 실제 들어보고 고르게 함.
  // 예전 male/female 이름 매칭 방식은 안드로이드 음성 이름에 성별이 표기되지 않아
  // 작동하지 않았으므로 폐기하고, 목록 전체를 노출하는 방식으로 교체
  Future<void> _showVoicePicker() async {
    final previewTts = FlutterTts();
    await previewTts.setLanguage('ko-KR');
    var voices = await previewTts.getVoices;
    for (var i = 0; i < 5 && (voices as List).isEmpty; i++) {
      await Future.delayed(const Duration(milliseconds: 300));
      voices = await previewTts.getVoices;
    }
    final koreanVoices = (voices as List)
        .whereType<Map>()
        .where((v) => (v['locale']?.toString() ?? '').toLowerCase().startsWith('ko'))
        .toList();
    if (!mounted) return;

    await showModalBottomSheet(
      context: context,
      backgroundColor: _surface,
      isScrollControlled: true,
      builder: (_) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Text("음성 선택",
                  style: TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold, color: _s.preset.onSurface)),
            ),
            if (koreanVoices.isEmpty)
              Padding(
                padding: const EdgeInsets.all(20),
                child: Text("사용 가능한 한국어 음성을 찾지 못했습니다.",
                    style: TextStyle(color: _s.preset.grey)),
              ),
            for (final v in koreanVoices)
              ListTile(
                title: Text(v['name']?.toString() ?? '',
                    style: TextStyle(color: _s.preset.onSurface)),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: Icon(Icons.play_circle_outline, color: _accent),
                      onPressed: () async {
                        await previewTts.setVoice({
                          'name': v['name'].toString(),
                          'locale': v['locale'].toString(),
                        });
                        await previewTts.speak('안녕하세요, 슬로우 조깅을 시작합니다.');
                      },
                    ),
                    if (_s.ttsVoiceName == v['name']?.toString())
                      Icon(Icons.check_rounded, color: _accent),
                  ],
                ),
                onTap: () {
                  _update(() => _s.ttsVoiceName = v['name']?.toString());
                  Navigator.pop(context);
                },
              ),
          ],
        ),
      ),
    );
    await previewTts.stop();
  }

  // ── 다이얼로그 ──────────────────────────────────────────────────────────────

  // 140~200을 5단위로. 슬로우 조깅 권장 대역(155~190)을 세밀하게 고를 수 있게
  // 기존 10단위에서 5단위로만 좁힌 것(하한 140은 유지)
  void _showBpmPicker() {
    const minBpm = _minBpm, maxBpm = _maxBpm, step = _bpmStep;
    const count = (maxBpm - minBpm) ~/ step + 1;
    var selectedIndex = ((_s.bpm - minBpm) / step).round().clamp(0, count - 1);
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: _surface,
        title: const Text("메트로놈 BPM"),
        content: SizedBox(
          height: 180,
          child: _wheelColumn(
            itemCount: count,
            initialIndex: selectedIndex,
            onChanged: (i) => selectedIndex = i,
            label: (i) => '${minBpm + i * step} BPM',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              _update(() => _s.bpm = minBpm + selectedIndex * step);
              Navigator.pop(context);
            },
            child: Text("확인", style: TextStyle(color: _accent)),
          ),
        ],
      ),
    );
  }

  // 휠(스크롤) 형태의 숫자 선택 컬럼 — 타이핑 대신 돌려서 값을 고르는 방식
  Widget _wheelColumn({
    required int itemCount,
    required int initialIndex,
    required ValueChanged<int> onChanged,
    required String Function(int index) label,
  }) {
    return CupertinoPicker(
      backgroundColor: _surface,
      scrollController: FixedExtentScrollController(initialItem: initialIndex),
      itemExtent: 40,
      onSelectedItemChanged: onChanged,
      children: List.generate(
        itemCount,
        (i) => Center(
          child: Text(label(i),
              style: TextStyle(fontSize: 20, color: _s.preset.onSurface)),
        ),
      ),
    );
  }

  void _showWeightPicker() {
    const minKg = 30.0, maxKg = 150.0, step = 0.5;
    final count = ((maxKg - minKg) / step).round() + 1;
    var selectedIndex =
        ((_s.weightKg - minKg) / step).round().clamp(0, count - 1);
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: _surface,
        title: const Text("체중 (kg)"),
        content: SizedBox(
          height: 180,
          child: _wheelColumn(
            itemCount: count,
            initialIndex: selectedIndex,
            onChanged: (i) => selectedIndex = i,
            label: (i) => '${(minKg + i * step).toStringAsFixed(1)} kg',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              _update(() => _s.weightKg = minKg + selectedIndex * step);
              Navigator.pop(context);
            },
            child: Text("확인", style: TextStyle(color: _accent)),
          ),
        ],
      ),
    );
  }


  void _showDistancePicker() {
    const minKm = 1.0, maxKm = 50.0, step = 0.1;
    final count = ((maxKm - minKm) / step).round() + 1;
    var selectedIndex =
        ((_s.targetDistanceKm - minKm) / step).round().clamp(0, count - 1);
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: _surface,
        title: const Text("목표 거리 (km)"),
        content: SizedBox(
          height: 180,
          child: _wheelColumn(
            itemCount: count,
            initialIndex: selectedIndex,
            onChanged: (i) => selectedIndex = i,
            label: (i) => '${(minKm + i * step).toStringAsFixed(1)} km',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              _update(() => _s.targetDistanceKm = minKm + selectedIndex * step);
              Navigator.pop(context);
            },
            child: Text("확인", style: TextStyle(color: _accent)),
          ),
        ],
      ),
    );
  }

  void _showPacePicker() {
    var selectedMin = _s.paceMinutes.clamp(4, 20);
    var selectedSec = _s.paceSeconds.clamp(0, 59);
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: _surface,
        title: const Text("페이스 설정 (분:초 /km)"),
        content: SizedBox(
          height: 180,
          child: Row(
            children: [
              Expanded(
                child: _wheelColumn(
                  itemCount: 17, // 4~20분
                  initialIndex: selectedMin - 4,
                  onChanged: (i) => selectedMin = i + 4,
                  label: (i) => '${i + 4}분',
                ),
              ),
              Expanded(
                child: _wheelColumn(
                  itemCount: 60, // 0~59초
                  initialIndex: selectedSec,
                  onChanged: (i) => selectedSec = i,
                  label: (i) => '${i.toString().padLeft(2, '0')}초',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              _update(() {
                _s.paceMinutes = selectedMin;
                _s.paceSeconds = selectedSec;
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
