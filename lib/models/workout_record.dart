class WorkoutRecord {
  final int? id;
  final DateTime date;
  final double distanceKm;
  final int durationSeconds;
  final double avgPaceSecPerKm;
  final int avgCadence;
  final double caloriesBurned;
  final double? weatherTempC;
  final int? weatherHumidity;
  final int? weatherPrecipitationPercent;

  const WorkoutRecord({
    this.id,
    required this.date,
    required this.distanceKm,
    required this.durationSeconds,
    required this.avgPaceSecPerKm,
    this.avgCadence = 0,
    this.caloriesBurned = 0.0,
    this.weatherTempC,
    this.weatherHumidity,
    this.weatherPrecipitationPercent,
  });

  Map<String, dynamic> toMap() => {
    if (id != null) 'id': id,
    'date': date.toIso8601String(),
    'distance_km': distanceKm,
    'duration_seconds': durationSeconds,
    'avg_pace_sec': avgPaceSecPerKm,
    'avg_cadence': avgCadence,
    'calories_burned': caloriesBurned,
    'weather_temp_c': weatherTempC,
    'weather_humidity': weatherHumidity,
    'weather_precipitation_percent': weatherPrecipitationPercent,
  };

  factory WorkoutRecord.fromMap(Map<String, dynamic> map) => WorkoutRecord(
    id: map['id'] as int?,
    date: DateTime.parse(map['date'] as String),
    distanceKm: (map['distance_km'] as num).toDouble(),
    durationSeconds: map['duration_seconds'] as int,
    avgPaceSecPerKm: (map['avg_pace_sec'] as num).toDouble(),
    avgCadence: (map['avg_cadence'] as num?)?.toInt() ?? 0,
    caloriesBurned: (map['calories_burned'] as num?)?.toDouble() ?? 0.0,
    weatherTempC: (map['weather_temp_c'] as num?)?.toDouble(),
    weatherHumidity: (map['weather_humidity'] as num?)?.toInt(),
    weatherPrecipitationPercent:
        (map['weather_precipitation_percent'] as num?)?.toInt(),
  );

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
