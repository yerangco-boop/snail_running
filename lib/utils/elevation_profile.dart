import 'dart:math' as math;
import 'package:latlong2/latlong.dart';

// 이력 상세의 고도 그래프용 계산 (2026-11-15).
// 고도 원본은 러닝 중 GPS가 준 값(Position.altitude)을 경로 좌표와 같은 순서로 저장한 것.
// - 안드로이드 GPS 고도는 해수면이 아니라 WGS84 타원체 기준이라 한국에서는 실제 해발보다
//   20~30m 높게 나옴 → 절대 높이는 보여주지 않고 "출발 지점 = 0m" 기준의 상대 높이만 씀
// - GPS 고도는 수직 오차가 수 m라 그대로 더하면 평지에서도 오르막이 수십 m 쌓임
//   → 이동평균(11점)으로 다듬고, 방향이 climbThresholdM 이상 뒤집힌 것만 오르막/내리막
//     전환으로 인정함. 다만 GPS 오차가 천천히 흘러가는 경우(같은 방향으로 수십 초)는
//     실제 지형과 구분할 수 없어 평지에서도 오르막이 일부 잡힐 수 있음 — 기압계를 쓰면 해결됨
class ElevationProfile {
  // 각 점의 출발점 기준 누적 거리(km)
  final List<double> distanceKm;
  // 각 점의 출발 지점 기준 높이(m, 다듬은 값)
  final List<double> heightM;
  final double ascentM;
  final double descentM;
  final double minM;
  final double maxM;

  const ElevationProfile._({
    required this.distanceKm,
    required this.heightM,
    required this.ascentM,
    required this.descentM,
    required this.minM,
    required this.maxM,
  });

  double get rangeM => maxM - minM;

  // 그래프를 그리기에 고도 값이 있는 점이 너무 적으면 null
  static const int minPoints = 10;
  // 이동평균 반경: 앞뒤 5점씩, 총 11점 (슬로우 조깅 1~2초 간격 측위 기준 약 10~20초)
  static const int smoothRadius = 5;
  // 오르막/내리막으로 인정하는 최소 변화량(m)
  static const double climbThresholdM = 3.0;

  static ElevationProfile? compute(
    List<LatLng> points,
    List<double?> altitudes, {
    double? totalDistanceKm,
    // 기압계 높이처럼 잡음이 작은 값은 덜 다듬고 더 작은 오르내림도 인정할 수 있게 열어 둠
    int smoothRadius = ElevationProfile.smoothRadius,
    double climbThresholdM = ElevationProfile.climbThresholdM,
  }) {
    final n = math.min(points.length, altitudes.length);
    if (n < minPoints) return null;

    // 경로 전체(고도 없는 점 포함)를 따라 누적 거리를 구해야 x 위치가 실제와 맞음
    const dist = Distance();
    final cum = List<double>.filled(n, 0);
    for (var i = 1; i < n; i++) {
      cum[i] = cum[i - 1] + dist.as(LengthUnit.Meter, points[i - 1], points[i]) / 1000.0;
    }
    // 경로선은 스무딩된 좌표라 측정 거리보다 약간 짧을 수 있음 → 그래프 끝이
    // 화면에 표시된 거리와 같도록 비례로 늘리거나 줄임
    final routeKm = cum[n - 1];
    final scale = (totalDistanceKm != null && totalDistanceKm > 0 && routeKm > 0)
        ? totalDistanceKm / routeKm
        : 1.0;

    final xs = <double>[];
    final raw = <double>[];
    for (var i = 0; i < n; i++) {
      final a = altitudes[i];
      if (a == null || !a.isFinite) continue;
      xs.add(cum[i] * scale);
      raw.add(a);
    }
    if (raw.length < minPoints) return null;

    final smoothed = List<double>.generate(raw.length, (i) {
      final from = math.max(0, i - smoothRadius);
      final to = math.min(raw.length - 1, i + smoothRadius);
      var sum = 0.0;
      for (var j = from; j <= to; j++) {
        sum += raw[j];
      }
      return sum / (to - from + 1);
    });

    final base = smoothed.first;
    final heights = smoothed.map((h) => h - base).toList();

    // 오르막/내리막 합계: 직전 꼭짓점(ref)에서 threshold 이상 벌어져야 방향이 정해지고,
    // 반대쪽으로 threshold 이상 되돌아와야 그 구간의 높이를 통째로 더함
    var ascent = 0.0, descent = 0.0;
    var ref = heights.first, peak = heights.first;
    var dir = 0; // 1 = 오르는 중, -1 = 내려가는 중, 0 = 아직 모름
    var minH = heights.first, maxH = heights.first;
    for (final h in heights) {
      if (dir == 0) {
        if (h - ref >= climbThresholdM) {
          dir = 1;
          peak = h;
        } else if (ref - h >= climbThresholdM) {
          dir = -1;
          peak = h;
        }
      } else if (dir == 1) {
        if (h > peak) {
          peak = h;
        } else if (peak - h >= climbThresholdM) {
          ascent += peak - ref;
          ref = peak;
          dir = -1;
          peak = h;
        }
      } else {
        if (h < peak) {
          peak = h;
        } else if (h - peak >= climbThresholdM) {
          descent += ref - peak;
          ref = peak;
          dir = 1;
          peak = h;
        }
      }
      if (h < minH) minH = h;
      if (h > maxH) maxH = h;
    }
    if (dir == 1) ascent += peak - ref;
    if (dir == -1) descent += ref - peak;

    return ElevationProfile._(
      distanceKm: xs,
      heightM: heights,
      ascentM: ascent,
      descentM: descent,
      minM: minH,
      maxM: maxH,
    );
  }
}
