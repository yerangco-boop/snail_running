import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/services.dart';

import 'file_logger.dart';

// 기압 센서로 "러닝 시작 지점 대비 높이"를 재는 시험용 (2026-11-26).
// GPS 고도는 평평한 운동장에서도 108 → 115m로 계단식으로 흘러가서(11/26 실측) 이력의
// 고도 그래프가 실제와 달랐음. 기압은 높이가 약 8m 변할 때 1hPa쯤 변하고 센서 잡음이
// 훨씬 작아 계단·언덕 같은 작은 높이 변화를 볼 수 있을 것으로 기대함 — 실측으로 확인 필요.
// 한계: 날씨로 기압이 변하면(시간당 1~2hPa까지) 그만큼 높이가 흘러감.
class Barometer {
  static const _channel = EventChannel('snail_running/pressure');
  // 센서 잡음을 줄이는 지수평균 계수. 초당 약 5회 수신 기준 약 2초 평균 (임의로 정한 값)
  static const double _alpha = 0.1;

  StreamSubscription<dynamic>? _sub;
  double? _smoothedHpa;
  double? _baseHpa;
  int _samples = 0;

  void start() {
    stop();
    _smoothedHpa = null;
    _baseHpa = null;
    _samples = 0;
    try {
      _sub = _channel.receiveBroadcastStream().listen(
        (value) {
          final hpa = (value as num).toDouble();
          if (!hpa.isFinite || hpa <= 0) return;
          final prev = _smoothedHpa;
          _smoothedHpa = prev == null ? hpa : prev + _alpha * (hpa - prev);
          _samples++;
          // 처음 10개(약 2초)는 평균이 자리 잡는 동안이라 기준으로 쓰지 않음
          if (_baseHpa == null && _samples >= 10) {
            _baseHpa = _smoothedHpa;
            FileLogger.instance.log('[Baro] 기준 기압 ${_baseHpa!.toStringAsFixed(2)}hPa');
          }
        },
        // 웹·센서 없는 기기 등 통로가 없으면 조용히 포기 (높이는 null로 남음)
        onError: (_) {},
        cancelOnError: true,
      );
    } catch (_) {}
  }

  void stop() {
    _sub?.cancel();
    _sub = null;
  }

  /// 시작 지점보다 얼마나 높은지(m). 아직 기준이 없거나 센서가 없으면 null
  double? get relativeHeightM {
    final p = _smoothedHpa, p0 = _baseHpa;
    if (p == null || p0 == null) return null;
    return heightFromPressure(p, p0);
  }

  /// 국제 표준 대기식: 기압 p가 기준 p0일 때보다 낮으면 그만큼 높은 곳
  static double heightFromPressure(double hpa, double baseHpa) =>
      44330.77 * (1 - math.pow(hpa / baseHpa, 0.190263));
}
