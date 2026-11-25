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
dart analyze lib test        # 한글 경로에서 flutter analyze가 크래시할 때는 이걸 사용

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
`ThemePreset` (in `lib/models/theme_preset.dart`) holds color roles including `background`, `surface`, `accent`, `grey`, `runGradient`, plus `accentGradientStart`/`accentGradientEnd` and `cardGradient`/`cardBorder` (added 2026-07-13 for the dark-luxury redesign). The five built-in presets in `kThemePresets` are now **dark luxury gem-tone themes** (미드나잇 바이올렛/아크틱 블루/에메랄드 나이트/로즈 골드/앰버 프레스티지) — dark background + saturated jewel-tone cards + 2-color gradient accents (replaced the earlier light-background 코랄 선샤인 etc. set on 2026-07-13, per a Claude Design mockup). `AppSettings.preset` holds the active selection.

`ThemePreset` derives: `sheetBg`, `divider`, `onBackground` (text color for content sitting directly on `background`), `onSurface` (text color for content sitting on `surface` — **not** the same computed value as `onBackground` since the two can have very different luminance; conflating them was the root cause of several invisible-text bugs), `onBackgroundMuted` (translucent `onBackground`, used instead of the flat `grey` field wherever text sits directly on `background`), and `onRun`.

`MaterialApp`'s `ColorScheme.onSurface` (in `main.dart`) must be wired to `preset.onSurface`, not `preset.onBackground` — Flutter uses `ColorScheme.onSurface` as the default color for unstyled text/dialogs/TextFields, so getting this backwards makes anything using the Material default (dialog titles, `_settingCard` labels, TextField values) render invisible white-on-light-card text.

### Metronome & platform split
`MetronomeService` wraps a `ClickPlayer` selected by a conditional import:
- **Mobile/desktop** (`click_player_stub.dart`): uses `audioplayers` with `AudioFocus.none` and, on Android, `contentType: music` / `usageType: media` (routes through the normal media volume slider — using `sonification`/`assistanceSonification` instead routes to the separate system/accessibility sound volume, which is often muted independently and made the metronome silent on real devices even with media volume up and TTS working fine). On iOS: `AVAudioSession.ambient + mixWithOthers` so the metronome overlays music apps.
  - **채널 자동 전환 (2026-11-25)**: 플레이어를 두 개 둠 — 평소용(media)과 통화용(`usageType: alarm`). `MainActivity.kt`의 `snail_running/audio` 통로(`isInCall`, `AudioManager.mode` 조회)로 1초마다 통화 여부를 확인해 **통화 중에만** 통화용으로 울리고, 통화가 끝나면 평소용 플레이어를 새로 만들어 복귀. 알람 채널 하나로 항상 울리던 방식(11/3 기본값 변경)은 박자마다 음악이 같이 끊겨서 폐기. "통화 중에도 재생" 스위치가 꺼져 있으면 통화용 플레이어를 만들지 않음(통화 중 무음). 확인 항목은 `TEST_CHECKLIST.md`
- **Web** (`click_player_web.dart`): synthesises a 1500 Hz sine burst via Web Audio API through `dart:js`, bypassing the missing `OscillatorNode.start()` Dart binding.

The click sound asset is `assets/sounds/click.wav` (used only on native).

### TTS voice selection
Name-based male/female matching was abandoned (2026-07-11) — Android voice names don't reliably encode gender, so it silently never matched on real devices. `AppSettings.ttsVoiceName` now stores the exact voice name the user picked from a full list-with-preview picker in Settings (`null` = auto). `HomeScreen._applyTtsVoice()` matches `ttsVoiceName` exactly against `flutter_tts.getVoices`; if unset or no longer present, falls back to a voice with "google" in the name, then the first available Korean voice. Re-applied reactively via `didUpdateWidget` when `ttsVoiceName` changes.

Available voices are entirely dependent on the browser/OS — on desktop Chrome this project has seen anywhere from one voice (`Microsoft Heami`, robotic) to a better one (`Google 한국의`) depending on browser session state, with no code-level way to force a specific voice into existence if the platform doesn't expose it. Real devices (Android/iOS OS-level TTS) are expected to have more reliable multi-voice support.

