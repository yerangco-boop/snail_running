import 'package:flutter/material.dart';
import '../../services/weather_service.dart';
import '../../theme/tokens.dart';
import '../clay/clay_background.dart';
import '../clay/clay_card.dart';
import '../clay/clay_chip.dart';
import '../clay/clay_image_button.dart';
import '../clay/clay_text.dart';
import '../snail_animation.dart';

/// 시작 전 홈 화면 (C안 점토 시안). 상태는 가지지 않고, 값과 콜백을 받아 그리기만 한다.
class PreRunView extends StatelessWidget {
  const PreRunView({
    super.key,
    required this.placeText,
    required this.weather,
    required this.weatherFallbackText,
    required this.isDistanceGoal,
    required this.goalValueText,
    required this.paceText,
    required this.bpm,
    required this.streakDays,
    required this.onGoalTap,
    required this.onStart,
    this.permissionBanner,
  });

  /// 목표 페이스 표시값 (예: 10'38"/km). 설정 전이면 "--"
  final String paceText;

  /// 설정에 저장된 메트로놈 BPM — 페이스와 서로 연동되는 한 쌍
  final int bpm;

  /// "오후 3:12 기준 · 충주시 목행동" 같은 지역·시각 한 줄
  final String placeText;

  /// 날씨를 못 받았을 때(또는 확인 중일 때) 대신 보여 줄 글자
  final String weatherFallbackText;
  final WeatherSnapshot? weather;
  final bool isDistanceGoal;
  final String goalValueText;
  final int streakDays;
  final VoidCallback onGoalTap;
  final VoidCallback onStart;
  final Widget? permissionBanner;

  @override
  Widget build(BuildContext context) {
    return ClayBackground(
      child: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            // 화면 높이에 맞춰 달팽이 크기를 줄여 목표 카드·시작 버튼이 첫 화면에 다 들어오게 함.
            // 고정 영역(제목·날씨·문구·목표 카드·시작 버튼)의 대략적인 높이를 빼고 남는 만큼만 달팽이에게 줌.
            // 글자 크기를 키운 경우를 위해 시스템 글자 배율도 반영.
            final textScale = MediaQuery.textScalerOf(context).scale(1.0);
            final narrow = constraints.maxWidth < 340;
            final compact = constraints.maxHeight < 600 || narrow;
            final startSize = constraints.maxHeight >= 700 ? 100.0 : (compact ? 72.0 : 84.0);
            // 낮은 화면에서는 보조 정보인 연속 카드를 접어 목표 카드와 시작 버튼을 우선 보여 줌
            final showStreak = streakDays > 0 && constraints.maxHeight >= 600 && !narrow;
            // 낮은 화면은 여유 없이 보수적으로, 충분히 큰 화면은 달팽이를 더 키워 남는 공간을 채움
            // (그래도 남는 높이는 아래 스크롤 영역에서 구역 사이로 고르게 나뉨)
            final fixed = ((compact ? 440 : 380) + startSize + (permissionBanner != null ? 92 : 0) + (showStreak ? 80 : 0)) *
                (1 + (textScale - 1) * 0.6);
            final snailHeight = (constraints.maxHeight - fixed).clamp(compact ? 64.0 : 96.0, 240.0);
            final padTop = compact ? 8.0 : 14.0;
            return Column(
              children: [
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, box) => SingleChildScrollView(
                      padding: EdgeInsets.fromLTRB(22, padTop, 22, 8),
                      // 내용이 화면보다 짧으면 남는 높이를 구역 사이에 고르게 나눔 (카드와 시작 버튼 사이만 비어 보이지 않게)
                      child: ConstrainedBox(
                        constraints: BoxConstraints(minHeight: box.maxHeight - padTop - 8),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  '달팽이 러닝',
                                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: Tokens.ink),
                                ),
                                // 배너는 자체 좌우 여백(16)이 있어 화면 여백(22)과 겹치지 않게 당겨 붙임
                                if (permissionBanner != null)
                                  Transform.translate(
                                      offset: const Offset(-16, 0),
                                      child: SizedBox(width: MediaQuery.sizeOf(context).width, child: permissionBanner)),
                                const SizedBox(height: 8),
                                _WeatherRow(placeText: placeText, weather: weather, fallbackText: weatherFallbackText),
                              ],
                            ),
                            _HeroRow(snailHeight: snailHeight, showSubtitle: !compact),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                _GoalCard(
                                  isDistanceGoal: isDistanceGoal,
                                  valueText: goalValueText,
                                  paceText: paceText,
                                  bpm: bpm,
                                  stackInfo: narrow,
                                  onTap: onGoalTap,
                                  compact: compact,
                                ),
                                if (showStreak) ...[
                                  const SizedBox(height: 14),
                                  _StreakCard(days: streakDays),
                                ],
                              ],
                            ),
                            // 마지막 빈 칸: 카드 아래에도 다른 구간과 같은 간격이 생기게 하는 자리
                            const SizedBox(height: 14),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                // 시작 버튼은 스크롤 영역 아래에 따로 놓아 카드와 겹치지 않음
                Padding(
                  padding: const EdgeInsets.only(top: 2, bottom: 10),
                  child: ClayImageButton(
                    asset: 'assets/ui/btn_start.webp',
                    size: startSize,
                    label: '시작',
                    onTap: onStart,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _WeatherRow extends StatelessWidget {
  const _WeatherRow({required this.placeText, required this.weather, required this.fallbackText});

  final String placeText;
  final WeatherSnapshot? weather;
  final String fallbackText;

  @override
  Widget build(BuildContext context) {
    final w = weather;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (placeText.isNotEmpty)
          Row(
            children: [
              if (w != null) ...[
                Image.asset(_conditionAsset(w.iconCode), width: 26, height: 26, excludeFromSemantics: true),
                const SizedBox(width: 6),
              ],
              Flexible(
                child: Text(placeText,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13, color: Tokens.inkMuted)),
              ),
            ],
          ),
        const SizedBox(height: 8),
        if (w == null)
          Text(fallbackText, style: const TextStyle(fontSize: 13, color: Tokens.inkMuted))
        else
          Row(
            children: [
              _WeatherChip(asset: 'thermometer', label: '기온', value: '${w.tempC.round()}°'),
              const SizedBox(width: 8),
              _WeatherChip(asset: 'droplet', label: '습도', value: '${w.humidity}%'),
              const SizedBox(width: 8),
              _WeatherChip(asset: 'umbrella_with_rain_drops', label: '강수', value: '${w.precipitationPercent}%'),
              const SizedBox(width: 8),
              _WeatherChip(asset: 'dashing_away', label: '풍속', value: '${w.windSpeedMs.toStringAsFixed(1)}m/s'),
            ],
          ),
      ],
    );
  }
}

