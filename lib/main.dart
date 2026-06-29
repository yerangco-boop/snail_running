import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
// 웹: dart:html AudioElement / 모바일: audioplayers — 조건부 임포트
import 'click_player_stub.dart' if (dart.library.html) 'click_player_web.dart';

// ── 색상 팔레트 ────────────────────────────────────────────────────────────────
const _kBg      = Color(0xFF000000); // OLED 블랙
const _kSurface = Color(0xFF0D1B2A); // 딥 네이비
const _kAccent  = Color(0xFF7C4DFF); // 보라 포인트
const _kGrey    = Color(0xFF8A8A8A);

// ── main ──────────────────────────────────────────────────────────────────────
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
  ));
  runApp(const SnailRunningApp());
}

// ── MetronomeService ──────────────────────────────────────────────────────────
// ClickPlayer는 조건부 임포트로 주입됨:
//   웹   → click_player_web.dart  (dart:html AudioElement)
//   모바일 → click_player_stub.dart (audioplayers)
class MetronomeService {
  final ClickPlayer _click = ClickPlayer();
  Timer? _timer;
  int _gen = 0; // race condition 방지용 세대 번호
  bool get isRunning => _timer != null;

  Future<void> init() async => _click.init();

  // playImmediately=true : 즉시 첫 박 재생 후 타이머 시작 (최초 시작 / AudioContext unlock)
  // playImmediately=false: 타이머만 시작, 즉시 재생 없음 (재개 — 박자 위상 깨짐 방지)
  Future<void> start(int bpm, {bool playImmediately = true}) async {
    stop();
    final myGen = _gen;
    final intervalMs = (60000 / bpm).round();
    final interval = Duration(milliseconds: intervalMs);
    print('[Metro] start bpm=$bpm → ${intervalMs}ms | immediate=$playImmediately | gen=$myGen');

    if (playImmediately) {
      await _click.play(); // user gesture 체인 안에서 AudioContext unlock
      if (_gen != myGen) {
        print('[Metro] gen mismatch — timer 등록 취소 ($myGen vs $_gen)');
        return;
      }
    }

    var lastMs = DateTime.now().millisecondsSinceEpoch;
    var tickCount = 0;
    _timer = Timer.periodic(interval, (_) {
      final now = DateTime.now().millisecondsSinceEpoch;
      final actual = now - lastMs;
      lastMs = now;
      tickCount++;
      if (tickCount <= 5) {
        print('[Metro] tick #$tickCount: 실제=${actual}ms (예상=${intervalMs}ms)');
      }
      _click.play();
    });
    print('[Metro] TIMER SET gen=$_gen');
  }

  void stop() {
    if (_timer != null) {
      print('[Metro] TIMER CANCEL gen=$_gen');
      _timer!.cancel();
      _timer = null;
    }
    _gen++;
  }

  Future<void> updateBpm(int bpm) async {
    if (isRunning) await start(bpm);
  }

  void dispose() {
    stop();
    _click.dispose();
  }
}

// ── App ───────────────────────────────────────────────────────────────────────
class SnailRunningApp extends StatelessWidget {
  const SnailRunningApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: _kBg,
        colorScheme: const ColorScheme.dark(
          surface: _kSurface,
          primary: _kAccent,
          secondary: _kAccent,
          onPrimary: Colors.white,
          onSurface: Colors.white,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
          systemOverlayStyle: SystemUiOverlayStyle.light,
        ),
        cardTheme: CardThemeData(
          color: _kSurface,
          elevation: 0,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      ),
      home: const RunningScreen(),
    );
  }
}

enum WorkoutState { idle, running, paused }

// ── RunningScreen ─────────────────────────────────────────────────────────────
class RunningScreen extends StatefulWidget {
  const RunningScreen({super.key});
  @override
  State<RunningScreen> createState() => _RunningScreenState();
}

class _RunningScreenState extends State<RunningScreen> {
  WorkoutState _workoutState = WorkoutState.idle;
  double _distanceKm = 0.0;
  double _targetDistanceKm = 5.0;
  int _seconds = 0;
  int _bpm = 150;
  int _paceMinutes = 8, _paceSeconds = 0;

