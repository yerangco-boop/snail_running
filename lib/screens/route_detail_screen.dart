import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import '../widgets/clay/clay_card.dart';
import '../theme/tokens.dart';
import '../models/app_settings.dart';
import '../models/workout_record.dart';
import '../utils/route_utils.dart';
import '../utils/elevation_profile.dart';

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
  // 고도 기록이 없거나(2026-11-15 이전 기록) 너무 적으면 null
  ElevationProfile? _elevation;
  // 기압계 높이로 그렸으면 true (없으면 GPS 고도로 그림)
  bool _elevationFromBaro = false;

  @override
  void initState() {
    super.initState();
    final r = widget.record;
    // 기압계 높이가 있으면 그것을 우선 사용 — GPS 고도보다 잡음이 작아 덜 다듬음.
    // 반경 2(5점)·1.5m는 임의로 정한 시험값 — 실측 비교 후 조정
    final baro = r.routeBaroHeights;
    if (r.hasRoute && baro != null) {
      _elevation = ElevationProfile.compute(
        r.routePoints!,
        baro,
        totalDistanceKm: r.distanceKm,
        smoothRadius: 2,
        climbThresholdM: 1.5,
      );
      _elevationFromBaro = _elevation != null;
    }
    if (_elevation == null && r.hasRoute && r.routeAltitudes != null) {
      _elevation = ElevationProfile.compute(
        r.routePoints!,
        r.routeAltitudes!,
        totalDistanceKm: r.distanceKm,
      );
    }
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
          const SizedBox(height: 16),
          _sectionHeader('고도'),
          const SizedBox(height: 8),
          _buildElevationCard(),
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
      return const SizedBox(
        height: 160,
        child: ClayCard(
          radius: 24,
          child: Center(
            child: Text('경로 정보 없음',
                style: TextStyle(color: Tokens.inkMuted, fontSize: 15)),
          ),
        ),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
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
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'snail_running',
              tileBuilder: (context, tileWidget, tile) => ColorFiltered(
                colorFilter: kMutedMapFilter,
                child: tileWidget,
              ),
            ),
            // 지도 출처 표시 — OpenStreetMap(ODbL) 표기가 이용 조건임.
            // 화면을 가리지 않도록 오른쪽 아래 ⓘ 버튼을 눌렀을 때만 펼쳐지는 방식
            const RichAttributionWidget(
              showFlutterMapAttribution: false,
              attributions: [
                TextSourceAttribution('OpenStreetMap contributors'),
              ],
            ),
            PolylineLayer(
                polylines: buildClayRoutePolylines(record.routePoints!)),
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
                  child: buildRouteEndpointMarker(
                      Icons.sports_score_rounded, _accent),
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
    return ClayCard(
      radius: 24,
      padding: const EdgeInsets.all(20),
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
                  color: Tokens.coralDisplay,
                  height: 1.0,
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(left: 6, bottom: 6),
                child:
                    Text('km', style: TextStyle(fontSize: 16, color: _p.grey)),
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
          if (r.totalSteps > 0)
            _statRow('총 걸음 수', '${_formatSteps(r.totalSteps)} 보'),
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

  // ── 고도 ──────────────────────────────────────────────────────────────────
  Widget _buildElevationCard() {
    final e = _elevation;
    if (e == null) {
      return const ClayCard(
        radius: 24,
        padding: EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        child: Text(
          '고도 기록이 없는 러닝이에요.\n고도 기능을 넣은 버전부터 달린 기록에 표시됩니다.',
          style: TextStyle(fontSize: 13, color: Tokens.inkMuted, height: 1.5),
        ),
      );
    }
    return ClayCard(
      radius: 24,
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: _elevStat('오르막', '+${e.ascentM.round()}', 'm')),
              Expanded(child: _elevStat('내리막', '-${e.descentM.round()}', 'm')),
              Expanded(child: _elevStat('고도차', '${e.rangeM.round()}', 'm')),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 150,
            child: CustomPaint(painter: _ElevationChartPainter(e)),
          ),
          const SizedBox(height: 10),
          Text(
            _elevationFromBaro
                ? '출발 지점을 0m로 본 높이예요. 기압계로 잰 값(시험 중)이에요.'
                : '출발 지점을 0m로 본 높이예요. GPS 측정값이라 몇 m 오차가 있을 수 있어요.',
            style: const TextStyle(fontSize: 11, color: Tokens.inkMuted, height: 1.4),
          ),
        ],
      ),
    );
  }

  Widget _elevStat(String label, String value, String unit) => Column(
        children: [
          Text(label, style: const TextStyle(fontSize: 12, color: Tokens.inkMuted)),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                value,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: Tokens.ink,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(width: 2),
              Text(unit,
                  style: const TextStyle(fontSize: 13, color: Tokens.inkMuted)),
            ],
          ),
        ],
      );

  // ── 랩 기록 ───────────────────────────────────────────────────────────────
  Widget _buildLapCard() {
    final r = widget.record;
    final intervals = r.lapIntervalSeconds;
    // 랩 완료 시점의 실측 GPS 누적 거리 / 구간 거리. v21 이전 기록에는 없어서 비어 있음
    final cumKm = r.lapSplitDistanceKm ?? const <double>[];
    final intervalKm = r.lapIntervalKm;
    final hasDistance =
        cumKm.length == intervals.length && intervals.isNotEmpty;

    // 가장 빠른/느린 랩을 찾아 강조 (랩이 2개 이상이고 서로 다를 때만 의미 있음)
    var fastest = -1, slowest = -1;
    if (intervals.length >= 2) {
      var minV = intervals[0], maxV = intervals[0];
      fastest = slowest = 0;
      for (var i = 1; i < intervals.length; i++) {
        if (intervals[i] < minV) {
          minV = intervals[i];
          fastest = i;
        }
        if (intervals[i] > maxV) {
          maxV = intervals[i];
          slowest = i;
        }
      }
      if (minV == maxV) {
        fastest = slowest = -1;
      }
    }

    return ClayCard(
      radius: 24,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      child: Column(
        children: [
          Row(
            children: [
              SizedBox(
                width: 34,
                child: Text('랩',
                    style: TextStyle(
                        fontSize: 11, color: _p.grey, letterSpacing: 1)),
              ),
              Expanded(
                child: Text('누적 거리',
                    textAlign: TextAlign.right,
                    style: TextStyle(
                        fontSize: 11, color: _p.grey, letterSpacing: 1)),
              ),
              Expanded(
                child: Text('구간 시간',
                    textAlign: TextAlign.right,
                    style: TextStyle(
                        fontSize: 11, color: _p.grey, letterSpacing: 1)),
              ),
              Expanded(
                child: Text('구간 페이스',
                    textAlign: TextAlign.right,
                    style: TextStyle(
                        fontSize: 11, color: _p.grey, letterSpacing: 1)),
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
                                  color: Tokens.coralText)),
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
                        hasDistance
                            ? '${cumKm[i].toStringAsFixed(2)} km'
                            : '--',
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
}

// 거리(가로) × 출발점 기준 높이(세로) 면 그래프.
// 평지에서 몇 m 잡음이 산처럼 보이지 않도록 세로 범위는 최소 10m로 잡는다
class _ElevationChartPainter extends CustomPainter {
  _ElevationChartPainter(this.e);

  final ElevationProfile e;

  static const double _minSpanM = 10;
  static const double _leftAxis = 40;
  static const double _bottomAxis = 18;

  @override
  void paint(Canvas canvas, Size size) {
    final xs = e.distanceKm;
    final ys = e.heightM;
    if (xs.length < 2) return;

    var lo = e.minM, hi = e.maxM;
    if (hi - lo < _minSpanM) {
      final mid = (hi + lo) / 2;
      lo = mid - _minSpanM / 2;
      hi = mid + _minSpanM / 2;
    }
    final x0 = xs.first;
    final xSpan = (xs.last - x0) <= 0 ? 1.0 : xs.last - x0;

    final plot = Rect.fromLTRB(_leftAxis, 6, size.width, size.height - _bottomAxis);
    Offset at(int i) => Offset(
          plot.left + (xs[i] - x0) / xSpan * plot.width,
          plot.bottom - (ys[i] - lo) / (hi - lo) * plot.height,
        );

    // 점이 많으면 화면 폭 정도로 솎아서 그림
    final step = math.max(1, (xs.length / plot.width).floor());
    final line = Path()..moveTo(at(0).dx, at(0).dy);
    for (var i = step; i < xs.length; i += step) {
      final p = at(i);
      line.lineTo(p.dx, p.dy);
    }
    final last = at(xs.length - 1);
    line.lineTo(last.dx, last.dy);

    final area = Path.from(line)
      ..lineTo(last.dx, plot.bottom)
      ..lineTo(plot.left, plot.bottom)
      ..close();

    final grid = Paint()
      ..color = Tokens.inkMuted.withValues(alpha: 0.18)
      ..strokeWidth = 1;
    canvas.drawLine(plot.topLeft, plot.topRight, grid);
    canvas.drawLine(plot.bottomLeft, plot.bottomRight, grid);
    if (lo < 0 && hi > 0) {
      final zeroY = plot.bottom - (0 - lo) / (hi - lo) * plot.height;
      canvas.drawLine(Offset(plot.left, zeroY), Offset(plot.right, zeroY), grid);
    }

    canvas.drawPath(
      area,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Tokens.coralFace.withValues(alpha: 0.40),
            Tokens.coralFace.withValues(alpha: 0.05),
          ],
        ).createShader(plot),
    );
    canvas.drawPath(
      line,
      Paint()
        ..color = Tokens.coralFace
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );

    _label(canvas, _fmtM(hi), Offset(0, plot.top), alignBottom: false);
    _label(canvas, _fmtM(lo), Offset(0, plot.bottom), alignBottom: true);
    _label(canvas, '0 km', Offset(plot.left, size.height - _bottomAxis + 4));
    _label(canvas, '${xs.last.toStringAsFixed(2)} km',
        Offset(plot.right, size.height - _bottomAxis + 4),
        alignRight: true);
  }

  String _fmtM(double v) {
    final r = v.round();
    return r > 0 ? '+$r m' : '$r m';
  }

  void _label(Canvas canvas, String text, Offset pos,
      {bool alignRight = false, bool? alignBottom}) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(
          fontSize: 11,
          color: Tokens.inkMuted,
          fontFeatures: [FontFeature.tabularFigures()],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final dx = alignRight ? pos.dx - tp.width : pos.dx;
    var dy = pos.dy;
    if (alignBottom == true) dy -= tp.height;
    if (alignBottom == false) dy -= 1;
    tp.paint(canvas, Offset(dx, dy));
  }

  @override
  bool shouldRepaint(covariant _ElevationChartPainter old) => old.e != e;
}
