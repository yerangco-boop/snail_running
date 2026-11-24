import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:snail_running/main.dart';

// 앱 루트 위젯이 예외 없이 첫 화면(설정 로드 대기 화면)을 그리는지만 확인하는 스모크 테스트.
// 설정 로드 뒤의 MainScreen/HomeScreen은 GPS·TTS·DB 같은 플랫폼 플러그인을 쓰므로 여기서는
// 그리지 않는다(첫 프레임 이후 pump하지 않음). 홈 화면 배치는 pre_run_layout_test.dart가 검사.
void main() {
  testWidgets('앱 루트가 첫 화면을 예외 없이 그린다', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(const SnailRunningApp());

    expect(find.byType(MaterialApp), findsOneWidget);
    expect(find.byType(Scaffold), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
