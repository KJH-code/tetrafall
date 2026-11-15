# Tetrafall 고도 클라

고도 4.7.2 GDScript (렌더러 Compatibility — 웹·PC 같은 빌드). 서버는 JS 서버 (`npm start`) 또는 C# 서버 (`godot/server`) — 같은 프로토콜.
지금은 **G0 뼈대**: 접속·재접속(자리 토큰)·핑·스냅샷·보간·입력·키 설정 + 개발용 상자 화면. 묶음 나누기 규칙은 `../PLAN.md` 7절.

## 실행 (레포 뿌리에서, 고도 받기는 `../prototype/README.md`)

```
PORT=3000 npm start                                     # JS 게임 서버 (C# 서버도 됨)
godot --headless --path godot/client --import           # 처음 한 번 (글꼴 등)
godot --path godot/client                               # 창 클라 → ws://127.0.0.1:3000. 방 만들기·봇 추가·시작, 화면 클릭하면 마우스 잡힘 (Esc 풂)
godot --path godot/client -- --server ws://주소:3000 --room ABCD   # 다른 서버·바로 그 방
```

옵션 (`--` 뒤, 웹이면 주소 뒤 `?키=값`): `--server` · `--room` · `--name` · `--profile` (자리 토큰 저장을 나눔 — 같은 PC 에서 사람 둘) ·
자동 확인 `--auto host|guest` `--bots N` `--wait-players N` `--drop-at 초` (연결 끊었다 같은 자리로) `--quit-after-rounds N` `--quit-after 초` `--min-moved 칸` `--shot 파일.png --shot-after 초` `--expect-left` (이유 있는 '방 밖' 을 받아야 성공). 자동 확인 로그엔 접속 상태 글이 바뀔 때마다 `접속: …`, 방 밖으로 나가지면 `방 밖: 이유`

스냅샷 묶음: PC 클라는 주소에 `?pack=gzip` 을 붙여 접속 (`core/net.gd` `packed_url`) → C# 서버가 큰 메시지 (`NET_DEFLATE_MIN_BYTES` 이상, 사실상 스냅샷) 를 gzip 바이너리로 보내고 클라가 풂 (`unpack`). 고도 WebSocketPeer 는 permessage-deflate 를 못 써서 8명 판이 약 418KB/s 로 오던 것 → 약 92KB/s (헤드리스 8명 판 30초 실측). 웹 판은 쿼리 없이 붙어 예전처럼 브라우저 압축 (Text + permessage-deflate), JS 서버는 쿼리를 무시하고 Text 로 보냄 — 글자 패킷은 예전처럼 읽으니 어느 서버든 붙음. `--auto` 로 돌리면 끝날 때 `[net] 받은 N KB/s (스냅샷 n개, gzip 켬|끔)` 한 줄. 푼 크기는 `INBOUND_MAX_BYTES` (4MB, 받는 버퍼와 같은 값) 까지: gzip 꼬리에 적힌 크기가 넘으면 풀지 않고 버리고, 풀 때도 적힌 크기까지만 (작은 패킷 하나가 수백 MB 로 풀리는 것 막기, `tests/test_core.gd` `test_net_unpack_limit`).

