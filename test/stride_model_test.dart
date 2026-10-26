import 'package:flutter_test/flutter_test.dart';
import 'package:snail_running/services/stride_model.dart';

void main() {
  realHistoryTests();
  test('빈 모델은 보폭을 모른다', () {
    expect(StrideModel().strideFor(150), isNull);
  });

  test('관측한 케이던스 근처에서만 보폭을 돌려준다', () {
    final m = StrideModel()..observe(150, 650, 1000);
    expect(m.strideFor(150), closeTo(0.65, 0.001));
    expect(m.strideFor(160), closeTo(0.65, 0.001)); // 이웃 구간
    expect(m.strideFor(105), isNull); // 걷기 구간은 모른다 → 달리기 보폭을 걷기에 쓰지 않음
  });

  test('걷기와 달리기 보폭이 섞이지 않는다', () {
    final m = StrideModel()
      ..observe(150, 650, 1000)
      ..observe(105, 780, 1000);
    expect(m.strideFor(105)!, closeTo(0.78, 0.02));
    expect(m.strideFor(150)!, closeTo(0.65, 0.02));
  });

  test('케이던스가 두 구간 사이면 가중 평균', () {
    final m = StrideModel()
      ..observe(140, 600, 1000)
      ..observe(160, 700, 1000);
    expect(m.strideFor(150)!, closeTo(0.65, 0.01));
  });

  test('표본이 부족하면 쓰지 않는다', () {
    final m = StrideModel()..observe(150, 65, 100);
    expect(m.strideFor(150), isNull);
  });

  test('비현실적인 관측은 무시한다', () {
    final m = StrideModel()
      ..observe(150, 1700, 1000) // 1.7m/걸음
      ..observe(40, 300, 500) // 케이던스 40
      ..observe(150, 0, 100)
      ..observe(150, 100, 0);
    expect(m.isEmpty, isTrue);
  });

  test('JSON 저장/복원 후 같은 값', () {
    final m = StrideModel()
      ..observe(150, 650, 1000)
      ..observe(105, 780, 1000);
    final r = StrideModel.fromJson(m.toJson());
    expect(r.strideFor(150), closeTo(m.strideFor(150)!, 1e-9));
    expect(r.strideFor(105), closeTo(m.strideFor(105)!, 1e-9));
  });

  test('표본이 많아져도 최근 값에 적응한다', () {
    final m = StrideModel();
    for (var i = 0; i < 20; i++) {
      m.observe(150, 650 * 5, 5000); // 0.65
    }
    for (var i = 0; i < 20; i++) {
      m.observe(150, 700 * 5, 5000); // 0.70
    }
    expect(m.strideFor(150)!, greaterThan(0.69));
    expect(m.totalSteps, lessThan(StrideModel.maxBinSteps + 5000));
  });
}

// 앱 이력 캡처(10/13~10/26)에서 읽은 실제 러닝 6건으로 모델을 채워 본다 — 화면 켠 러닝 위주
void realHistoryTests() {
  test('실제 이력으로 채운 모델: 150spm 보폭은 약 0.62~0.72m, 걷기(105spm)는 모름', () {
    final m = StrideModel()
      ..observe(159, 4190, 6254) // 10/13
      ..observe(154, 4190, 6780) // 10/14
      ..observe(163, 5310, 8093) // 10/15
      ..observe(147, 4200, 5884) // 10/19
      ..observe(168, 4160, 5946) // 10/21
      ..observe(147, 3200, 5176); // 10/26
    final s150 = m.strideFor(150)!;
    expect(s150, inInclusiveRange(0.62, 0.72));
    expect(m.strideFor(105), isNull);
  });
}
