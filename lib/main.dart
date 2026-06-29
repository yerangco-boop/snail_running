import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const SnailRunningApp());
}

class SnailRunningApp extends StatelessWidget {
  const SnailRunningApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(),
      home: const MainRunningTab(),
    );
  }
}

class MainRunningTab extends StatefulWidget {
  const MainRunningTab({super.key});
  @override
  State<MainRunningTab> createState() => _MainRunningTabState();
}

class _MainRunningTabState extends State<MainRunningTab> {
  // --- 상태 변수 ---
  double _distanceKm = 0.0, _targetDistanceKm = 5.0;
  int _seconds = 0, _bpm = 150;
  int _targetMinutes = 40, _targetSeconds = 0;
  int _paceMinutes = 8, _paceSeconds = 0;
  bool _isRunning = false;
  Timer? _timer;
  final FlutterTts _tts = FlutterTts();

  @override
  void initState() {
    super.initState();
    _tts.setLanguage("ko-KR");
  }

  // --- 핵심 기능 함수들 ---
  void _startWorkout() {
    setState(() => _isRunning = true);
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        _seconds++;
        double paceInSec = (_paceMinutes * 60.0) + _paceSeconds;
        _distanceKm += 1.0 / paceInSec;
        _checkAudioGuide();
      });
    });
  }

  void _checkAudioGuide() {
    int floorKm = _distanceKm.floor();
    if (floorKm > 0 && floorKm % 1 == 0 && _seconds % 60 == 0) {
      _tts.speak("현재 $floorKm 킬로미터 지점입니다.");
    }
    if (_distanceKm >= _targetDistanceKm && _seconds % 10 == 0) {
      _tts.speak("목표 거리에 도달했습니다. 운동은 계속됩니다.");
    }
  }

  // BPM 140~200 (10단위, 170 포함)
  void _showBpmDialog() {
    final List<int> bpms = [140, 150, 160, 170, 180, 190, 200];
    showDialog(context: context, builder: (context) => SimpleDialog(
      title: const Text("BPM 선택"),
      children: bpms.map((b) => SimpleDialogOption(
        onPressed: () { setState(() => _bpm = b); Navigator.pop(context); },
        child: Text("$b BPM"),
      )).toList(),
    ));
  }

  // 숫자 직접 입력 (거리, 시간, 페이스)
  void _showInputDialog(String title, Function(String) onConfirm) {
    final ctrl = TextEditingController();
    showDialog(context: context, builder: (context) => AlertDialog(
      title: Text(title),
      content: TextField(controller: ctrl, keyboardType: TextInputType.number),
      actions: [TextButton(onPressed: () { onConfirm(ctrl.text); Navigator.pop(context); }, child: const Text("확인"))],
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("슬로우 조깅")),
      body: Column(
        children: [
          const Spacer(),
          Text("${_distanceKm.toStringAsFixed(2)} km", style: const TextStyle(fontSize: 50)),
          const SizedBox(height: 20),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            ElevatedButton(onPressed: () => _showInputDialog("거리 설정(km)", (v) => setState(() => _targetDistanceKm = double.parse(v))), child: const Text("거리 설정")),
            const SizedBox(width: 10),
            ElevatedButton(onPressed: _showBpmDialog, child: Text("$_bpm BPM")),
          ]),
          const Spacer(),
          ElevatedButton(
            style: ElevatedButton.styleFrom(fixedSize: const Size(150, 150), shape: const CircleBorder()),
            onPressed: _startWorkout, child: const Text("시작", style: TextStyle(fontSize: 30)),
          ),
          const Spacer(),
        ],
      ),
    );
  }
}