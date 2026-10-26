import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// 케이던스(분당 걸음 수)별 보폭을 러닝마다 쌓아 저장해 두는 모델.
///
/// 보폭은 걷기(~105spm)와 슬로우 조깅(~150spm)에서 다르다. 예전엔 보폭을 매 러닝
/// 처음부터 새로 배워서, 화면이 처음부터 꺼져 GPS가 나쁘면 보폭을 못 배우고 거리가
/// 부풀었다(10/23). 이제 GPS가 좋았던 구간의 (이동거리, 걸음 수)를 케이던스 구간별로
/// 저장하고, 다음 러닝은 시작부터 그 보폭으로 걸음 기반 거리를 채운다.
class StrideModel {
  static const int binWidth = 10; // spm
  static const int minUsableSteps = 200; // 이보다 표본이 적으면 쓰지 않음
  static const double maxBinSteps = 6000; // 넘으면 절반으로 줄여 최근 값에 적응
  static const double minStride = 0.3;
  static const double maxStride = 1.6;
  static const String _prefsKey = 'stride_model_v1';

  // 키: 케이던스 구간 번호(spm ÷ 10 반올림), 값: [누적 미터, 누적 걸음]
  final Map<int, List<double>> _bins = {};

  bool get isEmpty => _bins.isEmpty;
  double get totalSteps => _bins.values.fold(0.0, (s, b) => s + b[1]);

  int _binOf(double cadenceSpm) => (cadenceSpm / binWidth).round();

  /// GPS가 정확했던 구간의 관측을 기록한다.
  void observe(double cadenceSpm, double meters, num steps) {
    if (steps <= 0 || meters <= 0) return;
    if (cadenceSpm < 60 || cadenceSpm > 220) return;
    final stride = meters / steps;
    if (stride < minStride || stride > maxStride) return;
    final bin = _bins.putIfAbsent(_binOf(cadenceSpm), () => [0.0, 0.0]);
    bin[0] += meters;
    bin[1] += steps.toDouble();
    if (bin[1] > maxBinSteps) {
      bin[0] /= 2;
      bin[1] /= 2;
    }
  }

  /// 현재 케이던스에 맞는 보폭(m). 가까운 구간(±25spm)의 표본을 거리 가중 평균하고,
  /// 표본이 [minUsableSteps]보다 적으면 null.
  double? strideFor(double cadenceSpm) {
    if (cadenceSpm <= 0) return null;
    var weightSum = 0.0, strideWeighted = 0.0, stepsInRange = 0.0;
    _bins.forEach((bin, acc) {
      final d = (bin * binWidth - cadenceSpm).abs();
      if (d > 25 || acc[1] <= 0) return;
      final w = (1 - d / 30) * acc[1];
      weightSum += w;
      strideWeighted += w * (acc[0] / acc[1]);
      stepsInRange += acc[1];
    });
    if (stepsInRange < minUsableSteps || weightSum <= 0) return null;
    return strideWeighted / weightSum;
  }

  Map<String, dynamic> toJson() => {
        'bins': _bins.map((k, v) => MapEntry('$k', [v[0], v[1]])),
      };

  static StrideModel fromJson(Map<String, dynamic> json) {
    final model = StrideModel();
    final bins = json['bins'];
    if (bins is Map) {
      bins.forEach((k, v) {
        final key = int.tryParse('$k');
        if (key != null && v is List && v.length == 2) {
          model._bins[key] = [(v[0] as num).toDouble(), (v[1] as num).toDouble()];
        }
      });
    }
    return model;
  }

  static Future<StrideModel> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw == null) return StrideModel();
      return fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return StrideModel();
    }
  }

  Future<void> save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, jsonEncode(toJson()));
    } catch (_) {}
  }
}
