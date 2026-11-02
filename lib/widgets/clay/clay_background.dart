import 'package:flutter/material.dart';
import '../../theme/tokens.dart';
import 'clay_style.dart';

/// 화면 배경: 크림색 바탕 위에 아주 연한 주름 질감을 깐다.
class ClayBackground extends StatelessWidget {
  const ClayBackground({super.key, required this.child, this.color = Tokens.bg});

  final Widget child;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(color: color),
      // 바탕은 시안처럼 깨끗한 크림색 — 질감 타일을 깔면 얼룩져 보여서 아주 옅은 알갱이만 얹음
      child: DecoratedBox(
        decoration: ClayStyle.tileDecoration(ClayStyle.grainAsset, opacity: 0.18),
        child: SizedBox.expand(child: child),
      ),
    );
  }
}
