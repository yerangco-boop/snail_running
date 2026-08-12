import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

// 러닝 중 진행 상태를 주기적으로 저장해두는 스냅샷.
// 앱이 강제 종료되거나 OS에 의해 죽어도 다음 실행 때 기록을 되살릴 수 있게 함
// (뒤로가기 1회로 세션 전체가 날아가던 문제의 안전장치).
class WorkoutSnapshot {
  final DateTime savedAt;
  final DateTime startedAt;
  final double distanceKm;
  final int seconds;
  final int totalSteps;
  final int avgCadence;
  final int cadenceActiveSeconds;
  final int lapCount;
  final double caloriesBurned;
  final List<LatLng> routePoints;
  final List<LatLng> lapCompletionPoints;
  final List<int> lapSplitSeconds;

  const WorkoutSnapshot({
    required this.savedAt,
    required this.startedAt,
    required this.distanceKm,
    required this.seconds,
    required this.totalSteps,
    required this.avgCadence,
    required this.cadenceActiveSeconds,
    required this.lapCount,
    required this.caloriesBurned,
    required this.routePoints,
    required this.lapCompletionPoints,
    required this.lapSplitSeconds,
  });

  static const _key = 'workoutSnapshot';

  // 좌표는 소수점 6자리(약 0.1m)로 잘라 저장 — 30초마다 쓰는 데이터라 크기를 줄임
  static List<List<double>> _encodePoints(List<LatLng> pts) => pts
      .map((p) => [
            double.parse(p.latitude.toStringAsFixed(6)),
            double.parse(p.longitude.toStringAsFixed(6)),
          ])
      .toList();

  static List<LatLng> _decodePoints(dynamic raw) {
    if (raw is! List) return [];
    return raw
        .whereType<List>()
        .map((e) => LatLng((e[0] as num).toDouble(), (e[1] as num).toDouble()))
        .toList();
  }

  Map<String, dynamic> toJson() => {
        'savedAt': savedAt.toIso8601String(),
        'startedAt': startedAt.toIso8601String(),
        'distanceKm': distanceKm,
        'seconds': seconds,
        'totalSteps': totalSteps,
        'avgCadence': avgCadence,
        'cadenceActiveSeconds': cadenceActiveSeconds,
        'lapCount': lapCount,
        'caloriesBurned': caloriesBurned,
        'routePoints': _encodePoints(routePoints),
        'lapCompletionPoints': _encodePoints(lapCompletionPoints),
        'lapSplitSeconds': lapSplitSeconds,
      };

  static WorkoutSnapshot? _fromJson(Map<String, dynamic> m) {
    try {
      return WorkoutSnapshot(
        savedAt: DateTime.parse(m['savedAt'] as String),
        startedAt: DateTime.parse(m['startedAt'] as String),
        distanceKm: (m['distanceKm'] as num).toDouble(),
        seconds: (m['seconds'] as num).toInt(),
        totalSteps: (m['totalSteps'] as num?)?.toInt() ?? 0,
        avgCadence: (m['avgCadence'] as num?)?.toInt() ?? 0,
        cadenceActiveSeconds: (m['cadenceActiveSeconds'] as num?)?.toInt() ?? 0,
        lapCount: (m['lapCount'] as num?)?.toInt() ?? 0,
        caloriesBurned: (m['caloriesBurned'] as num?)?.toDouble() ?? 0.0,
        routePoints: _decodePoints(m['routePoints']),
        lapCompletionPoints: _decodePoints(m['lapCompletionPoints']),
        lapSplitSeconds:
            (m['lapSplitSeconds'] as List?)?.map((e) => (e as num).toInt()).toList() ?? [],
      );
    } catch (e) {
      debugPrint('[Snapshot] 파싱 실패: $e');
      return null;
    }
  }

  Future<void> save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, jsonEncode(toJson()));
    } catch (e) {
      debugPrint('[Snapshot] 저장 실패: $e');
    }
  }

  // 저장된 스냅샷을 읽음. 너무 오래됐거나(24시간 초과) 기록할 가치가 없을 만큼
  // 짧은 세션이면 무시하고 정리함
  static Future<WorkoutSnapshot?> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null || raw.isEmpty) return null;
      final snap = _fromJson(jsonDecode(raw) as Map<String, dynamic>);
      if (snap == null) {
        await clear();
        return null;
      }
      final tooOld = DateTime.now().difference(snap.savedAt).inHours >= 24;
      final tooShort = snap.distanceKm < 0.05 || snap.seconds < 30;
      if (tooOld || tooShort) {
        await clear();
        return null;
      }
      return snap;
    } catch (e) {
      debugPrint('[Snapshot] 로드 실패: $e');
      return null;
    }
  }

  static Future<void> clear() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_key);
    } catch (_) {}
  }
}
