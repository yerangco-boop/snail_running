import 'dart:async';
import '../click_player_stub.dart'
    if (dart.library.html) '../click_player_web.dart';

class MetronomeService {
  final ClickPlayer _click = ClickPlayer();
  Timer? _timer;
  int _gen = 0;
  bool get isRunning => _timer != null;

  Future<void> init() async => _click.init();

  // playImmediately=true : 즉시 첫 박 재생 후 타이머 시작 (최초 시작 / AudioContext unlock)
  // playImmediately=false: 타이머만 시작 (재개 — 박자 위상 깨짐 방지)
  Future<void> start(int bpm, {bool playImmediately = true}) async {
    stop();
    final myGen = _gen;
    final interval = Duration(milliseconds: (60000 / bpm).round());

    if (playImmediately) {
      await _click.play();
      if (_gen != myGen) return;
    }

    _timer = Timer.periodic(interval, (_) => _click.play());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _gen++;
  }

  Future<void> updateBpm(int bpm) async {
    if (isRunning) await start(bpm);
  }

  void dispose() {
    stop();
    _click.dispose();
  }
}
