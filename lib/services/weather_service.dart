import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class WeatherSnapshot {
  final double tempC;
  final int humidity;
  final int precipitationPercent; // 0~100
  final double windSpeedMs;
  final String iconCode; // OpenWeatherMap 아이콘 코드 (예: "01d")
  final DateTime fetchedAt;
  final String cityName; // OpenWeatherMap 응답의 도시명 (current['name'])

  const WeatherSnapshot({
    required this.tempC,
    required this.humidity,
    required this.precipitationPercent,
    required this.windSpeedMs,
    required this.iconCode,
    required this.fetchedAt,
    required this.cityName,
  });

  String get summaryText =>
      '${tempC.round()}°C · 습도 $humidity% · 강수확률 $precipitationPercent% · 바람 ${windSpeedMs.toStringAsFixed(0)}m/s';

  // 조회 시각 + 도시명을 앞에 붙인 전체 요약 (날씨가 실제로 언제/어디 기준인지 확인용)
  String get fullSummaryText {
    final f = fetchedAt;
    final ts = '${f.year}.${f.month.toString().padLeft(2, '0')}.'
        '${f.day.toString().padLeft(2, '0')} '
        '${f.hour.toString().padLeft(2, '0')}:${f.minute.toString().padLeft(2, '0')}';
    final cityPart = cityName.isNotEmpty ? ' · $cityName' : '';
    return '$ts$cityPart · $summaryText';
  }
}

class WeatherService {
  // 제주도는 해안/중산간/산간 지역별 기상차가 커서, 위치를 못 가져온 경우에만
  // 쓰는 폴백 좌표 (제주시)
  static const double _fallbackLat = 33.4996;
  static const double _fallbackLon = 126.5312;

  // API 키는 코드에 하드코딩하지 않고 빌드 시 --dart-define=OPENWEATHER_API_KEY=xxx 로 주입
  static const String _apiKey = String.fromEnvironment('OPENWEATHER_API_KEY');

  // lat/lon을 지정하지 않으면(GPS 위치 없음) 제주시 좌표로 폴백
  Future<WeatherSnapshot?> fetchCurrentWeather({double? lat, double? lon}) async {
    final effectiveLat = lat ?? _fallbackLat;
    final effectiveLon = lon ?? _fallbackLon;

    if (_apiKey.isEmpty) {
      debugPrint('[Weather] OPENWEATHER_API_KEY가 설정되지 않음');
      return null;
    }
    try {
      final currentUri = Uri.https('api.openweathermap.org', '/data/2.5/weather', {
        'lat': '$effectiveLat',
        'lon': '$effectiveLon',
        'appid': _apiKey,
        'units': 'metric',
        'lang': 'kr',
      });
      // 무료 "현재 날씨" API는 강수확률(pop)을 제공하지 않아, 5일/3시간 예보의
      // 가장 가까운 구간 값을 강수확률로 사용
      final forecastUri = Uri.https('api.openweathermap.org', '/data/2.5/forecast', {
        'lat': '$effectiveLat',
        'lon': '$effectiveLon',
        'appid': _apiKey,
        'units': 'metric',
        'lang': 'kr',
      });

      final responses = await Future.wait([
        http.get(currentUri).timeout(const Duration(seconds: 8)),
        http.get(forecastUri).timeout(const Duration(seconds: 8)),
      ]);

      if (responses[0].statusCode != 200 || responses[1].statusCode != 200) {
        debugPrint('[Weather] API 응답 실패: '
            '${responses[0].statusCode}, ${responses[1].statusCode}');
        return null;
      }

      final current = jsonDecode(responses[0].body) as Map<String, dynamic>;
      final forecast = jsonDecode(responses[1].body) as Map<String, dynamic>;

      final main = current['main'] as Map<String, dynamic>;
      final wind = current['wind'] as Map<String, dynamic>? ?? {};
      final weatherList = current['weather'] as List?;
      final icon = (weatherList != null && weatherList.isNotEmpty)
          ? (weatherList.first['icon'] as String? ?? '')
          : '';

      final forecastList = forecast['list'] as List?;
      final pop = (forecastList != null && forecastList.isNotEmpty)
          ? (((forecastList.first['pop'] as num?) ?? 0).toDouble() * 100).round()
          : 0;

      return WeatherSnapshot(
        tempC: ((main['temp'] as num?) ?? 0).toDouble(),
        humidity: ((main['humidity'] as num?) ?? 0).toInt(),
        precipitationPercent: pop,
        windSpeedMs: ((wind['speed'] as num?) ?? 0).toDouble(),
        iconCode: icon,
        fetchedAt: DateTime.now(),
        cityName: (current['name'] as String?) ?? '',
      );
    } catch (e) {
      debugPrint('[Weather] 조회 실패: $e');
      return null;
    }
  }
}
