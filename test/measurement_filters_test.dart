import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:snail_running/services/lap_memory.dart';
import 'package:snail_running/utils/measurement_filters.dart';

void main() {
  group('isGpsSpike', () {
    test('1초에 20m(72km/h)는 튐', () {
      expect(isGpsSpike(meters: 20, elapsedSec: 1, stepsDelta: 2, strideMeters: 0.65), isTrue);
    });
    test('정상 러닝 1초 1.9m는 튐이 아님', () {
      expect(isGpsSpike(meters: 1.9, elapsedSec: 1, stepsDelta: 2, strideMeters: 0.65), isFalse);
    });
    test('시속 25km/h 초과는 보폭을 몰라도 튐', () {
      expect(isGpsSpike(meters: 8, elapsedSec: 1, stepsDelta: 2), isTrue);
    });
    test('걸음으로 설명 안 되는 6m 이동(시속 21.6)은 튐', () {
      expect(isGpsSpike(meters: 6, elapsedSec: 1, stepsDelta: 0, strideMeters: 0.65), isTrue);
    });
    test('보폭을 모르면 속도 상한 이하는 통과', () {
      expect(isGpsSpike(meters: 6, elapsedSec: 1, stepsDelta: 0), isFalse);
    });
    test('시간차가 0이면 판정하지 않음', () {
      expect(isGpsSpike(meters: 50, elapsedSec: 0, stepsDelta: 0), isFalse);
    });
  });

  group('isStationary', () {
    test('센서 살아있고 걸음 없음 → 제자리', () {
      expect(isStationary(accelAlive: true, stepsAlive: false), isTrue);
    });
    test('걸음이 있으면 제자리 아님', () {
      expect(isStationary(accelAlive: true, stepsAlive: true), isFalse);
    });
    test('센서가 죽어 있으면 판단하지 않음(거리를 잃지 않기 위해)', () {
      expect(isStationary(accelAlive: false, stepsAlive: false), isFalse);
    });
  });

  group('stepBoundMeters', () {
    test('걸음 수에 비례한 상한', () {
      expect(stepBoundMeters(10), closeTo(14.0, 1e-9));
    });
    test('10/23 사례: 55걸음인데 GPS 80m는 상한으로 잘린다', () {
      expect(80 > stepBoundMeters(55), isTrue);
      expect(stepBoundMeters(55), closeTo(68.0, 1e-9));
    });
  });

  group('LapMemory', () {
    const mem = LapMemory(lat: 36.9700, lon: 127.9300, lapMeters: 340);
    test('같은 코스 시작점(100m 이내)이면 저장된 한 바퀴 거리', () {
      expect(mem.seedFor(const LatLng(36.9705, 127.9303)), 340);
    });
    test('멀리 떨어진 곳이면 쓰지 않음', () {
      expect(mem.seedFor(const LatLng(36.9800, 127.9300)), isNull);
    });
    test('이상한 저장값은 거부', () {
      expect(LapMemory.fromJson({'lat': 1, 'lon': 2, 'lap': 50}), isNull);
      expect(LapMemory.fromJson({'lat': 'a'}), isNull);
      final ok = LapMemory.fromJson(mem.toJson());
      expect(ok!.lapMeters, 340);
    });
  });
}