### Distance tracking
Distance is measured from real GPS movement via `Geolocator.getPositionStream` (accuracy: high, `distanceFilter: 1`), accumulated in `HomeScreen._startGpsTracking()` **from raw (unsmoothed) coordinates** — an EMA-smoothed copy is kept separately purely for route-line/map-marker display, after an earlier attempt (2026-07-10) that fed the smoothed point into the distance calc itself turned out to systematically shorten distance on curved/looped courses (see git history on `_startGpsTracking` if this regresses). Readings with `accuracy` worse than `_gpsAccuracyThresholdMeters` (35m, loosened from 25m on 2026-07-11) are ignored; 3+ consecutive rejections log a `[GPS] 신호불량 N초 지속` line for diagnosis. Instantaneous speed over `_maxPlausibleSpeedKmh` (25km/h) is capped rather than discarded, and the reference point always advances (avoids the old "skip-and-chord" bug that cut corners on repeated-loop courses). The stream starts on workout start/resume and is cancelled on pause/stop. `AndroidManifest.xml` must declare `ACCESS_FINE_LOCATION`/`ACCESS_COARSE_LOCATION` — these were missing entirely until 2026-07-03, which silently broke all location features on real devices (web/desktop testing didn't surface it since the browser prompts separately).

**Background tracking (added 2026-08-10, v18) is the load-bearing part of distance accuracy** — not the accumulation algorithm. Until v17 the app ran with "while in use" location permission, so the OS cut the GPS/accelerometer streams the moment the screen turned off, losing whole stretches of the run (measured -7.9~-54.7%, worsening with run length). `_startGpsTracking` now requests `always` in the Android-required two-step order (whileInUse first, then escalate) and passes an `AndroidSettings` with `foregroundNotificationConfig` so the run is a foreground service; `wakelock_plus` additionally keeps the screen on by default. The `AndroidSettings` reference lives behind the `location_settings_factory.dart` conditional import so web builds don't pull in `geolocator_android`. **If distance under-measurement is ever reported again, first check the `[Perm]` log line says `always` and that a "러닝 기록 중" notification appeared — don't touch the accumulation math before ruling those out.**

Lap counting (`_checkLapCompletion`) counts a loop when the runner moves `_lapMinAwayMeters` (40m) from the start point and then returns within `_lapReturnRadiusMeters` (18m), with a 60-second minimum interval as hysteresis against double-counting. These numbers replaced 150m/80m on 2026-08-10: the real course is a ~240m loop, which as an equilateral-triangle approximation has 80m sides, so the *maximum* straight-line distance from the start vertex is 80.0m — the old `> 80m` test was mathematically unreachable and laps always read 0. A bearing-based "turnaround confirmation" gate existed briefly in v17 and was removed, since low-speed jogging makes GPS bearing too noisy and it suppressed real laps more than the 60s hysteresis suppresses false ones. The `[LAP]` log records current/max distance-from-start per check, so the max value tells you the course size if the thresholds need retuning again.

**현재 방식 (2026-09-14, v31)**: 위치 정확도가 나쁠 때(>20m, 직전 좌표 부정확, 콜백 간격 >5초)는 GPS 좌표 대신 `걸음 수 × 학습 보폭`(정밀 구간에서 학습, 150보 이상부터)으로 거리를 누적하고, 바퀴도 학습한 한 바퀴 거리(정밀 랩의 중앙값)를 채울 때마다 센다. 정밀 구간에서도 걸음×보폭×1.6+1.5m를 넘는 이동은 잘라낸다. 상세 경위는 `docs/history.md`의 v31 절.

### Data persistence
`DatabaseService` is a singleton wrapping `sqflite` (`snail_running.db`). All methods guard against web with `kIsWeb` checks (sqflite has no web support). Schema: single `workouts` table — `id, date, distance_km, duration_seconds, avg_pace_sec`.

### 업데이트 알림 (2026-09-28, v36)
스토어 밖 APK 배포라 설치한 사람은 새 버전이 나온 걸 알 수 없어서 추가. `lib/services/update_checker.dart`가
앱 시작 시(`HomeScreen._offerUpdate`) GitHub `releases/latest`의 `tag_name`(예: `v36`)을 읽어 설치된
앱의 빌드 번호(versionCode)보다 크면 "새 버전이 있습니다" 다이얼로그를 띄우고, [업데이트]는
`releases/latest/download/app-release.apk`를 브라우저로 열어 다운로드시킴(설치는 사용자가 직접 탭).
**릴리스 태그는 반드시 pubspec versionCode와 같은 `vN` 규칙**이어야 비교가 맞음. 네트워크·파싱 실패는 조용히 무시,
웹·러닝 중·다른 다이얼로그가 떠 있으면 그 실행에서는 건너뜀. **v35 이하를 이미 설치한 사람에게는 알림이 안 뜸**
(기능이 v36부터 들어 있으므로) — 그분들은 QR로 한 번 직접 받아야 함.

### Map
**타일 서버 교체 (2026-09-28, v35)**: CARTO(`basemaps.cartocdn.com`)가 어떤 좌표·스타일·UA로 요청해도
2,049바이트짜리 "API KEY REQUIRED" 이미지만 돌려주게 됨(직접 curl로 확인) → 지도 배경이 워터마크/빈 화면.
OSM 공용 서버(`https://tile.openstreetmap.org/{z}/{x}/{y}.png`)로 교체. **OSM 공용 타일은 소규모·개인 사용
전제(이용정책)** — 플레이스토어 등 대규모 배포 시에는 키 기반 무료 티어(MapTiler/Stadia 등, 키는 `--dart-define`)로
옮길 것. 이전에 적었던 "월 500만 타일 무료"는 더 이상 유효하지 않음.

**출처 표시 (2026-09-20, v34 추가)**: OSM 데이터(ODbL) 표기가 이용 조건. 이력 상세 지도에는
`RichAttributionWidget`(ⓘ 버튼), 주행 화면에는 하단 여백에 `지도 © OpenStreetMap contributors` 한 줄.
주행 화면은 지도 위에 알파 0.9 그라디언트 오버레이가 덮여 있어 **FlutterMap children 안에 넣으면
가려짐** — 반드시 오버레이보다 위(Stack의 마지막 child)에 얹을 것.

**지도 배경이 안 보이고 경로선만 나오는 경우**: 경로선·마커는 저장된 좌표로 기기에서 그리는 반면 타일은
매번 인터넷에서 받아오고 `flutter_map`은 기본적으로 디스크 캐시를 하지 않는다. 원인은 두 가지:
①그 시점에 인터넷이 안 됨(데이터 꺼짐/약한 신호/절약 모드), ②**타일 서버가 막혔거나 키를 요구**함(v34까지의
CARTO가 이 경우 — 9/22 "인터넷 문제"라는 진단은 사실 이쪽이었을 가능성이 높음). 의심되면 타일 URL을 curl로 받아
크기·내용부터 확인할 것(실제 타일은 수 KB~수십 KB, 워터마크는 2KB). 기록 자체는 정상 저장됨.

OpenStreetMap via `flutter_map` + OSM standard tiles. No API key required. `MapController` lives in `HomeScreen` state. The current-location marker uses `_s.accent` with no glow/shadow (a heavy shadow made it look like a warning light on the light tiles — fixed 2026-07-03).

## Key design notes from SPEC_v2.md

- **No-stop principle**: timer and distance never auto-stop at goal. Only a user "stop" action terminates a workout.
- **TTS milestones**: announced at each whole km, at 50% of goal distance, and at goal distance.
- BPM range: 140–200 in steps of 10 (values: 140, 150, 160, 170, 180, 190, 200).
- Stretching YouTube link (post-workout, implemented): `김병곤 [부위] 스트레칭` keyword via `url_launcher`, triggered from the workout-summary dialog.

## 환경

- Flutter SDK 위치: `D:\src\flutter` (강의실 PC)
- **2026-10-02: `JUNG WON DESK1` PC에 Flutter 3.47.6(stable) 설치** — `C:\src\flutter`, 사용자 PATH 등록. 웹(Chrome)·`dart analyze` 가능(설치 시점 오류 0·경고 0),
  Android SDK·Visual Studio는 없음(APK는 CI로). **`flutter pub get`을 돌리면 자동 생성 파일 20여 개(GeneratedPluginRegistrant, ephemeral, local.properties, pubspec.lock 등)가
  이 PC 경로로 바뀜** — 의도한 변경이 아니면 커밋 전에 `git checkout -- .`로 되돌릴 것
- **노트북에는 Flutter 없음** — `flutter run`/`flutter build`/`dart analyze` 전부 불가. 코드 편집(Edit/Write)과 `git`만 가능. 2026-07-11~14에 GitHub Actions로 release APK 자동 빌드·배포가 갖춰진 뒤로는(아래 "GitHub Actions APK 자동 빌드·릴리스" 참고), **노트북에서 코드만 고쳐서 push하면 GitHub Release 페이지에서 서명된 APK를 받아 폰에 설치하는 흐름이 로컬 빌드 환경 없이도 가능**함 — 방학 중 배포 자체는 이 경로로 준비 완료. 다만 노트북에는 문법 오류를 미리 잡아줄 `dart analyze`/`flutter run -d chrome` 같은 즉석 확인 수단이 없어서, 오타/타입 오류가 있으면 push 후 5~6분 뒤 CI 빌드가 실패하고 나서야 알게 됨(2026-07-13 테마 커밋이 실제로 이렇게 검증 없이 커밋된 사례) — 되도록 변경을 작게 나누고, 여유가 있으면 노트북에 Flutter SDK만이라도 설치해 `flutter run -d chrome`으로 UI를 미리 확인하는 걸 권장(Android SDK/키스토어까지는 필요 없음, 로컬 APK 빌드/서명은 강의실 PC 전용으로 유지)
- 한글 경로 문제로 `flutter analyze` 크래시 발생 → `dart analyze` 사용 (노트북에는 해당 없음 — Dart 자체가 없음)
- **Android APK 빌드 환경 (강의실 PC, 2026-07-03 세팅 완료)**:
  - JDK 21: `D:\src\jdk-21.0.11+10`
  - Android SDK: `D:\src` (cmdline-tools, platform-tools, platforms 31/33/35/36, build-tools 35/36 설치됨)
  - `android/build.gradle.kts`에 서브프로젝트 compileSdk를 36으로 강제 통일하는 블록 있음 (일부 플러그인이 낮은 compileSdk로 고정돼 최신 androidx와 충돌하는 문제 방지)
  - **중요**: 프로젝트 경로에 한글이 섞여 있어 Dart AOT 스냅샷 생성이 실패함 (`gradle.properties`의 `android.overridePathCheck=true`로는 AGP 경로 검사만 우회되고, 이 문제는 못 막음). `flutter build apk`는 반드시 **영문 경로로 복사한 뒤**(예: `robocopy "<프로젝트>" "C:\build\snail_running" /MIR /XD ".git" ".dart_tool" "build"`) 그 복사본에서 실행할 것. 빌드 결과물만 원본 위치로 복사해오면 됨
  - 빌드 후 실기기 배포는 같은 와이파이의 LAN IP로 `python -m http.server`(또는 유사 서버) 띄워서 폰 브라우저로 다운로드하거나, 카톡은 `.apk` 확장자를 차단하므로 `.zip`으로 이름 바꿔 보내고 받은 쪽에서 다시 `.apk`로 이름 변경 후 설치
  - **release 빌드마다 `pubspec.yaml`의 `version: 1.0.0+N`에서 `+N`(versionCode) 1씩 증가시킬 것** (2026-07-06부터 적용). 패키지 ID가 안 바뀌고 서명 키가 로컬·CI 양쪽에서 동일(아래 참고)하므로 기존 설치 앱 위에 그냥 덮어설치 가능하며 데이터도 유지되는데, versionCode를 안 올리면 안드로이드가 "업데이트"로 명확히 인식하지 못하고 재설치처럼 동작함
  - **릴리스 서명 키스토어 (2026-07-11부터, 로컬↔GitHub Actions 공용)**: 로컬 빌드는 debug 키(기기/세션마다 달라짐), CI는 러너마다 새로 생기는 debug 키를 각각 쓰던 게 원인이 되어 "로컬에서 설치한 앱 위에 CI가 만든 APK를 업데이트로 못 얹는" 서명 불일치 충돌이 있었음 → 하나의 release 키스토어를 만들어 로컬·CI 둘 다 그걸로 서명하도록 통일.
    - **최초 1회, 강의실 PC에서 키스토어 생성** (키스토어 파일과 비밀번호는 절대 커밋 금지 — `.gitignore`에 `*.jks`/`key.properties` 등록됨):
      ```bash
      "D:\src\jdk-21.0.11+10\bin\keytool.exe" -genkeypair -v \
        -keystore "D:\src\snail_running_upload_keystore.jks" \
        -alias upload -keyalg RSA -keysize 2048 -validity 10000
      ```
      스토어 비밀번호/키 비밀번호를 직접 정해서 입력(같아도 무방), 이름 등 나머지 질문은 그냥 Enter로 넘겨도 됨. **이 파일과 비밀번호를 잃어버리면 이후 업데이트 배포가 영구히 불가능해지므로 별도 백업 필수.**
    - **로컬(강의실 PC) 빌드 설정**: 프로젝트 루트의 `android/key.properties` 파일을 새로 만들고(커밋 안 됨) 아래 내용 채울 것:
      ```properties
      storePassword=<스토어 비밀번호>
      keyPassword=<키 비밀번호>
      keyAlias=upload
      storeFile=D:/src/snail_running_upload_keystore.jks
      ```
      `android/app/build.gradle.kts`가 이 파일이 있으면 release 서명에 자동으로 사용하고, 없으면(예: 이 파일을 아직 안 만든 다른 PC) debug 키로 안전하게 폴백함.
    - **GitHub Secrets 등록**: 저장소 → **Settings** → **Secrets and variables** → **Actions** → **New repository secret**에서 4개 등록:
      - `ANDROID_KEYSTORE_BASE64` — 키스토어 파일을 base64로 인코딩한 문자열. 클립보드로 바로 복사하려면:
        ```powershell
        [Convert]::ToBase64String([IO.File]::ReadAllBytes("D:\src\snail_running_upload_keystore.jks")) | Set-Clipboard
        ```
        복사된 값을 그대로 Secret 값 칸에 붙여넣기
      - `ANDROID_KEYSTORE_PASSWORD` — 스토어 비밀번호
      - `ANDROID_KEY_PASSWORD` — 키 비밀번호
      - `ANDROID_KEY_ALIAS` — `upload`
    - `.github/workflows/release-apk.yml`이 빌드 시점에 이 Secrets로 키스토어를 복원하고 `android/key.properties`를 러너 임시로 생성해 서명 — 커밋되는 파일은 없음
    - **2026-07-14 키 교체**: 원래 키스토어 파일이 이 PC에서 사라져 있었고(로컬 `android/key.properties`도 애초에 없어 그동안 로컬 빌드는 debug 키로 폴백되고 있었음) CI의 `ANDROID_KEYSTORE_BASE64`도 손상되어(`KeytoolException: Tag number over 30 is not supported`) v14 빌드가 실패 → 위와 동일한 방법으로 새 키스토어를 재생성하고 로컬·CI 양쪽에 재등록함. **주의**: `android/key.properties`를 PowerShell로 새로 쓸 때 `Set-Content -Encoding utf8`/`Out-File`은 UTF-8 **BOM을 붙여서** 저장하는데, Java `Properties` 파서가 BOM을 못 걷어내 첫 번째 키(`storePassword`)를 못 읽는 문제가 있었음 — 반드시 `[System.IO.File]::WriteAllText(path, content, (New-Object System.Text.UTF8Encoding($false)))`처럼 BOM 없는 인코딩으로 쓸 것. 새 키로 서명된 APK는 기존에 debug 키로 설치된 앱과 서명이 달라 처음 한 번은 삭제 후 재설치 필요
  - **날씨 기능(OpenWeatherMap) API 키는 이 PC의 사용자 환경변수 `OPENWEATHER_API_KEY`에 저장됨** (하드코딩 금지, `--dart-define`으로 주입). 이 Bash 세션은 등록 시점 이후에 뜬 새 프로세스가 아니면 `$env:`로 못 읽으므로, 빌드 시 레지스트리에서 직접 읽어와야 함:
    ```bash
    OWM_KEY=$(powershell.exe -NoProfile -Command "[Environment]::GetEnvironmentVariable('OPENWEATHER_API_KEY','User')" | tr -d '\r\n')
    flutter build apk --release --dart-define=OPENWEATHER_API_KEY="$OWM_KEY"
    ```
    (`flutter run -d chrome`으로 UI만 확인할 때는 키 없이 실행해도 됨 — "날씨 정보 없음"으로 안전하게 표시됨)

## 작업 규칙

- 브라우저 자동 스크린샷 시도 금지. UI 확인은 사용자가 직접 localhost에서 수행
  - (UI 개편 기간 2026-10-02~11-25에 한해 내장 브라우저 캡처 예외가 있었으나, 폰 최종 확인과 main 병합으로 종료됨)
- 실패하는 명령어는 2회 이내 재시도 후 다른 방법 제안
- APK 빌드는 기능·디자인 완성 후 마지막 단계에서 수행
- 작업 완료 후 반드시 `git commit` + `git push`
- **버그 수정 전 반드시 근본 원인을 먼저 진단할 것** (증상만 보고 값을 임의로 바꾸지 말 것 — 예: "화면이 검게 보인다"면 색상값을 이것저것 바꿔보기 전에 실제 RGB/명도(luminance)를 계산해서 원인을 수치로 확인). 같은 문제를 2번 이상 고쳤는데도 재발하면, 추가로 값을 바꾸지 말고 사용자에게 "재발 중이며 별도 진단이 필요할 수 있다"고 알릴 것
- ⚠️ **GPS/랩/케이던스 로직은 이제 검증된 상태 — 다른 문제를 고칠 때 이 3개는 건드리지 말 것** (2026-08-12 v18/v19 실외 검증 근거, 상세는 `docs/history.md`)
- 작업을 시작하기 전에 완료 기준을 한 줄로 먼저 밝힐 것
- 큰 작업은 하나씩 확인할 수 있는 작은 단위로 나눠서 진행할 것
- 완료 보고에는 실제로 돌린 명령과 결과(통과 수, 오류 수 등)를 함께 적을 것

## 동기화 방법

- 어느 컴퓨터든 세션 시작 시 가장 먼저 `git status && git pull origin main` 실행할 것.
- 세션 종료 시 미완성 상태여도 반드시 commit + push할 것 (WIP 커밋 허용, 커밋 메시지에 "WIP:" 표시).
- pull 시 충돌이 나면, 특별한 이유가 없는 한 더 최근에 push된 쪽(원격)을 우선 적용할 것.

## 다음 작업 목록

완료된 항목은 `docs/history.md`로 옮겼음.

- [ ] 지역명이 시/군 단위까지만 나오고 동 단위(예: "충주시 목행동")가 잘 안 나오는 경우 있음 — 안드로이드 기본 Geocoder(`geocoding` 패키지) 데이터가 이 위치에 대해 그 정도까지만 갖고 있는 것으로 보임. 카카오/네이버 로컬 API로 교체하면 더 정확할 수 있으나, **2026-07-08 기준 사용자가 "실사용해보고 필요하면 그때 바꾸자"고 보류 결정** — 먼저 바꾸자고 제안하지 말 것
- [ ] GitHub Pages 주소에서 웹 빌드 동작 테스트
- [ ] 메트로놈 `usageType`/`contentType` 변경 — 2026-07-11 커밋 메시지에 "과거 실기기 무음 버그의 근본 원인 수정을 되돌리는 것이라 사용자 확인 후 보류"라고만 기록되어 있고 원래 요청 내용 상세는 없음. **2026-09-07 v29에서 `metronomeDuringCall` 스위치로 해결됨** (아래 v29 항목 참고)
- [ ] **활동 종류 선택 (슬로우 조깅 / 러닝 / 걷기) — 2026-09-07 사용자 승인, "v29를 다음에 수정할 때 함께 진행" 으로 보류.** 기본값은 슬로우 조깅 유지.
  - 배경: "슬로우 조깅 말고 일반 러닝·산책·도보운동에서도 모든 측정이 정상이면 좋겠다"는 요청. 코드를 훑어 확인한 결과 **대부분의 측정은 활동 종류를 안 탐** — 시간·거리(GPS)·걸음수·케이던스·바퀴·경로·페이스 모두 정상. v28의 저정밀 속도 상한도 "최근 실측 속도 × 1.5" 방식이라 걷기 속도에 자동으로 맞춰짐. **손봐야 할 곳은 아래 2개뿐임**
  - **(1) 칼로리 MET 구간표** — `_metForPace`가 슬로우 조깅 기준으로 상향돼 있어(2026-08-12 v20) 걷기에서 크게 과다. 같은 페이스라도 조깅은 상하 운동이 커서 MET가 높은데 앱은 페이스만 보고 판단함. 검산값:

    | 활동 | 페이스 | 앱 MET | 실제 MET | 오차 |
    |---|---|---|---|---|
    | 러닝~슬로우 조깅 | 5~11분 | 6.2~10.0 | 6.0~11.5 | ±13% 이내 (문제 없음) |
    | 빠르게 걷기 | 10분 | 7.5 | 5.0 | **+50%** |
    | 보통 걷기 | 12분 | 6.2 | 3.5 | **+77%** |
    | 산책 | 15분 | 5.0 | 3.0 | **+67%** |

  - **(2) 케이던스 필터 통과대역** — 빠른 필터가 3Hz(`_stepFastAlpha=0.2738`)라 통과대역이 0.5~3.0Hz = **30~180spm**. 슬로우 조깅(150~175spm)은 여유가 있으나 **190~200spm대 전력 질주는 감쇠되어 걸음이 덜 잡힐 수 있음**(필터 설계상 추정, 실측 미확인). 러닝 모드에서는 4Hz(240spm)까지 확장 검토
  - 그 외: 걷기 모드에서는 BPM 권장 카드를 숨기는 게 자연스러움(표준 보폭표가 7~15분/km만 정의됨). 오래 서 있으면 GPS 잡음이 거리로 조금씩 쌓이는 문제는 활동 종류와 무관한 별개 사안

## 플레이스토어 출시 로드맵 — 보류

`docs/store_launch_roadmap.md`로 옮겼음. **보류 상태 — 먼저 착수를 제안하지 말 것.** 사용자가 출시 작업을 꺼낼 때 그 문서부터 볼 것.

## UI 개편 최신 결정 (2026-10-05~07) — 아래 10/02 기준과 충돌하면 **이 절이 우선**

상세 경위·참조 ID는 Claude 메모(`project_ui_redesign_decisions.md`)와 저장소 밖 폴더
`Documents\달팽이_디자인_이미지`(`목록_읽어주세요.md`)에 있음. **현재 상태: 구현 완료 — 2026-11-25 사용자 폰 확인 후 main 병합(v37). 테스트용 미리보기 앱(`.preview`)은 `ui-redesign` 브랜치에 push할 때만 빌드됨.**
10/21 도미체크 발표는 끝나 보류 해제(2026-10-26). 유료 결제가 드는 이미지 작업은 사용자가 시작을 승인할 때까지 대기. 색·토큰 설계안은 `docs/design_tokens.md`.

### 범위
- **순수 시각 변경만.** 성취 화면, 정지 길게 누르기, 풍향 추가, 주행 화면 일출·일몰 자동 전환은 이번에서 제외
- 지도 타일 교체는 나중. 이번엔 경로선·마커·오버레이 디자인만
- **라이트/다크 구분 없이 하나의 룩, 기본은 밝음.** (10/02의 "폰 다크모드 따름 + 주행 자동 전환" 대체)
- 10/02 기준 중 아래도 대체됨: "기본 색 체계 + 포인트 색 2~3종" 구조, 성취 화면, 박자/걸음 용어 통일, 정지 길게 누르기
- 대비·버튼 크기·글자 크기 수치 기준(7:1 / 4.5:1, 56·48px 등)과 Pretendard, 색은 테마 파일 한 곳에서만 정의하는 원칙은 유지

### 기준 디자인과 달팽이
- 기준은 **1번 시안**(크림 배경, 코랄 주황, 후드 입은 3D 달팽이). 레이아웃·문구·색은 그대로 두고 입체감만 더함. 유리형·도자기형·강한 입체는 기준이 아님
- 달팽이는 **분홍빛 코랄 껍질 + 주황 후드(흰 나선 로고) + 주황 운동화**로 고정. 매끈·통통하되 날렵하게 — 두껍고 거칠고 무겁게 만들지 말 것
- 시안에 있는 알림 벨, 연속 카드, 음악 버튼, 코칭 말풍선, 기록/코스/더보기 탭 등은 디자인 단계에서는 보여 주되, 실제 구현 범위는 구현 때 결정(이전 결정: 실제 앱 항목인 홈·이력·설정 탭과 날씨 줄만 반영)

### 질감 (클레이)
- 점토(클레이) 질감은 **달팽이 + 지도 경로선(굵은 점토 줄) + 시작/일시정지/정지/재생 버튼에만**. 은은한 매트 마감만
- 카드·배경·탭바·글자는 매끈한 평면 + 은은한 그림자. **주행 중 숫자는 평면 고대비**, 운동 완료 화면 숫자만 점토 허용
- 사용자 현재 의견은 "부분 점토". "부분 vs 전체 점토" 비교 이미지는 10/21 이후 제작 예정

### 이미지 제작 규칙
- 이미지에 **한글·영어 글자 금지**(라벨 자리는 빈 알약/회색 막대). **큰 숫자는 허용.** 글자는 앱에서 코드로 넣음
- 응원 동작: 음악 없이 달팽이만의 동작. 유사 동작은 한 번만 쓰고 나머지는 독자 동작. 삐끼삐끼 등 특정 유행 안무·음악 사용 금지
- 실패(목표 미달성) 동작: 울고 뒤돌아 멀어지다 마지막에 "내일 또" 손 흔들기. 압박감 없는 톤인지 재논의 필요
- 스튜디오 캐릭터·경쟁 앱 모방 금지, 이미지 생성물 라이선스 확인 (플레이스토어 **유료 판매** 계획)
- 이미지 도구: Canva(한도 11/1 복구) 또는 Higgsfield(3일 무료 체험 100크레딧, 3일 뒤 $49 자동결제 → 끝나면 자동 갱신 해지). 비용 드는 도구는 사용 전 고지·승인

### 홈·지도·날씨
- 홈: 시작 전엔 지도 없음, 시작(3·2·1) 후 지도 — 현재 구조 유지
- 날씨: 큰 글씨 + 3D 이모티콘(Fluent Emoji 3D, MIT) + 라벨(기온/습도/강수/풍속, 아이콘 의미에 맞게)
- 지도: 현재 OSM 타일에 채도↓ 필터 + 흰 덮개로 1차, 벡터 지도 이전(OpenFreeMap Positron 등)은 출시 전 별도 검토. 푸릇푸릇한 초록 지도·나무 일러스트는 참고안일 뿐 **적용 여부 미확정**

### 코랄 색과 글자 대비 (미확정)
- 시안 코랄 #F57A51은 흰/크림 위 2.5~2.7:1이라 글자에 부족. #C2410C는 사용자가 너무 어둡다고 함
- 제안: 면은 #F57A51, 큰 글자·아이콘은 약간 진한 주황, 작은 글자는 검정 또는 진한 주황 (색 실측 단계에서 확정)

### 구현 때 주의
- 텍스트 겹침 방지: 글자 영역 여유, 최대 줄 수·말줄임, 시스템 글자 크기 1.3~2배, 긴 지역명, 숫자 자릿수 변화 점검. 글자가 올라가는 면은 매끈하게
- 순서: 시안 확정 → 색 실측·대비 계산 → 디자인 토큰 → **별도 브랜치**에서 홈·주행부터 구현 → 사용자 폰 확인 후에만 main 병합
- 후속 아이디어(이번 범위 밖): 목표 거리 진행에 따라 달팽이가 완성되고 달성 시 응원 동작, 미달성 시 실패 동작

### 2026-11-02 확정 (위 "점토 부분 적용" 결정을 확대함 — 충돌하면 이 항목이 우선)
- **C안(06 점토 시안 방향)**: 점토 판처럼 부푼 카드·칩·탭바(미세 알갱이+주름 질감), 홈 큰 숫자·팝업 제목은 도톰한 엠보스. **주행 중 큰 숫자는 가독성 때문에 거의 평면 검정 유지**. 한글 글자엔 강한 입체 그림자 금지(번짐).
- **움직이는 달팽이 3종**(힉스필드 Wan 2.7 영상 → 투명 프레임 → 애니메이션 WebP): 같이 달리는(왼쪽을 향함, 무한 반복) / 목표 달성 응원(1회) / 미달성 아쉬워함(1회, 눈물→눈 닦음→돌아섬→돌아보며 손 흔들기). 소재는 `assets/snail/`(메타: `meta.json`에 프레임 수·몸통 비율 — 화면에서 달팽이 크기를 맞출 때 `avgBodyHeightRatio`로 보정). 버튼 4종·질감 타일은 `assets/ui/`.
- **지도는 A안**: 기존 OSM 지도를 채도↓·크림 덮개로 톤다운하고 **코드로** 점토 느낌 경로선(그림자→어두운 가장자리→코랄 본체→흰 하이라이트)과 핀·km 표시·깃발을 그림. 점토로 빚은 지도 이미지는 스타일 참고용.
- 모델이 좌우 방향 지시를 못 지키므로 이미지는 방향을 확인하고 어긋나면 **좌우 반전**으로 맞춤(왼쪽을 보고 껍질이 오른쪽이 기준).
- 원본 이미지·영상·시안 HTML은 저장소 밖(`Documents\달팽이_디자인_이미지`, 구글 드라이브 `달팽이앱`). 앱 적용 계획은 `docs/ui_apply_plan.md`, 디자인 정리는 `docs/design_asset_plan.md`.
- 힉스필드 Starter는 2026-12-02 갱신 전에 사용자가 직접 해지해야 함.

## UI 디자인 기준 (2026-10-02 확정, UI 개편용) — 일부는 위 최신 결정으로 대체됨

이번 개편은 **UI 디자인만** 바꾼다. 기능·설정 값·계산 로직(GPS·바퀴·걸음·메트로놈·DB)은 건드리지 않는다.
근거: 2026-10-02 v36 화면 진단(393×852 캡처, 대비 16개 요소 중 11개 미달) — https://claude.ai/artifact/EaEhiQNuiNc3jXp1fGJmtD

### 화면별 성격
- **정확**: 카운트다운·주행·일시정지 — 숫자가 화면을 지배, 캐릭터 없음
- **귀여움**: 홈·이력(빈 화면 포함)·운동 완료 팝업·성취 — 달팽이 캐릭터를 여기에 몰아줌
- 설정: 정돈된 목록, 장식 최소

### 수치 기준
| | 주행·일시정지·카운트다운 | 홈·이력·설정·팝업 |
|---|---|---|
| 글자 대비 | 7:1 이상 | 4.5:1 이상 |
| 버튼 최소 크기 | 56px | 48px |
| 핵심 숫자 | 48px 이상 | 28px |
- 버튼 사이 간격 16px 이상
- 글자 크기는 6단계 이내 (현재 19종 → 정리)
- 숫자가 세로로 정렬되는 곳은 고정폭 숫자(tabular figures)
- 아이콘만 있는 버튼 금지 — 아이콘 + 글자 라벨

### 밝기 모드
- 주행 외 화면: **폰의 다크 모드 설정을 따름** (밝은 화면·어두운 화면 둘 다 디자인하고 둘 다 대비 검수)
- 주행 화면: **지도 배경 유지 + 해 뜨고 지는 시각 기준 자동 전환**
  - 낮: 밝은 지도 + 흰 덮개, 숫자 뒤 흰 판, 검정 숫자 / 밤: 어두운 지도 + 검정 덮개, 흰 숫자
  - 지도 무늬 위에서 7:1을 숫자 뒤 판으로 보장 — **햇빛 아래 가독성은 실제 폰 확인 필요**

### 색·글꼴·테마
- 글꼴: **Pretendard** (앱에 파일로 포함)
- 대표색·상태색: **시안에서 2~3개 방향을 비교해 결정**
- 테마: 현재 5종은 모두 교체. **기본 색 체계 1종 + 사용자가 고르는 포인트 색 2~3종**
- 색은 테마 파일 한 곳에서만 정의하고 화면 파일에 색 값을 직접 쓰지 않음

### 달팽이 캐릭터
- **새로 디자인** (이미지 생성 도구로 후보를 만들어 선택, 비용이 드는 도구는 사용 전 승인)
- 쓰는 자리: 홈, 빈 이력, 운동 완료 팝업, 성취 뱃지

### 조작·표시
- 주행 종료: **정지 버튼 2초 길게 누르기 + 진동** (누르는 동안 진행 표시)
- 화면 용어: 메트로놈은 **"박자"**, 실측 케이던스는 **"걸음"** — 같은 줄에 나란히 (예: 박자 175 · 걸음 156)
- 날씨: 현재 항목 그대로 (기온·습도·강수확률·풍속), 보이는 방식만 다듬음
- 성취 화면: 누적 거리·꾸준함(연속 러닝)만 우선. 성취 지표는 아래 별도 과제 확정 후 결정

### 작업 방식
1. 화면을 바꾸기 전에 시안을 보여주고 승인받기
2. UI 뷰 코드만 수정, 끝나면 바뀐 파일 목록 보고
3. 웹 빌드 캡처로 대비·크기 수치 검수 (추정으로 "통과" 판정 금지)
4. 마지막에 실제 폰으로 확인

### UI 개편 밖 별도 과제 (개편 후 진행)
- **기록 학습으로 박자 자동 설정**: 최근 실측 걸음(예: 156)에서 시작해 박자를 잘 따라가면
  다음 러닝에 +5씩 올림. v22의 "슬로우 조깅 표준 보폭표" 방식과 바뀌는 지점이므로 착수 전 재논의

## 재발 시 먼저 볼 것

과거 결정과 실외 테스트 로그는 `docs/history.md`에 있음. **버그가 재발하면 거기서 먼저 검색할 것.**

- "OS 표준 동작이라 어쩔 수 없다"고 하기 전에 git 이력에서 우리가 바꾼 게 아닌지 확인할 것. 사용자의 "예전엔 됐는데"는 증거로 다룰 것 (v29)
- 설치 실패 신고가 오면 먼저 받은 파일 크기를 최신 릴리스 크기와 비교할 것. 폰의 MB 표시는 십진(÷1,000,000)임 (v25)
- 거리·바퀴 이상은 화면 켬 구간과 화면 끔 구간을 나눠 보고, 걸음 수 × 보폭으로 교차 확인할 것 (v31)
- 버그를 고친 뒤에는 실외에서 확인할 항목을 `TEST_CHECKLIST.md`에 추가할 것

## 코딩 행동 원칙 (Karpathy Guidelines)

LLM 코딩의 흔한 실수를 줄이기 위한 4원칙. 속도보다 신중함을 우선하되, 사소한 작업은 판단에 따름.

### 1. 코딩 전에 생각하기
가정하지 말고, 혼란을 숨기지 말고, 트레이드오프를 드러낼 것.
- 가정은 명시하고, 불확실하면 질문한다
- 해석이 여러 개면 조용히 하나를 고르지 말고 제시한다
- 더 단순한 방법이 있으면 말하고, 필요하면 반론한다
- 불분명한 것이 있으면 멈추고 무엇이 불분명한지 밝힌 뒤 묻는다

### 2. 단순함 우선
문제를 푸는 최소한의 코드만. 추측성 코드 금지.
- 요청하지 않은 기능 추가 금지
- 한 번만 쓰는 코드에 추상화 금지
- 요청하지 않은 "유연성"·"설정 가능성" 금지
- 일어날 수 없는 상황의 에러 처리 금지
- 200줄을 50줄로 줄일 수 있으면 다시 쓴다

### 3. 외과적 변경
꼭 필요한 곳만 건드리고, 자기가 만든 잔해만 치울 것.
- 인접한 코드·주석·서식을 "개선"하지 않는다
- 망가지지 않은 것을 리팩터링하지 않는다
- 내가 다르게 쓰더라도 기존 스타일에 맞춘다
- 무관한 죽은 코드를 발견하면 삭제하지 말고 알린다
- 내 변경 때문에 안 쓰이게 된 import·변수·함수만 제거한다
- 기준: 바뀐 모든 줄이 사용자의 요청에 직접 연결되어야 한다

### 4. 목표 중심 실행
성공 기준을 정하고, 검증될 때까지 반복할 것.
- "검증 추가" → 잘못된 입력 테스트를 먼저 쓰고 통과시킨다
- "버그 수정" → 재현 테스트를 먼저 쓰고 통과시킨다
- "리팩터링" → 전후로 테스트가 통과하는지 확인한다
- 여러 단계 작업은 `1. [단계] → 검증: [확인 방법]` 형식으로 짧은 계획을 먼저 밝힌다
