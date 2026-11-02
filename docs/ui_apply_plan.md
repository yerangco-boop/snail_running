# UI 개편 앱 적용 계획 (2026-11-02)

기준: 화면 시안 `Documents\달팽이_디자인_이미지\시안\화면시안_v1.html`의 **C안** + 지도 **A안**(기존 OSM 지도 + 코드로 그린 점토 경로선).
작업 브랜치: `ui-redesign` (main 병합은 사용자 폰 확인 후).

## 0. 확정된 것
- 달팽이 3종: 달리기·응원·아쉬워함 (Wan 영상 → 투명 프레임)
- 점토 버튼 4종(시작·일시정지·정지·재개), 점토 판 카드, 도톰한 숫자(주행 중 큰 숫자는 거의 평면)
- 지도: 기존 OSM 타일 + 채도↓·크림 덮개 + 점토 밧줄 경로선·핀·km 표시·깃발
- 앱 아이콘: `35_H7_앱아이콘_v1_좌향반전_1024.png` (후보)

## 1. 현재 코드 구조 (ui-redesign 브랜치 기준)
| 위치 | 내용 |
|---|---|
| `lib/theme/tokens.dart` | 색 토큰 (bg #FCF9F3, coralFace #F57A4F, coralDisplay #F3602F, ink …) |
| `home_screen.dart:1710` `_buildPreRunScreen` | 시작 전 홈 |
| `:1857` `_buildCountdownScreen` | 3·2·1 |
| `:1902` `_buildRunningScreen` | 주행 (FlutterMap + 그라디언트 덮개 0.90/0.80/0.93 + 메트릭) |
| `:2266` `_buildRunningControl` / `:2281` `_buildPausedControls` | 일시정지·정지·재개 버튼 |
| `:1540` `_showSummaryDialog` | 운동 완료 AlertDialog (스트레칭 부위 선택 포함) |
| `lib/utils/route_utils.dart` | `buildRoutePolyline`, km/랩/끝점/현재 위치 마커 |
| `history_screen.dart` / `route_detail_screen.dart` | 이력 목록 / 상세(지도·랩 표) |

## 2. 가장 큰 위험 3가지와 대응
1. **브랜치 충돌**: `measurement-fix`(측정 v37)가 `home_screen.dart`를 156줄 고쳤음. UI도 같은 파일을 고치므로 충돌 가능.
   → 새 UI는 **새 파일**(`lib/widgets/clay/…`, `lib/widgets/snail_animation.dart`)에 만들고 `home_screen.dart`는 호출부만 최소 수정. 주기적으로 `main`을 합쳐 충돌을 작게 유지.
2. **메모리**: 프레임 75~120장을 PNG로 올리면 디코딩 메모리가 큼(프레임당 약 1MB).
   → **애니메이션 WebP 3개**(달리기·응원·아쉬워함, 각 1~2MB)로 변환해 `Image.asset`으로 재생(프레임 단위로 디코딩). 반복 횟수는 파일에 지정(달리기=무한, 응원·아쉬워함=1회). 문제가 있으면 높이 360px 프레임 시퀀스로 대체.
3. **성능**: 점토 질감(그림자 여러 겹+노이즈)을 목록에 많이 쓰면 느려짐.
   → 질감은 작은 타일 이미지 1장을 반복, 그림자는 `BoxDecoration` 미리 만든 상수 재사용, 이력 목록은 가벼운 버전(그림자 2겹) 사용.

## 3. 단계 (각 단계 끝에 웹으로 확인하고 보고)
| 단계 | 내용 | 눈에 보이는 변화 |
|---|---|---|
| P1 소재 준비 | 애니메이션 WebP 3개, 버튼 4종 WebP, 마스터 달팽이 WebP, 질감 타일, `pubspec` assets 등록 | 없음 |
| P2 점토 부품 | `ClayCard`, `ClayChip`, `ClayImageButton`(눌림·튕김 효과), `ClayNumber` 스타일, 점토 탭바 | 없음(위젯만) |
| P3 홈(시작 전) | 헤드라인·마스터 달팽이·날씨 칩·목표 점토 카드·점토 시작 버튼·탭바 | 홈 |
| P4 주행 화면 | 메트릭 점토 카드, 점토 버튼(일시정지·정지·재개), 달리는 달팽이, 지도 덮개 연하게, **점토 경로선·핀·km 표시·깃발** | 주행 |
| P5 완료 팝업 | `AlertDialog` → 점토 팝업, 달성 시 응원·미달성 시 아쉬워함 애니메이션, 스트레칭 부위 선택 유지 | 팝업 |
| P6 이력·상세 | 목록 카드·상세 지도에 같은 점토 경로선, 랩 깃발 | 이력 |
| P7 마무리 | 앱 아이콘 교체(flutter_launcher_icons), 설정 화면 테마 영역 숨김·점토 카드, Pretendard 글꼴, 날씨 3D 아이콘 | 전체 |

## 4. 검증 방법
- 각 단계: `dart analyze` 오류 0, `flutter test`, `flutter run -d chrome`로 웹 화면을 시안과 나란히 비교(내장 브라우저, UI 개편 예외 규정 범위).
- 글자 크기 1.3~2배, 긴 지역명, 숫자 자릿수 변화에서 겹침 확인(CLAUDE.md 구현 때 주의 항목).
- 마지막: push → `preview-apk.yml`이 미리보기 APK 빌드 → 사용자 폰에서 확인 → 승인 후에만 main 병합.
- 이 PC에는 Android SDK가 없어서 폰 확인은 CI APK로만 가능.

## 5. 사용자 결정이 필요한 것
1. **"12일 연속" 카드**: 이력 DB에서 연속 일수를 계산해 실제 기능으로 넣을지 / 뺄지. (알림 벨은 기능이 없어 제외 권장)
2. **날씨 3D 아이콘**(Fluent Emoji, MIT)과 **Pretendard 글꼴** 내려받기 허용 (파일 내려받기는 그때 출처·크기를 알리고 확인)
3. **측정 브랜치(measurement-fix) 병합 순서**: UI 작업 전에 먼저 실외 검증 후 main에 합칠지 / UI와 나중에 함께 합칠지
4. 코랄 위 아이콘 색: 확정한 점토 버튼은 코코아색(대비 약 5.4:1, 주행 화면 7:1 기준 미달). 이대로 갈지

## 6. 예상 앱 용량 증가
애니메이션 WebP 약 4~5MB + 버튼·마스터 약 0.3MB + 글꼴 약 1~3MB + 질감 타일 소량 = **약 6~9MB**
