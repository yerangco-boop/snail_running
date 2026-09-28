import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

const String kLatestApkUrl =
    'https://github.com/yerangco-boop/snail_running/releases/latest/download/app-release.apk';

const String _latestReleaseApi =
    'https://api.github.com/repos/yerangco-boop/snail_running/releases/latest';

class UpdateInfo {
  final String tag;
  final int latestCode;
  final int currentCode;
  const UpdateInfo(this.tag, this.latestCode, this.currentCode);
}

class UpdateChecker {
  // 릴리스 태그는 pubspec의 versionCode(`v35` 등)와 같은 규칙이라, 설치된 앱의 빌드 번호와
  // 숫자로 비교함. 네트워크 실패·파싱 실패는 알림을 띄우지 않는 쪽으로 조용히 처리
  static Future<UpdateInfo?> check() async {
    if (kIsWeb) return null;
    try {
      final res = await http
          .get(Uri.parse(_latestReleaseApi),
              headers: {'Accept': 'application/vnd.github+json'})
          .timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return null;
      final tag = (jsonDecode(res.body) as Map<String, dynamic>)['tag_name'] as String?;
      final latest = int.tryParse(RegExp(r'\d+').stringMatch(tag ?? '') ?? '');
      final current = int.tryParse((await PackageInfo.fromPlatform()).buildNumber);
      if (tag == null || latest == null || current == null) return null;
      return latest > current ? UpdateInfo(tag, latest, current) : null;
    } catch (e) {
      debugPrint('[Update] 확인 실패: $e');
      return null;
    }
  }
}
