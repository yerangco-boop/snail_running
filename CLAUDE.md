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
`ThemePreset` (in `lib/models/theme_preset.dart`) holds five color roles: `background`, `surface`, `accent`, `grey`, `runGradient`. The five built-in presets live in `kThemePresets` and are currently light-background themes (코랄 선샤인/스카이 민트/레몬 스퀴즈/퍼플 팝/핫핑크 버스트), each with `background` luminance tuned to ~20% (was pure white; darkened per user request while keeping `surface` a light pastel). `AppSettings.preset` holds the active selection.

`ThemePreset` derives: `sheetBg`, `divider`, `onBackground` (text color for content sitting directly on `background`), `onSurface` (text color for content sitting on `surface` — **not** the same computed value as `onBackground` since the two can have very different luminance; conflating them was the root cause of several invisible-text bugs), `onBackgroundMuted` (translucent `onBackground`, used instead of the flat `grey` field wherever text sits directly on `background`), and `onRun`.

`MaterialApp`'s `ColorScheme.onSurface` (in `main.dart`) must be wired to `preset.onSurface`, not `preset.onBackground` — Flutter uses `ColorScheme.onSurface` as the default color for unstyled text/dialogs/TextFields, so getting this backwards makes anything using the Material default (dialog titles, `_settingCard` labels, TextField values) render invisible white-on-light-card text.

### Metronome & platform split
`MetronomeService` wraps a `ClickPlayer` selected by a conditional import:
- **Mobile/desktop** (`click_player_stub.dart`): uses `audioplayers` with `AudioFocus.none` and, on Android, `contentType: music` / `usageType: media` (routes through the normal media volume slider — using `sonification`/`assistanceSonification` instead routes to the separate system/accessibility sound volume, which is often muted independently and made the metronome silent on real devices even with media volume up and TTS working fine). On iOS: `AVAudioSession.ambient + mixWithOthers` so the metronome overlays music apps.
- **Web** (`click_player_web.dart`): synthesises a 1500 Hz sine burst via Web Audio API through `dart:js`, bypassing the missing `OscillatorNode.start()` Dart binding.

The click sound asset is `assets/sounds/click.wav` (used only on native).

### TTS voice selection
`HomeScreen._applyTtsVoice()` picks a Korean voice from `flutter_tts.getVoices` matching `AppSettings.ttsVoiceGender` ('male'/'female') by checking for "male"/"female" in the voice name, falling back to a voice with "google" in the name (usually more natural than an OS default), then to the first available Korean voice. Re-applied reactively via `didUpdateWidget` when `ttsVoiceGender` changes (previously only ran once in `initState`, so toggling the setting after the Home tab had already mounted had no effect).

Available voices are entirely dependent on the browser/OS — on desktop Chrome this project has seen anywhere from one voice (`Microsoft Heami`, robotic) to a better one (`Google 한국의`) depending on browser session state, with no code-level way to force a specific voice into existence if the platform doesn't expose it. Real devices (Android/iOS OS-level TTS) are expected to have more reliable multi-voice support.

