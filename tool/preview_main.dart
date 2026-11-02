// 디자인 확인용 개발 도구 — 실제 앱이 아니라 새 화면을 가짜 값으로 띄워 시안과 비교할 때 쓴다.
//   flutter run -d web-server --web-port 8771 -t tool/preview_main.dart
// 날씨 키·GPS·DB 없이도 화면 모양을 볼 수 있다.
import 'package:flutter/material.dart';
import 'package:snail_running/services/weather_service.dart';
import 'package:snail_running/theme/tokens.dart';
import 'package:snail_running/widgets/home/pre_run_view.dart';

void main() => runApp(const _PreviewApp());

class _PreviewApp extends StatelessWidget {
  const _PreviewApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(scaffoldBackgroundColor: Tokens.bg, useMaterial3: true),
      home: const _PreviewHome(),
    );
  }
}

class _PreviewHome extends StatelessWidget {
  const _PreviewHome();

  @override
  Widget build(BuildContext context) {
    final fake = WeatherSnapshot(
      tempC: 18.2,
      humidity: 45,
      precipitationPercent: 10,
      windSpeedMs: 2.1,
      iconCode: '01d',
      fetchedAt: DateTime(2026, 11, 2, 15, 12),
      cityName: '충주시',
    );
    return Scaffold(
      body: PreRunView(
        placeText: '오후 3:12 기준 · 충주시 목행동',
        weather: fake,
        weatherFallbackText: '날씨 정보 없음',
        isDistanceGoal: true,
        goalValueText: '5.0',
        streakDays: 12,
        onGoalTap: () {},
        onStart: () {},
      ),
    );
  }
}
