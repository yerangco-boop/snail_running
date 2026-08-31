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
`ThemePreset` (in `lib/models/theme_preset.dart`) holds color roles including `background`, `surface`, `accent`, `grey`, `runGradient`, plus `accentGradientStart`/`accentGradientEnd` and `cardGradient`/`cardBorder` (added 2026-07-13 for the dark-luxury redesign). The five built-in presets in `kThemePresets` are now **dark luxury gem-tone themes** (미드나잇 바이올렛/아크틱 블루/에메랄드 나이트/로즈 골드/앰버 프레스티지) — dark background + saturated jewel-tone cards + 2-color gradient accents (replaced the earlier light-background 코랄 선샤인 etc. set on 2026-07-13, per a Claude Design mockup). `AppSettings.preset` holds the active selection.

`ThemePreset` derives: `sheetBg`, `divider`, `onBackground` (text color for content sitting directly on `background`), `onSurface` (text color for content sitting on `surface` — **not** the same computed value as `onBackground` since the two can have very different luminance; conflating them was the root cause of several invisible-text bugs), `onBackgroundMuted` (translucent `onBackground`, used instead of the flat `grey` field wherever text sits directly on `background`), and `onRun`.

`MaterialApp`'s `ColorScheme.onSurface` (in `main.dart`) must be wired to `preset.onSurface`, not `preset.onBackground` — Flutter uses `ColorScheme.onSurface` as the default color for unstyled text/dialogs/TextFields, so getting this backwards makes anything using the Material default (dialog titles, `_settingCard` labels, TextField values) render invisible white-on-light-card text.

### Metronome & platform split
`MetronomeService` wraps a `ClickPlayer` selected by a conditional import:
- **Mobile/desktop** (`click_player_stub.dart`): uses `audioplayers` with `AudioFocus.none` and, on Android, `contentType: music` / `usageType: media` (routes through the normal media volume slider — using `sonification`/`assistanceSonification` instead routes to the separate system/accessibility sound volume, which is often muted independently and made the metronome silent on real devices even with media volume up and TTS working fine). On iOS: `AVAudioSession.ambient + mixWithOthers` so the metronome overlays music apps.
- **Web** (`click_player_web.dart`): synthesises a 1500 Hz sine burst via Web Audio API through `dart:js`, bypassing the missing `OscillatorNode.start()` Dart binding.

The click sound asset is `assets/sounds/click.wav` (used only on native).

### TTS voice selection
Name-based male/female matching was abandoned (2026-07-11) — Android voice names don't reliably encode gender, so it silently never matched on real devices. `AppSettings.ttsVoiceName` now stores the exact voice name the user picked from a full list-with-preview picker in Settings (`null` = auto). `HomeScreen._applyTtsVoice()` matches `ttsVoiceName` exactly against `flutter_tts.getVoices`; if unset or no longer present, falls back to a voice with "google" in the name, then the first available Korean voice. Re-applied reactively via `didUpdateWidget` when `ttsVoiceName` changes.

Available voices are entirely dependent on the browser/OS — on desktop Chrome this project has seen anywhere from one voice (`Microsoft Heami`, robotic) to a better one (`Google 한국의`) depending on browser session state, with no code-level way to force a specific voice into existence if the platform doesn't expose it. Real devices (Android/iOS OS-level TTS) are expected to have more reliable multi-voice support.

