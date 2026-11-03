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
    required this.streakDays,
    required this.onGoalTap,
    required this.onStart,
    this.permissionBanner,
  });

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
            final compact = constraints.maxHeight < 600;
            final startSize = constraints.maxHeight >= 700 ? 100.0 : (compact ? 72.0 : 84.0);
            // 낮은 화면에서는 보조 정보인 연속 카드를 접어 목표 카드와 시작 버튼을 우선 보여 줌
            final showStreak = streakDays > 0 && constraints.maxHeight >= 600;
            final fixed = (440 + startSize + (permissionBanner != null ? 92 : 0) + (showStreak ? 80 : 0)) *
                (1 + (textScale - 1) * 0.6);
            final snailHeight = (constraints.maxHeight - fixed).clamp(compact ? 64.0 : 96.0, 190.0);
            return Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.fromLTRB(22, compact ? 8 : 14, 22, 8),
                    child: Column(
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
                        SizedBox(height: compact ? 4 : 12),
                        _HeroRow(snailHeight: snailHeight, showSubtitle: !compact),
                        const SizedBox(height: 8),
                        _GoalCard(isDistanceGoal: isDistanceGoal, valueText: goalValueText, onTap: onGoalTap, compact: compact),
                        if (showStreak) ...[
                          const SizedBox(height: 14),
                          _StreakCard(days: streakDays),
                        ],
                        const SizedBox(height: 14),
                      ],
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
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('오늘도 천천히,\n같이 달려요!', style: ClayText.headline()),
              if (showSubtitle) ...[
                const SizedBox(height: 8),
                const Text(
                  '천천히 달려도,\n매일 조금씩 더 건강해져요.',
                  style: TextStyle(fontSize: 13, height: 1.5, color: Tokens.inkMuted),
                ),
              ],
            ],
          ),
        ),
        SnailAnimation(kind: SnailKind.home, bodyHeight: snailHeight),
      ],
    );
  }
}

class _GoalCard extends StatelessWidget {
  const _GoalCard({required this.isDistanceGoal, required this.valueText, required this.onTap, this.compact = false});

  final bool isDistanceGoal;
  final String valueText;
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
        ],
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
