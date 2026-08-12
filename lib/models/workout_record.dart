import 'dart:convert';
import 'package:latlong2/latlong.dart';

class WorkoutRecord {
  final int? id;
  final DateTime date;
  final double distanceKm;
  final int durationSeconds;
  final double avgPaceSecPerKm;
  final int avgCadence;
  // 가속도계 피크 검출로 실제로 센 누적 걸음 수 (평균 케이던스 × 시간으로 역산한 값이 아님)
  final int totalSteps;
  final int lapCount;
  final double caloriesBurned;
  final double? weatherTempC;
  final int? weatherHumidity;
  final int? weatherPrecipitationPercent;
  final List<LatLng>? routePoints;
  // 바퀴가 완료(카운트)된 시점의 좌표들 — 이력 상세 지도에 완주 지점 마커로 표시
  final List<LatLng>? lapCompletionPoints;
  // 각 바퀴가 완료된 시점의 누적 경과초 — 이력 상세에서 랩별 구간 기록으로 표시
  final List<int>? lapSplitSeconds;

  const WorkoutRecord({
    this.id,
    required this.date,
    required this.distanceKm,
    required this.durationSeconds,
    required this.avgPaceSecPerKm,
    this.avgCadence = 0,
    this.totalSteps = 0,
    this.lapCount = 0,
    this.caloriesBurned = 0.0,
    this.weatherTempC,
    this.weatherHumidity,
    this.weatherPrecipitationPercent,
    this.routePoints,
    this.lapCompletionPoints,
    this.lapSplitSeconds,
  });

  Map<String, dynamic> toMap() => {
    if (id != null) 'id': id,
    'date': date.toIso8601String(),
    'distance_km': distanceKm,
    'duration_seconds': durationSeconds,
    'avg_pace_sec': avgPaceSecPerKm,
    'avg_cadence': avgCadence,
    'total_steps': totalSteps,
    'lap_count': lapCount,
    'calories_burned': caloriesBurned,
    'weather_temp_c': weatherTempC,
    'weather_humidity': weatherHumidity,
    'weather_precipitation_percent': weatherPrecipitationPercent,
    'route_json': (routePoints != null && routePoints!.isNotEmpty)
        ? jsonEncode(routePoints!.map((p) => [p.latitude, p.longitude]).toList())
        : null,
    'lap_points_json': (lapCompletionPoints != null && lapCompletionPoints!.isNotEmpty)
        ? jsonEncode(lapCompletionPoints!.map((p) => [p.latitude, p.longitude]).toList())
        : null,
    'lap_splits_json': (lapSplitSeconds != null && lapSplitSeconds!.isNotEmpty)
        ? jsonEncode(lapSplitSeconds)
        : null,
  };

  factory WorkoutRecord.fromMap(Map<String, dynamic> map) => WorkoutRecord(
    id: map['id'] as int?,
    date: DateTime.parse(map['date'] as String),
    distanceKm: (map['distance_km'] as num).toDouble(),
    durationSeconds: map['duration_seconds'] as int,
    avgPaceSecPerKm: (map['avg_pace_sec'] as num).toDouble(),
    avgCadence: (map['avg_cadence'] as num?)?.toInt() ?? 0,
    totalSteps: (map['total_steps'] as num?)?.toInt() ?? 0,
    lapCount: (map['lap_count'] as num?)?.toInt() ?? 0,
    caloriesBurned: (map['calories_burned'] as num?)?.toDouble() ?? 0.0,
    weatherTempC: (map['weather_temp_c'] as num?)?.toDouble(),
    weatherHumidity: (map['weather_humidity'] as num?)?.toInt(),
    weatherPrecipitationPercent:
        (map['weather_precipitation_percent'] as num?)?.toInt(),
    routePoints: _parseRouteJson(map['route_json'] as String?),
    lapCompletionPoints: _parseRouteJson(map['lap_points_json'] as String?),
    lapSplitSeconds: _parseIntListJson(map['lap_splits_json'] as String?),
  );

  static List<int>? _parseIntListJson(String? json) {
    if (json == null || json.isEmpty) return null;
    try {
      final decoded = jsonDecode(json) as List;
      return decoded.map((e) => (e as num).toInt()).toList();
    } catch (_) {
      return null;
    }
  }

  static List<LatLng>? _parseRouteJson(String? json) {
    if (json == null || json.isEmpty) return null;
    try {
      final decoded = jsonDecode(json) as List;
      return decoded
          .map((e) {
            final pair = e as List;
            return LatLng((pair[0] as num).toDouble(), (pair[1] as num).toDouble());
          })
          .toList();
    } catch (_) {
      return null;
    }
  }

  bool get hasRoute => routePoints != null && routePoints!.isNotEmpty;

  // 랩 × 코스 1바퀴 거리로 추정한 거리 — GPS 거리의 정확도를 앱 자체로 교차검증하는 기준선
  double estimatedLapDistanceKm(double lapDistanceMeters) =>
      lapCount * lapDistanceMeters / 1000.0;

  // 랩별 구간 시간(초) — 저장된 "누적 경과초"의 차분으로 계산
  List<int> get lapIntervalSeconds {
    final splits = lapSplitSeconds;
    if (splits == null || splits.isEmpty) return const [];
    final out = <int>[];
    var prev = 0;
    for (final s in splits) {
      out.add(s - prev);
      prev = s;
    }
    return out;
  }

  bool get hasWeather =>
      weatherTempC != null && weatherHumidity != null && weatherPrecipitationPercent != null;

  String get weatherSummary => hasWeather
      ? '${weatherTempC!.round()}°C · 습도 $weatherHumidity% · 강수확률 $weatherPrecipitationPercent%'
      : '날씨 정보 없음';

  String get formattedDate {
    return "${date.year}.${date.month.toString().padLeft(2, '0')}.${date.day.toString().padLeft(2, '0')}";
  }

  String get weekday {
    const days = ['월', '화', '수', '목', '금', '토', '일'];
    return days[date.weekday - 1];
  }

  String get formattedDuration {
    final h = durationSeconds ~/ 3600;
    final m = (durationSeconds % 3600) ~/ 60;
    final s = durationSeconds % 60;
    if (h > 0) {
      return "$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}";
    }
    return "${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}";
  }

  String get formattedPace {
    if (avgPaceSecPerKm <= 0) return "--'--\"";
    final m = (avgPaceSecPerKm ~/ 60).toInt();
    final s = avgPaceSecPerKm.toInt() % 60;
    return "$m'${s.toString().padLeft(2, '0')}\"";
  }
}