서버 침묵 감지·죽은 방 탈출 (2026-11-14): 끊긴 뒤 어떤 경우에도 없어진 방 화면에 갇히지 않게 — 같은 자리로 돌아가거나, 이유를 띄우고 메뉴로.
- 침묵 감지 (`core/net.gd` `silent`·`SILENCE_MS` 6초): 소켓은 열려 있는데 아무것도 안 오면 (서버가 멈춤·길이 죽음 — TCP 는 한참 뒤에야 앎) 그 소켓을 버리고 끊겼을 때와 같은 길로 다시 붙음, 상태 글 '서버 응답 없음 — 다시 연결 중'. 서버는 내 핑마다 (`NET_PING_MS` 1초) pong 을 보내니 6초 침묵은 비정상 — 메뉴·대기실·판 어디서든 이 pong 하나가 받침 (방 목록은 바뀔 때만 와서 근거가 아님. 핑 간격을 늘리거나 핑을 빼면 `SILENCE_MS` 도 같이 볼 것). 붙은 순간부터 셈 (붙었는데 아무 말 없는 서버도 잡음). 쌓인 패킷을 다 읽은 뒤에 보고 프레임이 멈췄던 시간 (`meter.slack`) 은 빼서, 창이 멈췄다 풀린 직후엔 안 끊음. 다시 붙으면 자리 토큰으로 같은 자리
- 붙어 보기 상한 (`core/net.gd` `connect_stuck`·`CONNECT_MS` 6초): 처음 접속이든 다시 붙기든 한 번 붙어 보기가 6초 넘게 CONNECTING 이면 (멈춘 서버 — 커널이 TCP 는 받아 줘도 업그레이드 응답이 안 옴) 그 소켓을 버리고 다음 시도로. 그래서 서버가 멈춘 채 안 돌아와도 방 화면에 끝없이 남지 않음: 시도마다 max(`NET_RECONNECT_MS` 2초, 6초) = 6초라 침묵 6초 + `NET_RECONNECT_TRIES` 30번 × 6초 = 약 3분 뒤 포기 (`gave_up` → 메뉴로). 거절되는 서버 (꺼짐) 는 시도마다 2초라 약 1분. `retry()` 는 `NET_RECONNECT_MS` (2초) 넘게 매달린 소켓만 버리고 처음부터 (`retry_drops`, 프레임이 멈췄던 시간은 뺌) — 그보다 젊은 붙어 보기는 느린 핸드셰이크 (터널 TLS 등) 일 수 있어 그대로 두고 횟수만 되돌림 (버튼을 거듭 눌러도 핸드셰이크가 처음부터 다시 시작되지 않음)
- 죽은 방 탈출 (`core/store.gd` `join_error_action`·`_clear_room`): 다시 붙었는데 그 방이 없으면 (서버가 다시 켜짐 → rejoinError → join → joinError) 방 안에서 받은 joinError 라 방을 비우고 `left_room("방으로 돌아가지 못했습니다 — 서버 이유")` → 메뉴에 그 글 (앞머리는 이유와 상관없는 말 `LEFT_BACK_FAILED` — 자리 유지가 지나 다시 들어가려는데 방이 꽉 찬 것도 같은 길이라, 서버 이유 '그런 방이 없습니다'·'꽉 찼습니다' 가 까닭을 말함). 방 밖 joinError 는 예전처럼 메뉴 글만 (`join_error`)
- 다시 붙기를 `NET_RECONNECT_TRIES` 번 다 쓰면 `Net.gave_up` → 방 안이면 방을 비우고 상태 글을 이유로 메뉴로. 연결 없이 '방 나가기' 를 누르면 서버 답을 기다리지 않고 바로 방 밖
- 서버 끄기 (2026-11-15): 호스트가 C# 서버를 끄면 (SIGTERM·Ctrl+C) 서버가 방 안 사람마다 `left` '서버를 껐습니다 — 호스트가 다시 켜면 새로 들어오세요' 를 보내고 (그대로 메뉴에 그 글) `NET_SHUTDOWN_CLOSE_GAP_MS` (0.5초) 뒤 닫기 코드 1001 로 닫고 약 3초 안에 꺼짐 — 틈이 없으면 고도 WebSocketPeer 가 한 poll 에 left 와 닫기를 같이 받아 바로 닫힌 상태가 되고 left 를 못 읽음 (서버 쪽은 `godot/server/src/Tetrafall.Server/Program.cs` 머리 주석). 클라는 닫기 코드 + 까닭 글로 가름 (`core/net.gd` `is_shutdown`·`lost_reason`: 1001 + "server shutdown" 이면 `LOST_SHUTDOWN` '서버가 꺼짐', 그 밖 (다른 까닭의 1001 — 프록시·터널 포함) 은 '서버 연결 끊김') → 상태 글 '서버가 꺼짐 — 다시 연결 중 (n/N)', 다시 붙기는 그대로 (호스트가 다시 켜면 붙음 — 방은 없어서 새로 들어감). 틈 동안 한 번도 poll 못 해 (창 끌기·로딩·백그라운드 탭) left 를 잃어도 그 닫기 (`Net.server_shutdown`) 로 Store 가 같은 글로 방을 비우고 메뉴로 (`LEFT_SHUTDOWN` = 서버 `Rooms.SHUTDOWN_REASON`). `--online` 이면 터널은 서버가 접속을 다 닫은 뒤 (`ApplicationStopped`) 에 꺼져 터널로 붙은 사람도 같은 left·1001 을 받음 (끄기 시작 때는 터널 지키기에 다시 켜지 않음 표시만 — 그 사이 cloudflared 가 먼저 꺼져도 새로 안 켬, `Tunnel.cs` `NoRestart`·`online-cs.mjs` `noRestart`)
- 끊김 표시: 다시 붙는 중엔 오른쪽 위 핑 자리가 지난 핑 대신 '연결 끊김 · 다시 연결 중 N' (`ping_text`, N = 시도 횟수 — 첫 시도 전엔 숫자 없음), 성능 판 (F3) 핑 자리는 '끊김' (`ping_value`). 왼쪽 위 상태 글은 판 HUD 가 보이면 판 시간·튜토리얼 띠 아래 + 어두운 반투명 받침 (`ui/ui_calc.gd` `status_pos`·`status_box_pos`·`status_back`: 판 중 (16, 108) — 가운데 위 알림 칸 (`hud_extra` top_box, 블록 마스터 두 줄 배너 등)·가운데 '화면을 클릭하면 조작 시작'·연습 방 왼쪽 위 힌트 '연습 창 Tab' 과 연습 창 (`ui/practice.gd` `avoid_rects`, 'status_avoid' 무리 — 연습 화면이 위 층이라 겹치면 상태 글이 가려짐) 과 겹치면 그 아래로 (`ui.gd` `_avoid_rects`), 내려가다 아래 HUD (사람 판·F·R 칸·내 % — `status_room`) 에 닿으면 막은 칸 오른쪽 옆 (960×540 에서 연습 창을 열면 창 옆), 그 밖 (16, 12) 받침 없음) — 판 중 끊김 글이 시간·튜토리얼 띠·블록 마스터 배너·연습 힌트·연습 창과 겹치던 것
- 메뉴 (`ui/menu.gd` `_online_do`): 연결이 없을 때 방 만들기·들어가기·연습·튜토리얼을 누르면 '서버에 연결되지 않았습니다 — 다시 연결 중' 을 띄우고 `Net.retry()` (횟수를 되돌려 처음부터 다시 붙어 봄 — 붙어 보는 중이면 위 붙어 보기 상한 단락대로). 튜토리얼 창의 '시작' (설정 → 튜토리얼 길은 메뉴 문을 안 지남)·끝 화면 '봇 3명과 한 판' 도 같은 글 + `Net.retry()` (`ui/tutorial_ui.gd` `_offline`) — 튜토리얼을 done 으로 남기거나 봇 판 예약 (`quick_pending`) 을 켜지 않음