### Distance tracking
Distance is measured from real GPS movement via `Geolocator.getPositionStream` (accuracy: high, `distanceFilter: 1`), accumulated in `HomeScreen._startGpsTracking()` **from raw (unsmoothed) coordinates** — an EMA-smoothed copy is kept separately purely for route-line/map-marker display, after an earlier attempt (2026-07-10) that fed the smoothed point into the distance calc itself turned out to systematically shorten distance on curved/looped courses (see git history on `_startGpsTracking` if this regresses). Readings with `accuracy` worse than `_gpsAccuracyThresholdMeters` (35m, loosened from 25m on 2026-07-11) are ignored; 3+ consecutive rejections log a `[GPS] 신호불량 N초 지속` line for diagnosis. Instantaneous speed over `_maxPlausibleSpeedKmh` (25km/h) is capped rather than discarded, and the reference point always advances (avoids the old "skip-and-chord" bug that cut corners on repeated-loop courses). The stream starts on workout start/resume and is cancelled on pause/stop. `AndroidManifest.xml` must declare `ACCESS_FINE_LOCATION`/`ACCESS_COARSE_LOCATION` — these were missing entirely until 2026-07-03, which silently broke all location features on real devices (web/desktop testing didn't surface it since the browser prompts separately).

**Background tracking (added 2026-08-10, v18) is the load-bearing part of distance accuracy** — not the accumulation algorithm. Until v17 the app ran with "while in use" location permission, so the OS cut the GPS/accelerometer streams the moment the screen turned off, losing whole stretches of the run (measured -7.9~-54.7%, worsening with run length). `_startGpsTracking` now requests `always` in the Android-required two-step order (whileInUse first, then escalate) and passes an `AndroidSettings` with `foregroundNotificationConfig` so the run is a foreground service; `wakelock_plus` additionally keeps the screen on by default. The `AndroidSettings` reference lives behind the `location_settings_factory.dart` conditional import so web builds don't pull in `geolocator_android`. **If distance under-measurement is ever reported again, first check the `[Perm]` log line says `always` and that a "러닝 기록 중" notification appeared — don't touch the accumulation math before ruling those out.**

Lap counting (`_checkLapCompletion`) counts a loop when the runner moves `_lapMinAwayMeters` (40m) from the start point and then returns within `_lapReturnRadiusMeters` (18m), with a 60-second minimum interval as hysteresis against double-counting. These numbers replaced 150m/80m on 2026-08-10: the real course is a ~240m loop, which as an equilateral-triangle approximation has 80m sides, so the *maximum* straight-line distance from the start vertex is 80.0m — the old `> 80m` test was mathematically unreachable and laps always read 0. A bearing-based "turnaround confirmation" gate existed briefly in v17 and was removed, since low-speed jogging makes GPS bearing too noisy and it suppressed real laps more than the 60s hysteresis suppresses false ones. The `[LAP]` log records current/max distance-from-start per check, so the max value tells you the course size if the thresholds need retuning again.

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
- [x] 케이던스 실측 (가속도계 피크 감지, 2026-07-06) — 매 km/절반/목표/정지 시 음성 안내에 포함
- [x] 앱 아이콘 (2026-07-06) — `flutter_launcher_icons`로 달팽이 캐릭터 아이콘 생성 (`assets/icon/icon.png`, `icon_foreground.png`), 코랄-핑크 그라디언트 배경 + 보라색 나선 껍질
- [x] "다른 오디오와 함께 재생" 토글 연결 (2026-07-07) — `mixWithOtherAudio`가 false면 `AndroidAudioFocus.gain`으로 다른 오디오를 정지시키도록 `ClickPlayer.init()`에 실제 연결. 설정 변경 시 `didUpdateWidget`에서 재적용
- [x] OpenWeatherMap 날씨 연동 (2026-07-07~08) — `lib/services/weather_service.dart`. 실제 GPS 위치 기준으로 조회(제주시 좌표는 위치 실패 시 폴백 전용). 시작 전 화면에 역지오코딩 지역명(1번째 줄) + 조회시각·도시명·기온/습도/강수확률/풍속(2번째 줄) 표시, 가운데 정렬. API 키는 `--dart-define`으로 주입(하드코딩 금지, 위 "환경" 섹션 참고)
- [x] 이력에서 주행 경로 지도로 다시 보기 (2026-07-07) — `WorkoutRecord.routePoints`를 JSON 문자열로 DB 저장(DB v4), 이력 카드 탭 → `route_detail_screen.dart`에서 `PolylineLayer` + km 마커로 표시. `LatLngBounds.fromPoints` + `fitCamera`로 경로 전체가 보이도록 자동 줌
- [x] GPS 정확도 개선 (2026-07-08) — 순간 속도 25km/h 초과 구간은 기준점(`_lastGpsPoint`/`_lastGpsTime`)을 갱신하지 않음(신호 회복 시 실제 이동거리 온전히 반영). 최근 4개 원본 포인트의 이동평균으로 스무딩한 좌표를 거리 계산·경로 표시 양쪽에 사용해 지그재그 완화
- [x] km 단위 경로 마커 (2026-07-08) — `lib/utils/route_utils.dart`의 `computeKmMarkers`로 경로상 1km 간격 지점을 선형보간 계산, 이력 상세 지도·실시간 주행 지도 양쪽에 배지 표시
- [x] 설정 화면 숫자 입력을 휠 피커로 전환 (2026-07-08) — 목표거리/페이스/체중 입력을 타이핑 대신 `CupertinoPicker` 스크롤 방식으로 (나이키런 스타일)
- [x] 시작 전 화면 날짜/지역/날씨 2줄 레이아웃 (2026-07-09) — 1번째 줄 = 조회시각+지역명, 2번째 줄 = 순수 날씨 수치(도시명 제외)
- [x] GPS 거리 누적 알고리즘의 구조적 편향 수정 (2026-07-10) — 2026-07-09 실외 테스트(폴리텍 충주캠퍼스 트랙, GPS 방해물 없음)에서 나이키런 대비 거리가 크게 미달하고 뛴 거리가 늘수록 오차도 비례해서 커지는 패턴 확인. 원인: 순간속도가 `_maxPlausibleSpeedKmh`를 넘으면 구간을 통째로 버리고 기준점(`_lastGpsPoint`)도 갱신 안 하던 방식이, 다음 정상 구간에서 옛 기준점→새 지점을 직선(코너 지름길)으로 건너뛰어 트랙처럼 곡선이 반복되는 코스에서 바퀴 수만큼 오차가 누적되는 구조적 버그였음. 이제 상한만 적용하고 기준점은 항상 갱신(코너 지름길 자체를 없앰), 콜백 간격 0.5초 미만이면 순간속도 계산 스킵(짧은 시간차의 잡음성 고속 오탐 방지), 스무딩은 4점 박스평균 → EMA(지연 감소)로 교체. 진단용 `debugPrint('[GPS] ...')` 로그 추가(재발 시 `adb logcat`으로 확인)
- [x] 케이던스 상승 엣지 감지로 개선 (2026-07-10) — 임계값 초과할 때마다 카운트 → 임계값을 "넘는 순간"에만 카운트하도록 변경(임계값 근처 노이즈 중복 카운트 방지). 임계값 숫자(1.2 m/s²) 자체는 실기기 데이터 없이 변경 안 함
- [x] 경로 지도 디자인 업그레이드 (2026-07-10) — `route_utils.dart`에 `buildRoutePolyline`(흰 테두리 글로우 라인), `buildRouteEndpointMarker`(카드형 출발/도착 마커), `buildLiveLocationMarker`(펄스 실시간 위치) 공용 헬퍼 추가, `home_screen.dart`/`route_detail_screen.dart` 양쪽에 적용해 중복 제거
- [x] 바퀴 수 자동 감지 (2026-07-10, 반경 로직 2026-07-11 개선) — 트랙 등 루프 코스에서 나이키런/공인 거리와 비교 검증할 때 쓰려고 추가. 시작 지점에서 `_lapMinAwayMeters`(150m, 100m에서 상향) 이상 멀어졌다가 동적 반경(`max(20m, 최근 GPS 정확도×1.5)`, 고정 12m에서 변경) 이내로 돌아오면 1바퀴로 카운트. 편도 코스에선 그냥 0에 머묾(무해). DB v5(`lap_count` 컬럼), 중앙 표시 순환에 "바퀴" 모드, 이력 카드에 칩 표시(0바퀴면 숨김)
- [x] 케이던스/GPS/TTS 재작업 (2026-07-11) — 케이던스: 가속도계 샘플링을 50Hz(`SensorInterval.gameInterval`)로 명시하고 임계값 통과 시 `[Cadence]` 디버그 로그 추가. 거리: 2026-07-10에 도입했던 "거리 계산에 EMA 스무딩 좌표 사용"을 되돌리고 **원시 GPS 좌표로 거리 계산, EMA는 지도 표시 전용으로 분리**(정확도 컷도 25m→35m로 완화, 연속 3회 이상 정확도 미달 시 `[GPS] 신호불량 N초 지속` 로그). TTS: 이름 기반 male/female 매칭이 안드로이드에서 작동 안 해 폐기 → 설정 화면에 실제 음성 목록 + 미리듣기 버튼 피커로 교체, 선택값은 `AppSettings.ttsVoiceName`으로 저장(자동 폴백은 기존과 동일)
- [x] 다크 럭셔리 테마 5종으로 전면 교체 (2026-07-13) — Claude Design 시안 반영. 기존 밝은 5개 테마(코랄 선샤인 등) → 미드나잇 바이올렛/아크틱 블루/에메랄드 나이트/로즈 골드/앰버 프레스티지로 교체. `theme_preset.dart`에 `accentGradientStart/End`, `cardGradient`/`cardBorder` 추가. **Flutter 없는 환경(노트북)에서 텍스트 레벨로만 작성되어 dart analyze/flutter run 없이 커밋됨** — 2026-07-14 v14 실기기 설치로 처음 육안 확인, 의도대로 잘 나옴 확인 완료
- [x] GitHub Actions APK 자동 빌드·릴리스 (2026-07-11~14) — `.github/workflows/release-apk.yml`: push on main마다 release APK 빌드 후 GitHub Release로 태그(`vN`, pubspec의 versionCode)와 함께 자동 게시. 로컬·CI 공용 릴리스 키스토어 서명 통일(위 "환경" 섹션 키스토어 항목 참고). 2026-07-14, 원본 키스토어 파일 소실 + CI 시크릿 손상으로 v14 빌드가 한 차례 실패 → 키스토어 재발급으로 해결, 재실행 성공(태그 `v14` 정상 생성 확인)
  - **폰 설치용 QR코드는 `releases/latest/download/app-release.apk` 고정 주소로 만들 것** — `https://github.com/yerangco-boop/snail_running/releases/latest/download/app-release.apk`는 항상 최신 태그의 APK로 302 리다이렉트되므로, 한 번 QR을 만들어두면 버전이 올라가도 다시 만들 필요 없음. (2026-07-03에 만든 옛 QR이 그 당시의 임시 주소를 가리키고 있어서 v15 설치 시 최신 버전이 아닌 걸 받는 문제가 있었음 — `python -c "import qrcode; qrcode.make('https://github.com/yerangco-boop/snail_running/releases/latest/download/app-release.apk').save('snail_running_apk_qr.png')"`로 재생성함). 이 PNG는 `.gitignore`에 등록되어 커밋 안 되니, 다른 PC에서도 필요하면 같은 명령으로 다시 생성
- [ ] 지역명이 시/군 단위까지만 나오고 동 단위(예: "충주시 목행동")가 잘 안 나오는 경우 있음 — 안드로이드 기본 Geocoder(`geocoding` 패키지) 데이터가 이 위치에 대해 그 정도까지만 갖고 있는 것으로 보임. 카카오/네이버 로컬 API로 교체하면 더 정확할 수 있으나, **2026-07-08 기준 사용자가 "실사용해보고 필요하면 그때 바꾸자"고 보류 결정** — 먼저 바꾸자고 제안하지 말 것
- [ ] GitHub Pages 주소에서 웹 빌드 동작 테스트
- [ ] 메트로놈 `usageType`/`contentType` 변경 — 2026-07-11 커밋 메시지에 "과거 실기기 무음 버그의 근본 원인 수정을 되돌리는 것이라 사용자 확인 후 보류"라고만 기록되어 있고 원래 요청 내용 상세는 없음. 다시 논의 필요하면 사용자에게 무엇을 원했는지부터 확인할 것
- [x] 다크 럭셔리 테마 배경/카드/네비게이션 바 재정비 + 버전 표시 (2026-07-14, versionCode 15) — 5개 테마 `background`를 중간 명도 탁한 톤에서 근무채색 다크(#16~1c 범위)로 교체, `cardGradient`를 고정 회색이 아니라 실제 `background` 기반으로 재정의, `cardBorder` 알파 0.55→0.35(테두리가 너무 진하다는 피드백 반영), `cardShadow` 추가. `main.dart`의 `ColorScheme.light`+`surface` 원색 조합이 하단 네비게이션 바를 원색 막대로 보이게 하던 버그를 `ColorScheme.dark` 전환으로 수정. accent 채도 12% 상승. `package_info_plus`로 설정 화면 하단에 실제 설치 버전(versionName+versionCode) 표시 추가
- [x] 릴리스 키스토어 재발급 (2026-07-14) — 아래 "환경" 섹션 키스토어 항목 참고
- [x] 메트로놈 무음 버그 실외 재확인 (2026-07-14) — 나이키런과 동시 실행 상태로 실외 테스트, 달팽이 앱 메트로놈 정상 작동 확인. `PlayerMode.lowLatency`(2026-07-06 수정)가 유효한 것으로 판단, 재발 안 함
- [x] 바퀴 수 미인식 원인 확정 (2026-07-14) — 실외 테스트에서 "왕복 260m(편도 약 130m) 코스를 2회 왕복"했는데 바퀴 수가 0으로 나옴. `_lapMinAwayMeters`(150m)가 편도 130m보다 커서 "충분히 멀어짐" 조건 자체가 한 번도 안 걸린 것으로, 버그가 아니라 임계값이 짧은 왕복 코스에 안 맞았던 것(트랙 검증용으로 150m로 잡았던 값)
- [x] 케이던스 감지 진단 로깅 보강 (2026-07-14, versionCode 16) — 실외 테스트에서 케이던스가 러닝 내내 비정상적으로 낮게 나온 것 확인(로그 타임스탬프로 재구성한 실시간 케이던스가 대부분 11~97spm, 이력 저장 평균도 27spm). `userAccelerometerEventStream.listen`에 `onError`/`onDone` 핸들러가 없어 스트림이 죽어도 감지 불가능했던 문제 발견, 핸들러 추가. 5초마다 "수신 이벤트 수 vs 임계값 통과 수 vs 구간 mag 범위" 진단 로그 추가
- [x] 설정 영속 저장 (2026-07-22, versionCode 17) — `shared_preferences` 도입. `AppSettings.load()`/`save()` 추가(bpm/목표거리·시간/페이스/TTS음성/오디오옵션/체중/테마 이름 전부 대상). `main.dart`에서 앱 시작 시 로드 후 렌더링(로드 전엔 배경색만 있는 빈 스캐폴드로 짧게 대기), `onSettingsChanged`/`onChanged` 콜백마다 자동 저장
- [x] 바퀴 수 인식 로직 적용 (2026-07-22, versionCode 17) — `_lapMinAwayMeters` 150m→80m로 하향, 짧아진 반경에서 GPS 잡음이 복귀반경을 스치기만 해도 오탐하지 않도록 "방향 전환(턴어라운드) 확인" 로직 추가: 아웃존 진입 시점의 진행 방향(베어링)을 기록해두고, 이후 베어링이 100° 이상 바뀌어야(또는 복귀반경의 절반 이내로 아주 가깝게 돌아오면) 바퀴로 카운트. `_checkLapCompletion`에 단계별 디버그 로그(아웃존 진입/방향전환 감지/바퀴 완료/카운트 보류) 추가
- [x] 케이던스/GPS 로그를 파일로도 기록 (2026-07-22, versionCode 17) — `lib/services/file_logger.dart` 추가. `debugPrint`와 동시에 앱 문서 디렉터리의 텍스트 파일에 버퍼링 후 3초마다 append(50Hz 이벤트를 매번 디스크에 쓰지 않기 위함). 설정 화면 "디버그" 섹션의 "실외 테스트 로그 공유" 버튼으로 `share_plus`를 통해 카톡/메일 등 아무 앱으로나 바로 공유 가능 — **adb/USB 연결 없이도 실외 테스트 로그 확인 가능**. GPS 로그에는 정확도/순간속도/캡핑 여부에 더해 누적 수락·거부 포인트 수도 추가
- [x] 메트로놈 스피커 음량 개선 (2026-07-22, versionCode 17) — `assets/sounds/click.wav`가 피크는 이미 -0.21dBFS(최대치)였지만 파형이 아주 짧은 임펄스(크레스트 팩터 17dB)라 RMS(체감 음량)가 낮았던 것이 원인. 단순 게인 증폭은 이미 최대치라 의미 없어, 다이나믹 컴프레션(threshold -18dB, ratio 5:1) + 메이크업 게인으로 피크는 그대로 두고 RMS를 +7.7dB 높임. `click_player_stub.dart`에도 `_player.setVolume(1.0)` 명시적으로 추가(기존에도 기본값 1.0이었지만 방어적으로 고정)
- [x] 버전 표시 확인 + "정보" 섹션 추가 (2026-07-22, versionCode 17) — 하단 버전 표시는 이미 2026-07-14부터 `package_info_plus`로 동적 조회 중이었음(하드코딩 아님, 확인만 함). 앱 아이콘 + 앱 이름 + 버전 + "© 2026 홍정표 · Made by 홍정표"를 보여주는 "정보" 카드 섹션 추가
- [x] 지도에 바퀴 완료 지점 마커 추가 (2026-07-22, versionCode 17) — 바퀴가 카운트되는 좌표를 `_lapCompletionPoints`에 저장, `route_utils.dart`의 `buildLapMarkerChip`(깃발 아이콘 + 바퀴 번호)으로 실시간 주행 지도·이력 상세 지도 양쪽에 표시. `WorkoutRecord.lapCompletionPoints`로 DB 저장(DB v6, `lap_points_json` 컬럼)

- [x] **백그라운드 위치 유실 근본 원인 확정 및 수정 (2026-08-10, versionCode 18)** — 21세션 교차검증에서 **시간 오차는 +18초(정상)인데 거리만 -7.9~-54.7%로 불규칙 유실**되고, 세션 26~29분은 평균 -16.2% / 33~37분은 -31.9%로 **러닝 시간에 비례해 악화**되는 패턴 확인. 원인은 알고리즘이 아니라 **위치 권한이 "앱 사용 중에만 허용"이라 화면이 꺼지는 순간 GPS/가속도계 스트림이 OS에 의해 차단**된 것 + 배터리 최적화의 추가 억제. 처방: ①`ACCESS_BACKGROUND_LOCATION`/`FOREGROUND_SERVICE(_LOCATION)`/`POST_NOTIFICATIONS` 권한과 `GeolocatorLocationService`(foregroundServiceType=location) 선언 추가 ②`AndroidSettings.foregroundNotificationConfig`로 러닝 중 포그라운드 서비스 승격(알림 "달팽이 러닝 / 러닝 기록 중", `enableWakeLock`+`setOngoing`) ③whileInUse→always 단계적 권한 요청 + 미승인 시 시작 화면 경고 배너 & 설정 딥링크 ④`wakelock_plus`로 러닝 중 화면 켜두기(설정 토글, 기본 ON). **거리 계산 알고리즘 자체는 이번에 손대지 않음** — 원인이 알고리즘이 아니었음이 데이터로 확정됐기 때문
  - 웹 빌드가 깨지지 않도록 `AndroidSettings`(geolocator_android 전용) 참조는 `location_settings_factory.dart` 조건부 import로 분리 — 기존 `database_service`/`click_player`와 동일 패턴
- [x] 랩 카운트 임계값 재산정 (2026-08-10, versionCode 18) — **기존 80m가 물리적으로 도달 불가였던 것이 랩이 항상 0이던 원인.** 실측 트랙 둘레 240~250m를 정삼각형 근사하면 한 변 80~83m이고, 시작점(꼭짓점)에서 코스상 최대 직선 이격거리는 반대편 꼭짓점까지의 80.0m(둘레 240m 기준) → 조건이 `> 80m`(초과)라 절대 안 걸림. **40m/복귀 18m/최소 랩 간격 60초**로 교체. v17의 베어링 기반 "방향전환 확인" 게이트는 제거(저속 조깅에서 베어링 잡음으로 실제 랩을 억제할 위험이 60초 히스테리시스보다 컸음). `[LAP]` 로그에 현재이격/최대이격/경과시간/판정결과 기록 — **최대이격 값이 코스 크기를 알려주므로 다음 재조정의 근거가 됨**
- [x] 케이던스 임계값 하향 + 저역통과 필터 (2026-08-10, versionCode 18) — 나이키 132~148spm 대비 달팽이는 2~7spm으로 사실상 미감지. 폰을 손에 들고 뛰면 손이 완충 역할을 해 기기 진폭이 작음 → 임계값 **1.2 → 0.35 m/s²** 하향, 3Hz 1차 IIR 저역통과(alpha=0.2738 @50Hz)로 고주파 잡음 제거 후 그 결과에 임계값 적용(러닝 160spm=2.67Hz라 걸음 성분은 보존됨). **평균 케이던스 분모에서 0spm 구간 제외**(`_cadenceActiveSeconds`) — 스트림 중단 구간이 평균을 27spm까지 끌어내리던 문제. `[CADENCE]` 10초 요약 로깅
- [x] 칼로리 MET 동적 산출 (2026-08-10, versionCode 18) — **신규 발견 버그**: 12세션 중 8세션이 kcal/분 7.18~7.21로 고정 수렴, 26'14"/km와 11'20"/km의 분당 칼로리가 동일했음. 원인은 MET를 8~12분/km 구간에서 6~7로만 선형 보간해 폭이 너무 좁았던 것. 구간별 테이블(≤6분:10.0 / ≤8분:8.3 / ≤10분:6.0 / ≤13분:4.5 / 초과:3.5)로 교체 → 검산 결과 kcal/분이 11.67/9.68/7.00/5.25/4.08로 페이스를 실제 반영. 체중 기본값 60→70kg
- [x] 랩 기반 거리 병기 (2026-08-10, versionCode 18) — 이력 카드/상세에 "N바퀴 (추정 X km)"를 GPS 거리와 나란히 표시해 **앱 자체로 GPS 정확도를 교차검증**할 수 있게 함. 랩당 거리는 설정에서 조정(기본 240m = 실측 트랙 둘레)
- [x] 이력 상세 화면 통합 + 랩 스플릿 (2026-08-10, versionCode 18) — `route_detail_screen`을 지도만 있던 화면에서 **지도 + 통계 카드 + 랩별 구간 기록**을 한 화면에 스크롤로 보여주도록 재구성. 랩 완료 시점의 누적 경과초를 `WorkoutRecord.lapSplitSeconds`로 저장(DB v7, `lap_splits_json`)해 랩별 구간 시간 표시
- [x] 보안 점검 (2026-08-10) — 저장소가 public이므로 확인: `.gitignore`에 `*.jks`/`*.keystore`/`android/key.properties` 등록됨, **전체 커밋 이력에 키스토어·시크릿 파일 추가된 적 없음**, API 키도 `String.fromEnvironment`로만 주입(하드코딩 없음). 이상 없음
- [x] TEST_CHECKLIST.md 신설 (2026-08-10) — 실외 테스트 12항목 + v18 핵심 검증 + 로그 태그별 의미 정리. **테스트 전 "항상 허용" 권한과 배터리 최적화 해제를 먼저 확인**하도록 0번 섹션에 명시

- [x] **케이던스 구조적 버그 확정 및 수정 (2026-08-11, versionCode 19)** — v18 실외 테스트에서 나이키 134spm 대비 달팽이 **5spm**. 임계값을 1.2→0.35로 낮췄는데도 개선이 없어 값 조정이 아니라 로직을 재검토한 결과 **구조적 버그 확정**: `sqrt(x²+y²+z²)` 크기는 항상 0 이상인 **정류된 신호**라 러닝 중 평균 1~3 m/s² 부근에서 진동할 뿐 0 근처로 내려오지 않음 → 절대 임계값이 **한 번 참이 되면 계속 참**으로 유지되고, 상승 엣지 방식이라 **그 뒤로 걸음이 영영 안 잡힘**(5spm은 필터 워밍업 구간에만 잡힌 값). **임계값을 낮출수록 오히려 악화되는 구조**라 어떤 값을 넣어도 해결 불가였음.
  - 처방: 빠른 필터(3Hz, alpha 0.2738)에서 느린 필터(**0.5Hz, alpha 0.0591 = 기준선/DC**)를 뺀 **밴드패스 신호**에 임계값(0.20) 적용 — 0을 중심으로 진동하므로 걸음마다 상승 엣지가 정상 발생. 러닝 134spm=2.23Hz는 0.5~3Hz 통과대역 안이라 보존되고, 자세 변화 등 0.5Hz 미만은 기준선에 흡수됨
  - **검증**: 134spm 신호로 시뮬레이션 시 v18 방식은 기준선/진폭과 무관하게 1spm, v19 방식은 정확히 134spm 산출. `[CADENCE]` 로그에 `ac진폭범위`와 `기준선`을 함께 기록 — ac의 min이 계속 양수면 기준선 추적 실패, 진폭은 충분한데 통과=0이면 임계값 문제로 구분 가능
- **v18 실외 테스트 결과 (2026-08-11, 나이키 교차검증)** — 거리 2.42km vs 나이키 2.48km(**-2.4%**, 이전 -7.9~-54.7%에서 해결), 시간 26:59 vs 26:53(+6초 정상), **랩 10바퀴 정상 카운트**(이전엔 항상 0), 랩 추정 2.40km vs GPS 2.42km로 0.8% 차이(상호 검증 성립). **포그라운드 서비스 + always 권한이 거리 유실의 진짜 원인이었음이 실측으로 확정됨.** 칼로리는 146 vs 나이키 114인데 역산하면 나이키가 체중 약 56kg을 쓴 것으로, MET 로직이 아니라 **설정의 체중값(기본 70kg)이 실제와 다른 것** — 사용자가 설정에서 실제 체중 입력하면 일치할 것으로 보임

- **v18/v19 실외 검증 완료 (2026-08-12) — P0 3개 항목 전부 정상 작동 확인**
  - 거리 GPS 2.37km / 랩 기준 2.50km, 오차 -5.2% (정상 범위). 포그라운드 서비스 수정 유효
  - **랩 10회 정상 검출** — 직전 21세션이 전부 0이었으므로 40m 임계값이 적정함이 확정
  - 랩 구간 시간 평균 2:27, 표준편차 약 5초(편차 3.4%) → 검출 신뢰도 높음
  - **케이던스 113spm** (직전 3~5spm) → v19의 밴드패스(기준선 대비 진폭) 전환이 유효
  - ⚠️ **GPS/랩/케이던스 로직은 이제 검증된 상태 — 다른 문제를 고칠 때 이 3개는 건드리지 말 것**
- [x] 칼로리 MET 구간표 상향 (2026-08-12, versionCode 20) — v18 구간표로도 137kcal/25.3분 = 5.42 kcal/분(역산 MET 4.6)으로 "보통 걷기" 수준까지 떨어짐. 슬로우 조깅은 같은 속도의 걷기보다 상하 운동이 커서 실제 MET가 더 높으므로 느린 구간 위주로 상향: ≤6분 10.0 / ≤8분 **8.8** / ≤10분 **7.5** / ≤13분 **6.2** / 초과 **5.0**. 검산: 10'38"/km · 25분17초 · 70kg → 183kcal(목표 180~185 충족). 체중은 이미 `AppSettings.weightKg` + 설정 화면 휠 피커로 저장/로드되고 있어 추가 작업 없음(확인만 함)
- [x] **뒤로가기 1회로 러닝 세션이 통째로 날아가던 문제 수정 (2026-08-12, versionCode 20)** — `PopScope(canPop: !workoutActive)` + `onPopInvokedWithResult`로 운동 중일 때만 뒤로가기를 가로채고 "러닝을 종료할까요? / 기록이 저장되지 않습니다" 확인 다이얼로그 표시. 대기 상태에서는 기존 동작 그대로. `IndexedStack` 구조라 이력·설정 탭을 보고 있어도 HomeScreen이 트리에 남아 있어 함께 보호됨
  - 추가 안전장치: `lib/services/workout_snapshot.dart` 신설. 러닝 중 **30초마다** 진행 상태(거리/시간/걸음/랩/경로/랩스플릿)를 SharedPreferences에 저장하고, 앱 재실행 시 남아있는 스냅샷이 있으면 "이전 러닝 기록을 복구할까요?"를 띄워 **이력 DB에 저장**. 정상 종료 시에는 스냅샷을 지움. 24시간 초과했거나 0.05km/30초 미만인 스냅샷은 자동 폐기
- [x] 총 걸음 수 실측 저장/표시 (2026-08-12, versionCode 20) — 가속도계 피크로 실제 센 `_totalSteps`를 `WorkoutRecord.totalSteps`로 저장(**DB v8**, `ALTER TABLE ADD COLUMN`이라 기존 이력 보존). 러닝 중 중앙 숫자 순환에 "걸음" 모드 추가(천 단위 구분 표기), 이력 상세 기록 섹션에도 "총 걸음 수 N 보" 행 추가
- [x] 메트로놈 ON/OFF + 음량 슬라이더 (2026-08-12, versionCode 20) — 러닝 화면 상단에 즉시 토글 칩 배치(러닝 중에도 바로 껐다 켜짐), 설정 화면에 "메트로놈 사용" 스위치와 0~100% 음량 슬라이더 추가. 두 값 모두 SharedPreferences 영속. 음량은 안드로이드 SoundPool의 `leftVolume/rightVolume`(audioplayers `setVolume`)과 웹 Audio `gain`에 각각 연동되고, 러닝 중 슬라이더를 움직이면 재초기화 없이 즉시 반영됨
- [x] 이력 상세 랩 표 개선 (2026-08-12, versionCode 20) — 랩별 "구간 페이스" 열 추가(구간 시간을 코스 1바퀴 거리로 1km 환산), 가장 빠른 랩/느린 랩을 배경 하이라이트 + 화살표 아이콘으로 강조

- [x] 코스 1바퀴 거리 설정 폐지, 랩 거리 실측 저장으로 전환 (2026-08-13, versionCode 21) — 사용자가 "이 설정이 왜 필요한지 모르겠다"고 지적. 확인 결과 이 값은 거리 계산에 전혀 관여하지 않고 **표시 전용**이었으나(GPS 거리는 좌표 간 실제 이동거리만 누적), 입력값이 실제와 다르면 랩 표의 누적거리·구간페이스가 통째로 틀어지는 단점이 있었음. 원래 목적(랩×코스길이로 GPS 교차검증)은 GPS 정확도가 -2.4~-5.2%로 검증되면서 소멸 → **설정 항목 삭제**하고, 랩 완료 시점의 실제 GPS 누적 거리를 `WorkoutRecord.lapSplitDistanceKm`로 저장(**DB v9**)해 랩 표를 실측값으로 표시. v20 이전 기록은 해당 열이 '--'로 표시됨
- [x] 메트로놈 BPM ↔ 목표 페이스 연동 (2026-08-13, versionCode 21) — **속도 = 케이던스 × 보폭** 관계라 페이스만으로는 BPM이 정해지지 않고 보폭이 필요함. v20부터 걸음 수를 저장하므로 지난 기록에서 **실측 보폭**을 계산 가능해짐(`WorkoutRecord.strideMeters`, 최근 5개 평균). 설정의 목표 페이스 아래에 "이 페이스엔 N BPM 권장 / 내 보폭 83cm 기준" 카드와 [적용] 버튼 추가.
  - 검증: 8/12 세션 역산 보폭 83cm로 계산하면 실제 페이스 10'38"에서 113 BPM이 나와 **실측 케이던스 113spm과 정확히 일치**
  - **BPM 선택 범위를 140~200(10단위) → 100~200(5단위)로 확대**하고 휠 피커로 통일 — 느린 페이스의 권장값(110~130대)이 기존 범위 밖이라 적용 자체가 불가능했음. SPEC_v2.md의 "BPM 140~200" 항목을 대체함
  - 참고: 설정 BPM 150 vs 실측 케이던스 113spm으로, **메트로놈 박자를 실제로는 따라가지 않고 있었음**이 이 기능으로 드러남
- [x] 메트로놈이 통화 후 조용해지던 문제 (2026-08-13, versionCode 21) — 원인은 `AndroidAudioFocus.none`. 음악 앱과 겹쳐 재생하려고 오디오 포커스를 아예 요청하지 않는데, 그 부작용으로 전화가 오면 시스템이 스트림을 끊고도 **"다시 재생해도 된다"는 포커스 복귀 통지를 못 받아** 영영 조용해졌음. 처방 두 가지: ①`didChangeAppLifecycleState`의 `resumed` 시점에 러닝 중이면 `_restartMetronome()`으로 **자동 복구**(init부터 다시 — 세션이 깨진 뒤엔 start()만으론 안 살아남) ②러닝 화면의 메트로놈 토글 칩을 켤 때도 재초기화를 거치게 해 **수동 복구 버튼** 역할 부여

- [x] **BPM 제안 방향을 슬로우 조깅 원칙에 맞게 수정 (2026-09-01, versionCode 22)** — v21에 넣은 "목표 페이스 → 실측 보폭 → 권장 BPM"이 **방향이 거꾸로였음**. 실측 보폭을 쓰면 느린 페이스일수록 BPM을 낮추라고 제안하는데(예: 10'38"에서 113 BPM), 슬로우 조깅은 정반대로 **케이던스를 높게 유지하고 보폭을 줄여** 속도를 낮추는 방식임.
  - 추가로 계산 입력값도 틀렸음: 8/12 지시서의 "케이던스 113spm"을 앱 이력과 대조 없이 사용했는데, 실제 이력은 **146~153spm**이었음. 151spm 기준 보폭은 83cm가 아니라 **62cm**(슬로우 조깅다운 짧은 보폭). **앞으로 사용자가 준 수치라도 앱 이력과 교차 확인할 것**
  - 수정: 실측 보폭 대신 **슬로우 조깅 표준 보폭 앵커표**(7분:75cm ~ 15분:43cm, 선형 보간)를 기준으로 BPM 산출 → 페이스 전 구간에서 **155~190 BPM**의 높은 대역이 나옴. 실측 보폭은 "지난 러닝 62cm"처럼 비교용으로만 병기해 얼마나 잔발로 바꿔야 하는지 보여줌
  - BPM 범위는 v21에서 100~200으로 넓혔던 것을 **140~200(5단위)로 되돌림** — 하한을 낮췄던 이유가 잘못된 권장값(110~130)을 담기 위해서였는데 그 전제가 사라졌기 때문. 5단위는 유지(175 같은 값 선택 가능)

## 2026-08-13 작업 노트 (versionCode 21)

### 다음 실외 테스트에서 확인할 것
- 통화를 받았다 끊은 뒤 메트로놈이 자동으로 다시 들리는지 (안 되면 토글 칩을 껐다 켜서 복구되는지)
- 설정 → 목표 페이스 아래 "N BPM 권장" 카드가 뜨고 [적용]이 동작하는지
- 이력 상세의 랩 표 누적거리가 실제 GPS 거리와 맞는지 (v20 이전 기록은 '--'가 정상)
- DB v9 마이그레이션 후 기존 이력 보존 확인

### 보류 중
- **UI 디자인 개편** — 사용자가 "더 심도깊게 생각하고 의논해서 천천히 하자"고 결정(2026-08-13). 재개할 때 참고: 디자인 반복이 계속 어려웠던 근본 원인은 도구가 아니라 **노트북에 Flutter가 없어 미리보기가 불가능한 것**(색 하나 바꿔도 CI 6분+폰 설치 필요). 재개 전에 노트북에 Flutter SDK 설치(`flutter run -d chrome`만 되면 됨, Android SDK/키스토어 불필요)를 먼저 권할 것. 도구 옵션은 `/design` 스킬(편집 가능한 캔버스 아트보드) 또는 claude.ai/design + DesignSync MCP

## 2026-08-12 작업 노트 (versionCode 20)

노트북에 Flutter가 없어 이번에도 컴파일 검증 불가 — 괄호 균형 검사 + Flutter 공식 문서로 `PopScope`/`onPopInvokedWithResult` 시그니처 대조까지만 수행.

### 다음 실외 테스트에서 확인할 것
- 칼로리가 180kcal 안팎으로 올라오는지 (같은 조건 기준)
- **러닝 중 뒤로가기** → 확인 다이얼로그가 뜨는지, "계속 달리기"로 러닝이 유지되는지
- 앱을 강제 종료(작업 관리자에서 스와이프)한 뒤 재실행 → "이전 러닝 기록을 복구할까요?"가 뜨고 복구 시 이력에 저장되는지
- 총 걸음 수가 케이던스 × 시간과 얼추 맞는지 (113spm × 25분 ≈ 2,800보 수준)
- 메트로놈 토글/음량 슬라이더가 즉시 반영되고 앱 재시작 후에도 유지되는지
- DB v8 마이그레이션 후 **기존 이력이 그대로 남아 있는지** (가장 먼저 확인할 것)

## 2026-08-10 작업 노트 (versionCode 18, 다음 실외 테스트에서 확인)

### [이번 세션 변경 — 전부 실기기 미검증]
노트북에 Flutter가 없어 이번에도 `dart analyze`/`flutter run` 없이 텍스트 검증(괄호 균형 + pub.dev API 문서 대조)만 하고 커밋함.
`ForegroundNotificationConfig`(notificationTitle/notificationText/enableWakeLock/setOngoing)와 `AndroidSettings`(accuracy/distanceFilter/foregroundNotificationConfig)는 pub.dev 문서로 시그니처 확인함.

- **최우선 확인**: 러닝 시작 시 알림창에 "달팽이 러닝 / 러닝 기록 중"이 뜨는지 → 안 뜨면 포그라운드 서비스가 안 붙은 것
- **화면 끄고 5분 이상** 뛴 뒤 그 구간 거리가 누적되는지 (이번 수정의 핵심)
- 랩 카운트가 실제 바퀴 수와 맞는지 — 안 맞으면 `[LAP]` 로그의 `최대이격` 값으로 임계값 재조정
- 케이던스가 나이키와 비슷해지는지 — `[CADENCE]` 로그의 `수신이벤트`가 0인 구간이 있으면 스트림 문제, 없는데 `임계값통과`가 0이면 0.35도 여전히 높은 것
- 칼로리가 페이스에 따라 달라지는지
- 신규 패키지 3개(`geolocator_android` 명시 승격, `wakelock_plus`, DB v7 마이그레이션)가 실기기에서 정상 동작하는지

### [이전 버전에서 넘어온 미검증 항목]
v17에서 넣었지만 아직 실외에서 확인 못 한 것들 — TEST_CHECKLIST.md의 12항목 표로 함께 점검할 것:
설정 영속 저장 / 로그 파일 공유 버튼 / 메트로놈 컴프레션 체감 음량 / 바퀴 마커 표시

## 2026-07-22 작업 노트 (versionCode 17, 다음 실외 테스트 전 확인 필요)

### [이번 세션에서 처리, 아직 실외 미검증]
- 바퀴 수 인식(80m + 방향전환 확인 로직) — 코드 리뷰 수준으로만 검증(이 컴퓨터에 Flutter 없어 `flutter run`/`dart analyze` 불가, 괄호 균형 검사만 수행). **다음 실외 테스트에서 반드시 확인**: 왕복 코스에서 정확히 카운트되는지, 방향전환 각도 임계값(100°)이 저속 조깅 GPS 잡음에 너무 민감하거나 둔감하지 않은지
- 케이던스/GPS 진단 로그의 파일 저장 + 공유 기능 — 로직상으로는 완성했지만 실기기에서 실제로 파일이 쓰이고 공유 시트가 뜨는지는 미확인. 다음 실외 테스트 후 설정 화면에서 "실외 테스트 로그 공유"를 눌러 실제로 로그 파일이 나오는지부터 확인할 것
- 메트로놈 컴프레션 결과물이 실제로 더 크게 들리는지는 청감 테스트 필요(수치상 RMS는 개선됐으나 사람 귀 체감은 실기기에서 확인)
- 설정 영속 저장 — 로컬/CI 빌드 후 앱을 껐다 켜서 설정이 실제로 유지되는지 확인 필요

### [여전히 미해결]
- **케이던스 근본 원인**: versionCode 16의 진단 로그(수신이벤트/임계값통과/mag범위)를 아직 실외에서 못 뽑음(이전 테스트 때 USB가 빠지며 유실). 이번에 파일 로깅이 추가됐으니 다음 테스트에서는 USB 연결 여부와 무관하게 로그를 받을 수 있을 것 — 그 로그로 "스트림이 죽는지" vs "임계값(1.2 m/s²)이 안 맞는지" 확정 후 조정할 것. **추측성 값 변경 금지**
- **GPS 거리 정확도**: 나이키 대비 15~21% 과소측정 원인 미확정. 이번에 로그 항목(정확도/속도/누적 수락·거부 수)만 보강했고 값은 변경 안 함 — 다음 실외 테스트 로그로 원인 특정 필요

### [환경]
- 2026-07-22 기준 노트북(SAMSUNG-NOTE2)에 여전히 Flutter/Dart 미설치 확인. `flutter run -d chrome`/`dart analyze` 불가 — 코드 변경은 텍스트 레벨 검증(괄호 균형 등)만 가능. 실제 동작 확인은 강의실 PC 또는 GitHub Actions 빌드 후 실기기 설치로 진행
- DB 스키마 v6 (`lap_points_json` 컬럼 추가) — 기존 v5 이하 설치 기기에서는 `onUpgrade`로 자동 마이그레이션됨(컬럼 없이 저장된 과거 기록은 바퀴 마커 없이 표시)
