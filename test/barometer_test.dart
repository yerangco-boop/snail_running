import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:snail_running/services/barometer.dart';
import 'package:snail_running/utils/elevation_profile.dart';

void main() {
  test('기압이 같으면 0m, 1hPa 낮아지면 약 8m 높다', () {
    expect(Barometer.heightFromPressure(1000, 1000), closeTo(0, 1e-9));
    expect(Barometer.heightFromPressure(999, 1000), closeTo(8.4, 0.3));
    expect(Barometer.heightFromPressure(1001, 1000), closeTo(-8.4, 0.3));
  });

  test('기압계용 설정(덜 다듬기·1.5m)은 2m 계단을 오르막으로 잡고, GPS용 기본 설정은 잡지 않는다', () {
    // 평지 40점 → 2m 높은 평지 40점 (약 1.5m 간격으로 직진)
    final points = [for (var i = 0; i < 80; i++) LatLng(37.0 + i * 0.0000135, 127.9)];
    final heights = <double?>[for (var i = 0; i < 80; i++) i < 40 ? 0.0 : 2.0];

    final baro = ElevationProfile.compute(points, heights, smoothRadius: 2, climbThresholdM: 1.5)!;
    expect(baro.ascentM, closeTo(2.0, 0.01));
    expect(baro.descentM, 0);

    final gps = ElevationProfile.compute(points, heights)!;
    expect(gps.ascentM, 0);
  });
}
