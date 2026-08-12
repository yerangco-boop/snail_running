import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

// 모바일/데스크톱 전용 — audioplayers 사용
class ClickPlayer {
  final _player = AudioPlayer();
  double _volume = 1.0;

  Future<void> init({bool mixWithOtherAudio = true, double volume = 1.0}) async {
    _volume = volume.clamp(0.0, 1.0);
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
    await _player.stop();
    await _player.resume();
  }

  void dispose() => _player.dispose();
}
