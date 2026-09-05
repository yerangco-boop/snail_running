import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

import 'file_logger.dart';

// 러닝 중 화면이 꺼져도 위치 추적이 유지되려면 "항상 허용" 위치 권한만으로는 부족하다.
// 안드로이드는 그 위에 두 가지를 더 요구한다:
//
//  1) 알림 권한(Android 13+) — geolocator가 위치 추적을 포그라운드 서비스로 승격시킬 때
//     "달팽이 러닝 / 러닝 기록 중" 알림을 띄우는데, 알림 권한이 없으면 이 알림이 보이지
//     않는다. 사용자가 서비스가 살아있는지 눈으로 확인할 방법이 사라지고, 일부 제조사
//     스킨(삼성 등)에서는 알림 없는 서비스를 더 공격적으로 정리한다.
//  2) 배터리 최적화 예외 — 삼성 "앱 절전/미사용 앱 절전" 및 안드로이드 Doze는
//     화면이 꺼지면 앱의 위치 갱신 주기를 늘리거나 아예 멈춘다. 2026-09-05 실측에서
//     가속도계(앱 내부 센서)는 계속 들어오는데 위치 콜백만 4분 넘게 끊긴 것이 정확히
//     이 증상이었다.
//
// 둘 다 시스템 다이얼로그 한 번으로 끝나므로 러닝 시작 시점에 한 번만 물어본다.
class BackgroundPermissions {
  static bool get _isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  // 이미 물어본 뒤 거절한 경우 러닝 시작마다 다이얼로그가 뜨지 않도록 세션 내 1회로 제한
  static bool _batteryAsked = false;

  static Future<void> ensureForBackgroundTracking() async {
    if (!_isAndroid) return;
    try {
      final notif = await Permission.notification.status;
      if (!notif.isGranted) {
        final result = await Permission.notification.request();
        FileLogger.instance.log('[Perm] 알림 권한 요청 결과: $result');
      }
    } catch (e) {
      FileLogger.instance.log('[Perm] 알림 권한 확인 실패: $e');
    }

    try {
      final battery = await Permission.ignoreBatteryOptimizations.status;
      FileLogger.instance.log('[Perm] 배터리 최적화 예외 상태: $battery');
      if (!battery.isGranted && !_batteryAsked) {
        _batteryAsked = true;
        final result = await Permission.ignoreBatteryOptimizations.request();
        FileLogger.instance.log('[Perm] 배터리 최적화 예외 요청 결과: $result');
      }
    } catch (e) {
      FileLogger.instance.log('[Perm] 배터리 최적화 예외 확인 실패: $e');
    }
  }
}
