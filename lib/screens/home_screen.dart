import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/app_settings.dart';
import '../models/workout_record.dart';
import '../services/metronome_service.dart';
import '../services/database_service.dart';

enum WorkoutState { idle, countdown, running, paused }

class HomeScreen extends StatefulWidget {
  final AppSettings settings;
  final VoidCallback onSettingsChanged;
  final VoidCallback onGoToSettings;

  const HomeScreen({
    super.key,
    required this.settings,
    required this.onSettingsChanged,
    required this.onGoToSettings,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  WorkoutState _workoutState = WorkoutState.idle;
  double _distanceKm = 0.0;
  int _seconds = 0;
  int _countdownValue = 3;

  // 운동 중 중앙 큰 숫자 표시 모드: 0=거리, 1=시간, 2=BPM (탭할 때마다 순환)
  int _mainDisplayMode = 0;
  static const List<String> _mainDisplayLabels = ['km', '시간', 'BPM'];

  void _cycleMainDisplay() {
    setState(() => _mainDisplayMode = (_mainDisplayMode + 1) % _mainDisplayLabels.length);
  }

  int _lastAnnouncedKm = 0;
  int _lapStartSeconds = 0;
  bool _halfAnnounced = false;
  bool _goalAnnounced = false;

  Timer? _workoutTimer;
  Timer? _countdownTimer;
  final FlutterTts _tts = FlutterTts();
  final MetronomeService _metronome = MetronomeService();
  final MapController _mapController = MapController();

  LatLng _mapCenter = const LatLng(37.5665, 126.9780); // 서울 기본값
  bool _hasLocation = false;

  StreamSubscription<Position>? _positionSub;
  LatLng? _lastGpsPoint;
  static const int _gpsAccuracyThresholdMeters = 25; // 이보다 부정확한 측위는 거리 누적에서 제외

  AppSettings get _s => widget.settings;

  String? _appliedTtsGender;

  @override
  void initState() {
    super.initState();
    _tts.setLanguage("ko-KR");
    _applyTtsVoice();
    _metronome.init();
    _fetchLocation();
  }

  @override
  void didUpdateWidget(covariant HomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_appliedTtsGender != _s.ttsVoiceGender) {
      _applyTtsVoice();
    }
  }

  // ttsVoiceGender 설정에 맞는 한국어 음성을 찾아 적용
  Future<void> _applyTtsVoice() async {
    try {
      // 크롬은 speechSynthesis 음성 목록을 비동기로 늦게 채우는 경우가 있어
      // 빈 목록이 오면 잠깐 기다렸다가 다시 시도
      var voices = await _tts.getVoices;
      for (var i = 0; i < 5 && (voices as List).isEmpty; i++) {
        await Future.delayed(const Duration(milliseconds: 300));
        voices = await _tts.getVoices;
      }
      final koreanVoices = (voices as List)
          .whereType<Map>()
          .where((v) => (v['locale']?.toString() ?? '').toLowerCase().startsWith('ko'))
          .toList();
      debugPrint('[TTS] 한국어 음성 목록: $koreanVoices');

      final wantMale = _s.ttsVoiceGender == 'male';
      _appliedTtsGender = _s.ttsVoiceGender;
      Map? match;
      for (final v in koreanVoices) {
        final name = (v['name']?.toString() ?? '').toLowerCase();
        final isMale = name.contains('male') && !name.contains('female');
        final isFemale = name.contains('female');
        if (wantMale && isMale) { match = v; break; }
        if (!wantMale && isFemale) { match = v; break; }
      }
      // 성별이 이름에 명시되지 않은 경우, 더 자연스러운 음성(Google 계열)을 우선 사용
      match ??= koreanVoices.firstWhere(
        (v) => (v['name']?.toString() ?? '').toLowerCase().contains('google'),
        orElse: () => koreanVoices.isNotEmpty ? koreanVoices.first : {},
      );
      if (match.isEmpty) match = null;
      if (match != null) {
        await _tts.setVoice({
          'name': match['name'].toString(),
          'locale': match['locale'].toString(),
        });
        debugPrint('[TTS] 적용된 음성: ${match['name']} (${match['locale']})');
      }
    } catch (e) {
      debugPrint('[TTS] 음성 설정 실패: $e');
    }
  }

  @override
  void dispose() {
    _workoutTimer?.cancel();
    _countdownTimer?.cancel();
    _positionSub?.cancel();
    _metronome.dispose();
    _mapController.dispose();
    super.dispose();
  }

  Future<void> _fetchLocation() async {
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm != LocationPermission.always && perm != LocationPermission.whileInUse) return;
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
        timeLimit: const Duration(seconds: 10),
      );
      if (!mounted) return;
      setState(() {
        _mapCenter = LatLng(pos.latitude, pos.longitude);
        _hasLocation = true;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          try { _mapController.move(_mapCenter, 15.5); } catch (_) {}
        }
      });
    } catch (_) {}
  }

  // ── 운동 제어 ─────────────────────────────────────────────────────────────────

  void _startCountdown() {
    setState(() {
      _workoutState = WorkoutState.countdown;
      _countdownValue = 3;
    });
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) { timer.cancel(); return; }
      if (_countdownValue <= 1) {
        timer.cancel();
        _countdownTimer = null;
        _doStartWorkout();
      } else {
        setState(() => _countdownValue--);
      }
    });
  }

  Future<void> _doStartWorkout() async {
    setState(() => _workoutState = WorkoutState.running);
    _announceWorkoutStart();
    _metronome.start(_s.bpm);
    _lastGpsPoint = null;
    await _startGpsTracking();
    _launchTimer();
  }

  Future<void> _startGpsTracking() async {
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm != LocationPermission.always && perm != LocationPermission.whileInUse) return;

      _positionSub?.cancel();
      _positionSub = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 3,
        ),
      ).listen((pos) {
        if (!mounted) return;
        final point = LatLng(pos.latitude, pos.longitude);
        if (pos.accuracy <= _gpsAccuracyThresholdMeters) {
          if (_lastGpsPoint != null) {
            final meters = Geolocator.distanceBetween(
              _lastGpsPoint!.latitude, _lastGpsPoint!.longitude,
              point.latitude, point.longitude,
            );
            setState(() {
              _distanceKm += meters / 1000.0;
              _checkAudioGuide();
            });
          }
          _lastGpsPoint = point;
        }
        setState(() {
          _mapCenter = point;
          _hasLocation = true;
        });
      });
    } catch (_) {}
  }

  void _announceWorkoutStart() {
    final goalPart = _s.goalType == GoalType.distance
        ? '목표 거리 ${_s.targetDistanceKm.toStringAsFixed(1)}킬로미터'
        : '목표 시간 ${_s.targetTimeMinutes}분';
    _tts.speak(
        '$goalPart, 페이스 ${_s.paceMinutes}분 ${_s.paceSeconds}초로 슬로우 조깅을 시작합니다.');
  }

  void _pauseWorkout() {
    _workoutTimer?.cancel();
    _workoutTimer = null;
    _positionSub?.cancel();
    _positionSub = null;
    _metronome.stop();
    setState(() => _workoutState = WorkoutState.paused);
  }

  void _resumeWorkout() {
    setState(() => _workoutState = WorkoutState.running);
    _metronome.start(_s.bpm, playImmediately: false);
    _lastGpsPoint = null;
    _startGpsTracking();
    _launchTimer();
  }

  void _stopWorkout() {
    _workoutTimer?.cancel();
    _workoutTimer = null;
    _positionSub?.cancel();
    _positionSub = null;
    _metronome.stop();
    setState(() => _workoutState = WorkoutState.idle);
    _announceWorkoutSummary();
    _saveToDb();
    _showSummaryDialog();
  }

  void _announceWorkoutSummary() {
    final distStr = _distanceKm.toStringAsFixed(2);
    final tm = _seconds ~/ 60, ts = _seconds % 60;
    var paceStr = '';
    if (_distanceKm >= 0.01) {
      final avgSec = _seconds / _distanceKm;
      final am = (avgSec ~/ 60).toInt(), asec = avgSec.toInt() % 60;
      paceStr = ', 평균 페이스 $am분 $asec초';
    }
    _tts.speak('운동을 종료합니다. 총 거리 $distStr킬로미터, 총 시간 $tm분 $ts초$paceStr 였습니다.');
  }

  Future<void> _saveToDb() async {
    if (_distanceKm < 0.01 || _seconds < 5) return;
    final record = WorkoutRecord(
      date: DateTime.now(),
      distanceKm: _distanceKm,
      durationSeconds: _seconds,
      avgPaceSecPerKm: _seconds / _distanceKm,
    );
    await DatabaseService.instance.insertWorkout(record);
  }

  void _launchTimer() {
    _workoutTimer?.cancel();
    _workoutTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() => _seconds++);
    });
  }

  static const _stretchParts = ['종아리', '허벅지', '무릎', '허리', '발목'];

  Future<void> _openStretchYoutube(List<String> parts) async {
    final query = Uri.encodeComponent('김병곤 ${parts.join(' ')} 스트레칭');
    final uri = Uri.parse('https://www.youtube.com/results?search_query=$query');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  void _resetWorkout() {
    setState(() {
      _distanceKm = 0.0;
      _seconds = 0;
      _lastAnnouncedKm = 0;
      _lapStartSeconds = 0;
      _halfAnnounced = false;
      _goalAnnounced = false;
      _mainDisplayMode = 0;
    });
  }

  void _checkAudioGuide() {
    final km = _distanceKm.floor();
    if (km > 0 && km > _lastAnnouncedKm) {
      final lapSec = _seconds - _lapStartSeconds;
      _lapStartSeconds = _seconds;
      _lastAnnouncedKm = km;
      final lm = lapSec ~/ 60, ls = lapSec % 60;
      final avgSec = _seconds / _distanceKm;
      final am = (avgSec ~/ 60).toInt(), asec = avgSec.toInt() % 60;
      _tts.speak("$km킬로미터 도달. 구간 시간 $lm분 $ls초. 평균 페이스 $am분 $asec초.");
    }
    if (!_halfAnnounced && _distanceKm >= _s.targetDistanceKm * 0.5) {
      _halfAnnounced = true;
      _tts.speak("목표의 절반을 지났습니다.");
    }
    if (!_goalAnnounced && _distanceKm >= _s.targetDistanceKm) {
      _goalAnnounced = true;
      _tts.speak("목표 거리에 도달했습니다. 운동은 계속됩니다.");
    }
  }

  // ── 다이얼로그 ────────────────────────────────────────────────────────────────

  void _showGoalSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _GoalSheet(
        settings: _s,
        onConfirm: () {
          widget.onSettingsChanged();
          Navigator.pop(context);
          setState(() {});
        },
      ),
    );
  }

  void _showSummaryDialog() {
    final dist = _distanceKm.toStringAsFixed(2);
    final time = _formattedTime;
    final pace = _avgPaceDisplay;
    final selected = <String>{};

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          backgroundColor: _s.preset.surface,
          title: const Text("운동 완료", style: TextStyle(fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _summaryRow("거리", "$dist km"),
              _summaryRow("시간", time),
              _summaryRow("평균 페이스", "$pace /km"),
              const SizedBox(height: 20),
              Divider(color: _s.preset.onSurface.withValues(alpha: 0.12)),
              const SizedBox(height: 12),
              Text(
                "불편한 부위가 있나요?",
                style: TextStyle(fontSize: 13, color: _s.preset.onSurface.withValues(alpha: 0.54)),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _stretchParts.map((part) {
                  final on = selected.contains(part);
                  return GestureDetector(
                    onTap: () => setDlgState(() {
                      if (on) { selected.remove(part); } else { selected.add(part); }
                    }),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                      decoration: BoxDecoration(
                        color: on ? _s.accent : Colors.transparent,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                            color: on ? _s.accent : _s.preset.onSurface.withValues(alpha: 0.24)),
                      ),
                      child: Text(
                        part,
                        style: TextStyle(
                          fontSize: 13,
                          color: on ? Colors.white : _s.preset.onSurface.withValues(alpha: 0.54),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
              if (selected.isNotEmpty) ...[
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: _s.accent),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    onPressed: () => _openStretchYoutube(selected.toList()),
                    icon: Icon(Icons.play_circle_outline,
                        size: 18, color: _s.accent),
                    label: Text("김병곤 스트레칭 보기",
                        style: TextStyle(color: _s.accent)),
                  ),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                _resetWorkout();
              },
              child: Text("확인", style: TextStyle(color: _s.accent, fontSize: 16)),
            ),
          ],
        ),
      ),
    );
  }

  // ── 헬퍼 ─────────────────────────────────────────────────────────────────────

  // 운동 중 중앙 큰 숫자에 표시할 값 (탭으로 순환되는 모드에 따라 결정)
  String get _mainDisplayValue {
    switch (_mainDisplayMode) {
      case 1:
        return _formattedTime;
      case 2:
        return '${_s.bpm}';
      default:
        return _distanceKm.toStringAsFixed(2);
    }
  }

  String get _formattedTime {
    final m = _seconds ~/ 60, s = _seconds % 60;
    return "${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}";
  }

  String get _avgPaceDisplay {
    if (_distanceKm < 0.01) return "--'--\"";
    final ps = _seconds / _distanceKm;
    final m = ps ~/ 60, s = ps.toInt() % 60;
    return "$m'${s.toString().padLeft(2, '0')}\"";
  }

  // ── build ─────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    switch (_workoutState) {
      case WorkoutState.idle:
        return _buildPreRunScreen();
      case WorkoutState.countdown:
        return _buildCountdownScreen();
      case WorkoutState.running:
      case WorkoutState.paused:
        return _buildRunningScreen();
    }
  }

  // ┌────────────────────────────────────────────────────────┐
  // │  1. 시작 전 화면 — 테마 배경색, 지도 없음               │
  // └────────────────────────────────────────────────────────┘
  Widget _buildPreRunScreen() {
    return Scaffold(
      backgroundColor: _s.preset.background,
      body: SafeArea(
        child: Column(
          children: [
            // 상단 바
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 8, 0),
              child: Row(
                children: [
                  Text(
                    "달팽이 러닝",
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: _s.preset.onBackground,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: widget.onGoToSettings,
                    icon: Icon(Icons.settings_outlined,
                        color: _s.preset.onBackground.withValues(alpha: 0.7), size: 26),
                  ),
                ],
              ),
            ),

            const Spacer(flex: 3),

            // 목표 표시 (탭하여 변경)
            GestureDetector(
              onTap: _showGoalSheet,
              child: Column(
                children: [
                  Text(
                    _s.goalType == GoalType.distance ? '목표 거리' : '목표 시간',
                    style: TextStyle(
                      fontSize: 13,
                      color: _s.preset.onBackground.withValues(alpha: 0.38),
                      letterSpacing: 3,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _s.goalType == GoalType.distance
                        ? _s.targetDistanceKm.toStringAsFixed(1)
                        : '${_s.targetTimeMinutes}',
                    style: TextStyle(
                      fontSize: 96,
                      fontWeight: FontWeight.w800,
                      color: _s.preset.onBackground,
                      height: 1.0,
                      letterSpacing: -4,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _s.goalType == GoalType.distance ? 'km' : '분',
                    style: TextStyle(
                      fontSize: 20,
                      color: _s.preset.onBackground.withValues(alpha: 0.54),
                      letterSpacing: 6,
                      fontWeight: FontWeight.w300,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                    decoration: BoxDecoration(
                      color: _s.preset.onBackground.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: _s.preset.onBackground.withValues(alpha: 0.12)),
                    ),
                    child: Text(
                      "탭하여 목표 변경",
                      style: TextStyle(fontSize: 12, color: _s.preset.onBackground.withValues(alpha: 0.38)),
                    ),
                  ),
                ],
              ),
            ),

            const Spacer(flex: 4),

            // 시작 버튼 (큰 원형)
            Padding(
              padding: const EdgeInsets.only(bottom: 52),
              child: GestureDetector(
                onTap: _startCountdown,
                child: Container(
                  width: 88,
                  height: 88,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _s.accent,
                    boxShadow: [
                      BoxShadow(
                        color: _s.accent.withValues(alpha: 0.4),
                        blurRadius: 24,
                        spreadRadius: 6,
                      ),
                    ],
                  ),
                  child: const Center(
                    child: Icon(Icons.play_arrow_rounded, size: 52, color: Colors.white),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ┌────────────────────────────────────────────────────────┐
  // │  2. 카운트다운 화면 — 검정 배경, 3·2·1                   │
  // └────────────────────────────────────────────────────────┘
  Widget _buildCountdownScreen() {
    return Scaffold(
      backgroundColor: _s.preset.background,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              transitionBuilder: (child, anim) => ScaleTransition(
                scale: Tween<double>(begin: 0.4, end: 1.0).animate(
                  CurvedAnimation(parent: anim, curve: Curves.easeOutBack),
                ),
                child: FadeTransition(opacity: anim, child: child),
              ),
              child: Text(
                '$_countdownValue',
                key: ValueKey(_countdownValue),
                style: TextStyle(
                  fontSize: 200,
                  fontWeight: FontWeight.w900,
                  color: _s.preset.onBackground,
                  height: 1.0,
                ),
              ),
            ),
            const SizedBox(height: 36),
            Text(
              '준비...',
              style: TextStyle(
                fontSize: 20,
                color: _s.preset.onBackground.withValues(alpha: 0.3),
                letterSpacing: 6,
                fontWeight: FontWeight.w300,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ┌────────────────────────────────────────────────────────┐
  // │  3. 주행 중 화면 — 지도 배경 + 테마 오버레이             │
  // └────────────────────────────────────────────────────────┘
  Widget _buildRunningScreen() {
    final isPaused = _workoutState == WorkoutState.paused;

    return Scaffold(
      body: Stack(
        children: [
          // ── 배경: 다크 지도 (주행 시작 후에만 렌더링) ───────
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _mapCenter,
              initialZoom: 15.5,
              interactionOptions: const InteractionOptions(flags: InteractiveFlag.none),
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://basemaps.cartocdn.com/light_all/{z}/{x}/{y}.png',
                userAgentPackageName: 'snail_running',
              ),
              if (_hasLocation)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: _mapCenter,
                      child: Container(
                        width: 14,
                        height: 14,
                        decoration: BoxDecoration(
                          color: _s.accent,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                      ),
                    ),
                  ],
                ),
            ],
          ),

          // ── 테마 그라디언트 오버레이 (지도가 중앙에서 비침) ──
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  _s.preset.runGradient[0].withValues(alpha: 0.90),
                  _s.preset.runGradient[1].withValues(alpha: 0.55),
                  _s.preset.runGradient[2].withValues(alpha: 0.93),
                ],
                stops: const [0.0, 0.5, 1.0],
              ),
            ),
          ),

          // ── UI 콘텐츠 ────────────────────────────────────────
          SafeArea(
            child: Column(
              children: [
                // ── 상단 메트릭 3개 ──────────────────────────────
                _buildMetricsRow(),

                Container(height: 1, color: _s.preset.divider),

                // ── 중앙: 거리 (가장 크고 굵게) ──────────────────
                Expanded(
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (isPaused) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
                            decoration: BoxDecoration(
                              color: _s.preset.accent.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                  color: _s.preset.accent.withValues(alpha: 0.35)),
                            ),
                            child: Text(
                              "일시정지",
                              style: TextStyle(
                                  color: _s.preset.accent,
                                  fontSize: 12,
                                  letterSpacing: 3),
                            ),
                          ),
                          const SizedBox(height: 20),
                        ],
                        GestureDetector(
                          onTap: _cycleMainDisplay,
                          behavior: HitTestBehavior.opaque,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                _mainDisplayValue,
                                style: TextStyle(
                                  fontSize: 100,
                                  fontWeight: FontWeight.w800,
                                  color: _s.preset.onRun,
                                  letterSpacing: -5,
                                  height: 1.0,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                _mainDisplayLabels[_mainDisplayMode],
                                style: TextStyle(
                                  fontSize: 22,
                                  color: _s.preset.onRun.withValues(alpha: 0.3),
                                  letterSpacing: 10,
                                  fontWeight: FontWeight.w200,
                                ),
                              ),
                              const SizedBox(height: 14),
                              // 현재 표시 모드 인디케이터 (거리/시간/BPM 중 어디인지)
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: List.generate(_mainDisplayLabels.length, (i) {
                                  final active = i == _mainDisplayMode;
                                  return AnimatedContainer(
                                    duration: const Duration(milliseconds: 200),
                                    margin: const EdgeInsets.symmetric(horizontal: 3),
                                    width: active ? 16 : 6,
                                    height: 6,
                                    decoration: BoxDecoration(
                                      color: active
                                          ? _s.preset.accent
                                          : _s.preset.onRun.withValues(alpha: 0.25),
                                      borderRadius: BorderRadius.circular(3),
                                    ),
                                  );
                                }),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // ── 하단 컨트롤 ─────────────────────────────────
                Padding(
                  padding: const EdgeInsets.only(bottom: 56),
                  child: isPaused ? _buildPausedControls() : _buildRunningControl(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricsRow() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Expanded(child: _metricItem('페이스', _avgPaceDisplay)),
          Container(width: 1, height: 32, color: _s.preset.divider),
          Expanded(child: _metricItem('BPM', '${_s.bpm}')),
          Container(width: 1, height: 32, color: _s.preset.divider),
          Expanded(child: _metricItem('시간', _formattedTime)),
        ],
      ),
    );
  }

  Widget _metricItem(String label, String value) {
    final onRun = _s.preset.onRun;
    return Column(
      children: [
        Text(label,
            style: TextStyle(
                fontSize: 11,
                color: onRun.withValues(alpha: 0.5),
                letterSpacing: 1)),
        const SizedBox(height: 4),
        Text(value,
            style: TextStyle(
              fontSize: 19,
              color: onRun.withValues(alpha: 0.75),
              fontWeight: FontWeight.w300,
            )),
      ],
    );
  }

  // 주행 중: 일시정지 버튼만
  Widget _buildRunningControl() {
    return GestureDetector(
      onTap: _pauseWorkout,
      child: Container(
        width: 80,
        height: 80,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: _s.accent,
          boxShadow: [BoxShadow(color: _s.accent.withValues(alpha: 0.35), blurRadius: 20, spreadRadius: 4)],
        ),
        child: const Center(
          child: Icon(Icons.pause_rounded, size: 42, color: Colors.white),
        ),
      ),
    );
  }

  // 일시정지 중: 정지(좌) + 재개(우)
  Widget _buildPausedControls() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        GestureDetector(
          onTap: _stopWorkout,
          child: Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.transparent,
              border: Border.all(color: Colors.red.shade400, width: 2),
            ),
            child: Center(child: Icon(Icons.stop_rounded, size: 32, color: Colors.red.shade400)),
          ),
        ),
        const SizedBox(width: 40),
        GestureDetector(
          onTap: _resumeWorkout,
          child: Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _s.accent,
            ),
            child: const Center(
              child: Icon(Icons.play_arrow_rounded, size: 44, color: Colors.white),
            ),
          ),
        ),
      ],
    );
  }

  Widget _summaryRow(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(color: _s.preset.grey, fontSize: 15)),
        Text(value,
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: _s.preset.onSurface)),
      ],
    ),
  );
}

