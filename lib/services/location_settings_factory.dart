// 러닝 중 위치 스트림 설정을 만드는 팩토리.
// 안드로이드에서만 포그라운드 서비스 알림(ForegroundNotificationConfig)을 붙여야 하는데
// 그 클래스가 geolocator_android(안드로이드 전용 패키지)에 있어서, 웹 빌드가 깨지지 않도록
// database_service / click_player와 동일한 조건부 import 패턴으로 분리함.
export 'location_settings_stub.dart'
    if (dart.library.html) 'location_settings_web.dart';
