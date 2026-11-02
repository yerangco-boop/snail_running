import 'package:flutter/material.dart';
import '../../theme/tokens.dart';

/// 점토처럼 도톰하게 솟아 보이는 글자 스타일.
/// 숫자에는 강하게, 한글 제목에는 약하게 쓴다 (한글에 강한 그림자를 주면 번져서 읽기 어려움).
class ClayText {
  ClayText._();

  /// 큰 숫자용 도톰한 엠보스 (아래로 코랄 두께 + 부드러운 바닥 그림자).
  /// 두께는 글자 크기에 비례시켜, 작은 숫자가 겹쳐 보이지 않게 한다 (76px 기준 5px).
  static List<Shadow> embossShadows(double fontSize) => [
        Shadow(color: const Color(0xFFD9531E), offset: Offset(0, fontSize * 0.066)),
        Shadow(
          color: const Color(0x4D96320F),
          offset: Offset(0, fontSize * 0.145),
          blurRadius: fontSize * 0.16,
        ),
      ];

  /// 한글 제목용 약한 그림자 (번짐 방지)
  static const List<Shadow> softShadows = [
    Shadow(color: Color(0x73D9531E), offset: Offset(0, 2)),
  ];

  static TextStyle embossNumber({required double fontSize, Color color = Tokens.coralDisplay}) {
    return TextStyle(
      fontSize: fontSize,
      fontWeight: FontWeight.w800,
      color: color,
      height: 1.0,
      letterSpacing: -2,
      shadows: embossShadows(fontSize),
      fontFeatures: const [FontFeature.tabularFigures()],
    );
  }

  static TextStyle headline({double fontSize = 27}) {
    return TextStyle(
      fontSize: fontSize,
      fontWeight: FontWeight.w800,
      color: Tokens.coralDisplay,
      height: 1.28,
      letterSpacing: -0.3,
      shadows: softShadows,
    );
  }
}
