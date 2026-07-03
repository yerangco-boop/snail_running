import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

// 모바일/데스크톱 전용 — audioplayers 사용
class ClickPlayer {
  final _player = AudioPlayer();

  Future<void> init() async {
    await _player.setAudioContext(AudioContext(
      iOS: AudioContextIOS(
        category: AVAudioSessionCategory.ambient,
        options: const [AVAudioSessionOptions.mixWithOthers],
      ),
      android: AudioContextAndroid(
        audioFocus: AndroidAudioFocus.none,
        contentType: AndroidContentType.music,
        usageType: AndroidUsageType.media,
        isSpeakerphoneOn: false,
        stayAwake: false,
      ),
    ));
    await _player.setReleaseMode(ReleaseMode.stop);
    await _player.setSource(AssetSource('sounds/click.wav'));
    debugPrint('[Metro] native ClickPlayer init done, state=${_player.state}');
  }

  Future<void> play() async {
    await _player.seek(Duration.zero);
    await _player.resume();
  }

  void dispose() => _player.dispose();
}
