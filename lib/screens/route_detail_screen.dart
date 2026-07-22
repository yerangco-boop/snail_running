import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import '../models/app_settings.dart';
import '../models/workout_record.dart';
import '../utils/route_utils.dart';

// 이력 카드 탭 시 그날 주행 경로를 지도로 보여주는 화면
class RouteDetailScreen extends StatefulWidget {
  final AppSettings settings;
  final WorkoutRecord record;

  const RouteDetailScreen({
    super.key,
    required this.settings,
    required this.record,
  });

  @override
  State<RouteDetailScreen> createState() => _RouteDetailScreenState();
}

class _RouteDetailScreenState extends State<RouteDetailScreen> {
  final MapController _mapController = MapController();

  @override
  void initState() {
    super.initState();
    if (widget.record.hasRoute) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _fitToRoute());
    }
  }

  // 경로 전체가 화면에 다 보이도록 bounds 계산해서 카메라를 맞춤
  void _fitToRoute() {
    final points = widget.record.routePoints!;
    if (points.length < 2) return;
    try {
      final bounds = LatLngBounds.fromPoints(points);
      _mapController.fitCamera(
        CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(48)),
      );
    } catch (_) {}
  }

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final preset = widget.settings.preset;
    final record = widget.record;
    final accent = widget.settings.accent;

    return Scaffold(
      backgroundColor: preset.background,
      appBar: AppBar(
        backgroundColor: preset.background,
        elevation: 0,
        iconTheme: IconThemeData(color: preset.onBackground),
        title: Text(
          '${record.formattedDate} 경로',
          style: TextStyle(color: preset.onBackground, fontSize: 18),
        ),
      ),
      body: record.hasRoute
          ? FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: record.routePoints!.first,
                initialZoom: 15,
              ),
              children: [
                TileLayer(
                  urlTemplate:
                      'https://basemaps.cartocdn.com/light_all/{z}/{x}/{y}.png',
                  userAgentPackageName: 'snail_running',
                ),
                PolylineLayer(
                  polylines: [buildRoutePolyline(record.routePoints!, accent)],
                ),
                MarkerLayer(
                  markers: [
                    for (final m in computeKmMarkers(record.routePoints!))
                      Marker(
                        point: m.point,
                        width: 36,
                        height: 20,
                        child: buildKmMarkerChip(m.km, accent),
                      ),
                    if (record.lapCompletionPoints != null)
                      for (var i = 0; i < record.lapCompletionPoints!.length; i++)
                        Marker(
                          point: record.lapCompletionPoints![i],
                          width: 34,
                          height: 20,
                          child: buildLapMarkerChip(i + 1, accent),
                        ),
                    Marker(
                      point: record.routePoints!.first,
                      width: 30,
                      height: 30,
                      child: buildRouteEndpointMarker(Icons.flag_rounded, accent),
                    ),
                    Marker(
                      point: record.routePoints!.last,
                      width: 30,
                      height: 30,
                      child: buildRouteEndpointMarker(Icons.sports_score_rounded, accent),
                    ),
                  ],
                ),
              ],
            )
          : Center(
              child: Text(
                '경로 정보 없음',
                style: TextStyle(
                  color: preset.onBackgroundMuted,
                  fontSize: 16,
                ),
              ),
            ),
    );
  }
}
