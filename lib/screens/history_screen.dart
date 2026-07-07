import 'package:flutter/material.dart';
import '../models/app_settings.dart';
import '../models/workout_record.dart';
import '../services/database_service.dart';
import 'route_detail_screen.dart';

class HistoryScreen extends StatefulWidget {
  final AppSettings settings;

  const HistoryScreen({super.key, required this.settings});

  @override
  HistoryScreenState createState() => HistoryScreenState();
}

class HistoryScreenState extends State<HistoryScreen> {
  List<WorkoutRecord> _records = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    reload();
  }

  Future<void> reload() async {
    if (!mounted) return;
    setState(() => _loading = true);
    final records = await DatabaseService.instance.getWorkouts();
    if (mounted)
      setState(() {
        _records = records;
        _loading = false;
      });
  }

  Future<void> _delete(int id) async {
    await DatabaseService.instance.deleteWorkout(id);
    await reload();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final accent = cs.primary;
    final surface = cs.surface;
    final grey = cs.outline;

    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 28, 24, 8),
              child: Row(
                children: [
                  Text(
                    "운동 이력",
                    style: TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.bold,
                      color: widget.settings.preset.onBackground,
                    ),
                  ),
                  const Spacer(),
                  if (!_loading && _records.isNotEmpty)
                    Text(
                      "${_records.length}회",
                      style: TextStyle(
                          fontSize: 15,
                          color: widget.settings.preset.onBackgroundMuted),
                    ),
                ],
              ),
            ),
            if (!_loading && _records.isNotEmpty)
              _buildSummaryRow(accent, surface, grey),
            Expanded(
              child: _loading
                  ? Center(child: CircularProgressIndicator(color: accent))
                  : _records.isEmpty
                      ? _buildEmptyState()
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                          itemCount: _records.length,
                          itemBuilder: (_, i) =>
                              _buildCard(_records[i], accent, surface, grey),
                        ),
            ),
          ],
        ),
      ),
    );
  }

  // 최상단 통계 요약 바
  Widget _buildSummaryRow(Color accent, Color surface, Color grey) {
    final totalKm = _records.fold(0.0, (s, r) => s + r.distanceKm);
    final totalSec = _records.fold(0, (s, r) => s + r.durationSeconds);
    final avgPace = totalSec > 0 && totalKm > 0.01 ? totalSec / totalKm : 0.0;
    final avgM = (avgPace ~/ 60).toInt();
    final avgS = avgPace.toInt() % 60;
    final dividerColor =
        Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.12);

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _summaryItem(
              "총 거리", "${totalKm.toStringAsFixed(1)} km", accent, grey),
          Container(width: 1, height: 28, color: dividerColor),
          _summaryItem("총 시간", _fmtSec(totalSec), accent, grey),
          Container(width: 1, height: 28, color: dividerColor),
          _summaryItem(
            "평균 페이스",
            avgPace > 0
                ? "$avgM'${avgS.toString().padLeft(2, '0')}\"/km"
                : "--",
            accent,
            grey,
          ),
        ],
      ),
    );
  }

  Widget _summaryItem(String label, String value, Color accent, Color grey) =>
      Column(
        children: [
          Text(label,
              style: TextStyle(fontSize: 11, color: grey, letterSpacing: 0.5)),
          const SizedBox(height: 4),
          Text(value,
              style: TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w600, color: accent)),
        ],
      );

  // 개별 운동 기록 카드
  Widget _buildCard(
      WorkoutRecord record, Color accent, Color surface, Color grey) {
    return Dismissible(
      key: ValueKey(record.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: Colors.red.shade900.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Icon(Icons.delete_outline, color: Colors.red, size: 24),
      ),
      confirmDismiss: (_) async {
        return await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            backgroundColor: surface,
            title: const Text("기록 삭제"),
            content: const Text("이 운동 기록을 삭제할까요?"),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text("취소", style: TextStyle(color: grey)),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text("삭제", style: TextStyle(color: Colors.red)),
              ),
            ],
          ),
        );
      },
      onDismissed: (_) {
        if (record.id != null) _delete(record.id!);
      },
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => RouteDetailScreen(
              settings: widget.settings,
              record: record,
            ),
          ),
        ),
        child: Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: surface,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 날짜 + 요일
              Text(
                "${record.formattedDate} (${record.weekday})",
                style: TextStyle(fontSize: 13, color: grey),
              ),
              const SizedBox(height: 12),

              // 거리 (크게)
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    record.distanceKm.toStringAsFixed(2),
                    style: TextStyle(
                      fontSize: 44,
                      fontWeight: FontWeight.w700,
                      color: Theme.of(context).colorScheme.onSurface,
                      height: 1.0,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(left: 6, bottom: 5),
                    child:
                        Text("km", style: TextStyle(fontSize: 16, color: grey)),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // 시간 + 페이스
              Row(
                children: [
                  _statChip(Icons.timer_outlined, record.formattedDuration,
                      surface, grey),
                  const SizedBox(width: 12),
                  _statChip(Icons.speed_outlined, "${record.formattedPace}/km",
                      surface, grey),
                ],
              ),
              const SizedBox(height: 8),

              // 케이던스 + 칼로리
              Row(
                children: [
                  _statChip(Icons.directions_walk_outlined,
                      "${record.avgCadence} spm", surface, grey),
                  const SizedBox(width: 12),
                  _statChip(
                      Icons.local_fire_department_outlined,
                      "${record.caloriesBurned.toStringAsFixed(0)} kcal",
                      surface,
                      grey),
                ],
              ),
              const SizedBox(height: 10),

              // 당시 날씨 스냅샷
              Row(
                children: [
                  Icon(
                    record.hasWeather
                        ? Icons.wb_sunny_outlined
                        : Icons.cloud_off_outlined,
                    size: 13,
                    color: grey,
                  ),
                  const SizedBox(width: 5),
                  Text(record.weatherSummary,
                      style: TextStyle(fontSize: 12, color: grey)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statChip(IconData icon, String value, Color surface, Color grey) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: onSurface.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: grey),
          const SizedBox(width: 5),
          Text(value,
              style: TextStyle(
                  fontSize: 13, color: onSurface.withValues(alpha: 0.7))),
        ],
      ),
    );
  }

  Widget _buildEmptyState() => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.directions_run,
                size: 72, color: widget.settings.preset.onBackgroundMuted),
            const SizedBox(height: 16),
            Text("아직 운동 기록이 없습니다",
                style: TextStyle(
                    fontSize: 17,
                    color: widget.settings.preset.onBackgroundMuted)),
            const SizedBox(height: 8),
            Text("첫 번째 달팽이 런을 완료해보세요!",
                style: TextStyle(
                    fontSize: 14,
                    color: widget.settings.preset.onBackgroundMuted)),
          ],
        ),
      );

  String _fmtSec(int totalSec) {
    final h = totalSec ~/ 3600;
    final m = (totalSec % 3600) ~/ 60;
    if (h > 0) return "${h}h ${m}m";
    return "$m분";
  }
}
