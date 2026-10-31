# G4 화면 (godot/PLAN.md 5·7절): 메뉴 · 대기실 · 판 HUD · 결과 · 설정 · 화면 전환

JS `client/main.js`·`client/index.html` 의 화면을 옮김. 계산은 `ui_calc.gd` (JS shared/hud-layout·kills-hud·wipe·char-select·leave 그대로, 정답 테스트 `tests/test_ui.gd`).

| 파일 | 내용 (JS 원본) |
| --- | --- |
| `ui.gd` · `ui.tscn` | 뿌리 CanvasLayer: 화면 고르기 (screenOf)·전환 슬래시·접속 글·핑·Enter 시작 (main.js updateScreen) |
| `ui_style.gd` | '빛 사선' 모양: 빛 판·평행사변형 버튼·주 버튼·글자 빛·글자 칸, 판 중 HUD 밝은 모양 (index.html CSS) |
| `menu.gd` | 메뉴: 빛 로고·이름·큰 버튼 펼침·공개 방 목록·연습 (index.html #rooms, main.js openMenu·renderRoomList) |
| `lobby.gd` | 대기실 판 (오른쪽, lobby_dock): 상태·캐릭터 카드 3×3·랜덤·스킬 카드·이름·색·시작·방 설정·방 코드 (main.js drawHud 대기실 부분) |
| `host_players.gd` | 플레이어 관리 (방장): 팀전·팀 섞기·관전·내보내기 (updateHostPlayers) |
| `wipe.gd` | 전환 슬래시 (playWipe) |
| `portrait.gd` | 초상: G2 몸을 화면 밖 SubViewport 에 한 번 그려 캐시 (아래 판 96·카드 128 온몸·큰 캐릭터 256 온몸·결과 승자 192), 한 프레임에 한 장, 메뉴 PORTRAIT_WARM_MS 뒤 카드 8장 미리 (client/portrait.js) |
| `ui_prefs.gd` | 기억 (tf-name·tf-color·tf-char·tf-tutorial → user://ui.json) |

main.gd 가 `ui/ui.tscn` 을 자동으로 붙임 (2026-10-31 총괄이 고도로 돌려 스크립트 에러 0 확인). 화면 확인: `--auto host --bots 3 --shot <png> --shot-at menu|lobby|game|tab|settings|results` (core/autopilot.gd, tab 은 `--mode kills`).
초상은 portrait.gd (다 그려지기 전·헤드리스면 색 상자). 대기실 큰 캐릭터는 아직 정지 초상 (JS char-stage 의 도는 3D 는 다음). 3D 메뉴·대기실 배경은 범위 밖 — 빛 색은 `View.ui_theme` 가 생기면 그 테마, 없으면 자수정.