// OpenWeatherMap 아이콘 코드(예: "10d") → Fluent Emoji 3D 날씨 그림
String _conditionAsset(String code) {
  final night = code.endsWith('n');
  final name = switch (code.length >= 2 ? code.substring(0, 2) : '') {
    '01' => night ? 'crescent_moon' : 'sun',
    '02' => 'sun_behind_small_cloud',
    '03' || '04' => 'cloud',
    '09' || '10' => 'cloud_with_rain',
    '11' => 'cloud_with_lightning_and_rain',
    '13' => 'cloud_with_snow',
    '50' => 'fog',
    _ => 'sun_behind_small_cloud',
  };
  return 'assets/weather/$name.png';
}

class _WeatherChip extends StatelessWidget {
  const _WeatherChip({required this.asset, required this.label, required this.value});

  final String asset;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: ClayCard(
        radius: 18,
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset('assets/weather/$asset.png', width: 24, height: 24, excludeFromSemantics: true),
              Text(label, style: const TextStyle(fontSize: 11, color: Tokens.inkMuted)),
              Text(value, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Tokens.ink)),
            ],
          ),
        ),
      ),
    );
  }
}

class _HeroRow extends StatelessWidget {
  const _HeroRow({required this.snailHeight, required this.showSubtitle});

  final double snailHeight;
  final bool showSubtitle;

  @override
  Widget build(BuildContext context) {
    // 글 묶음과 달팽이를 같은 가로줄의 세로 중앙에 맞춰 좌우·상하 균형을 잡음
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const _KeepWordLines(
                // 단어 중간에서 끊기지 않게, 한 줄에 다 들어가면 2줄 아니면 3줄로 나눔
                candidates: [
                  ['오늘도 천천히,', '같이 달려요!'],
                  ['오늘도', '천천히,', '같이 달려요!'],
                ],
                fontSize: 27,
              ),
              if (showSubtitle) ...[
                const SizedBox(height: 8),
                const _KeepWordLines(
                  candidates: [
                    ['천천히 달려도,', '매일 조금씩 더 건강해져요.'],
                    ['천천히 달려도,', '매일 조금씩', '더 건강해져요.'],
                  ],
                  fontSize: 13,
                  isHeadline: false,
                ),
              ],
            ],
          ),
        ),
        const SizedBox(width: 8),
        SnailAnimation(kind: SnailKind.home, bodyHeight: snailHeight),
      ],
    );
  }
}

