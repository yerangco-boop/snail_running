import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:volume_controller/volume_controller.dart';

import 'services/file_logger.dart';

// 모바일/데스크톱 전용 — audioplayers 사용
//
// 플레이어를 두 개 둔다 (2026-11-25):
//  · 평소용(_media)  — 미디어 채널. 음악 앱과 겹쳐 재생되고 미디어 볼륨으로 조절됨
//  · 통화용(_call)   — 알람 채널. 통화 중에도 시스템이 막지 않음
// 통화 중일 때만 통화용으로 울리고, 통화가 끝나면 평소용으로 돌아온다.
// 예전(v30~)처럼 알람 채널 하나로 항상 울리면, 박자마다 알람 소리가 시작되면서
// 음악이 같이 끊기는 문제가 있었음(음악과 메트로놈이 함께 틱틱거림).
class ClickPlayer {
  static const _audioChannel = MethodChannel('snail_running/audio');

  AudioPlayer _media = AudioPlayer();
  AudioPlayer? _call; // "통화 중에도 재생"이 꺼져 있으면 null
  double _volume = 1.0;
  bool _mix = true;
  bool _inCall = false;
  bool _endingCall = false; // 통화 종료 처리(평소용 재생성)가 진행 중

  // init과 통화 종료 후 재생성이 겹쳐 실행되면 이미 폐기된 플레이어를 건드릴 수 있어 한 줄로 세움
  Future<void> _queue = Future.value();

  // 폰의 미디어 볼륨이 0이면 사용자가 소리를 끈 것으로 보고 울리지 않음.
  // 박자 타이밍이 흔들리지 않도록 클릭마다 기다리지 않고, 1초에 한 번만 갱신한 값을 씀
  bool _systemMuted = false;
  DateTime _stateCheckedAt = DateTime.fromMillisecondsSinceEpoch(0);

  void _refreshSystemState() {
    final now = DateTime.now();
    if (now.difference(_stateCheckedAt) < const Duration(seconds: 1)) return;
    _stateCheckedAt = now;
    VolumeController.instance.getVolume().then((v) {
      _systemMuted = v <= 0.0;
    }).catchError((_) {
      _systemMuted = false;
    });
    _queryInCall().then(_onCallState);
  }

  Future<bool> _queryInCall() async {
    try {
      return await _audioChannel.invokeMethod<bool>('isInCall') ?? false;
    } catch (_) {
      return false; // 안드로이드가 아니거나 통로가 없으면 통화 아님으로 봄
    }
  }

  void _onCallState(bool inCall) {
    if (inCall == _inCall) return;
    if (inCall) {
      _inCall = true;
      FileLogger.instance.log('[Metro] 통화 시작 감지 → ${_call != null ? "통화용(알람) 채널" : "무음(통화 중 재생 꺼짐)"}');
      return;
    }
    // 통화가 끝남: 통화 동안 시스템이 평소용 플레이어의 스트림을 회수해 죽어 있을 수 있으므로
    // 새로 만든 뒤에 전환한다 (그 사이 박자는 통화용 채널로 계속 울림)
    if (_endingCall) return;
    _endingCall = true;
    _queue = _queue.then((_) async {
      try {
        await _rebuildMedia();
      } catch (e) {
        debugPrint('[Metro] 통화 후 평소용 플레이어 재생성 실패: $e');
      }
      _inCall = false;
      _endingCall = false;
      FileLogger.instance.log('[Metro] 통화 종료 감지 → 평소용(미디어) 채널 복귀');
    });
  }

