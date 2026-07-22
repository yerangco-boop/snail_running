import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'models/app_settings.dart';
import 'screens/main_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
  ));
  runApp(const SnailRunningApp());
}

class SnailRunningApp extends StatefulWidget {
  const SnailRunningApp({super.key});

  @override
  State<SnailRunningApp> createState() => _SnailRunningAppState();
}

class _SnailRunningAppState extends State<SnailRunningApp> {
  final AppSettings _settings = AppSettings();
  bool _settingsLoaded = false;

  @override
  void initState() {
    super.initState();
    _settings.load().then((_) {
      if (mounted) setState(() => _settingsLoaded = true);
    });
  }

  // 설정이 바뀔 때마다(화면 재렌더 + 영속 저장) 호출됨 — 저장은 fire-and-forget으로
  // 충분함(SharedPreferences가 내부적으로 쓰기를 큐잉하므로 화면 전환을 막을 필요 없음)
  void _onSettingsChanged() {
    setState(() {});
    _settings.save();
  }

  @override
  Widget build(BuildContext context) {
    if (!_settingsLoaded) {
      final p = _settings.preset;
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(backgroundColor: p.background),
      );
    }
    final p = _settings.preset;
    final accent = p.accent;
    final grey = p.grey;
    final background = p.background;
    final onBackground = p.onBackground;

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: background,
        // surface/onSurface를 테마의 채도색(p.surface)이 아니라 근무채색 배경(p.background)에
        // 맞춰야 함 — Flutter가 다이얼로그·카드·네비게이션바 등 스타일 안 준 위젯의 기본
        // 배경으로 ColorScheme.surface를 쓰기 때문에, 여기가 채도색이면 라이트 테마 시절처럼
        // 원색이 화면 전체에 깔리는 문제가 재발함
        colorScheme: ColorScheme.dark(
          surface: background,
          primary: accent,
          secondary: accent,
          onPrimary: Colors.white,
          onSurface: onBackground,
          outline: grey,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
          systemOverlayStyle: SystemUiOverlayStyle.light,
        ),
        cardTheme: CardThemeData(
          color: background,
          elevation: 0,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        navigationBarTheme: NavigationBarThemeData(
          // 배경/그림자는 MainScreen이 감싸는 Container(카드 질감)가 담당하고,
          // NavigationBar 자체는 투명하게 비워서 그 위에 얹힘
          backgroundColor: Colors.transparent,
          elevation: 0,
          indicatorColor: accent.withValues(alpha: 0.28),
          labelTextStyle: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return TextStyle(color: accent, fontSize: 12, fontWeight: FontWeight.w600);
            }
            return TextStyle(color: grey, fontSize: 12);
          }),
          iconTheme: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              // 선택된 탭 아이콘에 은은한 포인트 컬러 글로우
              return IconThemeData(
                color: accent,
                shadows: [Shadow(color: accent.withValues(alpha: 0.7), blurRadius: 10)],
              );
            }
            return IconThemeData(color: grey);
          }),
        ),
        dialogTheme: DialogThemeData(backgroundColor: background),
      ),
      home: MainScreen(
        settings: _settings,
        onSettingsChanged: _onSettingsChanged,
      ),
    );
  }
}
