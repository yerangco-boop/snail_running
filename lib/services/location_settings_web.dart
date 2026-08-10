import 'package:geolocator/geolocator.dart';

// 웹에는 포그라운드 서비스 개념이 없으므로 기본 LocationSettings만 사용
LocationSettings buildTrackingLocationSettings({
  required LocationAccuracy accuracy,
  required int distanceFilter,
}) =>
    LocationSettings(accuracy: accuracy, distanceFilter: distanceFilter);
