import 'package:flutter/material.dart';
import '../models/app_settings.dart';
import 'home_screen.dart';
import 'history_screen.dart';
import 'settings_screen.dart';

class MainScreen extends StatefulWidget {
  final AppSettings settings;
  final VoidCallback onSettingsChanged;

  const MainScreen({
    super.key,
    required this.settings,
    required this.onSettingsChanged,
  });

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _tabIndex = 0;
  final _historyKey = GlobalKey<HistoryScreenState>();

  AppSettings get _s => widget.settings;

  void _onTabSelected(int i) {
    setState(() => _tabIndex = i);
    if (i == 1) _historyKey.currentState?.reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _tabIndex,
        children: [
          HomeScreen(
            settings: _s,
            onSettingsChanged: widget.onSettingsChanged,
          ),
          HistoryScreen(key: _historyKey, settings: _s),
          SettingsScreen(settings: _s, onChanged: widget.onSettingsChanged),
        ],
      ),
      bottomNavigationBar: Container(
        // 점토 판처럼 위로 살짝 솟은 탭바 (C안 시안)
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFFFFDF8), Color(0xFFF8EBD7)],
          ),
          borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
          boxShadow: [
            BoxShadow(color: Color(0x4D7D5023), blurRadius: 22, spreadRadius: -8, offset: Offset(0, -12)),
          ],
        ),
        child: NavigationBar(
          selectedIndex: _tabIndex,
          onDestinationSelected: _onTabSelected,
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.directions_run_outlined),
              selectedIcon: Icon(Icons.directions_run),
              label: '홈',
            ),
            NavigationDestination(
              icon: Icon(Icons.history_outlined),
              selectedIcon: Icon(Icons.history),
              label: '이력',
            ),
            NavigationDestination(
              icon: Icon(Icons.settings_outlined),
              selectedIcon: Icon(Icons.settings),
              label: '설정',
            ),
          ],
        ),
      ),
    );
  }
}
