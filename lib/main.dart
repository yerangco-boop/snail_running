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

  void _onSettingsChanged() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final p = _settings.preset;
    final accent = p.accent;
    final grey = p.grey;
    final surface = p.surface;

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: p.background,
        colorScheme: ColorScheme.dark(
          surface: surface,
          primary: accent,
          secondary: accent,
          onPrimary: Colors.white,
          onSurface: Colors.white,
          outline: grey,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
          systemOverlayStyle: SystemUiOverlayStyle.light,
        ),
        cardTheme: CardThemeData(
          color: surface,
          elevation: 0,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: surface,
          indicatorColor: accent.withValues(alpha: 0.2),
          labelTextStyle: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return TextStyle(color: accent, fontSize: 12);
            }
            return TextStyle(color: grey, fontSize: 12);
          }),
          iconTheme: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return IconThemeData(color: accent);
            }
            return IconThemeData(color: grey);
          }),
        ),
        dialogTheme: DialogThemeData(backgroundColor: surface),
      ),
      home: MainScreen(
        settings: _settings,
        onSettingsChanged: _onSettingsChanged,
      ),
    );
  }
}