## 테스트·확인

```
godot --headless --path godot/client -s res://tests/run_tests.gd   # 보간·핑·키 설정이 JS 와 같은 값 (tests/fixtures, JS 에서 뽑음)
node godot/client/tools/fixtures.mjs                              # 정답 자료 다시 뽑기 (client/interp.js·shared/net.js·client/keys.js)
node godot/client/tools/gen-config.mjs                            # shared/config.js → core/config.gd (JS config 를 바꾸면)
bash godot/client/tools/e2e.sh                                    # JS 서버 + 헤드리스 클라 둘: 방 만들기·코드로 들어가기·판·중간에 끊고 같은 자리로
bash godot/client/tools/e2e_net.sh                                # C# 서버 + 헤드리스 클라: A 서버를 죽였다 다시 켬 → '방으로 돌아가지 못했습니다 — …그런 방이 없습니다' 로 방 밖 · B 판 중 서버 12초 멈춤 (kill -STOP) → '서버 응답 없음' 뒤 같은 자리로 · C 판 중 서버 끔 (kill -TERM) → 5초 안에 꺼지고 '방 밖: 서버를 껐습니다'
xvfb-run -a godot --path godot/client --rendering-driver opengl3 -- --auto host --bots 7 --wait-players 8 --shot /tmp/s.png --shot-after 12 --quit-after 13
```

`e2e_net.sh`: 환경 변수 `PORT` (기본 3431) · `LOG` (기본 `/tmp/tf-e2e-net`, 서버·클라 로그) · `SERVER_DLL` (지어 둔 `Tetrafall.Server.dll` — 없으면 `$LOG/bin` 에 Release 로 지음) · `STALL` (B 가 멈추는 초). 약 3분, 마지막 줄 `e2e_net: A 통과 · B 통과 · C 통과` (하나라도 실패면 종료 코드 1). A 는 서버를 KILL 로 죽임 (TERM 이면 서버가 보내는 left '서버를 껐습니다' 가 A 가 기다리는 '그런 방이 없습니다' 보다 먼저 옴), C 는 TERM 을 보내고 꺼질 때까지 잼 (5초 넘으면 실패, 서버 콘솔 '서버 끄는 중:' · 방 로그 마지막 줄 '[서버 종료]' 도 봄). 그 밖에 서버를 내릴 땐 TERM 뒤 5초 안에 안 꺼지면 KILL. 끄는 것은 스크립트가 띄운 프로세스뿐

