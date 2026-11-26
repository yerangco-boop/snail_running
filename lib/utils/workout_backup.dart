import 'dart:convert';
import '../models/workout_record.dart';

// 러닝 기록을 파일 하나로 내보내고 다시 가져오기 위한 변환 (2026-11-26).
// 미리보기 앱 → 정식 앱처럼 서로 다른 앱 사이, 또는 폰을 바꿀 때 기록을 옮기는 용도.
// DB에 저장하는 것과 같은 모양(toMap)을 그대로 쓰되, 앱마다 달라지는 id는 뺀다.

const _formatName = 'snail_running_backup';

String encodeWorkoutBackup(List<WorkoutRecord> records, {DateTime? now}) => jsonEncode({
      'format': _formatName,
      'version': 1,
      'exportedAt': (now ?? DateTime.now()).toIso8601String(),
      'workouts': records.map((r) => r.toMap()..remove('id')).toList(),
    });

/// 달팽이 러닝 기록 파일이 아니면 [FormatException]
List<WorkoutRecord> decodeWorkoutBackup(String text) {
  final Object? decoded;
  try {
    decoded = jsonDecode(text);
  } catch (_) {
    throw const FormatException('달팽이 러닝 기록 파일이 아닙니다.');
  }
  if (decoded is! Map || decoded['format'] != _formatName || decoded['workouts'] is! List) {
    throw const FormatException('달팽이 러닝 기록 파일이 아닙니다.');
  }
  try {
    return (decoded['workouts'] as List)
        .map((m) => WorkoutRecord.fromMap(Map<String, dynamic>.from(m as Map)..remove('id')))
        .toList();
  } catch (_) {
    throw const FormatException('기록 파일의 내용을 읽을 수 없습니다.');
  }
}

// 같은 러닝인지 판단하는 기준: 시작 시각과 운동 시간이 모두 같으면 같은 기록
String _key(WorkoutRecord r) => '${r.date.toIso8601String()}|${r.durationSeconds}';

/// 이미 있는 기록과 겹치지 않는 것만 골라냄 (같은 파일을 두 번 가져와도 중복되지 않게)
List<WorkoutRecord> selectNewWorkouts(List<WorkoutRecord> existing, List<WorkoutRecord> incoming) {
  final seen = existing.map(_key).toSet();
  return [
    for (final r in incoming)
      if (seen.add(_key(r))) r,
  ];
}