  int _lastAnnouncedKm = 0;
  int _lapStartSeconds = 0;
  bool _halfAnnounced = false;
  bool _goalAnnounced = false;

  Timer? _workoutTimer;
  final FlutterTts _tts = FlutterTts();
  final MetronomeService _metronome = MetronomeService();

  @override
  void initState() {
    super.initState();
    _tts.setLanguage("ko-KR");
    _metronome.init();
  }

  @override
  void dispose() {
    _workoutTimer?.cancel();
    _metronome.dispose();
    super.dispose();
  }

  // ── 운동 제어 ─────────────────────────────────────────────────────────────────

  void _startWorkout() {
    setState(() => _workoutState = WorkoutState.running);
    _metronome.start(_bpm);
    _launchTimer();
  }

  void _pauseWorkout() {
    _workoutTimer?.cancel();
    _workoutTimer = null;
    _metronome.stop();
    setState(() => _workoutState = WorkoutState.paused);
  }

  void _resumeWorkout() {
    setState(() => _workoutState = WorkoutState.running);
    // playImmediately:false — 재개 시 즉시 재생 없이 타이머만 시작
    // (즉시 재생하면 정지 직전 박자와 겹쳐 BPM이 빠르게 들림)
    _metronome.start(_bpm, playImmediately: false);
    _launchTimer();
  }

  void _stopWorkout() {
    _workoutTimer?.cancel();
    _workoutTimer = null;
    _metronome.stop();
    setState(() => _workoutState = WorkoutState.idle);
    _showSummaryDialog();
  }