## 내보내기 (G7)

```
mkdir -p godot/client/build/{web,windows,linux}
godot --headless --path godot/client --export-release Web build/web/index.html
godot --headless --path godot/client --export-release Windows build/windows/tetrafall.exe
godot --headless --path godot/client --export-release Linux build/linux/tetrafall.x86_64
node godot/client/tools/serve_web.mjs 8060      # 브라우저 http://127.0.0.1:8060/?server=ws://127.0.0.1:3000
WEB_PORT=8060 xvfb-run -a node godot/client/tools/web_shot.cjs /tmp "?server=ws://127.0.0.1:3000&auto=host&bots=3&wait-players=4"
```

- 템플릿: `~/.local/share/godot/export_templates/4.7.2.stable/` 에 `web_nothreads_release.zip`·`windows_release_x86_64.exe`·`linux_release.x86_64` (받기는 prototype README)
- 웹 곡 따로 (2026-10-31): 웹 내보내기는 곡 녹음본 15개 (`audio/baked/music.*.ogg`, 3.7MB) 를 pck 에서 빼고 `build/web/music/` 에 복사 (`addons/web_music` 내보내기 플러그인, project.godot 에서 켬). 화면은 방에 들어가면 대기실 곡 → 지금 맵 곡 → 긴장 곡 → 나머지 순으로 받고 (`audio/music_fetch.gd`), 못 받은 곡은 곡 없이. PC 판은 pck 안 그대로. 웹 빌드 폴더를 옮길 땐 `music/` 도 같이
- 크기 (2026-10-31): 웹 wasm 39.5MB (gzip 약 10MB) + pck 0.3MB, 윈도우 exe 110MB, 리눅스 74MB (pck 포함 한 파일). `build/` 는 커밋 안 함
- 웹은 C# 서버가 `/play/` 로 같이 서빙 (같은 호스트라 `?server=` 없이 붙음). 서버·웹·PC 클라 한 zip 은 `node godot/server/tools/package.mjs --godot <고도>` (godot/server/README.md G7, 재혁 PC 순서 docs/godot-play.md)
- 재혁 PC (윈도우): `tetrafall.exe -- --server ws://<서버 IP>:3000` (또는 같은 PC 면 그냥 `tetrafall.exe`)

## 소리 (G5, `audio/`)

JS 화면의 합성 소리·곡을 **크로미움에서 그대로 녹음해 구움** (`tools/bake-audio.cjs` → `audio/baked/*.ogg` 314개 7.5MB + `manifest.json`). 고도는 녹음본만 틀어서 실행 중 합성이 없음 → JS 와 같은 소리, 웹에서도 가벼움.

- 왜 굽나 (2026-10-31): GDScript 로 직접 합성하면 데스크톱에선 목소리 8개 1초에 34ms (실시간의 3%) 로 되지만, WebAudio 와 같은 소리를 내려면 필터·띠 제한 파형·엔벌로프를 다 다시 만들어야 하고 웹(wasm)에선 몇 배 느림. 굽는 쪽이 같은 소리 + 비용 0
- 매번 다른 높낮이: 녹음본 여러 개 (효과음 3개, 타격 2개) + 재생할 때 ±SFX_DETUNE/2
- 다시 굽기 (JS 소리를 바꾸면): `PORT=3399 node server/index.js & node godot/client/tools/bake-audio.cjs 3399` (ffmpeg libvorbis, 약 8분)
- `audio/sound_math.gd` 거리·좌우·타격 세기·곡·앰비언트 테마 계산 (JS 와 같은지 tests/test_audio.gd) · `audio/sfx.gd` 재생기·버스 (SFX·SFXDirect·Music·좌우 버스) · `audio/music.gd` 곡 (맵 테마·긴장, 바뀌면 위치 이어서)·앰비언트 (메뉴·대기실)·위험 액체 지속음 · `audio/audio.gd` 이벤트 → 소리 (main.js 의 sound.play 줄 그대로)
- 화면 쪽 소리 (건축가 폭발·화살 박힘·위험 차오름·KO·슬로모션) 는 그리는 쪽이 `View.sound_cue.emit("blast", {x, y, z, big, wood})` 처럼

