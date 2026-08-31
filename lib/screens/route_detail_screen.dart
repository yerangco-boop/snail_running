import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import '../models/app_settings.dart';
import '../models/workout_record.dart';
import '../utils/route_utils.dart';

// 이력 카드 탭 시 그날 기록을 한 화면에 모아 보여주는 상세 화면 —
// 상단 지도(경로 + km/랩 마커) + 통계 카드 + 랩별 기록을 스크롤로 이어 붙임
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

  ThemePreset get _p => widget.settings.preset;
  Color get _accent => widget.settings.accent;

  @override
  Widget build(BuildContext context) {
    final record = widget.record;

    return Scaffold(
      backgroundColor: _p.background,
      appBar: AppBar(
        backgroundColor: _p.background,
        elevation: 0,
        iconTheme: IconThemeData(color: _p.onBackground),
        title: Text(
          '${record.formattedDate} (${record.weekday})',
          style: TextStyle(color: _p.onBackground, fontSize: 18),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
        children: [
          _buildMapCard(),
          const SizedBox(height: 16),
          _sectionHeader('기록'),
          const SizedBox(height: 8),
          _buildStatsCard(),
          if (record.lapCount > 0) ...[
            const SizedBox(height: 16),
            _sectionHeader('랩 기록'),
            const SizedBox(height: 8),
            _buildLapCard(),
          ],
        ],
      ),
    );
  }

  // ── 지도 ──────────────────────────────────────────────────────────────────
  Widget _buildMapCard() {
    final record = widget.record;
    if (!record.hasRoute) {
      return Container(
        height: 160,
        alignment: Alignment.center,
        decoration: _cardDecoration(),
        child: Text('경로 정보 없음',
            style: TextStyle(color: _p.onBackgroundMuted, fontSize: 15)),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: SizedBox(
        height: 300,
        child: FlutterMap(
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
              polylines: [buildRoutePolyline(record.routePoints!, _accent)],
            ),
            MarkerLayer(
              markers: [
                for (final m in computeKmMarkers(record.routePoints!))
                  Marker(
                    point: m.point,
                    width: 36,
                    height: 20,
                    child: buildKmMarkerChip(m.km, _accent),
                  ),
                if (record.lapCompletionPoints != null)
                  for (var i = 0; i < record.lapCompletionPoints!.length; i++)
                    Marker(
                      point: record.lapCompletionPoints![i],
                      width: 34,
                      height: 20,
                      child: buildLapMarkerChip(i + 1, _accent),
                    ),
                Marker(
                  point: record.routePoints!.first,
                  width: 30,
                  height: 30,
                  child: buildRouteEndpointMarker(Icons.flag_rounded, _accent),
                ),
                Marker(
                  point: record.routePoints!.last,
                  width: 30,
                  height: 30,
                  child:
                      buildRouteEndpointMarker(Icons.sports_score_rounded, _accent),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ── 통계 ──────────────────────────────────────────────────────────────────
  Widget _buildStatsCard() {
    final r = widget.record;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: _cardDecoration(),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                r.distanceKm.toStringAsFixed(2),
                style: TextStyle(
                  fontSize: 48,
                  fontWeight: FontWeight.w700,
                  color: _p.surface,
                  height: 1.0,
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(left: 6, bottom: 6),
                child: Text('km',
                    style: TextStyle(fontSize: 16, color: _p.grey)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text('GPS 측정 거리',
              style: TextStyle(fontSize: 11, color: _p.grey, letterSpacing: 1)),
          const SizedBox(height: 18),
          Divider(color: _p.cardBorder, height: 1),
          const SizedBox(height: 16),
          _statRow('시간', r.formattedDuration),
          _statRow('평균 페이스', '${r.formattedPace}/km'),
          _statRow('평균 케이던스', '${r.avgCadence} spm'),
          if (r.totalSteps > 0) _statRow('총 걸음 수', '${_formatSteps(r.totalSteps)} 보'),
          _statRow('칼로리', '${r.caloriesBurned.toStringAsFixed(0)} kcal'),
          if (r.lapCount > 0) _statRow('바퀴 수', '${r.lapCount}바퀴'),
          _statRow('당시 날씨', r.weatherSummary),
        ],
      ),
    );
  }

  Widget _statRow(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: TextStyle(fontSize: 13, color: _p.grey)),
            Text(
              value,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: _p.onBackground,
              ),
            ),
          ],
        ),
      );

  // ── 랩 기록 ───────────────────────────────────────────────────────────────
  Widget _buildLapCard() {
    final r = widget.record;
    final intervals = r.lapIntervalSeconds;
    // 랩 완료 시점의 실측 GPS 누적 거리 / 구간 거리. v21 이전 기록에는 없어서 비어 있음
    final cumKm = r.lapSplitDistanceKm ?? const <double>[];
    final intervalKm = r.lapIntervalKm;
    final hasDistance = cumKm.length == intervals.length && intervals.isNotEmpty;

    // 가장 빠른/느린 랩을 찾아 강조 (랩이 2개 이상이고 서로 다를 때만 의미 있음)
    var fastest = -1, slowest = -1;
    if (intervals.length >= 2) {
      var minV = intervals[0], maxV = intervals[0];
      fastest = slowest = 0;
      for (var i = 1; i < intervals.length; i++) {
        if (intervals[i] < minV) { minV = intervals[i]; fastest = i; }
        if (intervals[i] > maxV) { maxV = intervals[i]; slowest = i; }
      }
      if (minV == maxV) { fastest = slowest = -1; }
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: _cardDecoration(),
      child: Column(
        children: [
          Row(
            children: [
              SizedBox(
                width: 34,
                child: Text('랩',
                    style: TextStyle(fontSize: 11, color: _p.grey, letterSpacing: 1)),
              ),
              Expanded(
                child: Text('누적 거리',
                    textAlign: TextAlign.right,
                    style: TextStyle(fontSize: 11, color: _p.grey, letterSpacing: 1)),
              ),
              Expanded(
                child: Text('구간 시간',
                    textAlign: TextAlign.right,
                    style: TextStyle(fontSize: 11, color: _p.grey, letterSpacing: 1)),
              ),
              Expanded(
                child: Text('구간 페이스',
                    textAlign: TextAlign.right,
                    style: TextStyle(fontSize: 11, color: _p.grey, letterSpacing: 1)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Divider(color: _p.cardBorder, height: 1),
          if (intervals.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                '${r.lapCount}바퀴 (랩별 상세 기록은 v18 이후 기록부터 표시됩니다)',
                style: TextStyle(fontSize: 13, color: _p.grey),
              ),
            )
          else
            for (var i = 0; i < intervals.length; i++)
              Container(
                padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 6),
                margin: const EdgeInsets.symmetric(vertical: 1),
                decoration: (i == fastest || i == slowest)
                    ? BoxDecoration(
                        color: (i == fastest ? _accent : _p.grey)
                            .withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      )
                    : null,
                child: Row(
                  children: [
                    SizedBox(
                      width: 34,
                      child: Row(
                        children: [
                          Text('${i + 1}',
                              style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: _accent)),
                          if (i == fastest)
                            Padding(
                              padding: const EdgeInsets.only(left: 3),
                              child: Icon(Icons.arrow_drop_up_rounded,
                                  size: 15, color: _accent),
                            )
                          else if (i == slowest)
                            Padding(
                              padding: const EdgeInsets.only(left: 3),
                              child: Icon(Icons.arrow_drop_down_rounded,
                                  size: 15, color: _p.grey),
                            ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Text(
                        hasDistance ? '${cumKm[i].toStringAsFixed(2)} km' : '--',
                        textAlign: TextAlign.right,
                        style: TextStyle(fontSize: 14, color: _p.onBackground),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        _fmtDuration(intervals[i]),
                        textAlign: TextAlign.right,
                        style: TextStyle(
                          fontSize: 14,
                          color: _p.onBackground,
                          fontWeight: (i == fastest || i == slowest)
                              ? FontWeight.w700
                              : FontWeight.normal,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        hasDistance
                            ? _fmtLapPace(intervals[i], intervalKm[i] * 1000)
                            : '--',
                        textAlign: TextAlign.right,
                        style: TextStyle(fontSize: 14, color: _p.onBackground),
                      ),
                    ),
                  ],
                ),
              ),
        ],
      ),
    );
  }

  String _fmtDuration(int seconds) {
    final m = seconds ~/ 60, s = seconds % 60;
    return "$m:${s.toString().padLeft(2, '0')}";
  }

  // 한 랩(=lapMeters)을 seconds에 돈 것을 1km 환산 페이스로
  String _fmtLapPace(int seconds, double lapMeters) {
    if (lapMeters <= 0) return '--';
    final secPerKm = seconds / (lapMeters / 1000);
    final m = secPerKm ~/ 60;
    final s = secPerKm.round() % 60;
    return "$m'${s.toString().padLeft(2, '0')}\"";
  }

  static String _formatSteps(int steps) {
    final digits = steps.toString();
    final buf = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) buf.write(',');
      buf.write(digits[i]);
    }
    return buf.toString();
  }

  // ── 공통 ──────────────────────────────────────────────────────────────────
  Widget _sectionHeader(String text) => Padding(
        padding: const EdgeInsets.only(left: 8),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 12,
            color: _p.onBackgroundMuted,
            letterSpacing: 1.2,
            fontWeight: FontWeight.w600,
          ),
        ),
      );

  BoxDecoration _cardDecoration() => BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: _p.cardGradient,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _p.cardBorder),
        boxShadow: _p.cardShadow,
      );
}
