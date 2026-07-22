import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

// USB/adb 연결 없이도 실외 테스트 로그를 나중에 확인할 수 있도록, debugPrint와
// 동시에 앱 전용 저장소의 텍스트 파일에도 기록. 설정 화면에서 이 파일을
// share_plus로 바로 공유(카톡/메일 등)할 수 있게 연결되어 있음(FileLogger.filePath 참고).
// 매 줄마다 디스크에 쓰면 가속도계 50Hz 이벤트 등에서 I/O 부하가 커질 수 있어,
// 메모리에 버퍼링했다가 3초마다 한 번씩만 파일에 append함.
class FileLogger {
  static final FileLogger instance = FileLogger._();
  FileLogger._();

  File? _file;
  final List<String> _buffer = [];
  Timer? _flushTimer;
  bool _initializing = false;

  Future<void> init() async {
    if (kIsWeb || _file != null || _initializing) return;
    _initializing = true;
    try {
      final dir = await getApplicationDocumentsDirectory();
      final now = DateTime.now();
      final stamp = now.toIso8601String().replaceAll(RegExp(r'[:.]'), '-');
      _file = File('${dir.path}/snail_debug_$stamp.log');
      await _file!.writeAsString(
        '=== 달팽이 러닝 디버그 로그 시작 ${now.toIso8601String()} ===\n',
        mode: FileMode.write,
      );
      _flushTimer?.cancel();
      _flushTimer = Timer.periodic(const Duration(seconds: 3), (_) => _flush());
    } catch (e) {
      debugPrint('[FileLogger] 초기화 실패: $e');
    } finally {
      _initializing = false;
    }
  }

  // 콘솔(debugPrint)에는 항상 즉시 남기고, 파일에는 버퍼링 후 주기적으로 flush
  void log(String line) {
    debugPrint(line);
    if (_file == null) return;
    _buffer.add('${DateTime.now().toIso8601String()} $line');
  }

  Future<void> _flush() async {
    if (_file == null || _buffer.isEmpty) return;
    final lines = List<String>.from(_buffer);
    _buffer.clear();
    try {
      await _file!.writeAsString('${lines.join('\n')}\n', mode: FileMode.append);
    } catch (e) {
      debugPrint('[FileLogger] 파일 쓰기 실패: $e');
    }
  }

  Future<void> flushNow() => _flush();

  String? get filePath => _file?.path;

  Future<void> dispose() async {
    _flushTimer?.cancel();
    await _flush();
  }
}
