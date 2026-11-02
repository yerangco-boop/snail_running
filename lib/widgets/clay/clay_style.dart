import 'package:flutter/material.dart';

/// 점토 질감에 쓰는 공용 값.
/// 색 자체는 `Tokens`가 정의하고, 여기는 입체감(그림자·그라디언트·텍스처 경로)만 담당한다.
class ClayStyle {
  ClayStyle._();

  static const String grainAsset = 'assets/ui/clay_grain.png';
  static const String wrinkleAsset = 'assets/ui/clay_wrinkle.png';

  /// 점토 판 바탕: 왼쪽 위가 밝고 오른쪽 아래가 살짝 어두운 크림색
  static const LinearGradient slabFace = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFFFFFFF), Color(0xFFF8EEDD)],
  );

  /// 위쪽 밝은 테두리 + 아래쪽 그늘. CSS의 inset 그림자를 그라디언트 한 장으로 흉내 낸다.
  static const LinearGradient slabBevel = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xF2FFFFFF), Color(0x00FFFFFF), Color(0x00FFFFFF), Color(0x2EAF7841)],
    stops: [0.0, 0.10, 0.78, 1.0],
  );

  /// 점토 판이 바닥에서 살짝 떠 있는 느낌의 바깥 그림자
  static const List<BoxShadow> slabShadow = [
    BoxShadow(color: Color(0x4D7D5023), blurRadius: 24, spreadRadius: -8, offset: Offset(0, 18)),
    BoxShadow(color: Color(0x297D5023), blurRadius: 5, offset: Offset(0, 3)),
  ];

  /// 코랄 점토 면 (칩·버튼 바탕)
  static const LinearGradient coralFace = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFFF9A72), Color(0xFFF57A4F), Color(0xFFE8663C)],
    stops: [0.0, 0.55, 1.0],
  );

  static const List<BoxShadow> coralShadow = [
    BoxShadow(color: Color(0x80BE501E), blurRadius: 14, spreadRadius: -4, offset: Offset(0, 9)),
  ];

  /// 작은 타일 이미지를 이음새 없이 반복해 까는 장식 (손으로 주무른 질감)
  static BoxDecoration tileDecoration(String asset, {double opacity = 1.0}) => BoxDecoration(
        image: DecorationImage(
          image: AssetImage(asset),
          repeat: ImageRepeat.repeat,
          alignment: Alignment.topLeft,
          opacity: opacity,
        ),
      );
}
