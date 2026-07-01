# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

```bash
# Run on connected device / emulator
flutter run

# Run on specific platform
flutter run -d chrome        # Web
flutter run -d android
flutter run -d ios

# Build
flutter build apk            # Android APK
flutter build ios            # iOS (Mac required)

# Analyze / lint
flutter analyze

# Tests
flutter test
flutter test test/some_test.dart   # Single test file
```

## Architecture

### State management pattern
`AppSettings` is a plain mutable Dart object (no Provider/Riverpod/Bloc). It is created once in `_SnailRunningAppState` and passed down as a constructor argument. Mutations happen directly on the object; callers invoke the `onSettingsChanged` / `onChanged` VoidCallback to propagate changes upward so the root `setState` re-renders the MaterialApp theme.

### Screen structure
`MainScreen` uses `IndexedStack` with three tabs:
- **HomeScreen** — the workout screen (idle → countdown → running → paused state machine via `WorkoutState` enum). Contains the goal-setting bottom sheet (`_GoalSheet`) inline.
- **HistoryScreen** — lists past `WorkoutRecord`s from SQLite.
- **SettingsScreen** — BPM picker, pace input, theme preset grid, audio toggles.

### Theme system
`ThemePreset` (in `lib/models/theme_preset.dart`) holds five color roles: `background`, `surface`, `accent`, `grey`, `runGradient`. The five built-in presets live in `kThemePresets`. `AppSettings.preset` holds the active selection. `ThemePreset` also derives computed colors: `sheetBg`, `divider`, `onBackground`, `onRun`.

### Metronome & platform split
`MetronomeService` wraps a `ClickPlayer` selected by a conditional import:
- **Mobile/desktop** (`click_player_stub.dart`): uses `audioplayers` with `AudioFocus.none` (Android) and `AVAudioSession.ambient + mixWithOthers` (iOS) so the metronome overlays music apps.
- **Web** (`click_player_web.dart`): synthesises a 1500 Hz sine burst via Web Audio API through `dart:js`, bypassing the missing `OscillatorNode.start()` Dart binding.

The click sound asset is `assets/sounds/click.wav` (used only on native).

### Distance tracking
Distance is simulated from the configured pace (`paceMinutes:paceSeconds /km`), not from GPS. GPS (`geolocator`) is used only for the map center marker in the pre-run screen. Real GPS route recording is listed as a future feature in SPEC_v2.md.

### Data persistence
`DatabaseService` is a singleton wrapping `sqflite` (`snail_running.db`). All methods guard against web with `kIsWeb` checks (sqflite has no web support). Schema: single `workouts` table — `id, date, distance_km, duration_seconds, avg_pace_sec`.

### Map
OpenStreetMap via `flutter_map` + CartoDB dark tiles (`basemaps.cartocdn.com/dark_all`). No API key required. `MapController` lives in `HomeScreen` state.

## Key design notes from SPEC_v2.md

- **No-stop principle**: timer and distance never auto-stop at goal. Only a user "stop" action terminates a workout.
- **TTS milestones**: announced at each whole km, at 50% of goal distance, and at goal distance.
- BPM range: 140–200 in steps of 10 (values: 140, 150, 160, 170, 180, 190, 200).
- Stretching YouTube link (post-workout, not yet implemented): `김병곤 [부위] 스트레칭` keyword via `url_launcher`.

## 환경

- Flutter SDK 위치: `D:\src\flutter` (강의실 PC)
- 노트북에는 Flutter 없음 — 실행/빌드는 강의실 PC에서만 가능
- 한글 경로 문제로 `flutter analyze` 크래시 발생 → `dart analyze` 사용

## 작업 규칙

- 브라우저 자동 스크린샷 시도 금지. UI 확인은 사용자가 직접 localhost에서 수행
- 실패하는 명령어는 2회 이내 재시도 후 다른 방법 제안
- APK 빌드는 기능·디자인 완성 후 마지막 단계에서 수행
- 작업 완료 후 반드시 `git commit` + `git push`
- **버그 수정 전 반드시 근본 원인을 먼저 진단할 것** (증상만 보고 값을 임의로 바꾸지 말 것 — 예: "화면이 검게 보인다"면 색상값을 이것저것 바꿔보기 전에 실제 RGB/명도(luminance)를 계산해서 원인을 수치로 확인). 같은 문제를 2번 이상 고쳤는데도 재발하면, 추가로 값을 바꾸지 말고 사용자에게 "재발 중이며 별도 진단이 필요할 수 있다"고 알릴 것

## 다음 작업 목록

- [ ] 스트레칭 유튜브 연동 (종료 다이얼로그 → `url_launcher`)
- [ ] 케이던스 vs BPM 비교 표시
- [ ] GitHub Pages 주소에서 웹 빌드 동작 테스트
