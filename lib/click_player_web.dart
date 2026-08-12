import 'dart:js' as js;

// dart:web_audio 바인딩의 OscillatorNode.start() 미노출 문제를 우회.
// dart:js JsObject를 통해 Web Audio API를 직접 호출한다.
class ClickPlayer {
  js.JsObject? _ctx;
  double _volume = 1.0;

  // 웹 Audio API는 네이티브 AudioFocus 개념이 없어 mixWithOtherAudio는 무시됨
  // (인터페이스를 click_player_stub.dart와 맞추기 위한 매개변수)
  Future<void> init({bool mixWithOtherAudio = true, double volume = 1.0}) async {
    _volume = volume.clamp(0.0, 1.0);
    try {
      final ctor = js.context['AudioContext'] ?? js.context['webkitAudioContext'];
      _ctx = js.JsObject(ctor as js.JsFunction);
      print('[Metro] Web Audio init, state=${_ctx!["state"]}');
    } catch (e) {
      print('[Metro] init error: $e');
    }
  }

  Future<void> play() async {
    final ctx = _ctx;
    if (ctx == null) return;
    try {
      // autoplay 정책으로 suspended 상태면 resume
      if ((ctx['state'] as String?) == 'suspended') {
        ctx.callMethod('resume');
        print('[Metro] AudioContext resumed');
      }

      final now = (ctx['currentTime'] as num).toDouble();
      final osc  = ctx.callMethod('createOscillator') as js.JsObject;
      final gain = ctx.callMethod('createGain')       as js.JsObject;
      final dest = ctx['destination'];

      // OscillatorNode → GainNode → destination
      osc.callMethod('connect', [gain]);
      gain.callMethod('connect', [dest]);

      // 1500Hz sine, 최대 gain=2.0에 설정 음량(0.0~1.0)을 곱함
      // (gain > 1.0은 Web Audio API에서 허용 — 스피커 최종 출력이 클리핑되지 않는 선에서)
      osc['type'] = 'sine';
      (osc['frequency'] as js.JsObject)['value'] = 1500;

      // exponentialRampToValueAtTime은 0을 못 받으므로 음량 0에서도 최소값을 유지
      final peak = _volume <= 0 ? 0.0001 : 2.0 * _volume;
      final gainParam = gain['gain'] as js.JsObject;
      gainParam.callMethod('setValueAtTime',                [peak,  now]);
      gainParam.callMethod('exponentialRampToValueAtTime',  [0.00005, now + 0.018]);

      osc.callMethod('start', [now]);
      osc.callMethod('stop',  [now + 0.025]); // 25ms 후 자동 해제

      print('[Metro] click t=${now.toStringAsFixed(3)}s');
    } catch (e) {
      print('[Metro] play error: $e');
    }
  }

  // 러닝 중 슬라이더를 움직여도 즉시 반영되도록 별도 노출 (다음 play()부터 적용)
  Future<void> setVolume(double volume) async {
    _volume = volume.clamp(0.0, 1.0);
  }

  void dispose() {
    try { _ctx?.callMethod('close'); } catch (_) {}
    _ctx = null;
  }
}
