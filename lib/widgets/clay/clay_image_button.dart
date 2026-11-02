import 'package:flutter/material.dart';
import '../../theme/tokens.dart';

/// 점토 이미지 버튼. 아이콘만 있는 버튼 금지 규칙에 따라 글자 라벨을 함께 보여 준다.
/// 누르면 눌리고, 손을 떼면 점토처럼 탄력 있게 튕겨 돌아온다.
class ClayImageButton extends StatefulWidget {
  const ClayImageButton({
    super.key,
    required this.asset,
    required this.size,
    required this.label,
    required this.onTap,
  });

  final String asset;
  final double size;
  final String label;
  final VoidCallback onTap;

  @override
  State<ClayImageButton> createState() => _ClayImageButtonState();
}

class _ClayImageButtonState extends State<ClayImageButton> {
  bool _down = false;

  void _setDown(bool v) {
    if (_down != v) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    return Semantics(
      button: true,
      label: widget.label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => _setDown(true),
        onTapUp: (_) => _setDown(false),
        onTapCancel: () => _setDown(false),
        onTap: widget.onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedScale(
              scale: _down ? 0.92 : 1.0,
              duration: Duration(milliseconds: _down ? 90 : 420),
              curve: _down ? Curves.easeOut : Curves.elasticOut,
              child: SizedBox(
                width: s,
                height: s,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // 버튼 아래 바닥에 붙는 그림자
                    SizedBox(
                      width: s * 0.84,
                      height: s * 0.84,
                      child: const DecoratedBox(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(color: Color(0x59BE501E), blurRadius: 14, offset: Offset(0, 9)),
                          ],
                        ),
                      ),
                    ),
                    Image.asset(
                      widget.asset,
                      width: s,
                      height: s,
                      fit: BoxFit.contain,
                      filterQuality: FilterQuality.medium,
                      excludeFromSemantics: true,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              widget.label,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Tokens.ink),
            ),
          ],
        ),
      ),
    );
  }
}
