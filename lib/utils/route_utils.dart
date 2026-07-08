import 'package:flutter/material.dart';
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
