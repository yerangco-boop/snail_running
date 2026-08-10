import 'dart:io' show Platform;
import 'package:geolocator/geolocator.dart';
import 'package:geolocator_android/geolocator_android.dart';

// 모바일/데스크톱용 위치 설정.
// 안드로이드에서는 포그라운드 서비스로 승격시켜, 화면이 꺼지거나 앱이 백그라운드로
// 내려가도 OS가 위치 콜백을 스로틀링/차단하지 못하게 함 — v17까지 거리가 러닝 시간에
// 비례해 -7.9~-54.7% 유실되던 근본 원인이 이 백그라운드 억제였음.
LocationSettings buildTrackingLocationSettings({
  required LocationAccuracy accuracy,
  required int distanceFilter,
}) {
  if (Platform.isAndroid) {
    return AndroidSettings(
      accuracy: accuracy,
      distanceFilter: distanceFilter,
      foregroundNotificationConfig: const ForegroundNotificationConfig(
        notificationTitle: '달팽이 러닝',
        notificationText: '러닝 기록 중',
        enableWakeLock: true,
        // 알림을 스와이프로 지울 수 없게 함 — 실수로 지우면 서비스가 내려가 추적이 끊김
        setOngoing: true,
      ),
    );
  }
  return LocationSettings(accuracy: accuracy, distanceFilter: distanceFilter);
}
