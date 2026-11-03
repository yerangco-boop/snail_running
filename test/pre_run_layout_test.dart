import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snail_running/services/weather_service.dart';
import 'package:snail_running/theme/tokens.dart';
import 'package:snail_running/widgets/clay/clay_image_button.dart';
import 'package:snail_running/widgets/home/pre_run_view.dart';
import 'package:snail_running/widgets/snail_animation.dart';

// 시작 전 홈에서 목표 카드가 시작 버튼에 가려지거나 잘리지 않는지 화면 크기·글자 배율별로 검사
void main() {
  final weather = WeatherSnapshot(
    tempC: 18.2,
    humidity: 45,
    precipitationPercent: 10,
    windSpeedMs: 2.1,
    iconCode: '01d',
    fetchedAt: DateTime(2026, 11, 2, 15, 12),
    cityName: '충주시',
  );

  Widget app({required bool banner, required int streak}) => MaterialApp(
        theme: ThemeData(scaffoldBackgroundColor: Tokens.bg),
        home: Scaffold(
          body: PreRunView(
            placeText: '오후 3:12 기준 · 충주시 목행동',
            weather: weather,
            weatherFallbackText: '날씨 정보 없음',
            isDistanceGoal: true,
            goalValueText: '5.0',
            streakDays: streak,
            onGoalTap: () {},
            onStart: () {},
            permissionBanner: banner
                ? Container(
                    margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    height: 60,
                    color: Colors.amber,
                  )
                : null,
          ),
        ),
      );

  // (이름, 가로, 세로(상태바·탭바 제외한 본문), 글자 배율)
  final cases = <(String, double, double, double)>[
    ('393x748', 393, 748, 1.0),
    ('393x748 글자1.3', 393, 748, 1.3),
    ('360x536', 360, 536, 1.0),
    ('360x536 글자1.3', 360, 536, 1.3),
    ('411x820', 411, 820, 1.0),
    ('320x700', 320, 700, 1.0),
    ('280x640', 280, 640, 1.0),
    ('폴드 접힘 320x720', 320, 720, 1.0),
    ('폴드 접힘 320x720 글자1.3', 320, 720, 1.3),
    ('폴드 펼침 674x760', 674, 760, 1.0),
    ('폴드 펼침 674x760 글자1.3', 674, 760, 1.3),
    ('폴드 펼침 가로 841x560', 841, 560, 1.0),
  ];

  for (final c in cases) {
    for (final banner in [false, true]) {
      testWidgets('${c.$1} 배너=$banner: 목표 카드가 시작 버튼 위에 온전히 보임', (tester) async {
        tester.view.physicalSize = Size(c.$2, c.$3) * 2;
        tester.view.devicePixelRatio = 2;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(MediaQuery(
          data: MediaQueryData(size: Size(c.$2, c.$3), textScaler: TextScaler.linear(c.$4)),
          child: app(banner: banner, streak: 12),
        ));
        await tester.pump(const Duration(milliseconds: 300));
        expect(tester.takeException(), isNull);

        final button = tester.getRect(find.byType(ClayImageButton));
        final scrollFinder = find.byType(SingleChildScrollView);
        final scroll = tester.getRect(scrollFinder);
        final streakFinder = find.text('일 연속');
        final lastFinder = streakFinder.evaluate().isNotEmpty ? streakFinder : find.text('5.0');

        // 문구는 단어 중간에서 끊기지 않는 두 가지 형태 중 하나여야 함
        final headline = tester
            .widgetList<Text>(find.byType(Text))
            .map((t) => t.data)
            .firstWhere((d) => d != null && d.contains('같이 달려요!'))!;
        expect(['오늘도 천천히,\n같이 달려요!', '오늘도\n천천히,\n같이 달려요!'], contains(headline));
        // 문구 묶음과 달팽이의 세로 중심이 같아야 함 (구도 균형)
        final snailRect = tester.getRect(find.byType(SnailAnimation));
        final textTop = tester.getRect(find.text(headline)).top;
        final subs = find.textContaining('천천히 달려도');
        final textBottom = subs.evaluate().isNotEmpty
            ? tester.getRect(subs).bottom
            : tester.getRect(find.text(headline)).bottom;
        expect(((textTop + textBottom) / 2 - snailRect.center.dy).abs(), lessThan(3.0));
        // 스크롤 영역은 항상 시작 버튼 위에서 끝나야 함(겹침 없음)
        expect(scroll.bottom, lessThanOrEqualTo(button.top));
        // 글자 배율 1.0이면 스크롤 없이 한 화면에 전부, 크게 키운 경우는 맨 아래까지 밀었을 때 전부 보여야 함
        if (c.$4 > 1.0 && tester.getRect(lastFinder).bottom > scroll.bottom) {
          await tester.drag(scrollFinder, const Offset(0, -1000));
          await tester.pump(const Duration(milliseconds: 300));
        }
        final goal = tester.getRect(find.text('목표 거리').first);
        final goalValue = tester.getRect(find.text('5.0'));
        expect(goal.top, greaterThanOrEqualTo(scroll.top));
        expect(goalValue.bottom, lessThanOrEqualTo(scroll.bottom));
        if (c.$4 <= 1.0) {
          expect(tester.getRect(lastFinder).bottom, lessThanOrEqualTo(scroll.bottom));
        }
      });
    }
  }
}
