import 'package:flutter_test/flutter_test.dart';
import 'package:snail_running/utils/streak.dart';

void main() {
  final today = DateTime(2026, 11, 2, 15, 30);

  test('기록이 없으면 0', () {
    expect(computeStreakDays([], today), 0);
  });

  test('오늘부터 하루도 빠짐없이 3일 연속이면 3', () {
    expect(
      computeStreakDays([DateTime(2026, 11, 2, 7), DateTime(2026, 11, 1, 20), DateTime(2026, 10, 31, 6)], today),
      3,
    );
  });

  test('오늘 아직 안 뛰었어도 어제까지 이어졌으면 연속 유지', () {
    expect(computeStreakDays([DateTime(2026, 11, 1), DateTime(2026, 10, 31)], today), 2);
  });

  test('이틀 전이 마지막이면 연속이 끊겨 0', () {
    expect(computeStreakDays([DateTime(2026, 10, 31), DateTime(2026, 10, 30)], today), 0);
  });

  test('하루가 비면 그 앞은 세지 않는다', () {
    expect(
      computeStreakDays([DateTime(2026, 11, 2), DateTime(2026, 11, 1), DateTime(2026, 10, 29)], today),
      2,
    );
  });

  test('같은 날 여러 번 뛰어도 하루로 센다', () {
    expect(computeStreakDays([DateTime(2026, 11, 2, 6), DateTime(2026, 11, 2, 19)], today), 1);
  });

  test('달이 바뀌어도 이어진다', () {
    expect(
      computeStreakDays([DateTime(2026, 11, 1), DateTime(2026, 10, 31), DateTime(2026, 10, 30)], DateTime(2026, 11, 1)),
      3,
    );
  });
}
