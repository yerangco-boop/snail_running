import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

class KmMarkerPoint {
  final LatLng point;
  final int km;

  const KmMarkerPoint(this.point, this.km);
}

// 경로(points)를 따라 누적거리 1km/2km/... 지점을 선형 보간으로 계산
List<KmMarkerPoint> computeKmMarkers(List<LatLng> points) {
  if (points.length < 2) return [];

  final markers = <KmMarkerPoint>[];
  var cumulativeMeters = 0.0;
  var nextKm = 1;

  for (var i = 1; i < points.length; i++) {
    final prev = points[i - 1];
    final curr = points[i];
    final segMeters = Geolocator.distanceBetween(
      prev.latitude, prev.longitude,
      curr.latitude, curr.longitude,
    );
    final segStart = cumulativeMeters;
    cumulativeMeters += segMeters;

    while (nextKm * 1000 <= cumulativeMeters) {
      final targetMeters = nextKm * 1000;
      final t = segMeters > 0 ? (targetMeters - segStart) / segMeters : 0.0;
      final lat = prev.latitude + (curr.latitude - prev.latitude) * t;
      final lon = prev.longitude + (curr.longitude - prev.longitude) * t;
      markers.add(KmMarkerPoint(LatLng(lat, lon), nextKm));
      nextKm++;
    }
  }

  return markers;
}

// 지도 위 km 지점 라벨용 작은 배지
Widget buildKmMarkerChip(int km, Color color) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: Colors.white, width: 1.5),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.25),
          blurRadius: 4,
          offset: const Offset(0, 1),
        ),
      ],
    ),
    child: Text(
      '${km}km',
      style: const TextStyle(
        color: Colors.white,
        fontSize: 10,
        fontWeight: FontWeight.bold,
      ),
    ),
  );
}

// 주행 경로를 그리는 폴리라인 — 흰 테두리(glow)로 밝은 배경 지도 위에서도
// 또렷하게 도드라지도록 함(나이키류 러닝 앱의 두꺼운 입체 경로선 스타일)
Polyline buildRoutePolyline(List<LatLng> points, Color color) {
  return Polyline(
    points: points,
    color: color,
    strokeWidth: 5,
    borderStrokeWidth: 2.5,
    borderColor: Colors.white.withValues(alpha: 0.9),
  );
}

// 출발/도착 지점 마커 — 흰 원 배경 + 그림자 위에 아이콘을 얹은 카드형 스타일
Widget buildRouteEndpointMarker(IconData icon, Color color) {
  return Container(
    decoration: BoxDecoration(
      color: Colors.white,
      shape: BoxShape.circle,
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.3),
          blurRadius: 6,
          offset: const Offset(0, 2),
        ),
      ],
    ),
    padding: const EdgeInsets.all(5),
    child: Icon(icon, color: color, size: 18),
  );
}

// 실시간 현재 위치 마커 — 은은한 펄스 링 + 흰 테두리 원
Widget buildLiveLocationMarker(Color color) {
  return Stack(
    alignment: Alignment.center,
    children: [
      Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color.withValues(alpha: 0.18),
        ),
      ),
      Container(
        width: 14,
        height: 14,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 2),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.25),
              blurRadius: 3,
            ),
          ],
        ),
      ),
    ],
  );
}