// ┌────────────────────────────────────────────────────────────┐
// │  4. 목표 설정 바텀시트 — 거리/시간 선택, 숫자 크게           │
// └────────────────────────────────────────────────────────────┘
class _GoalSheet extends StatefulWidget {
  final AppSettings settings;
  final VoidCallback onConfirm;

  const _GoalSheet({required this.settings, required this.onConfirm});

  @override
  State<_GoalSheet> createState() => _GoalSheetState();
}

class _GoalSheetState extends State<_GoalSheet> {
  late GoalType _goalType;
  late double _distance;
  late int _timeMinutes;

  AppSettings get _s => widget.settings;

  @override
  void initState() {
    super.initState();
    _goalType = _s.goalType;
    _distance = _s.targetDistanceKm;
    _timeMinutes = _s.targetTimeMinutes;
  }

  String get _estimatedTime {
    final totalSec = (_distance * (_s.paceMinutes * 60 + _s.paceSeconds)).round();
    final m = totalSec ~/ 60;
    return m == 0 ? '1분 미만' : '$m분';
  }

  void _confirm() {
    _s.goalType = _goalType;
    _s.targetDistanceKm = _distance;
    _s.targetTimeMinutes = _timeMinutes;
    widget.onConfirm();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: widget.settings.preset.sheetBg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(
        top: 16,
        left: 24,
        right: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 36,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 드래그 핸들
          Container(
            width: 40, height: 4,
            decoration: BoxDecoration(
              color: widget.settings.preset.onBackground.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 24),

          Text(
            "목표 설정",
            style: TextStyle(
                fontSize: 20, fontWeight: FontWeight.w700, color: widget.settings.preset.onBackground),
          ),
          const SizedBox(height: 24),

          // 거리 / 시간 토글
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: widget.settings.preset.surface,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                _typeChip("거리", GoalType.distance),
                _typeChip("시간", GoalType.time),
              ],
            ),
          ),
          const SizedBox(height: 40),