### Distance tracking
Distance is measured from real GPS movement via `Geolocator.getPositionStream` (accuracy: high, `distanceFilter: 3`), accumulated in `HomeScreen._startGpsTracking()`. Readings with `accuracy` worse than `_gpsAccuracyThresholdMeters` (25m) are ignored to reduce drift while stationary. The stream starts on workout start/resume and is cancelled on pause/stop. `AndroidManifest.xml` must declare `ACCESS_FINE_LOCATION`/`ACCESS_COARSE_LOCATION` — these were missing entirely until 2026-07-03, which silently broke all location features on real devices (web/desktop testing didn't surface it since the browser prompts separately).

### Data persistence
`DatabaseService` is a singleton wrapping `sqflite` (`snail_running.db`). All methods guard against web with `kIsWeb` checks (sqflite has no web support). Schema: single `workouts` table — `id, date, distance_km, duration_seconds, avg_pace_sec`.

### Map
OpenStreetMap via `flutter_map` + CartoDB light tiles (`basemaps.cartocdn.com/light_all`, matches the current light theme presets — was `dark_all` under the old dark-theme design). No API key required. `MapController` lives in `HomeScreen` state. The current-location marker uses `_s.accent` with no glow/shadow (a heavy shadow made it look like a warning light on the light tiles — fixed 2026-07-03).

## Key design notes from SPEC_v2.md

- **No-stop principle**: timer and distance never auto-stop at goal. Only a user "stop" action terminates a workout.
- **TTS milestones**: announced at each whole km, at 50% of goal distance, and at goal distance.
- BPM range: 140–200 in steps of 10 (values: 140, 150, 160, 170, 180, 190, 200).
- Stretching YouTube link (post-workout, implemented): `김병곤 [부위] 스트레칭` keyword via `url_launcher`, triggered from the workout-summary dialog.

## 환경

- Flutter SDK 위치: `D:\src\flutter` (강의실 PC)
- 노트북에는 Flutter 없음 — 실행/빌드는 강의실 PC에서만 가능
- 한글 경로 문제로 `flutter analyze` 크래시 발생 → `dart analyze` 사용
- **Android APK 빌드 환경 (강의실 PC, 2026-07-03 세팅 완료)**:
  - JDK 21: `D:\src\jdk-21.0.11+10`
  - Android SDK: `D:\src` (cmdline-tools, platform-tools, platforms 31/33/35/36, build-tools 35/36 설치됨)
  - `android/build.gradle.kts`에 서브프로젝트 compileSdk를 36으로 강제 통일하는 블록 있음 (일부 플러그인이 낮은 compileSdk로 고정돼 최신 androidx와 충돌하는 문제 방지)
  - **중요**: 프로젝트 경로에 한글이 섞여 있어 Dart AOT 스냅샷 생성이 실패함 (`gradle.properties`의 `android.overridePathCheck=true`로는 AGP 경로 검사만 우회되고, 이 문제는 못 막음). `flutter build apk`는 반드시 **영문 경로로 복사한 뒤**(예: `robocopy "<프로젝트>" "C:\build\snail_running" /MIR /XD ".git" ".dart_tool" "build"`) 그 복사본에서 실행할 것. 빌드 결과물만 원본 위치로 복사해오면 됨
  - 빌드 후 실기기 배포는 같은 와이파이의 LAN IP로 `python -m http.server`(또는 유사 서버) 띄워서 폰 브라우저로 다운로드하거나, 카톡은 `.apk` 확장자를 차단하므로 `.zip`으로 이름 바꿔 보내고 받은 쪽에서 다시 `.apk`로 이름 변경 후 설치

## 작업 규칙

- 브라우저 자동 스크린샷 시도 금지. UI 확인은 사용자가 직접 localhost에서 수행
- 실패하는 명령어는 2회 이내 재시도 후 다른 방법 제안
- APK 빌드는 기능·디자인 완성 후 마지막 단계에서 수행
- 작업 완료 후 반드시 `git commit` + `git push`
- **버그 수정 전 반드시 근본 원인을 먼저 진단할 것** (증상만 보고 값을 임의로 바꾸지 말 것 — 예: "화면이 검게 보인다"면 색상값을 이것저것 바꿔보기 전에 실제 RGB/명도(luminance)를 계산해서 원인을 수치로 확인). 같은 문제를 2번 이상 고쳤는데도 재발하면, 추가로 값을 바꾸지 말고 사용자에게 "재발 중이며 별도 진단이 필요할 수 있다"고 알릴 것

## 동기화 방법

- 어느 컴퓨터든 세션 시작 시 가장 먼저 `git status && git pull origin main` 실행할 것.
- 세션 종료 시 미완성 상태여도 반드시 commit + push할 것 (WIP 커밋 허용, 커밋 메시지에 "WIP:" 표시).
- pull 시 충돌이 나면, 특별한 이유가 없는 한 더 최근에 push된 쪽(원격)을 우선 적용할 것.

## 다음 작업 목록

- [x] 스트레칭 유튜브 연동 (종료 다이얼로그 → `url_launcher`)
- [x] GPS 기반 실거리 측정 (2026-07-03, 페이스 시뮬레이션에서 전환)
- [ ] 앱 아이콘 미설정 — 아직 Flutter 기본 아이콘 그대로. 사용자가 디자인 방향 정하면 진행 예정
- [ ] 케이던스 vs BPM 비교 표시
- [ ] GitHub Pages 주소에서 웹 빌드 동작 테스트
- [ ] (참고) 실기기 테스트에서 TTS 남/여 음성이 실제로는 똑같이 나오는 경우 있음 — 기기의 한국어 TTS 음성 목록 자체에 성별 구분이 없는 환경 문제일 수 있어 실기기에서 재확인 필요
