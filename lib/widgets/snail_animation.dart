import 'package:flutter/material.dart';

/// 달팽이 소재 종류. 파일은 `assets/snail/`, 크기 보정 비율은 `meta.json`의 avgBodyHeightRatio.
enum SnailKind { home, run, runStill, cheer, fail }

/// 달팽이 애니메이션/이미지. 이미지 안의 여백(점프 공간 등)이 소재마다 달라서,
/// 화면에서는 "달팽이 몸 높이"([bodyHeight])를 기준으로 크기를 맞춘다.
class SnailAnimation extends StatelessWidget {
  const SnailAnimation({
    super.key,
    required this.kind,
    required this.bodyHeight,
    this.restartKey,
  });

  final SnailKind kind;

  /// 화면에 보일 달팽이 몸통의 높이 (논리 픽셀)
  final double bodyHeight;

  /// 1회 재생 애니메이션(응원·아쉬워함)을 처음부터 다시 재생하고 싶을 때 바꿔 주는 값
  final Object? restartKey;

  static const Map<SnailKind, String> _assets = {
    SnailKind.home: 'assets/snail/snail_home.webp',
    SnailKind.run: 'assets/snail/snail_run.webp',
    SnailKind.runStill: 'assets/snail/snail_run_still.webp',
    SnailKind.cheer: 'assets/snail/snail_cheer.webp',
    SnailKind.fail: 'assets/snail/snail_fail.webp',
  };

  // 이미지 높이 대비 달팽이 몸통 높이 (assets/snail/meta.json)
  static const Map<SnailKind, double> _bodyRatio = {
    SnailKind.home: 1.0,
    SnailKind.run: 0.936,
    SnailKind.runStill: 0.936,
    SnailKind.cheer: 0.766,
    SnailKind.fail: 0.851,
  };

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      _assets[kind]!,
      key: ValueKey('${kind.name}-$restartKey'),
      height: bodyHeight / _bodyRatio[kind]!,
      fit: BoxFit.contain,
      gaplessPlayback: true,
      filterQuality: FilterQuality.medium,
      excludeFromSemantics: true,
    );
  }
}
