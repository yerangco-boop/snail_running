import 'package:flutter/material.dart';
import 'clay_style.dart';

/// 점토 판처럼 두껍게 부푼 카드. 바깥 그림자 + 주름·알갱이 질감 + 위쪽 밝은 테두리/아래쪽 그늘.
class ClayCard extends StatelessWidget {
  const ClayCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.radius = 28,
    this.onTap,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final r = BorderRadius.circular(radius);
    final slab = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: r,
        gradient: ClayStyle.slabFace,
        boxShadow: ClayStyle.slabShadow,
      ),
      child: ClipRRect(
        borderRadius: r,
        child: Stack(
          // 부모가 정한 너비를 그대로 받아 안쪽 내용이 가운데·양끝 정렬을 제대로 하게 함
          fit: StackFit.passthrough,
          children: [
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(decoration: ClayStyle.tileDecoration(ClayStyle.wrinkleAsset, opacity: 0.10)),
              ),
            ),
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(decoration: ClayStyle.tileDecoration(ClayStyle.grainAsset, opacity: 0.30)),
              ),
            ),
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: r,
                    gradient: ClayStyle.slabBevel,
                    border: Border.all(color: const Color(0xA6FFFFFF), width: 1.5),
                  ),
                ),
              ),
            ),
            Padding(padding: padding, child: child),
          ],
        ),
      ),
    );
    if (onTap == null) return slab;
    return GestureDetector(behavior: HitTestBehavior.opaque, onTap: onTap, child: slab);
  }
}
