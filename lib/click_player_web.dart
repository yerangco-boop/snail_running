import 'dart:js' as js;

// dart:web_audio 바인딩의 OscillatorNode.start() 미노출 문제를 우회.
// dart:js JsObject를 통해 Web Audio API를 직접 호출한다.
class ClickPlayer {
  js.JsObject? _ctx;

  Future<void> init() async {
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

      // 1500Hz sine, gain=2.0 → 묵직하고 또렷한 "딱" 소리
      // (gain > 1.0은 Web Audio API에서 허용 — 스피커 최종 출력이 클리핑되지 않는 선에서)
      osc['type'] = 'sine';
      (osc['frequency'] as js.JsObject)['value'] = 1500;

      final gainParam = gain['gain'] as js.JsObject;
      gainParam.callMethod('setValueAtTime',                [2.0,   now]);
      gainParam.callMethod('exponentialRampToValueAtTime',  [0.001, now + 0.018]);

      osc.callMethod('start', [now]);
      osc.callMethod('stop',  [now + 0.025]); // 25ms 후 자동 해제

      print('[Metro] click t=${now.toStringAsFixed(3)}s');
    } catch (e) {
      print('[Metro] play error: $e');
    }
  }

  void dispose() {
    try { _ctx?.callMethod('close'); } catch (_) {}
    _ctx = null;
  }
}