  void _launchTimer() {
    _workoutTimer?.cancel(); // 방어적 취소 — resume 시 이전 타이머가 살아있으면 제거
    _workoutTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() {
        _seconds++;
        final paceInSec = _paceMinutes * 60.0 + _paceSeconds;
        if (paceInSec > 0) _distanceKm += 1.0 / paceInSec;
        _checkAudioGuide();
      });
    });
  }

  void _resetWorkout() {
    setState(() {
      _distanceKm = 0.0;
      _seconds = 0;
      _lastAnnouncedKm = 0;
      _lapStartSeconds = 0;
      _halfAnnounced = false;
      _goalAnnounced = false;
    });
  }

  // ── TTS ──────────────────────────────────────────────────────────────────────

  void _checkAudioGuide() {
    final km = _distanceKm.floor();
    if (km > 0 && km > _lastAnnouncedKm) {
      final lapSec = _seconds - _lapStartSeconds;
      _lapStartSeconds = _seconds;
      _lastAnnouncedKm = km;
      final lm = lapSec ~/ 60, ls = lapSec % 60;
      final avgSec = _seconds / _distanceKm;
      final am = (avgSec ~/ 60).toInt(), asec = avgSec.toInt() % 60;
      _tts.speak(
          "${km}킬로미터 도달. 구간 시간 ${lm}분 ${ls}초. 평균 페이스 ${am}분 ${asec}초.");
    }
    if (!_halfAnnounced && _distanceKm >= _targetDistanceKm * 0.5) {
      _halfAnnounced = true;
      _tts.speak("목표의 절반을 지났습니다.");
    }
    // 무중단 원칙: 목표 도달해도 타이머/거리 계속
    if (!_goalAnnounced && _distanceKm >= _targetDistanceKm) {
      _goalAnnounced = true;
      _tts.speak("목표 거리에 도달했습니다. 운동은 계속됩니다.");
    }
  }

  // ── 다이얼로그 ────────────────────────────────────────────────────────────────

  void _showSummaryDialog() {
    final dist = _distanceKm.toStringAsFixed(2);
    final time = _formattedTime;
    final pace = _avgPaceDisplay;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: _kSurface,
        title: const Text("운동 완료",
            style: TextStyle(fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _summaryRow("거리", "$dist km"),
            _summaryRow("시간", time),
            _summaryRow("평균 페이스", "$pace /km"),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _resetWorkout();
            },
            child: const Text("확인",
                style: TextStyle(color: _kAccent, fontSize: 16)),
          ),
        ],
      ),
    );
  }

  void _showBpmDialog() {
    const bpms = [140, 150, 160, 170, 180, 190, 200];
    showDialog(
      context: context,
      builder: (_) => SimpleDialog(
        backgroundColor: _kSurface,
        title: const Text("BPM 선택"),
        children: bpms
            .map((b) => SimpleDialogOption(
                  onPressed: () {
                    setState(() => _bpm = b);
                    _metronome.updateBpm(b);
                    Navigator.pop(context);
                  },
                  child: Text("$b BPM",
                      style: TextStyle(
                        fontWeight:
                            b == _bpm ? FontWeight.bold : FontWeight.normal,
                        color: b == _bpm ? _kAccent : Colors.white,
                        fontSize: 16,
                      )),
                ))
            .toList(),
      ),
    );
  }

  void _showDistanceDialog() {
    final ctrl =
        TextEditingController(text: _targetDistanceKm.toStringAsFixed(1));
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: _kSurface,
        title: const Text("목표 거리 (km)"),
        content: TextField(
          controller: ctrl,
          keyboardType:
              const TextInputType.numberWithOptions(decimal: true),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () {
              final v = double.tryParse(ctrl.text);
              if (v != null && v > 0) {
                setState(() {
                  _targetDistanceKm = v;
                  _halfAnnounced = _distanceKm >= v * 0.5;
                  _goalAnnounced = _distanceKm >= v;
                });
              }
              Navigator.pop(context);
            },
            child: const Text("확인", style: TextStyle(color: _kAccent)),
          ),
        ],
      ),
    );
  }

  void _showPaceDialog() {
    final mCtrl = TextEditingController(text: '$_paceMinutes');
    final sCtrl = TextEditingController(
        text: _paceSeconds.toString().padLeft(2, '0'));
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: _kSurface,
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
              final m = (int.tryParse(mCtrl.text) ?? _paceMinutes)
                  .clamp(4, 20);
              final s = (int.tryParse(sCtrl.text) ?? _paceSeconds)
                  .clamp(0, 59);
              setState(() {
                _paceMinutes = m;
                _paceSeconds = s;
              });
              Navigator.pop(context);
            },
            child: const Text("확인", style: TextStyle(color: _kAccent)),
          ),
        ],
      ),
    );
  }

  // ── 헬퍼 ─────────────────────────────────────────────────────────────────────

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

  String get _paceLabel =>
      "$_paceMinutes:${_paceSeconds.toString().padLeft(2, '0')}/km";

  // ── build ─────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _workoutState == WorkoutState.idle
          ? _buildIdleScreen()
          : _buildActiveScreen(),
    );
  }

  // ┌─────────────────────────────────────────────────────┐
  // │  시작 전 화면 — SJP 스타일 (딥 네이비 카드 + 알약 버튼) │
  // └─────────────────────────────────────────────────────┘
  Widget _buildIdleScreen() {
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 타이틀
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Text("슬로우 조깅",
                    style: TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.bold,
                        color: Colors.white)),
                SizedBox(height: 4),
                Text("오늘 운동을 시작해보세요",
                    style: TextStyle(fontSize: 15, color: _kGrey)),
              ],
            ),
          ),
          const SizedBox(height: 28),

          // 세션 설정 카드
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                children: [
                  _settingCard(
                    icon: Icons.flag_outlined,
                    label: "목표 거리",
                    value: "${_targetDistanceKm.toStringAsFixed(1)} km",
                    onTap: _showDistanceDialog,
                  ),
                  const SizedBox(height: 12),
                  _settingCard(
                    icon: Icons.speed_outlined,
                    label: "페이스",
                    value: _paceLabel,
                    onTap: _showPaceDialog,
                  ),
                  const SizedBox(height: 12),
                  _settingCard(
                    icon: Icons.music_note_outlined,
                    label: "BPM (메트로놈)",
                    value: "$_bpm",
                    onTap: _showBpmDialog,
                  ),
                ],
              ),
            ),
          ),

          // 시작 버튼 (알약 모양)
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 40),
            child: SizedBox(
              height: 60,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: _kAccent,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30)),
                ),
                onPressed: _startWorkout,
                child: const Text("시작",
                    style: TextStyle(
                        fontSize: 22, fontWeight: FontWeight.bold)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ┌─────────────────────────────────────────────────────┐
  // │  운동 중 화면 — Nike Run Club 스타일 (풀블랙, 거리 중앙) │
  // └─────────────────────────────────────────────────────┘
  Widget _buildActiveScreen() {
    final isRunning = _workoutState == WorkoutState.running;

    return SafeArea(
      child: Column(
        children: [
          // ── 상단 뱃지 바 ──────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _infoBadge("♪ $_bpm BPM"),
                _workoutState == WorkoutState.paused
                    ? _pausedBadge()
                    : _infoBadge(
                        "목표 ${_targetDistanceKm.toStringAsFixed(1)} km"),
              ],
            ),
          ),

          // ── 중앙 주요 수치 ─────────────────────────────────────
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // 거리 숫자 (아주 크게)
                Text(
                  _distanceKm.toStringAsFixed(2),
                  style: const TextStyle(
                    fontSize: 84,
                    fontWeight: FontWeight.w200,
                    letterSpacing: -3,
                    height: 1.0,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 2),
                const Text("km",
                    style: TextStyle(
                        fontSize: 18,
                        color: _kGrey,
                        letterSpacing: 6,
                        fontWeight: FontWeight.w300)),

                const SizedBox(height: 40),

                // 경과 시간
                Text(
                  _formattedTime,
                  style: const TextStyle(
                      fontSize: 38,
                      fontWeight: FontWeight.w300,
                      color: Colors.white70),
                ),
                const SizedBox(height: 8),

                // 평균 페이스
                Text(
                  "평균  $_avgPaceDisplay /km",
                  style: const TextStyle(fontSize: 17, color: _kGrey),
                ),
              ],
            ),
          ),

          // ── 하단 컨트롤 버튼 ────────────────────────────────────
          Padding(
            padding: const EdgeInsets.only(bottom: 52),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildStopBtn(),
                const SizedBox(width: 44),
                isRunning ? _buildPauseBtn() : _buildResumeBtn(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── 위젯 헬퍼 ─────────────────────────────────────────────────────────────────

  Widget _settingCard({
    required IconData icon,
    required String label,
    required String value,
    required VoidCallback onTap,
  }) =>
      InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
          decoration: BoxDecoration(
            color: _kSurface,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              Icon(icon, color: _kAccent, size: 22),
              const SizedBox(width: 16),
              Text(label, style: const TextStyle(fontSize: 16)),
              const Spacer(),
              Text(value,
                  style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white)),
              const SizedBox(width: 8),
              const Icon(Icons.chevron_right, color: _kGrey, size: 18),
            ],
          ),
        ),
      );

  Widget _infoBadge(String text) => Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: _kSurface,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(text,
            style:
                const TextStyle(fontSize: 13, color: Colors.white70)),
      );

  Widget _pausedBadge() => Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: Colors.amber.shade900.withOpacity(0.35),
          borderRadius: BorderRadius.circular(20),
        ),
        child: const Text("일시정지",
            style: TextStyle(color: Colors.amber, fontSize: 13)),
      );

  // 일시정지 버튼 (노란 원형)
  Widget _buildPauseBtn() => GestureDetector(
        onTap: _pauseWorkout,
        child: Container(
          width: 130,
          height: 130,
          decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.amber.shade700),
          child: const Center(
              child: Icon(Icons.pause, size: 56, color: Colors.white)),
        ),
      );

  // 재개 버튼 (보라 원형)
  Widget _buildResumeBtn() => GestureDetector(
        onTap: _resumeWorkout,
        child: Container(
          width: 130,
          height: 130,
          decoration: const BoxDecoration(
              shape: BoxShape.circle, color: _kAccent),
          child: const Center(
              child: Icon(Icons.play_arrow,
                  size: 56, color: Colors.white)),
        ),
      );

  // 정지 버튼 (작은 원형, 빨간 테두리)
  Widget _buildStopBtn() => GestureDetector(
        onTap: _stopWorkout,
        child: Container(
          width: 76,
          height: 76,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _kSurface,
            border: Border.all(color: Colors.red.shade400, width: 2.5),
          ),
          child: Center(
              child:
                  Icon(Icons.stop, size: 36, color: Colors.red.shade400)),
        ),
      );

  Widget _summaryRow(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label,
                style: const TextStyle(color: _kGrey, fontSize: 15)),
            Text(value,
                style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                    color: Colors.white)),
          ],
        ),
      );
}
