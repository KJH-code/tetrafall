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
- 끊김 표시 (2026-11-15 병합: 모습은 최신 쪽 접속 칸 `ui.gd` `make_net`·`_net_draw` — JS #netPing·#netWarn): 다시 붙는 중엔 오른쪽 위 핑 칸이 지난 핑 대신 '핑 끊김' (`ping_value`), 그 아래 빨강 알림 칸에 '연결 끊김 · 다시 연결 중 N' (`ping_text`, N = 시도 횟수 — 첫 시도 전엔 숫자 없음). 성능 판 (F3) 핑 자리도 '끊김' (`ping_value`). 왼쪽 위 상태 글은 판 HUD 가 보이면 판 시간·튜토리얼 띠 아래 + 어두운 반투명 받침 (`ui/ui_calc.gd` `status_pos`·`status_box_pos`·`status_back`: 판 중 (16, 108) — 가운데 위 알림 칸 (`hud_extra` top_box, 블록 마스터 두 줄 배너 등)·가운데 '화면을 클릭하면 조작 시작'·연습 방 왼쪽 위 힌트 '연습 창 Tab' 과 연습 창 (`ui/practice.gd` `avoid_rects`, 'status_avoid' 무리 — 연습 화면이 위 층이라 겹치면 상태 글이 가려짐) 과 겹치면 그 아래로 (`ui.gd` `_avoid_rects`), 내려가다 아래 HUD (사람 판·F·R 칸·내 % — `status_room`) 에 닿으면 막은 칸 오른쪽 옆 (960×540 에서 연습 창을 열면 창 옆), 그 밖 (16, 12) 받침 없음) — 판 중 끊김 글이 시간·튜토리얼 띠·블록 마스터 배너·연습 힌트·연습 창과 겹치던 것
- 메뉴 (`ui/menu.gd` `_online_do`): 연결이 없을 때 방 만들기·들어가기·연습·튜토리얼을 누르면 '서버에 연결되지 않았습니다 — 다시 연결 중' 을 띄우고 `Net.retry()` (횟수를 되돌려 처음부터 다시 붙어 봄 — 붙어 보는 중이면 위 붙어 보기 상한 단락대로). 튜토리얼 창의 '시작' (설정 → 튜토리얼 길은 메뉴 문을 안 지남)·끝 화면 '봇 3명과 한 판' 도 같은 글 + `Net.retry()` (`ui/tutorial_ui.gd` `_offline`) — 튜토리얼을 done 으로 남기거나 봇 판 예약 (`quick_pending`) 을 켜지 않음

## 테스트·확인

```
godot --headless --path godot/client -s res://tests/run_tests.gd   # 보간·핑·키 설정이 JS 와 같은 값 (tests/fixtures, JS 에서 뽑음)
node godot/client/tools/fixtures.mjs                              # 정답 자료 다시 뽑기 (client/interp.js·shared/net.js·client/keys.js)
node godot/client/tools/gen-config.mjs                            # shared/config.js → core/config.gd (JS config 를 바꾸면)
bash godot/client/tools/e2e.sh                                    # JS 서버 + 헤드리스 클라 둘: 방 만들기·코드로 들어가기·판·중간에 끊고 같은 자리로
bash godot/client/tools/e2e_net.sh                                # C# 서버 + 헤드리스 클라: A 서버를 죽였다 다시 켬 → '방으로 돌아가지 못했습니다 — …그런 방이 없습니다' 로 방 밖 · B 판 중 서버 12초 멈춤 (kill -STOP) → '서버 응답 없음' 뒤 같은 자리로 · C 판 중 서버 끔 (kill -TERM) → 5초 안에 꺼지고 '방 밖: 서버를 껐습니다'
xvfb-run -a godot --path godot/client --rendering-driver opengl3 -- --auto host --bots 7 --wait-players 8 --shot /tmp/s.png --shot-after 12 --quit-after 13
# W44 모션 QA (튐·떨림·발 미끄러짐·뚫림 자동 검출, docs/w44/README.md): 재연 + 표 합치기. 판 중 가벼운 모드는 클라에 --motion-qa (한 판 끝에 user://motion_qa.txt)
xvfb-run -a godot --path godot/client --rendering-driver opengl3 --fixed-fps 120 -- --replay <녹화.rec> --replay-fps 120 --replay-secs 44 --replay-warm 0 --no-pose-lod --set third=true --motion-qa /tmp/qa/<이름>
node godot/client/tools/motion_qa.mjs /tmp/qa [<후 폴더>]
```

`e2e.sh` 는 C# 서버로도: `TF_LOG_DIR=<로그 폴더> SERVER_CMD="dotnet godot/server/src/Tetrafall.Server/bin/Debug/net10.0/Tetrafall.Server.dll" bash godot/client/tools/e2e.sh` (환경 변수 `PORT` 기본 3302 · `LOG`). JS 서버로 돌리면 레포 `logs/` (git 무시) 에 방 로그가 생김.

`e2e_net.sh`: 환경 변수 `PORT` (기본 3431) · `LOG` (기본 `/tmp/tf-e2e-net`, 서버·클라 로그) · `SERVER_DLL` (지어 둔 `Tetrafall.Server.dll` — 없으면 `$LOG/bin` 에 Release 로 지음) · `STALL` (B 가 멈추는 초). 약 3분, 마지막 줄 `e2e_net: A 통과 · B 통과 · C 통과` (하나라도 실패면 종료 코드 1). A 는 서버를 KILL 로 죽임 (TERM 이면 서버가 보내는 left '서버를 껐습니다' 가 A 가 기다리는 '그런 방이 없습니다' 보다 먼저 옴), C 는 TERM 을 보내고 꺼질 때까지 잼 (5초 넘으면 실패, 서버 콘솔 '서버 끄는 중:' · 방 로그 마지막 줄 '[서버 종료]' 도 봄). 그 밖에 서버를 내릴 땐 TERM 뒤 5초 안에 안 꺼지면 KILL. 끄는 것은 스크립트가 띄운 프로세스뿐

### 겉모습 갤러리 (`tools/gallery.gd`)

서버·봇 없이 캐릭터·맵·블록을 정해진 시점으로 찍음. **겉모습을 바꾸기 전·뒤에 같은 명령으로 찍어 비교한다** (찍을 때마다 같은 사진 — 봇 판 사진은 장면이 매번 다름).

```
xvfb-run -a godot --path godot/client --resolution 1280x720 --rendering-driver opengl3 -s res://tools/gallery.gd -- --out <폴더> [--only chars,maps,pieces] [--low]
```

나오는 파일 (30장, 약 30초):
- `char-<캐릭터 id>.png` ×8 — 한 캐릭터를 앞·비스듬히 앞·옆·뒤로 나란히 (팔레트 첫 색, 초원 낮 빛, 가만히 선 자세) · `chars-lineup.png` — 8명 정면 한 줄 (팔레트 순서 색)
- `map-<맵 id>-over.png` ×7 — 8명 판 크기 시작 지형을 비스듬히 위에서 (필드 전체 + 하늘·먼 배경) · `map-<맵 id>-eye.png` ×7 — 필드 가장자리에 선 사람 눈높이에서 가운데를 봄
- `pieces-<테마 id>.png` ×7 — 그 테마 바닥·지형 단 위에 쌓인 테트리미노 7종 (뒷줄 I·O·T·L, 앞줄 S·Z·J) + 떨어지는 블록 하나와 그림자 칸

`--low` = 설정 '그래픽 낮춤' 으로 (파일 이름 같음 → 다른 `--out` 폴더에). 끝에 저장한 파일 목록, 종료 코드 0 (못 만든 사진·도는 동안 난 엔진/스크립트 오류가 있으면 1, `--headless` 처럼 그릴 수 없으면 안내 한 줄과 2).
판 그리기 (`world/world.tscn`) 를 그대로 띄우고 스냅샷 자리 (`Store.state`·`Store.grid`) 에 가짜 판 상태를 넣어 찍으므로 재질·빛·판 빛은 판 중과 같음. 같은 사진이 나오게 엔진 시간 배율을 0 으로 두고 (구름·먼 섬·셰이더 물결이 멈춤) 몸 동작 시계 (`chars/ext_motion.gd` `clock` — 외부 모델의 천·클립·가산 층) 에 가상 시계를 꽂음 (자세 한 걸음·그린 한 프레임마다 16ms, `gallery_config.gd` `clock_s` — 60Hz 로 가만히 선 몸의 천 모양. 예전엔 벽시계라 목도리·망토 자리가 찍을 때마다 달랐음) — 실제 시계로 움직이는 떠다니는 빛 알갱이 (수정·화산·하늘 성·버섯 테마) 만 조금 달라짐 (두 번 찍어 정규화 RMSE 0.03 아래, 나머지는 0). 캐릭터 사진은 래그돌을 끄고 떠 있는 섬·먼 배경을 숨김. 카메라·배치 수치는 `tools/gallery_config.gd`.
설정은 도구가 첫 프레임에 (자동 로드 View 가 `user://settings.json` 을 읽은 뒤) 고정 — 그림자·외곽선 켬 + 화질 높음 (`--low` 면 낮음), 파일에는 안 씀 → 저장된 설정이 무엇이든 같은 사진 (예전엔 `_initialize` 에서 넣어 파일 값에 덮였고, 확인용 `--low` 실행이 파일에 낮음 화질을 남겨 갤러리가 통째로 낮음으로 찍혔음 — c6 리뷰 M1. `world/gfx.gd` 도 이제 계산된 `lowGfx` 를 파일에 안 씀).
캐릭터 사진은 마지막 자리에 세운 뒤 가상 시계로 `CHAR_SETTLE_STEPS` 걸음 (4.8초) 더 돌려 외부 모델 천을 가라앉힘 (c6 리뷰 F7: 자세 돌리기 직후 사냥꾼 망토가 옆으로 뻗은 순간이 찍히던 것).
비교: `compare -metric RMSE 앞/char-tank.png 뒤/char-tank.png diff.png` (ImageMagick).

### 병합 뒤 기준선 (2026-11-15: 이 브랜치 `88d9b1d` + 최신 고도 작업 `6ba2e4d` v0.1.21-godot-preview)

표의 통과 수·cs 해시는 그 뒤 사이클을 따라 고쳐 적음 — 지금 값은 2026-11-17 c10 리뷰 지적 고치기 뒤 (34판 해시·JS 테스트 수는 병합 때 그대로).

| 명령 (레포 뿌리) | 결과 |
| --- | --- |
| `cd godot/server && dotnet test` | 363개 통과 (병합 때 330 = 최신 쪽 229 + 이 브랜치 쪽 101, c9 (돌발 이벤트 '번개') 뒤 344, c9 리뷰 지적 고치기 +7 `EventBoltTests`: 처마 밑 예고 높이 3·공중 예고·봇 높이·탱크 아머 로그 2 = 351, c10 (방 옵션 '필드 아이템') 뒤 361, c10 리뷰 지적 고치기 +2 `FieldItemTests`: 반격 아이템이 필드 아이템 자리를 안 차지함·판 시작 로그 줄) |
| `godot --headless --path godot/client --import` 뒤 `godot --headless --path godot/client -s res://tests/run_tests.gd` | `640 통과, 0 실패` (병합 때 524 = 최신 쪽 467 + 이 브랜치 쪽 57, 겉모습 사이클 1 (c6) +23 = 547, c6 리뷰 지적 고치기 +4 = 551: 화질 적용이 설정 파일을 안 씀·1인칭 팔 화풍·하늘 성 띠 대비·갤러리 천 가라앉히기, 겉모습 사이클 2·3 (c7·c8) 뒤 598, c9 (번개·대포수 모델·이벤트 세계 연출) 뒤 615, c9 리뷰 지적 고치기 +3: 번개 '내 고리' 판정·화면 신호 계산·화면 신호 노드 = 618, c10 (필드 아이템·아이템 모델·관전 카메라) 뒤 633, c10 리뷰 지적 고치기 +7: 관전 대상을 가리는 몸 옅게 (시선 계산·옅어지는 걸음·카메라·몸 재질) 4·옅은 칸 재질 사본·아이템 나옴/사라짐 신호 (계산·노드) 2) |
| `npm test` | 580개 통과 (최신 쪽 그대로 — JS 판은 `6ba2e4d` 와 글자까지 같음) |
| `cd godot/server && dotnet run --project src/Tetrafall.Trace -- hash` | `판 34개 해시 bf2e295158bcb4165fd79b097a1784c61b33716de4e28fa3023b46284dc4cc34` (최신 쪽 값) |
| `… -- cshash` | `cs 판 14개 해시 817aede5808ae28ab10fb395097b86c1dbee90de60cbb8f2fc8e0ae17e3da61c` (틱 합 31332. c10 리뷰 지적 고치기 — 필드 아이템 판 시작 로그 줄 — 때 다시 고정: 필드 아이템을 켠 끝 두 판만 바뀜. 내력: 병합 때 `cdc36128…` → c9 번개 `631bfa4c…` (12판, 틱 합 25438) → c9 리뷰 지적 고치기 `b84180ee…` (틱 합 25413) → c10 필드 아이템 판 2개 추가 `ed260619…` (14판, 틱 합 31332) → 지금 값 — `godot/server/README.md`) |
| `godot --headless --path godot/client -s res://tools/bench_bodies.gd` | `몸 묶음 뼈`·`외부 몸 sync`·`pose 합` ms (8명, `uptime` load 와 같이 볼 것). 외부 모델 캐릭터 (탱크·닌자·사냥꾼·갈고리) 는 코드 묶음 뼈 0 — 비용은 `외부 몸 sync` 쪽 |

- 몸 (`chars/body.gd`): 매 프레임 맞추는 묶음 뼈는 이 브랜치 쪽 `bone_groups` (부모 사슬이 같은 뼈끼리 묶음) 하나 — 최신 쪽 이름 `bone_dyn`·`bone_chain` 은 없음 (`tests/test_baked.gd` 는 묶음 안 뼈 수를 셈). 구운 몸 (.glb, 8명 모두) 은 사슬에 움직이는 노드가 없는 뼈가 묶음에 안 듦 (자세가 늘 같음)
- `core/config.gd` 는 `6ba2e4d` 것 그대로. `node godot/client/tools/gen-config.mjs` 로 다시 만들면 `VM_ACT_SWING`·`VM_ACT_STYLE` 묶음 (8줄, 최신 쪽이 손으로 넣은 1인칭 휘두름 표) 이 빠짐 — 최신 쪽 나무에서도 같음. 다시 만들 일이 있으면 그 묶음을 되살릴 것. 서버 `Config.g.cs`·`Maps.g.cs` 는 다시 만들어도 같음
- 본문 글꼴 `assets/fonts/noto-sans-kr-body.woff2` 는 병합 때 다시 만듦 (이 브랜치 쪽 문구 — 칭호·돌발 이벤트·연결 없음 글 — 의 글자가 빠져 있었음, `node tools/subset-body-font.mjs`, 글자 653개)

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

## 성능 재기 (웹·JS 같은 기계, W5 2026-11-02)

```
GAME_PORT=3000 WEB_PORT=8060 xvfb-run -a node godot/client/tools/perf_cmp.cjs js|web third pyramid 12 35   # 평균 프레임·1% low·그리기·CPU ms/프레임 (GPU·렌더러 프로세스)
GAME_PORT=3000 WEB_PORT=8060 xvfb-run -a node godot/client/tools/perf_ab.cjs msaa0                          # 한 판 안에서 설정 A/B 번갈아 → 'AB msaa0: A …ms · B …ms · B/A …'
xvfb-run -a godot --path godot/client --rendering-driver opengl3 --resolution 1280x720 -- --auto host --bots 7 --wait-players 8 --abshot msaa0 --abshot-dir /tmp --abshot-quit   # 같은 프레임 A/B 스샷·화소 차
```

- 기계를 나눠 쓰면 벽시계 프레임이 ±15% 흔들림 → 비용 차이는 `perf_ab` (같은 판 안 비율) 로, 큰 표는 `perf_cmp` 를 번갈아 여러 번. 종류 목록은 `world/perf_ab.gd` 머리
- 웹은 다중 샘플 끔 (`world_config.gd` MSAA_3D_WEB): llvmpipe 에서 4× 가 프레임 약 2배, 2× 도 4× 와 같은 비용. PC 는 4×

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
| `assets/fonts/body_font.tres` | 본문 글꼴 (JS 에서 system-ui 인 자리 — 설명·표 숫자·안내·체크 글·이름표, `ui_style.BODY`·`body()`·`body_label()`): Noto Sans KR Regular 부분 집합 `noto-sans-kr-body.woff2` (OFL, 약 40KB, 스크립트 글의 글자 + 영문·숫자·기호) + 대체 Black Han Sans·DejaVu 기호. 게임 문구를 바꾸면 `node tools/subset-body-font.mjs <NotoSansKR-Regular.ttf>` (받기·사용법은 파일 머리), 빠진 글자는 `tests/test_ui_nodes.gd` 가 잡음 |

## 화면 계산 (고도 판 전용 — JS 에 없는 것, `ui/ui_calc.gd` 아래쪽·`tests/test_ui.gd`)

- 대기실 판 배치 (2026-11-15 병합 뒤): `lobby.gd` `_place` 는 최신 쪽 방식 — 폭 `lobby_dock`, 세로 가운데 + 28px, 최대 높이 화면 − 92px 를 넘으면 판 안에서 스크롤 (`scroll`), 작은 창이면 `_small_sizes` (JS @media). 그 계산은 `ui_calc.gd` `lobby_scroll_h`·`lobby_y` (`tests/test_ui.gd` `test_lobby_panel_fits` 가 960×540·1280×720 에서 판이 화면 안·핑 칸 아래임을 고정). 이 브랜치 쪽 '통째로 줄이기' 계산은 `lobby.gd` 가 안 불러 지움 (같은 문제 — 작은 창에서 판이 넘침 — 를 최신 쪽이 스크롤로 풂). 결과 판은 그대로 `results_place` 를 씀 (칭호 줄이 붙어도 화면 안, 위 끝 `RESULTS_TOP` 74 = 오른쪽 위 핑 칸 아래 — 대기실 판의 가장 높은 위 끝과 같음).
- 방 옵션 표시 (`room_opts`): 손님 대기실 줄 (`lobby.gd` map_info, 방장은 체크 상자) 과 공개 방 목록 한 줄 (`menu.gd`) 에 켠 옵션을 ` · 하늘 계단 · 체력전 · 돌발 이벤트` 로 붙임.
- 돌발 이벤트 알림 (`ui/round_event_text.gd`, `tests/test_round_events.gd`): 서버 이벤트 `roundEvent` 가 올 때 한 번 뜨는 알림. 돌풍 화살표는 보는 방향 기준 (`hud_extra.gd` `_view_yaw`: 하늘 시점이면 `cam_rig.sky_yaw`, 아니면 `PlayerInput.yaw`) — 알림이 뜬 뒤에 몸을 돌리면 안 따라옴. 진행 중인 이벤트는 스냅샷 `roundEvent` (남은 시간·방향) 를 `status` 가 한 줄로 만들어 `hud_extra.gd` `refresh` 가 위 가운데 띠 (`event_chip`: '블록 폭우 N초'·'돌풍 → N초') 에 끝날 때까지 띄움 — 화살표는 매 프레임 보는 방향 기준, 보급은 띠 없음. 메뉴로 만든 방은 돌발 이벤트를 켠 채 시작 (`menu.gd` `_create` → `ui_calc.gd` `create_defaults`, 대기실 체크를 끄면 `ui_prefs` `roundEvents` 로 기억해 다음 방도 끔. 자동 조종 `--auto host` 는 예전 그대로 `--events on` 일 때만).

## 몸 굽기 (W7, 2026-11-02 시제품)

JS 몸을 .glb 로 구워 파일로 불러옴 (지금 탱크만, 나머지는 예전 조립 `chars/data/bodies.bin`): `node tools/bake-bodies.mjs tank` (레포 뿌리) → `assets/models/tank.glb` + `tank.json` → `--import`. 구조·숫자·남은 일은 [`chars/BAKE.md`](chars/BAKE.md). 비교 실행 인자 `--no-glb` (예전 조립)

## 성능 재기 (W6·W12)

GPU 가 없는 클라우드 컨테이너에선 렌더 ms·FPS 는 소프트웨어 (llvmpipe) 라 근거가 못 됨 → **스크립트 ms·그리기·물체·삼각형·SubViewport** 를 같은 판으로 A/B. 재혁 PC 는 F3 → Ctrl+C 한 줄.

```
# 판 기록 (자동 조종 8명 판, 받은 글자를 '시각\t글자' 줄로) — 한 번
xvfb-run -a godot --path godot/client --rendering-driver opengl3 -- --auto host --bots 7 --wait-players 8 --server ws://127.0.0.1:3000 --rec /tmp/game8.rec --quit-after 20
# 재연 (서버 없이 같은 판, 가상 시계 1/120초씩): 처음 playing + 3초부터 10초 동안 스크립트·물리 ms/프레임
xvfb-run -a godot --path godot/client --rendering-driver opengl3 -- --replay /tmp/game8.rec --profile replay [--prof] [--replay-render] [--set gfx=medium,third=true] [--shot a.png]
```

- `--no-shadow-opt` (W32): 해 그림자 줄이기 전부 끔 (몸 그림자 전용 저폴리·먼 몸/시야 밖 몸 그림자 끄기·블록 칸 그림자 상자·그림자 거리 카메라 맞춤) — 전후 비교. `--no-shadow-far` = 먼 몸 끄기만. `--census` 에 '그림자 던지는 삼각형' 열·해 그림자 거리. 장면 측정: `xvfb-run -a godot --path godot/client --rendering-driver opengl3 --resolution 1280x720 -s res://tools/shadow_meas.gd -- [--chars …] [--level high|medium|low] [--cells N --falling N] [--far m] [--close|--zoom] [--no-shadow-opt] [--shot a.png]` (8명 + 칸을 해 그림자 켠 장면에 놓고 그림자 패스 삼각형·그리기·프레임 ms). 자세한 내용 `chars/EXTERNAL.md` 13절
- `--frame-log <tsv>` (W17): 재는 동안 프레임마다 벽시계 ms·스크립트 ms·위험 켬·그리기·물체 한 줄 — 한 프레임만 튀는지 (셰이더 첫 컴파일) 보기
- `--census` (W15): 끝에 무리별 3D 물체·외곽선·삼각형, 보이는 2D 노드, viewport 마다 3D·그림자·2D 그리기
- `--prof`: 구간별 ms/프레임 (`core/prof.gd` — world·몸·HUD·net 구간, 느린 프레임 6개). 꺼져 있으면 비용 거의 0 (테스트 `test_prof_off_is_free`)
- `--replay-render`: 그리기 끔 대신 실제로 그리고 마지막에 그리기·물체·삼각형·영상 메모리 · `--set 키=값` 설정을 바꿔 알림만 (파일엔 안 남음 — 외곽선·그림자·화질 A/B)
- `--replay-warm -4 --replay-secs 0.5` 처럼 음수면 판 시작 전 (대기실) 을 잼·찍음
- 같은 판·같은 가상 시각이라 전/후 스크린샷을 화소로 비교할 수 있음 (래그돌 물리만 실제 시간 — 흔들림 바닥은 같은 빌드 두 번)
- 부하 평균이 높은 컨테이너 (다른 일 동시) 에선 한 번 숫자가 ±20% 흔들림 → 전/후를 번갈아 여러 번

### 규칙 (테스트로 고정, `tests/test_perf.gd`)

- **몸 자세 LOD** (`world/pose_lod.gd`, 수치 `world_config.gd POSE_LOD`): 자세 (figureAnim·래그돌 잡기·묶음 뼈) 만 덜 자주. 자리·방향·이름표는 매 프레임. 카메라 3m 안 = 매 프레임, 그보다 멀면 60Hz (120fps 면 한 프레임 걸러), 화면 밖 20Hz, 내 몸 (1인칭 팔이 관절을 베낌) 은 늘 매 프레임. 끄기 `--no-pose-lod`, 근거리 바꾸기 `--pose-lod-near <m>`
- **(W15) 둘째 LOD 단·SubViewport 상한·같은 스냅샷 건너뜀·투명 판 숨김·외곽선 그림자 빼기**: `test_pose_lod_far2`·`test_subview_rate`·`test_same_snapshot_skips`·`test_clear_overlays_hidden`·`test_outline_not_in_shadow_map`, 쉬는 래그돌은 `test_chars` 래그돌, 자동 화질 RTX 는 `test_gfx`
- **HUD 글자 색·크기는 바뀔 때만** (`ui_style.gd ov_color·ov_font_size`): `add_theme_*_override` 는 같은 값이어도 '테마 바뀜' 알림 → 글자 모양 다시 잡기·다시 배치. 판 중 매 프레임 ~45번 (아래 판 8명 × 5 + 큰 글자·내 %·아이템 시간·R 칸) 이 값이 바뀔 때만으로. 한 번 11µs → 0.6µs
- **설정 '외곽선'·'그림자'** 가 실제로 바뀜 (W12 전엔 듣는 쪽이 없었음): `G3.set_outline_on` (만든 재질 전부 next_pass 를 빼고 끼움, 외곽선 재질 하나를 나눠 씀), `world.shadows_wanted`

### 전/후 (W12, 2026-11-03 — 기준 `bb07ed2` + 재연 도구, 같은 판 `game8.rec` 8명·버섯 맵, 1280×720)

스크립트 ms/프레임 (재연 120fps, 그리기 끔, `--prof`, 기준/지금 번갈아 3번씩 평균 — 컨테이너 부하 평균 22~26, 다른 작업과 같이 돎):

| 항목 | 기준 | 지금 |
| --- | --- | --- |
| **스크립트 합** (평균 · 중앙 프레임) | **6.30 · 4.88** | **4.80 · 4.19** |
| world bodies.update (몸 자세 전체) | 3.93 | 2.73 |
| ·몸 묶음 뼈 | 1.10 | 0.73 |
| ·몸 figureAnim | 1.07 | 0.67 |
| ·몸 래그돌 잡기·넣기 | 0.83 | 0.53 |
| ·몸 움직임 상태 · 재질 | 0.30 · 0.20 | 0.20 · 0.10 |
| ui (HUD) · 그중 아래 판 | 0.47 · (구간 없음) | 0.30 · 0.10 |
| net (받기·JSON·state 신호) | 0.27 | 0.23 |
| world 판 빛 · 격자·건축 블록 | 0.23 · 0.30 | 0.27 · 0.20 |
| 래그돌 물리 (_physics) | 0.20 | 0.13 |
| 몸 자세를 센 몸 (번/프레임, 8명) | 8 | 5.4 (안 셈 2.6) |

(W6 의 '23.2ms' 는 실제 서버·자동 조종을 같이 돌린 판의 프레임 시간 안 스크립트라 재연과 조건이 다름 — 재연은 클라 스크립트만 같은 판으로.)

그리기 (재연 `--replay-render`, 보통 화질, 같은 가상 시각에 잼):

| 장면 | 기준 그리기 · 물체 · 삼각형 · 영상 메모리 | 지금 |
| --- | --- | --- |
| 판 1인칭 | 180 · 303 · 126k · 120.3MB | 179 · 302 · 126k · 120.3MB |
| 판 3인칭 | 212 · 335 · 171k · 101.3MB | 212 · 335 · 171k · 101.2MB |
| 대기실 (수정 테마) | 388 · 879 · 207k · 113.4MB | 387 · 878 · 207k · 113.4MB |

SubViewport 는 그대로: 판 1인칭 1 (팔, 3인칭이면 꺼짐) · 대기실 3 (팔·거울 호수·큰 캐릭터) · 타이틀 1 (거울, 창의 반).

모습 (같은 가상 시각 화소 차, 차 > 8/255 인 화소 비율 — 래그돌 물리·트윈은 실제 시간이라 같은 빌드끼리도 다름):
판 3인칭 기준↔기준 2.7% · 기준↔지금 4.1% (먼 몸 팔다리 자세 60Hz) · 대기실 기준↔기준 0.9% · 기준↔지금 0.7% · 타이틀 (`tools/title_shot.gd` 6초) 0.4%

설정으로 끌 수 있는 패스 (판 3인칭 보통, 지금): 외곽선 끔 → 그리기 212→191 · 삼각형 171k→122k (몸·칸마다 뒤집은 껍질 한 번 더 = next_pass) · 그림자 끔 → 188 · 108k (해 그림자 지도 1024, 직교 한 장).

### W15 (2026-11-03) — 기준 `fb61ae8` (v0.1.2) ↔ 지금, 같은 재연·번갈아 3번 평균

재연 기록 `game8.rec` (8명·버섯 맵 pillars, 자동 조종 판, 1280×720). 이 컨테이너는 부하가 낮아 (load ~1) W12 표보다 숫자가 다 작음 — 비율로 볼 것 (W12 의 4.80ms = 여기 기준 3.3ms 자리).
재기 도구: `--census` (재연 끝에 무리별 3D 물체·외곽선 패스·삼각형, 보이는 2D 노드, viewport 마다 3D·그림자·2D 그리기 — `core/replay.gd census`).

스크립트 ms/프레임 (120fps 재연, 그리기 끔, `--prof`):

| 항목 | 기준 1인칭 | 지금 1인칭 | 기준 3인칭 | 지금 3인칭 |
| --- | --- | --- | --- | --- |
| **스크립트 합 · 중앙 프레임** | **3.38 · 3.28** | **2.64 · 2.25** (−22%) | **3.21 · 3.47** | **2.47 · 1.90** (−23%) |
| world bodies.update (몸 자세) | 1.73 | 1.28 | 1.61 | 1.14 |
| ·figureAnim · 래그돌 잡기 · 움직임 상태 · 재질 · 묶음 뼈 | 0.58 · 0.43 · 0.17 · 0.11 · 0.10 | 0.47 · 0.17 · 0.14 · 0.09 · 0.09 | | |
| 몸 자세를 센 몸 (번/프레임) | 5.35 | 4.89 | 4.54 | 3.83 |
| ui (HUD) · 판 빛 · 떨어지는 칸 | 0.27 · 0.21 · 0.11 | 0.17 · 0.09 · 0.04 | | |
| 대기실 (재연 −5초부터 3초) | 3.42 | 2.96 | | |

한 일 (모습 그대로, 렌더러와 무관):
- 래그돌 잡기: 관절 전역 자리를 GDScript 부모 사슬 곱 (조각마다 두 번) 대신 엔진 `global_transform` 한 번 · 쉬는 몸 (모터 다 셈, 대부분) 은 골반 목표만 셈 — 깨는 프레임만 팔다리 목표 속도 0 · 쉬는 몸은 `restore` 안 함 (`_apply` 가 어차피 덮음)
- figureAnim: 관절 스프링·휘청 스프링을 배열 없이 (칸마다 `[x, v]` 를 만들던 것), 걸음걸이 표·자동 로드 노드는 한 번만 찾음, 발밑 모서리 상수
- 같은 값 다시 쓰기 제거: 몸 재질 발광·피부 색 (`set_shader_parameter` — 값·재질이 같으면 건너뜀), 이름표 글자·색·크기 (예전엔 update 가 a = 1, thin_labels 가 다시 흐리게 → 이름표마다 매 프레임 두 번 다시 만듦), 핑 칸 (글자 색 덮어쓰기·바탕색·reset_size 가 HUD 비용의 절반), 판 빛 Environment 색 보정 5값 (켬·프리셋이 바뀔 때만), 빛 무리 목록·인스턴스·떨어지는 칸 (스냅샷이 바뀔 때만 — 120fps 면 같은 목록을 4번씩 쓰던 것, 하늘 블록은 반짝임 색만 매 프레임)
- 몸 자세 LOD 둘째 단 `POSE_LOD.far2` 10m 밖 30Hz (3m 안 매 프레임 · 10m 까지 60Hz · 화면 밖 20Hz 그대로)
- 거울 반사·대기실 큰 캐릭터 SubViewport 다시 그리기 60Hz 상한 (`WC.SUBVIEW_HZ`, `pose_lod.frame_due` — 60fps 이하 화면은 그대로, 120fps 면 한 프레임 걸러). 큰 캐릭터는 자세도 같이
- 투명한 화면 전체 판 안 그림: 타이틀 하얀 막 (메뉴·대기실·판 내내 a = 0 으로 그리던 것), 대기실 맵 번쩍, 판 번쩍 (`hud_extra.flash`) — 색 a = 0 은 modulate a = 0 과 달리 그리기를 안 건너뜀 (실측)
- 외곽선 껍질 (next_pass) 은 해 그림자 지도 (직교 투영) 에 안 그림 — 고도가 next_pass 도 그림자 패스에 넣어 그림자가 껍질만큼 커지고 그림자 지도 삼각형이 한 벌 더 들던 것. JS OutlineEffect 처럼. 그리기 수 세기엔 안 보임 (셰이더가 클립 밖으로 납작하게 → 래스터만 빠짐)
- 자동 화질: 고성능 외장 (`gfx_calc.FAST_RE` NVIDIA RTX·Radeon RX 네 자리) 이면 `GFX_BIG_PX_FAST` 3200×2000 까지 높음 (재혁 노트북 2880×1800 RTX 5070 = 높음, 4K = 보통, GTX·옛 RX·Quadro 는 예전 2560×1440)

그리기 (보통 화질, `--replay-render --census`, 3D + 그림자 + 2D):

| 장면 | 기준 그리기 · 물체 · 삼각형 | 지금 | 창 viewport 3D · 2D 그리기 (지금) |
| --- | --- | --- | --- |
| 판 1인칭 | 185 · 308 · 153k | 183 · 306 · 153k | 77 · 82 (+ 1인칭 팔 SubViewport 24) |
| 판 3인칭 | 188 · 311 · 172k | 187 · 310 · 172k | 106 · 81 |
| 대기실 (버섯) | 320 · 810 · 261k | 318 · 808 · 261k | 70 · **210** (2D 물체 **692**) + 거울 10 + 팔 24 + 큰 캐릭터 4 |

- **대기실이 판보다 무거운 건 3D 가 아니라 2D 화면 판**: 3D 그리기는 판과 비슷 (대기실 108 = 창 70 + 거울 10 + 팔 24 + 큰 캐릭터 4, 판 1인칭 101). 2D 는 대기실 판 131 그리기 (캐릭터 카드 9 × 4·버튼마다 바탕·외곽선 글자·글자, 글꼴 대체 (· 기호 DejaVu) 마다 묶음이 끊김 — 상태 글 한 줄이 12), 플레이어 관리 58, 위 점수 띠 16. 화면 모습을 안 바꾸고 줄일 길이 없어 (UI 모습 범위 밖) 그대로 — 목표 387 → 250 은 2D 를 굽거나 (SubViewport 에 한 번 그려 바뀔 때만) 화면 판을 다시 짜야 함
- 거울·큰 캐릭터 60Hz 상한·투명 판은 재연 (소프트웨어 GL, 4fps) 에선 매 프레임 그리는 셈이라 위 숫자에 안 보임 — 120fps 화면에서 거울 (창의 0.35×3D 배율, 그림자 지도까지 다시) 이 반으로
- 외곽선 끔 (설정) 이면 3인칭 그리기 187 → 169 · 삼각형 172k → 123k (그중 그림자 지도 63k → 38k — 이번에 껍질을 그림자에서 뺀 몫이 이만큼, 셈에는 남음), 대기실 318 → 296. 먼 몸 외곽선 생략은 외곽선 굵기가 화면 비율 고정 (720p 2.3px · 1800p 5.9px) 이라 작은 먼 몸일수록 테두리가 크게 보여 빼면 눈에 띔 → 안 함. 화면 공간 가장자리 한 패스는 지형 칸 가장자리·겹친 팔 안쪽까지 선이 생겨 모습이 바뀜 → 안 함

모습 (같은 가상 시각, 보통 화질, 차 > 8/255 인 화소 비율, 두 번씩):

| 장면 | 기준↔기준 | 지금↔지금 | 기준↔지금 |
| --- | --- | --- | --- |
| 판 3인칭 | 1.4% | 0.8~1.8% | 2.4~3.0% (먼 몸 30Hz·래그돌·빛 가루 — W12 기준 흔들림 2.7%) |
| 대기실 | 1.4% | 2.8% | 1.6~3.0% |
| 타이틀 (버섯 6초) | 0.15% | 0.24% | 0.14~0.28% |
| 메뉴 (수정, 메뉴 카메라 6초) | 0% | 0% | 0% |

자동 화질 비용 (2880×1800 = 5.18M 화소, 화소 일 = 3D 화소 × MSAA, 거울 화소):

| 화질 | 3D 배율 | 3D 화소 × MSAA | 거울 | 비고 |
| --- | --- | --- | --- | --- |
| 높음 | 1.0 | 5.18M × 4 = 20.7M | 0.5² → 1.30M | RTX 자동 (W15) |
| 보통 | 0.84 (2560×1440 상한) | 3.66M × 2 = 7.3M (35%) | (0.35×0.84)² → 0.45M | 예전 RTX 자동 |
| 낮음 | 0.71 (1920×1080) | 2.07M × 1 | 없음 | 내장 그래픽 자동 |

'높음' 이 필요한 기준 (제안): 화소 일 = 화면 화소 × 4. RTX 노트북 120fps 를 4K (33M) 까진 장담 못 해 3200×2000 (25.6M) 에서 끊음 — 재혁 PC F3 숫자 (높음·보통 각각) 로 다시 정할 것.

### W16 (2026-11-03) — 2D 화면 판 그리기 (기준 `cbabe64` = W15 ↔ 지금, 같은 재연 `game8.rec`, 번갈아 3번)

재기 도구 (테스트 밖 확인용): `--census` 끝에 **2D 화면 요소별 빼 보기** (`core/ui_census.gd` — 요소마다 그리기만 RenderingServer 로 끄고 한 프레임 그려 창 2D 그리기·물체가 준 만큼, 노드·글·버튼·StyleBoxFlat (사선·그림자·둥근)·외곽선 글 수, 60프레임 동안 다시 그린 노드와 그 draw 함수), `--replay-open settings` (설정 창을 띄우고 잼), `--ui-check` (구운 판 위 입력 확인 `core/ui_check.gd`), `--bake-why` (구운 판을 다시 구운 까닭). 자동 조종도 `--ui-census` (찍는 순간 — 메뉴·결과).

**2D 비용 순위 (W15 기준, 1280×720, 창 viewport 2D 그리기 · 물체):**

| 화면 · 요소 | 그리기 | 물체 | 노드 | 비고 |
| --- | --- | --- | --- | --- |
| 대기실 + 설정 창 | **387** | 1079 | 272 | 설정 창 144 (키 목록 54) + 뒤 대기실 판 그대로 |
| 대기실 전체 | **210** | 692 | 152 | |
| ·대기실 판 (`lobby.gd`) | 131 | 399 | 85 | 캐릭터 카드 3×3 38 · '방 설정' 묶음 24 · 방 코드 줄 15 · 색 칸 15 · 상태 글 12 (글꼴 대체 · 마다 끊김) · 큰 캐릭터 칸 11 |
| ·플레이어 관리 (`host_players.gd`) | 59 | 231 | 39 | 버튼 15개 × 3~4 (바탕·외곽선 글·글) |
| ·위 점수 띠 | 17 | 54 | 25 | 사람 사이 '·' 가 DejaVu 대체라 2번씩 |
| 판 HUD (1인칭) | 82 | 205 | 113 | 아래 판 8장 65 (장마다 8) · 시간 3 · F·R 5 · '화면을 클릭하면' 5 |
| 결과 | 55 | 176 | | |
| 메뉴 | 43 | 240 | | 큰 버튼 반짝임 6개가 늘 다시 그림 (보이는 애니) |

다시 그림 (같은 값인데 매 갱신): 대기실 이름 칸 (같은 글을 다시 넣음 — LineEdit 는 같아도 다시 그림), 판 F·R 칸 (StyleBox 테두리·그림자 색을 매 갱신 씀 → changed), 조준 고리 (갱신마다 queue_redraw), 메뉴 큰 버튼 반짝임 트윈 6개는 메뉴가 안 보이는 판 중에도 돎.

**한 일 (모습 그대로):** 대기실 판·플레이어 관리·설정 창은 그림만 구움 (`ui/baked_panel.gd`, `ui/README.md` 'W16 2D 판 굽기') · 위 다시 그림 넷은 값이 바뀔 때만·안 보이면 멈춤.
안 한 것: 판 HUD 아래 판 굽기 (맞으면 % 흔들림·죽음 회색이 거의 매 프레임 → 재연에서 120번/초 다시 구움, 되돌림) · 메뉴·결과 (작음, 메뉴는 반짝임이 늘 돎).

| 장면 (보통 화질) | 기준 그리기 · 물체 (창 2D) | 지금 | 화소 차 > 8/255 기준↔기준 · 지금↔지금 · 기준↔지금 |
| --- | --- | --- | --- |
| 대기실 1280×720 | 319 · 809 (**210** · 692) | 135 · 191 (**26** · 74) | 1.8~2.6% · 1.0~2.5% · 0.4~2.6% (큰 3D 캐릭터 도는 자세 = 벽시계, 판 부분만은 0%) |
| 대기실 2880×1800 (UI 2.25배) | 316 · 806 (210 · 692) | 132 · 188 (26 · 74) | 0.8~2.9% · 2.7~2.8% · 0.9~3.0% (판 부분 0%, 최대 21/255) |
| 대기실 + 설정 창 1280×720 | 484 · 1184 (**387** · 1079) | 124 · 180 (**27** · 75) | 0.6% · 0.2~0.7% · 0.6~0.7% |
| 대기실 + 설정 창 2880×1800 | 487 · 1213 (390 · 1108) | 124 · 180 (27 · 75) | — · 0.5% · 0.5% |
| 판 1인칭 1280×720 | 181~184 · 307 (82 · 205) | 181~184 · 307 (82 · 205) | 0.8~1.1% · 0.7~0.8% · 0.1~1.3% |
| 판 1인칭 2880×1800 | 164~167 · 290 (82 · 205) | 167 · 290 (82 · 205) | 0.7% · 0.6% · 0.1~0.8% |

- 구운 판을 다시 구운 수: 가만히 있는 대기실 60프레임 0번 (기준: 이름 칸이 갱신마다 다시 그림), hover·클릭·글자·사람 들어옴 때만 (구울 때 그 프레임만 SubViewport 2D 127 + 59)
- 스크립트 ms/프레임 (그리기 끔, 평균·중앙): 대기실 2.30·1.43 → 2.33·1.45, 판 2.52·2.24 → 2.56·2.22 — 같음 (흔들림 안). 이번 일은 그리기 (CPU 명령·GPU 반투명 칠) 쪽
- 영상 메모리: 구운 판 텍스처 (2880×1800 에서 대기실 ~1220×1505 + 플레이어 관리 655×756, 설정 창은 화면 전체) — 재연 +3~18MB
- 입력 (`--ui-check`, 대기실 재연): hover·'조작법'·'스킬 보기' (산 칸)·이름 칸 초점·글자 입력·모드 고르기 목록·플레이어 관리 hover·'설정' → 설정 창 체크 칸·'닫기' — 1280×720·960×540 (판 휠 스크롤 포함)·2880×1800·UI 150% 모두 통과, `--no-bake` 와 같음
- 재혁 PC 에서 볼 것: 대기실 F3 '그리기' 가 판과 비슷해졌는지 (예전 대기실 ≈ 판 + 130) · 대기실·설정 창 글자가 흐리거나 1화소 밀려 보이지 않는지 (2880×1800 200%) · 이상하면 `--no-bake` 로 비교

### 남은 큰 비용과 다음 후보 (순위, W15 재연 근거)

1. **몸 자세 1.28ms (스크립트의 48%)** — 센 몸 하나 ~0.26ms, figureAnim 0.47 이 가장 큼: 사전 (P·V·T) 기반 GDScript 라 연산 수 자체 (몸 하나 ~1000 연산). 다음: 자세 표를 PackedFloat64Array 로 (JS 정답 테스트 `test_chars` 를 같이 옮겨야 함) · 3~10m 도 120fps 에선 60Hz 라 더 줄이려면 가까운 몸도 60Hz (모습 확인 필요)
2. ~~대기실 2D 화면 판~~ (W16 에 구움: 창 2D 210 → 26). 남은 2D: 판 HUD 82 (아래 판 65 — 굽기는 안 맞음, 줄이려면 카드 모양을 한 장 그림 + 글로 다시 짜야 함) · 결과 55 · 메뉴 43
3. **외곽선 패스** — 화면 쪽은 삼각형의 ~15% (그림자 쪽은 W15 에 뺌). 먼 몸 생략·화면 공간 한 패스는 모습이 바뀜 (위). 남은 길: 떨어지는 칸 모양 (테마 칸 메시) 삼각형 줄이기
4. HUD 0.17 · net 0.23 (JSON 파싱 0.11 = 엔진) · 표식·투사체·갈고리 0.12 · 격자·건축 블록 0.10 — 작음
5. 렌더러: Forward+·Mobile 숫자는 재혁 PC (`start-lan-forward/mobile.bat`, `../README.md`)

### W17 (2026-11-04) — 용암 (위험 액체) 이 나올 때 랙

재연 기록 `lava8.rec` (8명·bowl 화산 맵, 서버 `LAVA_TRIGGER_AVG_HEIGHT` 를 0.12 로 낮춘 복사본으로 판 21초에 용암), `--replay-render --replay-fps 30 --frame-log`, 640×360, 3번씩:

| | 용암 첫 프레임 벽시계 (중앙 프레임 대비) | 그 프레임 스크립트 |
| --- | --- | --- |
| 기준 (`a6dc963`) | 196 · 174 · 178ms (1.8~2.0배, +~85ms) | 29~31ms (world 위험 12.3 · audio 4.6) |
| 지금 | 118 · 116 · 113ms (1.16~1.19배) | 17ms |
| 표만 고치고 미리 그리기 끔 | 216ms (2.2배) | 17ms |

원인: (1) 위험 셰이더 갈래 (near·far, 테마 STYLE·낮춤 SHIMMER) 와 가장자리 경고 셰이더가 처음 나오는 프레임에 컴파일 — 메뉴 G3.prewarm 은 메뉴 테마의 near 만 · (2) 닿는 곳 거리 표 (`hazard_field.gd field`, 19칸 판 화소 15k 두 번 훑기 + 그림 바이트) 가 한 번 12ms, 위험 중 칸이 떨어질 때마다 (격자 버전) 다시 셈 · (3) 위험 소리 파일을 그 프레임에 읽음. 스냅샷 크기는 그대로 (중앙 13.4k → 13.5k 글자), 위험 셰이더에 화면 복사 없음.
고침: `hazard_view` 가 set_g3 (테마·낮춤이 정해질 때) 뒤 위험이 꺼진 동안 2프레임 같은 재질을 카메라 앞 1mm 상자로·경고 판을 세기 0 으로 그림, 처음 표 (zs < 0 은 격자와 무관) 를 미리 셈·올림, 칸 값 (`HF.columns`) 이 같으면 표를 다시 안 셈 (위험 위에 쌓이는 칸) · `field` 는 뚫린/먼 칸을 칸 단위로 Image 로 늘리고 사이 칸 화소만 훑음 (값 비트 그대로 — `test_hazard_field_fast_same_as_ref`, 11.8 → 2.3~3.7ms) · `music.gd` 가 테마가 정해질 때 위험 소리를 미리 불러 둠.
모습: 같은 가상 시각 (용암 위, 3인칭 1280×720) 차 > 8/255 화소 기준↔기준 1.07% · 지금↔지금 1.30% · 기준↔지금 0.66~2.73% (래그돌 흔들림 안).