          // 숫자 증감
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _adjBtn(Icons.remove_rounded, () {
                setState(() {
                  if (_goalType == GoalType.distance) {
                    _distance = ((_distance * 10 - 1) / 10).clamp(0.1, 100.0);
                  } else {
                    _timeMinutes = (_timeMinutes - 5).clamp(5, 300);
                  }
                });
              }),
              const SizedBox(width: 28),
              Column(
                children: [
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 150),
                    transitionBuilder: (child, anim) =>
                        FadeTransition(opacity: anim, child: child),
                    child: Text(
                      _goalType == GoalType.distance
                          ? _distance.toStringAsFixed(1)
                          : '$_timeMinutes',
                      key: ValueKey(
                          _goalType == GoalType.distance ? _distance : _timeMinutes),
                      style: TextStyle(
                        fontSize: 80,
                        fontWeight: FontWeight.w800,
                        color: widget.settings.preset.onBackground,
                        height: 1.0,
                      ),
                    ),
                  ),
                  Text(
                    _goalType == GoalType.distance ? 'km' : '분',
                    style: TextStyle(
                      fontSize: 18,
                      color: widget.settings.preset.grey,
                      letterSpacing: 3,
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 28),
              _adjBtn(Icons.add_rounded, () {
                setState(() {
                  if (_goalType == GoalType.distance) {
                    _distance = ((_distance * 10 + 1) / 10).clamp(0.1, 100.0);
                  } else {
                    _timeMinutes = (_timeMinutes + 5).clamp(5, 300);
                  }
                });
              }),
            ],
          ),
          const SizedBox(height: 16),

          // 예상 시간
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: _goalType == GoalType.distance
                ? Text(
                    "예상 운동 시간: $_estimatedTime",
                    key: const ValueKey('dist'),
                    style: TextStyle(
                        fontSize: 14, color: widget.settings.preset.grey),
                  )
                : Text(
                    "목표 시간까지 운동이 계속됩니다",
                    key: const ValueKey('time'),
                    style: TextStyle(
                        fontSize: 14, color: widget.settings.preset.grey),
                  ),
          ),
          const SizedBox(height: 32),

          // 확인 버튼
          SizedBox(
            width: double.infinity,
            height: 54,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: widget.settings.accent,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                elevation: 0,
              ),
              onPressed: _confirm,
              child: const Text(
                "확인",
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _typeChip(String label, GoalType type) {
    final selected = _goalType == type;
    final accent = widget.settings.accent;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _goalType = type),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 11),
          decoration: BoxDecoration(
            color: selected ? accent : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: selected ? Colors.white : widget.settings.preset.grey,
              fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
              fontSize: 15,
            ),
          ),
        ),
      ),
    );
  }

  Widget _adjBtn(IconData icon, VoidCallback onTap) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        color: widget.settings.preset.surface,
        shape: BoxShape.circle,
      ),
      child: Center(child: Icon(icon, color: widget.settings.preset.onSurface, size: 28)),
    ),
  );
}
