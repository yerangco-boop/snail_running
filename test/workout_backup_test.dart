import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:snail_running/models/workout_record.dart';
import 'package:snail_running/utils/workout_backup.dart';

void main() {
  final full = WorkoutRecord(
    id: 7,
    date: DateTime(2026, 11, 26, 12, 23, 15),
    distanceKm: 1.42,
    durationSeconds: 2893,
    avgPaceSecPerKm: 2033,
    avgCadence: 79,
    totalSteps: 1681,
    lapCount: 2,
    caloriesBurned: 289,
    weatherTempC: 12,
    weatherHumidity: 61,
    weatherPrecipitationPercent: 0,
    routePoints: const [LatLng(36.99, 127.92), LatLng(36.991, 127.921)],
    lapCompletionPoints: const [LatLng(36.99, 127.92)],
    lapSplitSeconds: const [170, 345],
    lapSplitDistanceKm: const [0.28, 0.56],
    routeAltitudes: const [80.5, null],
    routeBaroHeights: const [0.0, 1.25],
  );
  final plain = WorkoutRecord(
    date: DateTime(2026, 11, 10, 19, 0),
    distanceKm: 3.0,
    durationSeconds: 1800,
    avgPaceSecPerKm: 600,
  );

  test('내보낸 뒤 다시 읽으면 모든 값이 같고 id는 빠진다', () {
    final back = decodeWorkoutBackup(encodeWorkoutBackup([full, plain]));
    expect(back.length, 2);
    expect(back[0].id, isNull);
    expect(back[0].toMap(), full.toMap()..remove('id'));
    expect(back[1].toMap(), plain.toMap());
  });

  test('다른 파일은 거부한다', () {
    expect(() => decodeWorkoutBackup('안녕하세요'), throwsFormatException);
    expect(() => decodeWorkoutBackup('{"workouts": []}'), throwsFormatException);
    expect(() => decodeWorkoutBackup('[1, 2, 3]'), throwsFormatException);
    expect(
      () => decodeWorkoutBackup('{"format":"snail_running_backup","workouts":[{"date":"x"}]}'),
      throwsFormatException,
    );
  });

  test('이미 있는 기록과 파일 안의 중복은 건너뛴다', () {
    final other = WorkoutRecord(
      date: DateTime(2026, 11, 12, 19, 0),
      distanceKm: 2.0,
      durationSeconds: 1200,
      avgPaceSecPerKm: 600,
    );
    final picked = selectNewWorkouts([plain], [full, plain, other, other]);
    expect(picked.map((r) => r.date), [full.date, other.date]);
  });
}
