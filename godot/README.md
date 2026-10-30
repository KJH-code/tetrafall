# Tetrafall 고도(Godot) 시제품

JS 판(Node 서버 + three.js)을 고도로 옮길지 정하기 위한 시제품. JS 코드와 섞지 않고 이 폴더만 씀.

- 고도 **4.7.2 stable** (2026-10-30 github releases 최신 안정판), GDScript 만, 렌더러 Compatibility (웹 내보내기용)
- 철학은 JS 판과 같음: 헤드리스 서버가 판정 권위 (30Hz 고정 틱), 클라는 입력 보내기 + 그리기 (예측 없음)
- 범위: 격자 필드·테트리미노 낙하·착지·압사(머리 박음)·층 지우기·용암 / 이동·점프·2단 점프·대시·밀치기·% 넉백·콤보 / 낙사·판 끝. 2~8명 같은 방
- 범위 밖: 캐릭터 스킬·아이템·모드·맵 지형·타이틀·메뉴·래그돌·셰이더 꾸밈·재접속

## 구조

| 파일 | 내용 |
| --- | --- |
| `sim/config.gd` | 튜닝 수치 (`shared/config.js` 값 그대로 시작). 코드에 숫자 안 박음 |
| `sim/pieces.gd` | 테트리미노 모양·회전 (`shared/pieces.js`) |
| `sim/game.gd` | 게임 규칙 `Game` (노드 없음, 순수 계산). 입출력은 `handle_input`·`handle_action`·`tick`·`snapshot` 뿐 → 나중에 이 경계 그대로 C#/GDExtension 으로 뺄 수 있음 |
| `net/server.gd` | 헤드리스 서버: `TCPServer` + `WebSocketPeer` 직접, 방 코드마다 `Game`, `_physics_process` 30Hz. 2명 모이면 시작, 끝나면 3초 뒤 다음 판 |
| `client/client.gd` | 클라: 접속·입력·그리기 (쌓인 칸 MultiMesh, 떨어지는 칸·그림자 MeshInstance 묶음, 사람 캡슐 + 이름·%), `--bot` 자동 입력 |
| `main.gd` | 실행 모드 고르기 (명령줄 `--` 뒤, 웹이면 항상 클라) |
| `tests/` | 헤드리스 테스트 러너(GUT 없음)·규칙 테스트·JS 비교 테스트·틱 벤치 |
| `tools/` | JS 비교 숫자 뽑기, 서버+클라 2개 자동 확인, 웹 서빙·브라우저 스샷, JS 틱 벤치 |

메시지는 JSON 글자 (웹·JS 도구도 붙기 쉽게): 클라 → `hello{room,name}`·`input{fwd,strafe,jump,yaw}`·`action{name}`, 서버 → `welcome{id}`·`grid{gv,W,D,H,data base64}` (격자는 바뀔 때만)·`state{…snapshot, events}`.

## 고도 받기 (리눅스 컨테이너)

```
mkdir -p /opt/godot-dl && cd /opt/godot-dl
curl -LO https://github.com/godotengine/godot/releases/download/4.7.2-stable/Godot_v4.7.2-stable_linux.x86_64.zip
unzip Godot_v4.7.2-stable_linux.x86_64.zip && ln -sf $PWD/Godot_v4.7.2-stable_linux.x86_64 /usr/local/bin/godot
# 내보내기 템플릿 (1.3GB 묶음에서 필요한 것만 꺼냄)
curl -LO https://github.com/godotengine/godot/releases/download/4.7.2-stable/Godot_v4.7.2-stable_export_templates.tpz
D=~/.local/share/godot/export_templates/4.7.2.stable && mkdir -p $D
unzip -j Godot_v4.7.2-stable_export_templates.tpz templates/version.txt templates/linux_release.x86_64 templates/web_nothreads_release.zip -d $D
```

윈도우는 같은 곳에서 `Godot_v4.7.2-stable_win64.exe.zip`. 편집기로 `godot/project.godot` 를 열면 됨.