## 구조 (G0 = core/)

| 파일 | 내용 (JS 원본) |
| --- | --- |
| `core/net.gd` (자동 로드 `Net`) | 접속·보내기·받기·끊기면 다시 붙기·핑 (main.js connect, net.js) |
| `core/store.gd` (`Store`) | 프로토콜 처리·최신 스냅샷·격자·보간 위치 `view_pos` (main.js onmessage) |
| `core/player_input.gd` (`PlayerInput`) | 키보드·마우스 → input·action (input.js) |
| `core/view.gd` (`View`) | 화면 공용 상태: 시점·관전·설정 |
| `core/keys.gd` · `interp.gd` · `net_meter.gd` · `seat.gd` · `coords.gd` | keys.js · interp.js · shared/net.js · seat.js · 좌표/색 |
| `core/config.gd` | 만든 파일 (shared/config.js) |
| `core/dev_view.gd` · `dev_ui.gd` · `autopilot.gd` | 개발용 상자 화면·버튼·자동 조종 (G1·G4 씬이 생기면 안 쓰임) |
| `assets/fonts/ui_font.tres` | 프로젝트 글꼴: Black Han Sans 한글·라틴 (OFL) + 기호 대체 `dejavu-sans-bold-symbols.woff2` (DejaVu Sans Bold 조각 — · — … ← → ↺ ▸ ° 등, 라이선스 `DejaVu-LICENSE.txt`). 웹엔 시스템 글꼴 대체가 없어 여기 없는 글자는 빈 칸 → `tests/test_core.gd` 가 스크립트 글의 글자를 다 확인. 다시 만들기: `pyftsubset DejaVuSans-Bold.ttf --unicodes="U+0020-007E,U+00A0-00FF,U+2010-2027,U+2030-203A,U+2190-21FF,U+2212,U+2460-2473,U+25A0-25FF,U+2600-2606,U+2713-2717,U+2764" --flavor=woff2 --layout-features= --no-hinting` |

## 화면 계산 (고도 판 전용 — JS 에 없는 것, `ui/ui_calc.gd` 아래쪽·`tests/test_ui.gd`)

- 대기실 판 배치 (`lobby.gd` `_place` → `lobby_place`): 폭은 `lobby_dock`, 오른쪽 끝·위 (`LOBBY_TOP` 84) 에 붙임. 내용이 자리 (위 84 ~ 화면 아래 여백) 보다 크면 판을 통째로 줄임 — 960×540 약 0.67배, 1280×720 약 0.99배, 1920×1080 은 줄임 없음 (세로 가운데로 내려오지 않고 위에 붙음).
- 방 옵션 표시 (`room_opts`): 손님 대기실 줄 (`lobby.gd` map_info, 방장은 체크 상자) 과 공개 방 목록 한 줄 (`menu.gd`) 에 켠 옵션을 ` · 하늘 계단 · 체력전 · 돌발 이벤트` 로 붙임.
- 돌발 이벤트 알림 (`ui/round_event_text.gd`, `tests/test_round_events.gd`): 서버 이벤트 `roundEvent` 가 올 때 한 번 뜨는 알림. 돌풍 화살표는 보는 방향 기준 (`hud_extra.gd` `_view_yaw`: 하늘 시점이면 `cam_rig.sky_yaw`, 아니면 `PlayerInput.yaw`) — 알림이 뜬 뒤에 몸을 돌리면 안 따라옴. 진행 중인 이벤트는 스냅샷 `roundEvent` (남은 시간·방향) 를 `status` 가 한 줄로 만들어 `hud_extra.gd` `refresh` 가 위 가운데 띠 (`event_chip`: '블록 폭우 N초'·'돌풍 → N초') 에 끝날 때까지 띄움 — 화살표는 매 프레임 보는 방향 기준, 보급은 띠 없음. 메뉴로 만든 방은 돌발 이벤트를 켠 채 시작 (`menu.gd` `_create` → `ui_calc.gd` `create_defaults`, 대기실 체크를 끄면 `ui_prefs` `roundEvents` 로 기억해 다음 방도 끔. 자동 조종 `--auto host` 는 예전 그대로 `--events on` 일 때만).
