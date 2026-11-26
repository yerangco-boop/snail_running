import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:snail_running/utils/elevation_profile.dart';

// 동쪽으로 약 1.1m씩 이동하는 직선 경로 (위도 0에서 경도 0.00001° ≈ 1.11m)
List<LatLng> _line(int n, {double stepDeg = 0.0001}) =>
    List.generate(n, (i) => LatLng(0, i * stepDeg));

void main() {
  test('평지 + GPS 잡음(±2m)은 오르막·내리막으로 쌓이지 않는다', () {
    final pts = _line(200);
    final alts = List<double?>.generate(200, (i) => 30.0 + ((i % 4) - 1.5) * 1.3);
    final e = ElevationProfile.compute(pts, alts)!;
    expect(e.ascentM, lessThan(3));
    expect(e.descentM, lessThan(3));
  });

  test('꾸준한 오르막 20m는 오르막 약 20m로 잡힌다', () {
    final pts = _line(101);
    final alts = List<double?>.generate(101, (i) => 50.0 + i * 0.2);
    final e = ElevationProfile.compute(pts, alts)!;
    expect(e.ascentM, closeTo(19, 1));
    expect(e.descentM, 0);
    expect(e.heightM.first, 0);
    expect(e.maxM, closeTo(19, 1));
  });

  test('오르고 내려오면 오르막·내리막이 각각 잡힌다', () {
    final pts = _line(101);
    final alts = List<double?>.generate(101, (i) => i <= 50 ? i * 0.3 : (100 - i) * 0.3);
    final e = ElevationProfile.compute(pts, alts)!;
    // 다듬기 때문에 꼭대기가 약간 깎여 15m보다 조금 작게 나옴 (약 13.4m)
    expect(e.ascentM, closeTo(13.4, 1));
    expect(e.descentM, closeTo(13.4, 1));
  });

  test('고도 값이 있는 점이 10개 미만이면 null', () {
    final pts = _line(30);
    final alts = List<double?>.generate(30, (i) => i < 9 ? 10.0 : null);
    expect(ElevationProfile.compute(pts, alts), isNull);
  });

  test('고도 없는 점은 건너뛰고, 가로축 끝은 기록 거리에 맞춘다', () {
    final pts = _line(50);
    final alts = List<double?>.generate(50, (i) => i.isEven ? 10.0 : null);
    final e = ElevationProfile.compute(pts, alts, totalDistanceKm: 2.0)!;
    expect(e.heightM.length, 25);
    // 마지막 고도 점은 인덱스 48 → 경로 전체(49구간) 중 48/49 지점
    expect(e.distanceKm.last, closeTo(2.0 * 48 / 49, 0.001));
  });
}