## 실행 (레포 뿌리에서)

```
godot --headless --path godot -- --server --port 3100            # 서버 (Ctrl+C 로 끔)
godot --path godot -- --client --url ws://127.0.0.1:3100          # 창 클라 (사람). WASD 이동 · Space 점프(2단) · Shift 대시 · 클릭/J 밀치기
godot --path godot -- --client --bot --name 봇1                   # 봇 클라 (자동 입력), --headless 붙이면 창 없이
```

옵션: `--room 코드` (기본 A), `--rounds N` (서버: N판 끝나면 종료), `--quit-after-rounds N` (클라), `--shot 파일.png --shot-after 초` (클라 화면 저장 후 종료).

## 테스트·확인

```
godot --headless --path godot --import                          # 처음 한 번 (글꼴 등 가져오기)
godot --headless --path godot -s res://tests/run_tests.gd       # 규칙 테스트 + JS 비교 (실패하면 종료 코드 1)
node godot/tools/js_compare.mjs > godot/tests/js_expected.json  # JS 판 비교 숫자 다시 뽑기 (JS 규칙이 바뀌면)
bash godot/tools/e2e.sh 3                                       # 헤드리스 서버 + 봇 클라 2개, 3판 돌고 셋 다 정상 종료하는지
godot --headless --path godot -s res://tests/bench.gd           # 서버 틱 시간 (같은 각본: node godot/tools/js_tick_bench.mjs)
```

JS 비교 (`tests/js_expected.json` 과 같은 장면을 고도에서 돌림, 전부 일치):

| 장면 | JS | 고도 |
| --- | --- | --- |
| 밀치기 한 방 거리 (피해 0% / 50%) | 0.619 / 1.063칸 | 같음 (±0.005) |
| O 블록 16칸 높이 → 착지 | 8033ms | 같음 |
| 떨어지는 블록에 압사까지 | 7533ms | 같음 |
| 점프 최고 높이·공중 시간 | 1.283칸 · 700ms | 같음 |
| 대시 거리 · 1초 걷기 | 0.901 · 4.5칸 | 같음 |
| 피해 150% 가장자리 밀치기 → 낙사 | 1067ms | 같음 |

## 내보내기

```
mkdir -p godot/build/web godot/build/linux
godot --headless --path godot --export-release "Web" build/web/index.html
godot --headless --path godot --export-release "Linux" build/linux/tetrafall.x86_64
node godot/tools/serve_web.mjs 8060      # http://127.0.0.1:8060/?server=ws://127.0.0.1:3100 (봇으로: &bot)
```

- 웹은 스레드 없는 판 (`variant/thread_support=false`) → COOP/COEP 헤더 필요 없음, 아무 정적 서버나 됨. 서버 주소는 `?server=` 또는 지금 페이지 호스트:3100
- `build/` 는 커밋 안 함 (`.gitignore`, 고도가 안 읽게 `.gdignore`)
- 브라우저 스샷: `WEB_GL=mesa xvfb-run -a node godot/tools/web_shot.cjs <폴더>`. 헤드리스 크로미움 기본(SwiftShader WebGL)에선 고도 화면이 띠·큰 다각형으로 깨져 보임 — 같은 빌드를 Mesa 로 띄우면 멀쩡하고, 고도 데스크톱(리눅스) 렌더도 멀쩡

## JS 판과 다른 점 (시제품이라 뺀 것)

- 자동 블록 자리: JS 는 층 지우기 쪽으로 몰리는 가중 무작위 (`CLEAR_BIAS`, `game-placement.js`), 여기는 균등 무작위
- 시작 지형(맵)·하늘 계단·조종권·아이템·캐릭터·카운터히트·팀·관전 전환·재접속 없음. 판 중 들어오면 다음 판까지 관전
- 화면 위치 보간 없음 (스냅샷 그대로 그림)