  Future<void> _configure(AudioPlayer player, {required bool forCall}) async {
    // lowLatency 모드는 안드로이드에서 SoundPool을 사용해 즉시 재생됨.
    // 기존 MediaPlayer 기반 seek+resume 방식은 GPS 스트림 등으로 메인 스레드가
    // 바쁠 때(실외 주행 중) 박자가 불규칙하게 밀리거나 씹히는 문제가 있었음.
    await player.setPlayerMode(PlayerMode.lowLatency);
    await player.setAudioContext(AudioContext(
      iOS: AudioContextIOS(
        category: AVAudioSessionCategory.ambient,
        options: _mix ? const [AVAudioSessionOptions.mixWithOthers] : const [],
      ),
      android: AudioContextAndroid(
        // mixWithOtherAudio=false면 다른 오디오(음악 앱 등)를 멈추도록 포커스를 가져옴.
        // 통화용은 통화를 방해하지 않도록 항상 포커스를 요청하지 않음
        audioFocus: (_mix || forCall) ? AndroidAudioFocus.none : AndroidAudioFocus.gain,
        // ── 출력 스트림 ──────────────────────────────────────────────
        // media: 미디어 볼륨으로 제어되고 음악과 자연스럽게 겹치지만, 통화 중엔 시스템이 막음.
        // alarm: 통화 중에도 울리도록 설계된 채널. (assistanceSonification은 9/9 실측에서
        //        이 기기의 알림 볼륨이 꺼져 있어 무음이었음 → 알람으로 교체한 이력)
        contentType: forCall ? AndroidContentType.sonification : AndroidContentType.music,
        usageType: forCall ? AndroidUsageType.alarm : AndroidUsageType.media,
        isSpeakerphoneOn: false,
        stayAwake: false,
      ),
    ));
    await player.setReleaseMode(ReleaseMode.stop);
    // audioplayers의 volume은 lowLatency(SoundPool) 백엔드에서 그대로
    // leftVolume/rightVolume에 매핑됨 — 설정 화면 슬라이더 값이 여기로 전달됨
    await player.setVolume(_volume);
    await player.setSource(AssetSource('sounds/click.wav'));
  }

  // ★ 반드시 플레이어 인스턴스를 새로 만들 것 (2026-09-05).
  // 전화가 오면 시스템이 이 앱의 SoundPool 스트림을 회수하는데, 우리는
  // AudioFocus.none(다른 앱 소리와 겹쳐 재생하려고)이라 "다시 재생해도 된다"는
  // 포커스 복귀 통지를 받지 못한다. 그 상태의 AudioPlayer는 setSource/setVolume을
  // 다시 호출해도 되살아나지 않아, 통화 뒤 재초기화 로그는 남는데 소리는 영영
  // 안 나는 현상이 있었음 → 죽은 인스턴스를 버리고 완전히 새로 만든다.
  Future<void> _rebuildMedia() async {
    await _discard(_media);
    _media = AudioPlayer();
    await _configure(_media, forCall: false);
  }

  Future<void> _discard(AudioPlayer player) async {
    try {
      await player.release();
      player.dispose();
    } catch (_) {}
  }

  Future<void> init({
    bool mixWithOtherAudio = true,
    double volume = 1.0,
    bool audibleDuringCall = false,
  }) {
    _queue = _queue.then((_) async {
      _volume = volume.clamp(0.0, 1.0);
      _mix = mixWithOtherAudio;
      await _rebuildMedia();
      final oldCall = _call;
      _call = null;
      if (oldCall != null) await _discard(oldCall);
      if (audibleDuringCall) {
        final call = AudioPlayer();
        await _configure(call, forCall: true);
        _call = call;
      }
      // 통화 중에 앱을 켠 경우에도 첫 박부터 통화용 채널로 울리도록 지금 상태를 바로 반영
      _inCall = await _queryInCall();
      debugPrint('[Metro] native ClickPlayer init done, volume=$_volume '
          '통화용=${audibleDuringCall ? "있음" : "없음"} 통화중=$_inCall');
    });
    return _queue;
  }

  // 러닝 중 슬라이더를 움직여도 재초기화 없이 즉시 반영되도록 별도 노출
  Future<void> setVolume(double volume) async {
    _volume = volume.clamp(0.0, 1.0);
    await _media.setVolume(_volume);
    await _call?.setVolume(_volume);
  }

  Future<void> play() async {
    _refreshSystemState();
    if (_systemMuted) return;
    // 통화 중에는 통화용 채널로, 평소에는 미디어 채널로. "통화 중에도 재생"이 꺼져 있으면 통화 중엔 쉼
    final player = _inCall ? _call : _media;
    if (player == null) return;
    // SoundPool(lowLatency) 백엔드는 이미 재생 중이던 스트림에 resume()만 호출하면
    // (완료된 스트림은 paused 상태가 아니라서) 무시되는 경우가 있어, stop()으로
    // streamId를 확실히 비운 뒤 resume()을 호출해 매번 새로 재생되게 함
    // 재초기화 도중 폐기된 플레이어에 남은 호출이 도달해도 앱이 죽지 않도록 방어
    try {
      await player.stop();
      await player.resume();
    } catch (e) {
      debugPrint('[Metro] play 실패: $e');
    }
  }

  void dispose() {
    _media.dispose();
    _call?.dispose();
  }
}
