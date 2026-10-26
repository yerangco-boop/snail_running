import 'package:flutter/material.dart';

// 디자인 토큰 — 색은 이 파일에서만 정의한다 (docs/design_tokens.md, 1번 시안 실측값 기준).
// 대비는 #FCF9F3 배경 / 흰 카드 위 기준.
class Tokens {
  Tokens._();

  static const bg = Color(0xFFFCF9F3);
  static const card = Color(0xFFFFFFFF);

  // 면(버튼 바탕·진행 막대·칩·경로선) 전용. 글자·얇은 아이콘 금지 (대비 2.6~2.7)
  static const coralFace = Color(0xFFF57A4F);
  // 큰 숫자·헤드라인·굵은 아이콘 (3:1 이상)
  static const coralDisplay = Color(0xFFF3602F);
  // 작은 코랄 글자·링크 (4.5:1 이상)
  static const coralText = Color(0xFFD13A12);

  // 본문·주행 숫자, 코랄 면 위 글자(7.0:1)
  static const ink = Color(0xFF111111);
  // 보조 글자 (5.4:1)
  static const inkMuted = Color(0xFF6A6762);
  // 주행 화면 보조 글자 (8.1:1, 주행 7:1 기준 통과)
  static const inkSoft = Color(0xFF4F4B52);

  static const danger = Color(0xFFD32F2F);
  static const warnFace = Color(0xFFFFE3A8);
  static const warnText = Color(0xFF8A4B00);
  static const ok = Color(0xFF1E8E5A);
}
