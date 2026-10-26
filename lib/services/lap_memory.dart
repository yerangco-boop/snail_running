import 'dart:convert';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 마지막으로 배운 "한 바퀴 거리"와 그 코스의 시작 위치를 저장해 둔다.
///
/// 한 바퀴 거리를 못 배운 채 화면이 꺼지면(10/19: 시작 2분 만에 꺼짐) 위치로
/// 바퀴를 판정하게 되는데, 그때 GPS 오차(60m+)만큼 판정 반경이 넓어져 가짜 바퀴가
/// 생겼다(21바퀴, 실제 약 12~13). 같은 코스에서 시작하면 저장된 거리를 바로 써서
/// 처음부터 거리 기반으로 센다.
class LapMemory {
  static const String _prefsKey = 'lap_memory_v1';
  static const double matchRadiusMeters = 150.0;

  final double lat;
  final double lon;
  final double lapMeters;

  const LapMemory({required this.lat, required this.lon, required this.lapMeters});

  /// [start]가 저장된 코스 시작점 근처면 저장된 한 바퀴 거리, 아니면 null.
  double? seedFor(LatLng start) {
    final d = const Distance().as(LengthUnit.Meter, LatLng(lat, lon), start);
    return d <= matchRadiusMeters ? lapMeters : null;
  }

  Map<String, dynamic> toJson() => {'lat': lat, 'lon': lon, 'lap': lapMeters};

  static LapMemory? fromJson(Map<String, dynamic> j) {
    final lat = j['lat'], lon = j['lon'], lap = j['lap'];
    if (lat is! num || lon is! num || lap is! num) return null;
    if (lap < 100 || lap > 2000) return null;
    return LapMemory(lat: lat.toDouble(), lon: lon.toDouble(), lapMeters: lap.toDouble());
  }

  static Future<LapMemory?> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw == null) return null;
      return fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<void> save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, jsonEncode(toJson()));
    } catch (_) {}
  }
}
