# G4 화면 (godot/PLAN.md 5·7절): 메뉴 · 대기실 · 판 HUD · 결과 · 설정 · 화면 전환

JS `client/main.js`·`client/index.html` 의 화면을 옮김. 계산은 `ui_calc.gd` (JS shared/hud-layout·kills-hud·wipe·char-select·leave 그대로, 정답 테스트 `tests/test_ui.gd`).

| 파일 | 내용 (JS 원본) |
| --- | --- |
| `ui.gd` · `ui.tscn` | 뿌리 CanvasLayer: 화면 고르기 (screenOf)·전환 슬래시·접속 글·핑·Enter 시작 (main.js updateScreen) |
| `ui_style.gd` | '빛 사선' 모양: 빛 판·평행사변형 버튼·주 버튼·글자 빛·글자 칸, 판 중 HUD 밝은 모양 (index.html CSS) |
| `menu.gd` | 메뉴: 빛 로고·이름·큰 버튼 펼침·공개 방 목록·연습 (index.html #rooms, main.js openMenu·renderRoomList) |
| `big_btn.gd` | (W8) 메뉴 큰 버튼 꾸밈: 사선을 칸 안으로 (StyleBoxFlat skew 넘침을 expand_margin 으로), 세로 그라데이션 바탕·안쪽 빛·왼쪽 아래 빛 세모 (뒤 겹), 빛 줄기 반짝임 5.5초 (앞 겹, 움직임 줄이기·그래픽 낮춤이면 없음) — index.html `#rooms button.big` |
| `text_glow.gd` | (W8) 글자 흐린 빛 (CSS text-shadow 흉내): 글자를 SubViewport 에 반 크기로 한 번 그려 반씩 줄였다 키워 흐린 판 → 더하기 섞기 TextureRect. 메뉴 로고 18·46·90px (`S.LOGO_BLUR`). 고도 Label 의 외곽선·그림자는 흐리지 못해 굵은 외곽선 겹은 얇은 띠로 보임 |
| `lobby.gd` | 대기실 판 (오른쪽, lobby_dock): 상태·캐릭터 카드 3×3·랜덤·스킬 카드·이름·색·시작·방 설정·방 코드 (main.js drawHud 대기실 부분) |
| `host_players.gd` | 플레이어 관리 (방장): 팀전·팀 섞기·관전·내보내기 (updateHostPlayers) |
| `wipe.gd` | 전환 슬래시 (playWipe) |
| `portrait.gd` | 초상: G2 몸을 화면 밖 SubViewport 에 한 번 그려 캐시 (아래 판 96·카드 128 온몸·큰 캐릭터 256 온몸·결과 승자 192), 한 프레임에 한 장, 메뉴 PORTRAIT_WARM_MS 뒤 카드 8장 미리 (client/portrait.js) |
| `practice.gd` | (G6) 연습 방 창: 토글·내 피해·캐릭터·맵·허수아비·연습 나가기 + 허수아비 콤보 기록 (main.js updatePractice) |
| `tutorial_ui.gd` · `tutorial_calc.gd` | (G6) 튜토리얼: 묻기·캐릭터 고르기·진행 띠·끝 화면, 띠 문구 계산 (client/tutorial-ui.js, shared/tutorial.js). 메뉴·설정 '튜토리얼' → View.open_panel |
| `perf.gd` · `perf_calc.gd` | (G6) F3 성능 표시·계산 (client/perf.js, shared/perf.js), 켬 = View.settings.perf |
| `char_stage.gd` | 대기실 큰 3D 캐릭터: 고르면 정면 도발 한 번 → 천천히 돎, 판 시작하면 놓음, 그래픽 낮춤이면 정지 초상 (client/char-stage.js) |
| `ui_prefs.gd` | 기억 (tf-name·tf-color·tf-char·tf-tutorial → user://ui.json) |

main.gd 가 `ui/ui.tscn` 을 자동으로 붙임 (2026-10-31 총괄이 고도로 돌려 스크립트 에러 0 확인). 화면 확인: `--auto host --bots 3 --shot <png> --shot-at menu|lobby|game|tab|settings|results` (core/autopilot.gd, tab 은 `--mode kills`).
초상은 portrait.gd (다 그려지기 전·헤드리스면 색 상자).  3D 메뉴·대기실 배경은 범위 밖 — 빛 색은 `View.ui_theme` 가 생기면 그 테마, 없으면 자수정.

## UI 배율 (W9, 2026-11-02 재혁 'UI 가 너무 작다')

화면 판·글자는 기준 화면 1280×720 으로 만들고 창 크기에 맞춰 키움 (`core/ui_scale.gd`, project.godot `window/stretch` = canvas_items + expand). 3D 는 창 픽셀 그대로.
- 자동: 논리 크기 (창 픽셀 / 화면 배율 k — 윈도우 150%·200%, 브라우저 devicePixelRatio. JS 의 CSS 픽셀) 에서 기준 1280×720 이 다 들어가는 배율 min(폭/1280, 높이/720) × k.
  16:9 는 창 높이 / 720 (1080 → 1.5배), 16:10 은 폭 기준 (재혁 노트북 2880×1800 200% → 2.25배, UI 1280×800). 논리 1280×720 보다 작은 창은 1 × k (960×540 = W4 작은 창 배치 그대로, 웹 DPR 2 도 JS 처럼),
  960×540 도 안 들어가면 줄임, 최소 0.75 · 최대 2.5. 설정 'UI 크기' 80~200% 고정 = 그 값 × k (JS 브라우저 확대 자리, `View.settings.uiScale`)
- 판 코드가 읽는 `get_viewport_rect()`·`get_visible_rect()`·마우스 위치·`unproject_position` 은 전부 UI 좌표 (= 창 픽셀 / 배율) → '작은 창' (`ui_calc.small`) 도 UI 좌표로
- 화면 밖에 그리는 것 (초상·대기실 큰 캐릭터·1인칭 팔·타이틀 거울) 은 UI 좌표 × 배율 = 창 픽셀 크기로 (`UiScale.pixel_size`, `Portrait.render_px`) — 아니면 배율만큼 흐림
- 마우스 시선은 `screen_relative` (창 픽셀) — `relative` 는 배율로 나뉘어 창 크기마다 감도가 바뀜
- 화면 배율 k: 윈도우는 고도 screen_get_scale 이 1 이라 DPI / 96, 웹·macOS 는 screen_get_scale. PC 는 처음 창도 1280×720 × k (화면에 맞춰) 로 키움 (안 그러면 200% 화면에 논리 640×360 창). 웹은 캔버스가 CSS × DPR (allow_hidpi)

## W8 타이틀·메뉴 '맛' (JS 와 나란히, 2026-11-03)

7개 테마 × (JS `?title=` · 고도 전 bb07ed2 · 고도 후) 를 1280×720 에서 찍어 대조 (타이틀 = 로고 완성 + 3.5초, 메뉴 = 메뉴 카메라 + 4초, `--shot-at title|menu --title <테마>`).
고친 것: 메뉴 로고 흐린 빛 (`text_glow.gd`) · 큰 버튼 (`big_btn.gd`: 칸 안 사선·그라데이션·안쪽 빛·빛 세모·반짝임·글자 빛) · 3D 넓은 빛 안개 (`title/haze.gdshader`,
고도 Compatibility 글로는 `glow_levels` 세기를 무시해 JS UnrealBloom 처럼 넓게 못 번짐 — 실측) · 버섯 갓 밑 뚫기 (`title_fx.hemi_open`) · 타이틀 위 겹 (검은 띠·가장자리·Enter 빛).
화면 평균 밝기 (rgb, 위아래 60px 뺌) 전 → 후 / JS: 버섯 타이틀 21,41,38 → 49,84,78 / 59,92,83 · 화산 31,8,2 → 59,16,4 / 58,19,8 · 하늘 성 23,25,40 → 43,48,73 / 44,48,71.

비용 (버섯, 1280×720, xvfb llvmpipe — 시간은 소프트웨어 GPU 라 참고만, 그리기 수가 기준):

| 효과 | 그리기 수 | SubViewport | 전체 화면 패스 | 그래픽 낮춤 |
|---|---|---|---|---|
| 메뉴 전체 (전 → 후) | 53 → 63 | 0 → 0 (굽기 때 한 프레임만 1) | 0 → 1 (안개) | 안개·반짝임 없음, 로고 빛 1장 |
| 로고 흐린 빛 3장 | +3 | 굽기 1번 (글자 크기 바뀔 때만), 바로 버림 | — | 14px 1장 |
| 큰 버튼 6개 꾸밈 | +6 (반짝일 때 +1씩) | — | — | 반짝임 없음 |
| 빛 안개 | +1 + 화면 복사·밉맵 | — | 1 (밉 5 단계 17곳 읽기) | 끔 |
| 타이틀 전체 (전 → 후, 위 겹 포함) | 29 → 42 | 거울 그대로 | 0 → 1 | 끔 |
