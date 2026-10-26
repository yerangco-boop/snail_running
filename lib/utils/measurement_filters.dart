// 화면 켬/끔과 무관하게 같은 측정값을 내기 위한 순수 판정 함수 모음 (2026-10-27).
// 화면 상태·GPS 상태에 의존하지 않도록 입력값만으로 판정하게 분리해 단위 테스트가 가능하다.

/// 이전 좌표 → 이번 좌표 이동이 GPS 튐인지 판정한다.
/// - 순간 속도가 [maxSpeedKmh]를 넘거나
/// - 보폭을 아는 상태에서, 그 사이 걸음 수(+초당 1.5m 여유+3m)로 설명되지 않는 이동이면 튐.
/// 2026-10-27 로그: 화면을 켠 러닝에서도 정확도 5~15m인데 1초에 10~27m(시속 37~74km)
/// 이동으로 찍히는 값이 러닝당 5~9번 있었고, 거리는 상한으로 막았지만 지도 경로선에는 그대로 그려졌다.
bool isGpsSpike({
  required double meters,
  required double elapsedSec,
  required int stepsDelta,
  double? strideMeters,
  double maxSpeedKmh = 25.0,
}) {
  if (elapsedSec <= 0) return false;
  final speedKmh = meters / elapsedSec * 3.6;
  if (speedKmh > maxSpeedKmh) return true;
  if (strideMeters != null) {
    final explained = stepsDelta * strideMeters * 1.6 + 1.5 * elapsedSec + 3.0;
    if (meters > explained) return true;
  }
  return false;
}

/// 가속도 센서는 살아 있는데 걸음이 한동안 없으면 "제자리"로 본다.
/// 제자리의 GPS 흔들림(수 m)이 거리로 쌓이는 것을 막는다 (책상 위 0.01km).
bool isStationary({required bool accelAlive, required bool stepsAlive}) =>
    accelAlive && !stepsAlive;

/// 걸음 수로 설명할 수 있는 최대 이동거리(m). 보폭을 모를 때 GPS 값이
/// 걸음 수에 비해 터무니없이 부풀지 않도록 거는 상한.
/// 2026-10-27 10/23 로그: 걸음당 1.1~1.5m(케이던스 105spm)로 부풀었음.
double stepBoundMeters(int stepsDelta, {double maxStrideMeters = 1.2}) =>
    stepsDelta * maxStrideMeters + 2.0;
