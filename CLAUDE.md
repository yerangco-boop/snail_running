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
- [x] 바퀴 수 자동 감지 (2026-07-10) — 트랙 등 루프 코스에서 나이키런/공인 거리와 비교 검증할 때 쓰려고 추가. 시작 지점에서 100m 이상 멀어졌다가 12m 반경 이내로 돌아오면 1바퀴로 카운트(`_checkLapCompletion`). 반경을 스마트폰 GPS 잡음(3~10m)보다 더 좁히면 실제 통과도 못 잡아 undercounting되므로 12m로 유지하고, 과다 카운트는 "100m 이상 멀어짐" 가드로 방지. 편도 코스에선 그냥 0에 머묾(무해). DB v5(`lap_count` 컬럼), 중앙 표시 순환에 "바퀴" 모드, 이력 카드에 칩 표시(0바퀴면 숨김) 추가. versionCode 12로 빌드
- [ ] 지역명이 시/군 단위까지만 나오고 동 단위(예: "충주시 목행동")가 잘 안 나오는 경우 있음 — 안드로이드 기본 Geocoder(`geocoding` 패키지) 데이터가 이 위치에 대해 그 정도까지만 갖고 있는 것으로 보임. 카카오/네이버 로컬 API로 교체하면 더 정확할 수 있으나, **2026-07-08 기준 사용자가 "실사용해보고 필요하면 그때 바꾸자"고 보류 결정** — 먼저 바꾸자고 제안하지 말 것
- [ ] GitHub Pages 주소에서 웹 빌드 동작 테스트
- [ ] (참고) 실기기 테스트에서 TTS 남/여 음성이 실제로는 똑같이 나오는 경우 있음 — 기기의 한국어 TTS 음성 목록 자체에 성별 구분이 없는 환경 문제일 수 있어 실기기에서 재확인 필요

### 다음 실외 테스트 시 확인 항목 (2026-07-10 빌드=versionCode 12 기준)

- **바퀴 수 자동 감지가 실제 바퀴 수와 맞는지** — 트랙 실측(RealityScan + 네이버맵 거리재기 둘 다 270m로 수렴, 신뢰도 높은 기준값)과 비교. 반경 12m/가드 100m가 적정한지 이번 테스트로 판단(과다/과소 카운트 여부)
- **거리 측정치가 나이키런/공인 트랙거리(270m×바퀴수)와 비슷해졌는지가 최우선 확인 항목** — 이번이 거리 정확도 수정 2번째 시도(1차: 2026-07-08 이동평균 스무딩, 결과 여전히 큰 오차로 재확인됨). 이번에도 오차가 크게 남으면 값만 또 바꾸지 말고, 코드에 추가된 `[GPS]` 디버그 로그(`adb logcat`)로 실제 accuracy/speed 수치를 받아서 진단할 것

- **거리 측정치가 나이키런과 비슷해졌는지가 최우선 확인 항목** — 이번이 거리 정확도 수정 2번째 시도(1차: 2026-07-08 이동평균 스무딩, 결과 여전히 큰 오차로 재확인됨). 이번에도 오차가 크게 남으면 값만 또 바꾸지 말고, 코드에 추가된 `[GPS]` 디버그 로그(`adb logcat`)로 실제 accuracy/speed 수치를 받아서 진단할 것
- 트랙처럼 곡선이 반복되는 코스 + 직선 위주 코스(공원 산책로 등) 양쪽에서 비교 — 곡선 구간에서만 벌어지는 오차인지 구분하기 위함
- 정확한 바퀴 수를 세면서 뛰고, 트랙의 공인 거리(학교 시설 정보/표지판)와 비교해볼 것 — 나이키런도 100% 정답은 아님
- 케이던스 상승 엣지 감지 적용 후 체감 페이스와 얼마나 맞는지, threshold `1.2 m/s²` 조정 필요 여부
- 메트로놈 규칙성 — `PlayerMode.lowLatency`(SoundPool) 전환 효과가 실제로 있는지 (2026-07-06 수정, 아직 실외 확인 안 됨)
- 바람 조건에 따른 오탐지 여부 — 강풍 시 손 흔들림으로 걸음 수 과다 카운트 가능성 (제주 등 강풍 지역에서 특히 확인 필요)
- 새 경로 지도 디자인(흰 테두리 글로우 라인, 카드형 마커)이 실제 화면에서 의도대로 보이는지
- 날짜/지역/날씨 2줄 레이아웃이 의도대로 나오는지