/// 한글은 단어 중간에서 줄이 바뀌면 오류처럼 보이므로, 미리 나눠 둔 줄 묶음 중
/// 모든 줄이 가로 폭에 들어가는 첫 번째 묶음을 쓴다. 어느 것도 안 들어가면 마지막 묶음을 비율로 줄여 맞춘다.
class _KeepWordLines extends StatelessWidget {
  const _KeepWordLines({required this.candidates, required this.fontSize, this.isHeadline = true});

  final List<List<String>> candidates;
  final double fontSize;
  final bool isHeadline;

  @override
  Widget build(BuildContext context) {
    final style = isHeadline
        ? ClayText.headline(fontSize: fontSize)
        : TextStyle(fontSize: fontSize, height: 1.5, color: Tokens.inkMuted);
    final scaler = MediaQuery.textScalerOf(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        double widthOf(String line) {
          final tp = TextPainter(
            text: TextSpan(text: line, style: style),
            textDirection: TextDirection.ltr,
            textScaler: scaler,
            maxLines: 1,
          )..layout();
          return tp.width;
        }

        var chosen = candidates.last;
        for (final lines in candidates) {
          if (lines.every((l) => widthOf(l) <= constraints.maxWidth)) {
            chosen = lines;
            break;
          }
        }
        return FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(chosen.join('\n'), style: style, softWrap: false),
        );
      },
    );
  }
}

class _GoalCard extends StatelessWidget {
  const _GoalCard({
    required this.isDistanceGoal,
    required this.valueText,
    required this.paceText,
    required this.bpm,
    required this.stackInfo,
    required this.onTap,
    this.compact = false,
  });

  final bool isDistanceGoal;
  final String valueText;
  final String paceText;
  final int bpm;

  /// 좁은 화면에서는 페이스·BPM을 숫자 옆이 아니라 아래 한 줄로 내림
  final bool stackInfo;
  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return ClayCard(
      radius: 36,
      padding: const EdgeInsets.fromLTRB(22, 14, 16, 20),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                isDistanceGoal ? '목표 거리' : '목표 시간',
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Tokens.ink),
              ),
              const Spacer(),
              ClayChip(label: '목표 변경', onTap: onTap),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Flexible(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(valueText, style: ClayText.embossNumber(fontSize: compact ? 58 : 76)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      isDistanceGoal ? 'km' : '분',
                      style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: Tokens.inkMuted),
                    ),
                  ],
                ),
              ),
              if (!stackInfo) _PaceBpmInfo(paceText: paceText, bpm: bpm, vertical: true),
            ],
          ),
          if (stackInfo) ...[
            const SizedBox(height: 6),
            _PaceBpmInfo(paceText: paceText, bpm: bpm, vertical: false),
          ],
        ],
      ),
    );
  }
}

/// 목표 카드 안의 보조 정보: 목표 페이스와 메트로놈 BPM (설정에서 서로 연동되는 한 쌍)
class _PaceBpmInfo extends StatelessWidget {
  const _PaceBpmInfo({required this.paceText, required this.bpm, required this.vertical});

  final String paceText;
  final int bpm;
  final bool vertical;

  Widget _item(String label, String value) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: const TextStyle(fontSize: 11, color: Tokens.inkMuted)),
          Text(value, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Tokens.ink)),
        ],
      );

  @override
  Widget build(BuildContext context) {
    final pace = _item('목표 페이스', paceText);
    final metro = _item('메트로놈', '$bpm BPM');
    if (!vertical) {
      return Wrap(spacing: 24, runSpacing: 4, children: [pace, metro]);
    }
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.only(left: 12),
      decoration: const BoxDecoration(border: Border(left: BorderSide(color: Color(0x1F000000), width: 2))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [pace, const SizedBox(height: 8), metro],
      ),
    );
  }
}

class _StreakCard extends StatelessWidget {
  const _StreakCard({required this.days});

  final int days;

  @override
  Widget build(BuildContext context) {
    return ClayCard(
      radius: 26,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFFFF9A76), Color(0xFFF26A3E)],
              ),
              boxShadow: [BoxShadow(color: Color(0x4D963C14), blurRadius: 6, offset: Offset(0, 4))],
            ),
            child: const Icon(Icons.favorite_rounded, size: 19, color: Tokens.ink),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('최고예요!', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Tokens.ink)),
                SizedBox(height: 2),
                Text('꾸준함이 가장 큰 힘이에요.', style: TextStyle(fontSize: 12.5, color: Tokens.inkMuted)),
              ],
            ),
          ),
          // 숫자와 "일 연속"이 같은 기준선에 앉도록 맞춤 (따로 띄우면 숫자가 떠 보임)
          Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text('$days', style: ClayText.embossNumber(fontSize: 30)),
              const SizedBox(width: 4),
              const Text('일 연속', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Tokens.inkMuted)),
            ],
          ),
        ],
      ),
    );
  }
}
