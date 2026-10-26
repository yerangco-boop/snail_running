import 'package:flutter/material.dart';
import '../theme/tokens.dart';
import '../models/app_settings.dart';
import '../models/workout_record.dart';
import '../services/database_service.dart';
import 'route_detail_screen.dart';

// 요약 바의 집계 기간 (나이키런의 주/월/년/전체와 같은 방식)
enum _Period { week, month, year, all }

class HistoryScreen extends StatefulWidget {
  final AppSettings settings;

  const HistoryScreen({super.key, required this.settings});

  @override
  HistoryScreenState createState() => HistoryScreenState();
}

class HistoryScreenState extends State<HistoryScreen> {
  List<WorkoutRecord> _records = [];
  bool _loading = true;
  _Period _period = _Period.all;
  // 0 = 이번 주/월/년, -1 = 직전 …
  int _offset = 0;

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


  // 선택한 기간의 [시작, 끝) — 전체면 null. 주는 월요일 시작
  (DateTime, DateTime)? _periodRange() {
    final now = DateTime.now();
    switch (_period) {
      case _Period.week:
        final monday = DateTime(now.year, now.month, now.day)
            .subtract(Duration(days: now.weekday - 1));
        final start = DateTime(monday.year, monday.month, monday.day + 7 * _offset);
        return (start, DateTime(start.year, start.month, start.day + 7));
      case _Period.month:
        return (DateTime(now.year, now.month + _offset, 1),
            DateTime(now.year, now.month + _offset + 1, 1));
      case _Period.year:
        return (DateTime(now.year + _offset, 1, 1), DateTime(now.year + _offset + 1, 1, 1));
      case _Period.all:
        return null;
    }
  }

  List<WorkoutRecord> get _periodRecords {
    final range = _periodRange();
    if (range == null) return _records;
    return _records
        .where((r) => !r.date.isBefore(range.$1) && r.date.isBefore(range.$2))
        .toList();
  }

  // 더 이전 기간에 기록이 남아 있을 때만 이전 버튼 활성
  bool get _canGoPrev {
    final range = _periodRange();
    if (range == null || _records.isEmpty) return false;
    return _records.any((r) => r.date.isBefore(range.$1));
  }

  String get _rangeLabel {
    final range = _periodRange();
    if (range == null) return '전체 기간';
    final start = range.$1;
    switch (_period) {
      case _Period.week:
        final last = range.$2.subtract(const Duration(days: 1));
        final endText = last.month == start.month ? '${last.day}일' : '${last.month}월 ${last.day}일';
        return '${start.month}월 ${start.day}일 – $endText';
      case _Period.month:
        return '${start.year}년 ${start.month}월';
      case _Period.year:
        return '${start.year}년';
      case _Period.all:
        return '전체 기간';
    }
  }

  void _selectPeriod(_Period p) => setState(() {
        _period = p;
        _offset = 0;
      });

  Widget _buildPeriodSelector() {
    const labels = {
      _Period.week: '주',
      _Period.month: '월',
      _Period.year: '년',
      _Period.all: '전체',
    };
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: Tokens.card,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: widget.settings.preset.cardBorder),
            ),
            child: Row(
              children: [
                for (final p in _Period.values)
                  Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => _selectPeriod(p),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 11),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: _period == p ? Tokens.coralFace : Colors.transparent,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          labels[p]!,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: _period == p ? FontWeight.w700 : FontWeight.w500,
                            color: _period == p ? Tokens.ink : Tokens.inkMuted,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          SizedBox(
            height: 48,
            child: Row(
              children: [
                if (_period != _Period.all)
                  IconButton(
                    tooltip: '이전',
                    onPressed: _canGoPrev ? () => setState(() => _offset--) : null,
                    icon: const Icon(Icons.chevron_left_rounded),
                    color: Tokens.ink,
                    disabledColor: Tokens.ink.withValues(alpha: 0.25),
                  )
                else
                  const SizedBox(width: 48),
                Expanded(
                  child: Text(
                    _rangeLabel,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w600, color: Tokens.ink),
                  ),
                ),
                if (_period != _Period.all)
                  IconButton(
                    tooltip: '다음',
                    onPressed: _offset < 0 ? () => setState(() => _offset++) : null,
                    icon: const Icon(Icons.chevron_right_rounded),
                    color: Tokens.ink,
                    disabledColor: Tokens.ink.withValues(alpha: 0.25),
                  )
                else
                  const SizedBox(width: 48),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final preset = widget.settings.preset;
    final accent = preset.accent;
    final surface = preset.surface;
    final grey = preset.grey;

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
            if (!_loading && _records.isNotEmpty) ...[
              _buildPeriodSelector(),
              _buildSummaryRow(preset, accent, grey),
            ],
            Expanded(
              child: _loading
                  ? Center(child: CircularProgressIndicator(color: accent))
                  : _records.isEmpty
                      ? _buildEmptyState()
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                          itemCount: _records.length,
                          itemBuilder: (_, i) =>
                              _buildCard(_records[i], preset, accent, surface, grey),
                        ),
            ),
          ],
        ),
      ),
    );
  }

  // 최상단 통계 요약 바
  Widget _buildSummaryRow(ThemePreset preset, Color accent, Color grey) {
    final recs = _periodRecords;
    final totalKm = recs.fold(0.0, (s, r) => s + r.distanceKm);
    final totalSec = recs.fold(0, (s, r) => s + r.durationSeconds);
    final avgPace = totalSec > 0 && totalKm > 0.01 ? totalSec / totalKm : 0.0;
    final avgM = (avgPace ~/ 60).toInt();
    final avgS = avgPace.toInt() % 60;
    final dividerColor = preset.onSurface.withValues(alpha: 0.12);

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: preset.cardGradient,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: preset.cardBorder),
        boxShadow: preset.cardShadow,
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
                  fontSize: 15, fontWeight: FontWeight.w600, color: Tokens.coralText)),
        ],
      );

  // 개별 운동 기록 카드
  Widget _buildCard(WorkoutRecord record, ThemePreset preset, Color accent,
      Color surface, Color grey) {
    return Dismissible(
      key: ValueKey(record.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: Tokens.danger.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Icon(Icons.delete_outline, color: Tokens.danger, size: 24),
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
                child: const Text("삭제", style: TextStyle(color: Tokens.danger)),
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
            gradient: LinearGradient(
              begin: Alignment.topRight,
              end: Alignment.bottomLeft,
              colors: preset.cardGradient,
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: preset.cardBorder),
            boxShadow: preset.cardShadow,
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
                      color: Tokens.coralDisplay,
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

              // 시간·페이스·케이던스·칼로리·바퀴 — Row는 폭이 모자라면 카드 밖으로
              // 넘쳐서(15바퀴 칩이 오른쪽으로 잘림) Wrap으로 자동 줄바꿈되게 함
              Wrap(
                spacing: 12,
                runSpacing: 8,
                children: [
                  _statChip(Icons.timer_outlined, record.formattedDuration,
                      surface, grey),
                  _statChip(Icons.speed_outlined, "${record.formattedPace}/km",
                      surface, grey),
                  _statChip(Icons.directions_walk_outlined,
                      "${record.avgCadence} spm", surface, grey),
                  _statChip(
                      Icons.local_fire_department_outlined,
                      "${record.caloriesBurned.toStringAsFixed(0)} kcal",
                      surface,
                      grey),
                  if (record.lapCount > 0)
                    _statChip(Icons.replay_circle_filled_outlined,
                        "${record.lapCount}바퀴", surface, grey),
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
                  fontSize: 13, color: Tokens.ink)),
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
