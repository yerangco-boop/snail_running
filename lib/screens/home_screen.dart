import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/app_settings.dart';
import '../models/workout_record.dart';
import '../services/metronome_service.dart';
import '../services/database_service.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../services/weather_service.dart';
import '../services/file_logger.dart';
import '../services/location_settings_factory.dart';
import '../utils/route_utils.dart';

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

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  WorkoutState _workoutState = WorkoutState.idle;
  double _distanceKm = 0.0;
  int _seconds = 0;
  int _countdownValue = 3;

  // 운동 중 중앙 큰 숫자 표시 모드: 0=거리, 1=시간, 2=케이던스, 3=kcal (탭할 때마다 순환)
  int _mainDisplayMode = 0;
  static const List<String> _mainDisplayLabels = ['km', '시간', '케이던스', 'kcal', '바퀴'];

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
  LatLng? _lastGpsPoint; // 마지막으로 거리 누적에 반영된 지점 (원시 좌표)
  DateTime? _lastGpsTime;
  static const int _gpsAccuracyThresholdMeters = 35; // 이보다 부정확한 측위는 거리 누적에서 제외
  static const double _maxPlausibleSpeedKmh = 25.0; // 이보다 빠른 순간 속도는 GPS 튐으로 간주 (아래 "캡" 참고)
  // 연속으로 정확도 기준을 못 넘는 상태가 몇 초나 지속되는지 진단하기 위한 카운터
  int _gpsRejectStreak = 0;
  DateTime? _gpsRejectStreakStart;
  double _lastGpsAccuracyMeters = 20.0;
  // 이번 운동 전체 누적 거부 포인트 수 — 나이키런 대비 거리 과소측정 진단용.
  // 매 accepted 포인트 로그에도 함께 남겨, "지금까지 몇 개나 버려졌는지"를
  // 특정 구간만 보지 않고도 로그 파일 전체에서 추적할 수 있게 함
  int _gpsRejectedTotal = 0;
  int _gpsAcceptedTotal = 0;
  // 콜백 간격이 이보다 짧으면 순간속도 계산을 건너뜀 — distanceFilter가 촘촘해서(1m)
  // 아주 짧은 시간차에 콜백이 몰릴 때는 정상적인 GPS 잡음(2~5m)만으로도 순간속도가
  // 크게 튀어 오탐하기 쉬움
  static const double _minGpsIntervalSec = 0.5;

  // 최근 스무딩된 좌표(지수이동평균, EMA) — 고정 구간 박스평균과 달리 지연이 적어
  // 곡선(트랙 등)에서 경로가 안쪽으로 당겨지며 실제보다 짧게 잡히는 현상을 줄여줌
  LatLng? _emaPoint;
  static const double _emaAlpha = 0.4;

  // ── 바퀴 수 자동 감지 (루프 코스용) ────────────────────────────────────────
  // 운동 시작 지점에서 일정 거리 이상 멀어졌다가 다시 근처로 돌아오면 1바퀴로 카운트.
  // 편도 코스(A→B)에서는 시작 지점으로 돌아올 일이 없으니 그냥 0(또는 1)에 머물 뿐,
  // 별도 처리 없이도 안전하게 무해함.
  LatLng? _lapStartPoint;
  int _lapCount = 0;
  bool _hasLeftLapZone = false;
  // ── 임계값 재산정 (2026-08-10) ──────────────────────────────────────────────
  // 실측 트랙 둘레 240~250m를 정삼각형으로 근사하면 한 변이 80~83m.
  // 시작점(꼭짓점)에서 코스상 가장 먼 지점까지의 직선거리는 "반대편 꼭짓점 = 한 변(80m)"이고
  // 반대편 변의 중점까지는 삼각형 높이(69m)임. 즉 기존 임계값 80m는 둘레 240m에서
  // 물리적으로 초과 불가(정확히 80.0m가 최대)라 "충분히 멀어짐" 조건이 영영 안 걸렸음
  // → 랩이 항상 0으로 나오던 근본 원인. 여유를 두고 40m로 하향.
  static const double _lapMinAwayMeters = 40.0;
  // 복귀 판정 반경: 아웃존(40m)의 절반 이하로 두어 히스테리시스를 확보
  static const double _lapReturnRadiusMeters = 18.0;
  // 같은 지점을 GPS 잡음으로 여러 번 스쳐도 중복 카운트되지 않도록 하는 최소 랩 간격
  static const int _lapMinIntervalSeconds = 60;

  // 바퀴가 카운트된 지점들 — 지도에 마커로 표시하고 기록 저장 시 함께 보존
  final List<LatLng> _lapCompletionPoints = [];
  // 각 랩이 완료된 시점의 누적 경과초 — 이력 상세에서 랩별 구간 기록으로 표시
  final List<int> _lapSplitSeconds = [];
  // 이번 랩에서 시작점으로부터 실제로 도달한 최대 이격거리(진단 로그용 — 임계값이
  // 코스 크기에 맞는지 로그만 보고 판단할 수 있게 함)
  double _lapMaxAwayMeters = 0.0;
  int _lastLapSeconds = 0;

  LatLng _applyEma(LatLng raw) {
    final prev = _emaPoint;
    if (prev == null) return raw;
    return LatLng(
      prev.latitude + _emaAlpha * (raw.latitude - prev.latitude),
      prev.longitude + _emaAlpha * (raw.longitude - prev.longitude),
    );
  }

  // 지도에 그릴 주행 경로
  final List<LatLng> _routePoints = [];

  // ── 케이던스(걸음수/분) — 가속도계 피크 감지 방식 ─────────────────────────
  StreamSubscription<UserAccelerometerEvent>? _accelSub;
  int _totalSteps = 0;
  int _lapStepsAtLastKm = 0;
  DateTime? _lastStepAt;
  bool _belowStepThreshold = true; // 상승 엣지 감지용: 직전 샘플이 임계값 이하였는지
  // 2026-08-10 하향: 폰을 손에 들고 뛰면 손이 완충 역할을 해서 기기에 실제로 실리는
  // 진폭이 작고, 아래 저역통과 필터가 피크를 추가로 깎음. 1.2 m/s²에서는 실외 러닝 내내
  // 임계값 통과가 거의 안 잡혀 케이던스가 2~7spm(나이키 132~148spm)으로 측정됐음
  static const double _stepMagnitudeThreshold = 0.35; // m/s²
  static const int _minStepIntervalMs = 250; // 분당 최대 240보 한도로 노이즈 중복 감지 방지

  // 3Hz 1차 저역통과(IIR) — 팔 흔들림/노면 충격의 고주파 성분을 걷어내고 걸음 주기만 남김.
  // alpha = dt/(RC+dt), RC = 1/(2πfc). 50Hz 샘플링(dt=0.02s), fc=3Hz → 0.2738.
  // 러닝 케이던스 160spm은 2.67Hz라 컷오프 아래이므로 걸음 신호 자체는 보존됨
  static const double _stepFilterAlpha = 0.2738;
  double _filteredMag = 0.0;

  // 평균 케이던스 계산용 — 스트림이 끊기거나 정지해 있던 0spm 구간을 분모에서 빼야
  // 실제로 뛴 구간의 평균이 나옴(예전엔 이 구간들이 평균을 27spm까지 끌어내렸음)
  int _cadenceActiveSeconds = 0;

  // 진단용: 실제로 들어온 가속도계 이벤트 수 vs 임계값을 넘은 수를 구분해서 남겨야
  // "스트림 자체가 죽었다"와 "임계값이 너무 높아 걸음을 못 잡는다"를 로그로 구별할 수 있음
  int _accelEventCount = 0;
  double _windowMagMin = double.infinity;
  double _windowMagMax = 0;
  Timer? _cadenceDiagnosticTimer;

  // 최근 걸음 시각(실시간 케이던스 롤링 윈도우 계산용)
  final List<DateTime> _recentStepTimestamps = [];
  static const int _cadenceWindowSeconds = 12; // 10~15초 롤링 윈도우

  // 최근 윈도우 기준 실시간 케이던스(분당 걸음수)
  int get _liveCadenceSpm {
    final cutoff = DateTime.now().subtract(const Duration(seconds: _cadenceWindowSeconds));
    _recentStepTimestamps.removeWhere((t) => t.isBefore(cutoff));
    if (_recentStepTimestamps.isEmpty) return 0;
    final spanSeconds =
        DateTime.now().difference(_recentStepTimestamps.first).inMilliseconds / 1000.0;
    final effectiveSpan = spanSeconds < 1 ? 1.0 : spanSeconds;
    return (_recentStepTimestamps.length / (effectiveSpan / 60.0)).round();
  }

  AppSettings get _s => widget.settings;

  String? _appliedTtsVoiceName;
  bool? _appliedMixSetting;

  // ── 날씨 ─────────────────────────────────────────────────────────────────
  final WeatherService _weatherService = WeatherService();
  WeatherSnapshot? _weather;
  bool _weatherLoading = true;
  WeatherSnapshot? _workoutStartWeather; // 운동 시작 시점 스냅샷 (기록 저장용)

  // 날씨가 실제로 "지금 있는 위치" 기준인지 확인할 수 있도록 역지오코딩한 지명
  String? _locationName;

  Future<void> _fetchWeather() async {
    setState(() => _weatherLoading = true);
    // 위치를 이미 구했다면(_fetchLocation 완료) 그 좌표를 그대로 사용 —
    // 제주도는 해안/중산간/산간 기상차가 커서 실제 뛰는 위치 기준이어야 함
    final snapshot = await _weatherService.fetchCurrentWeather(
      lat: _hasLocation ? _mapCenter.latitude : null,
      lon: _hasLocation ? _mapCenter.longitude : null,
    );
    if (!mounted) return;
    setState(() {
      _weather = snapshot;
      _weatherLoading = false;
    });
  }

  // 좌표 → 지명(시/동) 역지오코딩. 웹/플랫폼 미지원이거나 실패하면 조용히 무시
  Future<void> _reverseGeocode() async {
    if (!_hasLocation) return;
    try {
      final placemarks =
          await placemarkFromCoordinates(_mapCenter.latitude, _mapCenter.longitude);
      if (placemarks.isEmpty || !mounted) return;
      setState(() => _locationName = _buildLocationName(placemarks.first));
    } catch (e) {
      debugPrint('[Geocode] 역지오코딩 실패: $e');
    }
  }

  // 시/동(subLocality)이 비어있는 기기가 있어, locality 기준으로 단계적으로
  // 폴백해서 최대한 구체적인 지명을 구성 (예: "충주시 목행동", 안 되면 "충주시 OO로")
  String? _buildLocationName(Placemark p) {
    final locality = p.locality?.trim();
    final subLocality = p.subLocality?.trim();
    final thoroughfare = p.thoroughfare?.trim();
    final admin = p.administrativeArea?.trim();

    if (locality != null && locality.isNotEmpty) {
      if (subLocality != null && subLocality.isNotEmpty) return '$locality $subLocality';
      if (thoroughfare != null && thoroughfare.isNotEmpty) return '$locality $thoroughfare';
      return locality;
    }
    return (admin != null && admin.isNotEmpty) ? admin : null;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    FileLogger.instance.init();
    _tts.setLanguage("ko-KR");
    _applyTtsVoice();
    _appliedMixSetting = _s.mixWithOtherAudio;
    _metronome.init(mixWithOtherAudio: _s.mixWithOtherAudio);
    // 위치를 먼저 구한 뒤 그 좌표로 날씨를 조회 (위치 조회 실패해도 fetchLocation이
    // 내부에서 예외를 삼키므로 이어서 항상 폴백 좌표로 날씨 조회가 진행됨)
    _fetchLocation().then((_) {
      _reverseGeocode();
      _fetchWeather();
    });
  }

  // 사용자가 설정 앱에서 "항상 허용"으로 바꾸고 돌아오면 경고 배너가 즉시 사라지도록
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) _refreshPermissionStatus();
  }

  @override
  void didUpdateWidget(covariant HomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_appliedTtsVoiceName != _s.ttsVoiceName) {
      _applyTtsVoice();
    }
    if (_appliedMixSetting != _s.mixWithOtherAudio) {
      _appliedMixSetting = _s.mixWithOtherAudio;
      _metronome.init(mixWithOtherAudio: _s.mixWithOtherAudio);
    }
  }

  // ttsVoiceName(설정에서 직접 고른 음성)에 맞는 음성을 적용. 선택된 음성이 없거나
  // 더 이상 목록에 없으면 Google 계열 우선, 없으면 첫 한국어 음성으로 폴백
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

      _appliedTtsVoiceName = _s.ttsVoiceName;
      Map? match;
      if (_s.ttsVoiceName != null) {
        match = koreanVoices.firstWhere(
          (v) => v['name']?.toString() == _s.ttsVoiceName,
          orElse: () => {},
        );
        if (match.isEmpty) match = null;
      }
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
    _accelSub?.cancel();
    _cadenceDiagnosticTimer?.cancel();
    _metronome.dispose();
    _mapController.dispose();
    WidgetsBinding.instance.removeObserver(this);
    WakelockPlus.disable();
    super.dispose();
  }

  // 러닝 중 화면 꺼짐 방지 — 설정에서 끌 수 있게 하되 기본은 ON
  Future<void> _applyWakelock(bool enable) async {
    try {
      if (enable && _s.keepScreenOn) {
        await WakelockPlus.enable();
      } else {
        await WakelockPlus.disable();
      }
    } catch (e) {
      debugPrint('[Wakelock] 적용 실패: $e');
    }
  }

  // ── 위치 권한 ─────────────────────────────────────────────────────────────
  // Android 11+는 "항상 허용"(always)을 한 번의 다이얼로그로 못 받음 — 먼저 whileInUse를
  // 받은 뒤 별도 요청을 해야 하고, 그마저도 대부분 기기에서 시스템이 다이얼로그 대신
  // 앱 설정으로 유도함. 그래서 "단계적 요청 시도 + 실패 시 설정 딥링크 배너" 두 경로를 모두 둠.
  LocationPermission? _locationPermission;
  bool get _hasAlwaysLocation => _locationPermission == LocationPermission.always;

  Future<LocationPermission> _ensureLocationPermission({bool wantAlways = false}) async {
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission(); // 1단계: whileInUse
    }
    // 2단계: whileInUse가 승인된 뒤에만 always 승격 요청이 의미 있음(Android 11+ 요구 순서)
    if (wantAlways && perm == LocationPermission.whileInUse) {
      final upgraded = await Geolocator.requestPermission();
      if (upgraded == LocationPermission.always) perm = upgraded;
    }
    if (mounted) setState(() => _locationPermission = perm);
    FileLogger.instance.log('[Perm] 위치 권한 상태: $perm (wantAlways=$wantAlways)');
    return perm;
  }

  Future<void> _refreshPermissionStatus() async {
    final perm = await Geolocator.checkPermission();
    if (mounted) setState(() => _locationPermission = perm);
  }

  Future<void> _fetchLocation() async {
    try {
      final perm = await _ensureLocationPermission();
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
    _applyWakelock(true);
    _workoutStartWeather = _weather;
    _announceWorkoutStart();
    _metronome.start(_s.bpm);
    _lastGpsPoint = null;
    _lastGpsTime = null;
    _emaPoint = null;
    _gpsRejectStreak = 0;
    _gpsRejectStreakStart = null;
    _gpsRejectedTotal = 0;
    _gpsAcceptedTotal = 0;
    _lapStartPoint = null;
    _lapCount = 0;
    _hasLeftLapZone = false;
    _lapCompletionPoints.clear();
    _lapSplitSeconds.clear();
    _lapMaxAwayMeters = 0.0;
    _lastLapSeconds = 0;
    await _startGpsTracking();
    _startStepDetection();
    _launchTimer();
  }

  void _startStepDetection() {
    _accelSub?.cancel();
    _cadenceDiagnosticTimer?.cancel();
    _lastStepAt = null;
    _belowStepThreshold = true;
    _accelEventCount = 0;
    _windowMagMin = double.infinity;
    _windowMagMax = 0;
    _filteredMag = 0.0;

    // 10초마다 "수신 이벤트 수 vs 임계값 통과 수 vs 그 구간 mag 범위"를 요약 — 스트림이
    // 죽었다면 이벤트=0으로 바로 드러나고, 스트림은 살아있는데 걸음만 못 잡는 거라면
    // mag 최댓값이 임계값 근처에서 못 넘는 패턴으로 드러남
    var lastLoggedEventCount = 0;
    var lastLoggedSteps = _totalSteps;
    _cadenceDiagnosticTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      final eventsInWindow = _accelEventCount - lastLoggedEventCount;
      final stepsInWindow = _totalSteps - lastLoggedSteps;
      final magRange = _windowMagMin.isFinite
          ? '${_windowMagMin.toStringAsFixed(3)}~${_windowMagMax.toStringAsFixed(3)}'
          : '(이벤트 없음)';
      FileLogger.instance.log(
        '[CADENCE] 10초 요약 | 수신이벤트=$eventsInWindow개 임계값통과=$stepsInWindow개 '
        '구간filtered_mag범위=${magRange}m/s² (임계값=$_stepMagnitudeThreshold) '
        '실시간=${_liveCadenceSpm}spm 누적걸음=$_totalSteps 활성구간=${_cadenceActiveSeconds}s',
      );
      lastLoggedEventCount = _accelEventCount;
      lastLoggedSteps = _totalSteps;
      _windowMagMin = double.infinity;
      _windowMagMax = 0;
    });

    _accelSub = userAccelerometerEventStream(
      samplingPeriod: SensorInterval.gameInterval, // 50Hz(20ms) — 상승 엣지 감지에 충분한 해상도
    ).listen(
      (e) {
        _accelEventCount++;
        final rawMag = math.sqrt(e.x * e.x + e.y * e.y + e.z * e.z);
        // 3Hz 저역통과로 고주파 잡음 제거 후 그 결과에 임계값을 적용
        _filteredMag += _stepFilterAlpha * (rawMag - _filteredMag);
        final mag = _filteredMag;
        if (mag < _windowMagMin) _windowMagMin = mag;
        if (mag > _windowMagMax) _windowMagMax = mag;
        final now = DateTime.now();
        final isAbove = mag > _stepMagnitudeThreshold;
        // 임계값을 "넘는 순간"(상승 엣지)에만 걸음으로 카운트 — 신호가 임계값 위에
        // 머무는 동안 여러 샘플이 들어와도 한 걸음으로만 잡히도록 함(디바운스만으로는
        // 임계값 근처에서 값이 미세하게 떨릴 때 중복 카운트될 여지가 있었음)
        if (isAbove &&
            _belowStepThreshold &&
            (_lastStepAt == null ||
                now.difference(_lastStepAt!).inMilliseconds > _minStepIntervalMs)) {
          _lastStepAt = now;
          _totalSteps++;
          _recentStepTimestamps.add(now);
        }
        _belowStepThreshold = !isAbove;
      },
      onError: (Object error, StackTrace stack) {
        FileLogger.instance.log('[CADENCE] 가속도계 스트림 에러: $error');
      },
      onDone: () {
        FileLogger.instance.log('[CADENCE] 가속도계 스트림 종료(onDone) — totalSteps=$_totalSteps 시점에 중단됨');
      },
      cancelOnError: false,
    );
  }

  // lapSteps 이후의 시간(초) 동안의 케이던스(분당 걸음수)
  int _cadenceSpm(int steps, int elapsedSeconds) {
    if (elapsedSeconds <= 0) return 0;
    return (steps / (elapsedSeconds / 60.0)).round();
  }

  // 평균 케이던스 — 걸음이 전혀 안 잡힌 구간(스트림 중단/정지)을 분모에서 제외.
  // 활성 구간이 아예 없으면 전체 시간 기준으로 폴백
  int get _avgCadenceSpm => _cadenceActiveSeconds > 0
      ? _cadenceSpm(_totalSteps, _cadenceActiveSeconds)
      : _cadenceSpm(_totalSteps, _seconds);

  String _fmtMinSec(num totalSeconds) {
    final s = totalSeconds.toInt();
    final m = s ~/ 60, sec = s % 60;
    return '$m분 $sec초';
  }

  // 페이스 구간별 MET. 기존에는 8~12분/km를 MET 6~7로만 선형 보간해서 폭이 너무 좁았고,
  // 그 결과 12세션 중 8세션이 kcal/분 7.18~7.21로 사실상 고정 수렴 — 26'14"/km 세션과
  // 11'20"/km 세션의 분당 칼로리가 같게 나오는 명백한 결함이 있었음.
  // 실제 속도 차이가 반영되도록 구간별 MET 테이블로 교체(느린 걷기~빠른 러닝 전 구간 커버).
  double _metForPace(double paceMinPerKm) {
    if (paceMinPerKm <= 6) return 10.0;
    if (paceMinPerKm <= 8) return 8.3;
    if (paceMinPerKm <= 10) return 6.0;
    if (paceMinPerKm <= 13) return 4.5;
    return 3.5;
  }

  // MET × 체중(kg) × 시간(h) 공식 기반 칼로리 소모량
  double _calculateCalories() {
    if (_distanceKm < 0.01 || _seconds < 1) return 0.0;
    final paceMinPerKm = (_seconds / 60.0) / _distanceKm;
    final met = _metForPace(paceMinPerKm);
    final hours = _seconds / 3600.0;
    return met * _s.weightKg * hours;
  }

  Future<void> _startGpsTracking() async {
    try {
      // 러닝 시작 시점에는 always(백그라운드)까지 시도 — 화면이 꺼져도 스트림이 살아있어야 함
      final perm = await _ensureLocationPermission(wantAlways: true);
      if (perm != LocationPermission.always && perm != LocationPermission.whileInUse) return;

      _positionSub?.cancel();
      _positionSub = Geolocator.getPositionStream(
        // 안드로이드에서는 포그라운드 서비스 알림이 붙은 설정이 반환됨(웹은 기본 설정)
        locationSettings: buildTrackingLocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 1,
        ),
      ).listen((pos) {
        if (!mounted) return;
        if (pos.accuracy > _gpsAccuracyThresholdMeters) {
          _gpsRejectStreak++;
          _gpsRejectedTotal++;
          _gpsRejectStreakStart ??= DateTime.now();
          if (_gpsRejectStreak >= 3) {
            final badSec = DateTime.now().difference(_gpsRejectStreakStart!).inSeconds;
            FileLogger.instance.log(
              '[GPS] 신호불량 $badSec초 지속 (acc=${pos.accuracy.toStringAsFixed(1)}m, '
              '연속거부=$_gpsRejectStreak회, 누적거부=$_gpsRejectedTotal개)',
            );
          }
          return;
        }
        _gpsRejectStreak = 0;
        _gpsRejectStreakStart = null;
        _lastGpsAccuracyMeters = pos.accuracy;
        _gpsAcceptedTotal++;

        final rawPoint = LatLng(pos.latitude, pos.longitude);
        final now = pos.timestamp;
        // EMA 스무딩 좌표는 경로 표시(_routePoints)와 지도 마커 전용 — 거리 계산은
        // 원시 좌표로 되돌려, 스무딩이 곡선 구간에서 경로를 안쪽으로 당겨 실제보다
        // 짧게 잡히게 하는 효과가 거리 수치에 섞이지 않도록 함
        final smoothed = _applyEma(rawPoint);
        _emaPoint = smoothed;
        _checkLapCompletion(smoothed);

        if (_lastGpsPoint != null && _lastGpsTime != null) {
          final elapsedSec = now.difference(_lastGpsTime!).inMilliseconds / 1000.0;
          if (elapsedSec < _minGpsIntervalSec) {
            // 콜백 간격이 너무 짧으면 순간속도가 잡음만으로 튈 수 있으니 위치 표시만 갱신하고
            // 거리 누적은 다음 콜백(충분한 시간차가 쌓였을 때)으로 미룸
            setState(() {
              _mapCenter = smoothed;
              _hasLocation = true;
            });
            return;
          }

          final meters = Geolocator.distanceBetween(
            _lastGpsPoint!.latitude, _lastGpsPoint!.longitude,
            rawPoint.latitude, rawPoint.longitude,
          );
          final speedKmh = (meters / elapsedSec) * 3.6;
          // 비현실적인 순간속도는 "버리지" 않고 최대 그럴듯한 속도로 상한만 적용.
          // (예전엔 구간을 통째로 버리고 기준점도 갱신 안 해서, 다음 정상 구간이 왔을 때
          //  옛 기준점→새 지점을 직선으로 건너뛰어 버렸음. 트랙처럼 계속 곡선을 도는
          //  코스에서는 이 직선이 실제 호 경로보다 훨씬 짧아서 바퀴를 돌수록 오차가
          //  누적되는 원인이었음 — 기준점은 항상 갱신해 이 "코너 지름길" 자체를 없앰)
          final cappedMeters = speedKmh > _maxPlausibleSpeedKmh
              ? (_maxPlausibleSpeedKmh / 3.6) * elapsedSec
              : meters;
          FileLogger.instance.log(
            '[GPS] acc=${pos.accuracy.toStringAsFixed(1)}m '
            'speed=${speedKmh.toStringAsFixed(1)}km/h '
            '${speedKmh > _maxPlausibleSpeedKmh ? "capped ${meters.toStringAsFixed(1)}m->${cappedMeters.toStringAsFixed(1)}m" : "meters=${meters.toStringAsFixed(1)}m"} '
            '누적거리=${_distanceKm.toStringAsFixed(3)}km 수락=$_gpsAcceptedTotal개 거부=$_gpsRejectedTotal개',
          );

          setState(() {
            _distanceKm += cappedMeters / 1000.0;
            _routePoints.add(smoothed);
            _checkAudioGuide();
          });
          _lastGpsPoint = rawPoint;
          _lastGpsTime = now;
        } else {
          _routePoints.add(smoothed);
          _lastGpsPoint = rawPoint;
          _lastGpsTime = now;
        }
        setState(() {
          _mapCenter = smoothed;
          _hasLocation = true;
        });
      });
    } catch (_) {}
  }

  // 시작 지점에서 _lapMinAwayMeters(40m) 이상 멀어졌다가 _lapReturnRadiusMeters(18m)
  // 이내로 돌아오면 1바퀴. 시작 지점은 이번 운동의 첫 GPS 픽스로 고정(일시정지/재개에도 유지).
  //
  // v17의 "방향전환(베어링) 확인" 게이트는 제거함 — 40m/18m + 60초 히스테리시스만으로도
  // 중복 카운트가 막히는데, 저속 조깅에서는 베어링 자체가 잡음으로 튀어 오히려 실제 랩을
  // 억제할 위험이 더 컸음. 랩이 계속 0으로 나오던 상황이라 "놓치지 않는 것"을 우선함.
  void _checkLapCompletion(LatLng point) {
    _lapStartPoint ??= point;
    final distFromStart = Geolocator.distanceBetween(
      _lapStartPoint!.latitude, _lapStartPoint!.longitude,
      point.latitude, point.longitude,
    );
    if (distFromStart > _lapMaxAwayMeters) _lapMaxAwayMeters = distFromStart;
    final sinceLastLap = _seconds - _lastLapSeconds;

    if (distFromStart > _lapMinAwayMeters) {
      if (!_hasLeftLapZone) {
        FileLogger.instance.log(
          '[LAP] 아웃존 진입 | 현재이격=${distFromStart.toStringAsFixed(1)}m '
          '최대이격=${_lapMaxAwayMeters.toStringAsFixed(1)}m 경과=${sinceLastLap}s 판정=대기',
        );
      }
      _hasLeftLapZone = true;
      return;
    }

    if (_hasLeftLapZone && distFromStart <= _lapReturnRadiusMeters) {
      if (sinceLastLap < _lapMinIntervalSeconds) {
        FileLogger.instance.log(
          '[LAP] 복귀 감지했으나 보류(최소 랩 간격 미달) | 현재이격=${distFromStart.toStringAsFixed(1)}m '
          '최대이격=${_lapMaxAwayMeters.toStringAsFixed(1)}m 경과=${sinceLastLap}s '
          '판정=보류(${_lapMinIntervalSeconds}s 필요)',
        );
        return;
      }
      _hasLeftLapZone = false;
      _lastLapSeconds = _seconds;
      FileLogger.instance.log(
        '[LAP] 바퀴 완료 | 현재이격=${distFromStart.toStringAsFixed(1)}m '
        '최대이격=${_lapMaxAwayMeters.toStringAsFixed(1)}m 경과=${sinceLastLap}s '
        '판정=카운트(총 ${_lapCount + 1}바퀴)',
      );
      setState(() {
        _lapCount++;
        _lapCompletionPoints.add(point);
        _lapSplitSeconds.add(_seconds);
      });
      _lapMaxAwayMeters = 0.0;
    }
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
    _accelSub?.cancel();
    _accelSub = null;
    _cadenceDiagnosticTimer?.cancel();
    _metronome.stop();
    _applyWakelock(false);
    setState(() => _workoutState = WorkoutState.paused);
  }

  void _resumeWorkout() {
    setState(() => _workoutState = WorkoutState.running);
    _applyWakelock(true);
    _metronome.start(_s.bpm, playImmediately: false);
    _lastGpsPoint = null;
    _lastGpsTime = null;
    _emaPoint = null;
    _gpsRejectStreak = 0;
    _gpsRejectStreakStart = null;
    _startGpsTracking();
    _startStepDetection();
    _launchTimer();
  }

  void _stopWorkout() {
    _workoutTimer?.cancel();
    _workoutTimer = null;
    _positionSub?.cancel();
    _positionSub = null;
    _accelSub?.cancel();
    _accelSub = null;
    _cadenceDiagnosticTimer?.cancel();
    _metronome.stop();
    _applyWakelock(false);
    setState(() => _workoutState = WorkoutState.idle);
    _announceWorkoutSummary();
    _saveToDb();
    _showSummaryDialog();
    // 운동 종료 직후 로그가 파일에 확실히 반영되도록 즉시 flush
    // (평소엔 3초 주기 버퍼링이라, 종료 직후 바로 공유하면 최신 로그가 누락될 수 있음)
    FileLogger.instance.flushNow();
  }

  void _announceWorkoutSummary() {
    _tts.speak(_buildFullSummary(prefix: '운동을 종료합니다. '));
  }

  Future<void> _saveToDb() async {
    if (_distanceKm < 0.01 || _seconds < 5) return;
    final record = WorkoutRecord(
      date: DateTime.now(),
      distanceKm: _distanceKm,
      durationSeconds: _seconds,
      avgPaceSecPerKm: _seconds / _distanceKm,
      avgCadence: _avgCadenceSpm,
      lapCount: _lapCount,
      caloriesBurned: _calculateCalories(),
      weatherTempC: _workoutStartWeather?.tempC,
      weatherHumidity: _workoutStartWeather?.humidity,
      weatherPrecipitationPercent: _workoutStartWeather?.precipitationPercent,
      routePoints: List<LatLng>.from(_routePoints),
      lapCompletionPoints: List<LatLng>.from(_lapCompletionPoints),
      lapSplitSeconds: List<int>.from(_lapSplitSeconds),
    );
    await DatabaseService.instance.insertWorkout(record);
  }

  void _launchTimer() {
    _workoutTimer?.cancel();
    _workoutTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() {
        _seconds++;
        // 이 1초 구간에 실제로 걸음이 감지되고 있었는지 기록 — 평균 케이던스의 분모로 씀
        if (_liveCadenceSpm > 0) _cadenceActiveSeconds++;
      });
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
      _totalSteps = 0;
      _lapStepsAtLastKm = 0;
      _lastStepAt = null;
      _recentStepTimestamps.clear();
      _routePoints.clear();
      _emaPoint = null;
      _lapStartPoint = null;
      _lapCount = 0;
      _hasLeftLapZone = false;
      _lapCompletionPoints.clear();
      _lapSplitSeconds.clear();
      _lapMaxAwayMeters = 0.0;
      _lastLapSeconds = 0;
      _gpsRejectedTotal = 0;
      _gpsAcceptedTotal = 0;
      _cadenceActiveSeconds = 0;
    });
  }

  void _checkAudioGuide() {
    final km = _distanceKm.floor();
    if (km > 0 && km > _lastAnnouncedKm) {
      final lapSec = _seconds - _lapStartSeconds;
      final lapSteps = _totalSteps - _lapStepsAtLastKm;
      _lapStartSeconds = _seconds;
      _lapStepsAtLastKm = _totalSteps;
      _lastAnnouncedKm = km;
      final cadence = _cadenceSpm(lapSteps, lapSec);
      _tts.speak(
        '$km킬로미터 지점입니다. '
        '총 거리 ${_distanceKm.toStringAsFixed(2)}킬로미터, '
        '총 시간 ${_fmtMinSec(_seconds)}, '
        '이번 1킬로미터 구간 시간 ${_fmtMinSec(lapSec)}, '
        '케이던스 분당 $cadence걸음.',
      );
    }
    if (!_halfAnnounced && _distanceKm >= _s.targetDistanceKm * 0.5) {
      _halfAnnounced = true;
      _tts.speak(_buildFullSummary(
        prefix: '목표의 절반인 ${(_s.targetDistanceKm / 2).toStringAsFixed(1)}킬로미터를 지났습니다. ',
      ));
    }
    if (!_goalAnnounced && _distanceKm >= _s.targetDistanceKm) {
      _goalAnnounced = true;
      _tts.speak(_buildFullSummary(prefix: '목표 거리에 도달했습니다. 운동은 계속됩니다. '));
    }
  }

  // 누적 거리/시간/평균 페이스/평균 케이던스를 종합한 안내 문구
  String _buildFullSummary({String prefix = ''}) {
    final cadence = _avgCadenceSpm;
    final paceStr = _distanceKm >= 0.01
        ? ', 평균 페이스 ${_fmtMinSec(_seconds / _distanceKm)}'
        : '';
    return '$prefix'
        '총 거리 ${_distanceKm.toStringAsFixed(2)}킬로미터, '
        '총 시간 ${_fmtMinSec(_seconds)}$paceStr, '
        '평균 케이던스 분당 $cadence걸음이었습니다.';
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
        return '$_liveCadenceSpm';
      case 3:
        return _calculateCalories().toStringAsFixed(0);
      case 4:
        return '$_lapCount';
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

            // 백그라운드 위치 권한 경고 — 이게 "항상 허용"이 아니면 화면이 꺼지는 순간
            // 위치 스트림이 끊겨 거리가 통째로 유실됨(v17까지의 -7.9~-54.7% 오차 원인)
            if (!_hasAlwaysLocation) _buildPermissionBanner(),

            // 지역 + 날씨 요약 (실제 위치 기준 — 지명을 함께 표시해 신뢰도 확인 가능)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(
                    _weatherLoading
                        ? '위치 확인 중...'
                        : '${_weather?.fetchedAtText ?? ''}${_locationName != null ? ' · $_locationName' : ''}',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: _s.preset.onBackground.withValues(alpha: 0.92),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _weatherLoading
                        ? '날씨 확인 중...'
                        : (_weather?.summaryText ?? '날씨 정보 없음'),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: _s.preset.onBackground.withValues(alpha: 0.8),
                    ),
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
                  ShaderMask(
                    shaderCallback: (bounds) => LinearGradient(
                      colors: [_s.preset.accentGradientStart, _s.preset.accentGradientEnd],
                    ).createShader(bounds),
                    child: Text(
                      _s.goalType == GoalType.distance
                          ? _s.targetDistanceKm.toStringAsFixed(1)
                          : '${_s.targetTimeMinutes}',
                      style: const TextStyle(
                        fontSize: 96,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        height: 1.0,
                        letterSpacing: -4,
                      ),
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
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [_s.preset.accentGradientStart, _s.preset.accentGradientEnd],
                    ),
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
              if (_routePoints.length > 1)
                PolylineLayer(
                  polylines: [buildRoutePolyline(_routePoints, _s.accent)],
                ),
              if (_routePoints.length > 1)
                MarkerLayer(
                  markers: [
                    for (final m in computeKmMarkers(_routePoints))
                      Marker(
                        point: m.point,
                        width: 36,
                        height: 20,
                        child: buildKmMarkerChip(m.km, _s.accent),
                      ),
                  ],
                ),
              if (_lapCompletionPoints.isNotEmpty)
                MarkerLayer(
                  markers: [
                    for (var i = 0; i < _lapCompletionPoints.length; i++)
                      Marker(
                        point: _lapCompletionPoints[i],
                        width: 34,
                        height: 20,
                        child: buildLapMarkerChip(i + 1, _s.accent),
                      ),
                  ],
                ),
              if (_hasLocation)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: _mapCenter,
                      width: 28,
                      height: 28,
                      child: buildLiveLocationMarker(_s.accent),
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

  // "항상 허용"이 아닐 때 시작 화면 상단에 띄우는 경고 + 설정 앱 딥링크
  Widget _buildPermissionBanner() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.orange.withValues(alpha: 0.5)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '위치 권한을 "항상 허용"으로 바꿔주세요',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: _s.preset.onBackground,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '지금은 화면이 꺼지면 거리 기록이 끊깁니다.\n설정 → 권한 → 위치 → "항상 허용"',
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.4,
                    color: _s.preset.onBackground.withValues(alpha: 0.7),
                  ),
                ),
                const SizedBox(height: 8),
                GestureDetector(
                  onTap: () => Geolocator.openAppSettings(),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.orange.withValues(alpha: 0.9),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      '설정 열기',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
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
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [_s.preset.accentGradientStart, _s.preset.accentGradientEnd],
          ),
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
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [_s.preset.accentGradientStart, _s.preset.accentGradientEnd],
              ),
              boxShadow: [BoxShadow(color: _s.accent.withValues(alpha: 0.35), blurRadius: 20, spreadRadius: 4)],
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
