import 'package:flutter/material.dart';
import '../../theme/tokens.dart';
import 'clay_style.dart';

/// 코랄 점토 알약 칩. 코랄 면 위 글자는 대비 때문에 항상 ink(검정)를 쓴다.
class ClayChip extends StatelessWidget {
  const ClayChip({super.key, required this.label, this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final chip = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        gradient: ClayStyle.coralFace,
        boxShadow: ClayStyle.coralShadow,
        border: Border.all(color: const Color(0x8CFFFFFF), width: 1.2),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        child: Text(
          label,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Tokens.ink),
        ),
      ),
    );
    // 눈에 보이는 높이는 작아도 손가락이 닿는 영역은 넉넉하게
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: chip),
    );
  }
}
