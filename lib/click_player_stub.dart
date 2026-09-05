import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

// 모바일/데스크톱 전용 — audioplayers 사용
class ClickPlayer {
  AudioPlayer _player = AudioPlayer();
  double _volume = 1.0;

  Future<void> init({bool mixWithOtherAudio = true, double volume = 1.0}) async {
    _volume = volume.clamp(0.0, 1.0);
    // ★ 반드시 플레이어 인스턴스를 새로 만들 것 (2026-09-05).
    // 전화가 오면 시스템이 이 앱의 SoundPool 스트림을 회수하는데, 우리는
    // AudioFocus.none(다른 앱 소리와 겹쳐 재생하려고)이라 "다시 재생해도 된다"는
    // 포커스 복귀 통지를 받지 못한다. 그 상태의 AudioPlayer는 setSource/setVolume을
    // 다시 호출해도 되살아나지 않아, 통화 뒤 재초기화 로그는 남는데 소리는 영영
    // 안 나는 현상이 있었음 → 죽은 인스턴스를 버리고 완전히 새로 만든다.
    try {
      await _player.release();
      _player.dispose();
    } catch (_) {}
    _player = AudioPlayer();
    // lowLatency 모드는 안드로이드에서 SoundPool을 사용해 즉시 재생됨.
    // 기존 MediaPlayer 기반 seek+resume 방식은 GPS 스트림 등으로 메인 스레드가
    // 바쁠 때(실외 주행 중) 박자가 불규칙하게 밀리거나 씹히는 문제가 있었음.
    await _player.setPlayerMode(PlayerMode.lowLatency);
    await _player.setAudioContext(AudioContext(
      iOS: AudioContextIOS(
        category: AVAudioSessionCategory.ambient,
        options: mixWithOtherAudio
            ? const [AVAudioSessionOptions.mixWithOthers]
            : const [],
      ),
      android: AudioContextAndroid(
        // mixWithOtherAudio=false면 다른 오디오(음악 앱 등)를 멈추도록 포커스를 가져옴
        audioFocus: mixWithOtherAudio
            ? AndroidAudioFocus.none
            : AndroidAudioFocus.gain,
        contentType: AndroidContentType.music,
        usageType: AndroidUsageType.media,
        isSpeakerphoneOn: false,
        stayAwake: false,
      ),
    ));
    await _player.setReleaseMode(ReleaseMode.stop);
    // audioplayers의 volume은 lowLatency(SoundPool) 백엔드에서 그대로
    // leftVolume/rightVolume에 매핑됨 — 설정 화면 슬라이더 값이 여기로 전달됨
    await _player.setVolume(_volume);
    await _player.setSource(AssetSource('sounds/click.wav'));
    debugPrint('[Metro] native ClickPlayer init done, volume=$_volume state=${_player.state}');
  }

  // 러닝 중 슬라이더를 움직여도 재초기화 없이 즉시 반영되도록 별도 노출
  Future<void> setVolume(double volume) async {
    _volume = volume.clamp(0.0, 1.0);
    await _player.setVolume(_volume);
  }

  Future<void> play() async {
    // SoundPool(lowLatency) 백엔드는 이미 재생 중이던 스트림에 resume()만 호출하면
    // (완료된 스트림은 paused 상태가 아니라서) 무시되는 경우가 있어, stop()으로
    // streamId를 확실히 비운 뒤 resume()을 호출해 매번 새로 재생되게 함
    // 재초기화 도중 폐기된 플레이어에 남은 호출이 도달해도 앱이 죽지 않도록 방어
    try {
      await _player.stop();
      await _player.resume();
    } catch (e) {
      debugPrint('[Metro] play 실패: $e');
    }
  }

  void dispose() => _player.dispose();
}
