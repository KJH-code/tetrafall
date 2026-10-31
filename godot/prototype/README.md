# Tetrafall 고도(Godot) 시제품

JS 판(Node 서버 + three.js)을 고도로 옮길지 정하기 위한 시제품. JS 코드와 섞지 않고 이 폴더만 씀.

- 고도 **4.7.2 stable** (2026-10-30 github releases 최신 안정판), GDScript 만, 렌더러 Compatibility (웹 내보내기용)
- 철학은 JS 판과 같음: 헤드리스 서버가 판정 권위 (30Hz 고정 틱), 클라는 입력 보내기 + 그리기 (예측 없음)
- 범위: 격자 필드·테트리미노 낙하·착지·압사(머리 박음)·층 지우기·용암 / 이동·점프·2단 점프·대시·밀치기·% 넉백·콤보 / 낙사·판 끝. 2~8명 같은 방 (판 크기 10~19)
- 2단계 (2026-10-30): 캐릭터 하나 = 닌자 (평타 지상 4타·공중 2타, F 순간 베기·벽 차기, R 표창 강화, 패시브, 카운터히트·F/R 캔슬), 자동 블록 자리 고르기 CLEAR_BIAS 점수, 서버 봇
- 범위 밖: 다른 캐릭터 7명·아이템·모드·맵 지형·하늘 계단·조종권·타이틀·메뉴·래그돌·셰이더 꾸밈·재접속

## 구조

| 파일 | 내용 |
| --- | --- |
| `sim/config.gd` | 튜닝 수치 (`shared/config.js` 값 그대로 시작). 코드에 숫자 안 박음 |
| `sim/pieces.gd` | 테트리미노 모양·회전 (`shared/pieces.js`) |
| `sim/game.gd` | 게임 규칙 `Game` (노드 없음, 순수 계산). 입출력은 `handle_input`·`handle_action`·`tick`·`snapshot` 뿐 → 나중에 이 경계 그대로 C#/GDExtension 으로 뺄 수 있음. `Game.new(log, true)` 면 캐릭터 켬 (모두 닌자, 서버 방은 켬), 끄면 예전 밀치기 규칙 |
| `sim/placement.gd` | 자동 블록 자리 점수 (`game-placement.js` placementScorer 그대로) |
| `sim/bot.gd` | 서버 봇 (아주 단순, `handle_input`·`handle_action` 만). `Game.add_bot()` |
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

윈도우는 같은 곳에서 `Godot_v4.7.2-stable_win64.exe.zip`. 편집기로 `godot/prototype/project.godot` 를 열면 됨.

## 실행 (레포 뿌리에서)

```
godot --headless --path godot/prototype -- --server --port 3100            # 서버 (Ctrl+C 로 끔)
godot --path godot/prototype -- --client --url ws://127.0.0.1:3100          # 창 클라 (사람). WASD 이동 · Space 점프(2단) · Shift 대시 · 클릭/J 평타 · F 순간 베기 · R 강화
godot --path godot/prototype -- --client --bot --name 봇1                   # 봇 클라 (자동 입력), --headless 붙이면 창 없이
```

옵션: `--room 코드` (기본 A), `--bots N` (서버: 방 A 에 봇 N명, 사람 없이도 판이 돎), `--rounds N` (서버: N판 끝나면 종료), `--quit-after-rounds N` (클라), `--shot 파일.png --shot-after 초` (클라 화면 저장 후 종료).

## 테스트·확인

```
godot --headless --path godot/prototype --import                          # 처음 한 번 (글꼴 등 가져오기)
godot --headless --path godot/prototype -s res://tests/run_tests.gd       # 규칙 테스트 + JS 비교 (실패하면 종료 코드 1)
node godot/prototype/tools/js_compare.mjs > godot/prototype/tests/js_expected.json  # JS 판 비교 숫자 다시 뽑기 (JS 규칙이 바뀌면)
node godot/prototype/tools/js_placement.mjs > godot/prototype/tests/js_placement.json  # 자리 고르기 점수 비교용 격자 8개
bash godot/prototype/tools/e2e.sh 3                                       # 헤드리스 서버 + 봇 클라 2개, 3판 돌고 셋 다 정상 종료하는지
bash godot/prototype/tools/e2e8.sh 2                                      # 8명: 서버 봇 7 + 봇 클라 1, 2판
godot --headless --path godot/prototype -s res://tests/bench.gd -- 18000 8   # 서버 틱 시간 8명 (같은 각본: node godot/prototype/tools/js_tick_bench.mjs 18000 8), --bots 면 서버 봇
godot --headless --path godot/prototype -s res://tests/bench_placement.gd    # 자리 고르기 한 번 시간 (JS: node godot/prototype/tools/js_placement_bench.mjs)
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
| 닌자 지상 연타 (3틱마다 1.5초) → 피해·밀린 거리·띄운 높이 | 20% · 1.013 · 1.478칸 | 같음 |
| 닌자 F 순간 베기 → 위치·베인 피해 | x 4.8 · 8% | 같음 |
| 닌자 R → 표창 2연발 피해 | 4% | 같음 |
| 닌자 F 벽 차기 높이 | 1.467칸 | 같음 |
| 자리 고르기: 격자 8개 (10~19칸) 모든 후보 점수 3만여 개 · 무작위 값 5개씩 고른 자리 | — | 전부 같음 |

## 서버 틱 시간 (2026-10-30, 이 컨테이너 4코어, 같은 각본, 틱 = game.tick + 스냅샷 JSON, 예산 33.3ms)

| | JS (node 22) | 고도 GDScript |
| --- | --- | --- |
| 2명 닌자 평균 / 99% / 최대 | 0.07 / 1.0 / 30ms | 0.75 / 2.2 / 78ms |
| 8명 닌자 평균 / 99% / 최대 | 0.54 / 14.9 / 44ms | 6.3 / 187 / 337ms |
| 8명 예산 넘은 틱 | 거의 없음 | 18000틱 중 530개 = 자동 블록 자리 고를 때마다 |
| 자리 고르기 한 번 (19×19) | 7~21ms | 147~289ms |

8명 고도 틱 평균 6.3ms 의 구간: 자리 고르기 5.0 · 용암 판단(`avg_height` 매 틱) 1.0 · 물리 0.08 · 전투 0.05 (`tests/bench.gd` 가 찍음).
실제 서버 8명 2판 (`tools/e2e8.sh`): 평균 5.8ms · 99% 161ms · 최대 270ms → 블록이 나올 때마다 서버가 0.2초쯤 멈칫.

### GDExtension(C++) 로 뺄 후보 (구현 안 함)

| 순위 | 곳 | 지금 (8명 19×19) | 왜 | 다른 길 |
| --- | --- | --- | --- | --- |
| 1 | 자동 블록 자리 고르기 `auto_candidates` + `placement.gd` score | 틱 평균의 80%, 한 번 150~290ms | 후보 8천여 개 × 점수(빈 칸 덩어리 너비 우선 탐색). 촘촘한 정수 반복이라 C++ 면 JS 보다도 빠를 것 | 서버는 네이티브라 C# 도 됨 (웹 클라와 상관없음), 또는 다음 블록 자리를 WorkerThreadPool 에서 미리 |
| 2 | 용암 판단 `avg_height` (매 틱 전체 기둥 훑기) | 1.0ms | W×D×H 칸 훑기 | C++ 보다 기둥 높이 캐시 (격자 바뀔 때만) 가 맞음 — GDScript 안에서 고침 |
| 3 | 스냅샷 JSON | 약 0.2ms | 8명·블록 수만큼 문자열 | 바이너리 (PackedByteArray) 로 바꾸면 크기·시간 둘 다 |
| — | 물리·전투 | 0.13ms | 가벼움 | GDScript 그대로 |

## 내보내기

```
mkdir -p godot/prototype/build/web godot/prototype/build/linux godot/prototype/build/windows
godot --headless --path godot/prototype --export-release "Web" build/web/index.html
godot --headless --path godot/prototype --export-release "Linux" build/linux/tetrafall.x86_64
godot --headless --path godot/prototype --export-release "Windows" build/windows/tetrafall.exe   # 템플릿 windows_release_x86_64.exe 필요
node godot/prototype/tools/serve_web.mjs 8060      # http://127.0.0.1:8060/?server=ws://127.0.0.1:3100 (봇으로: &bot)
```

- 웹은 스레드 없는 판 (`variant/thread_support=false`) → COOP/COEP 헤더 필요 없음, 아무 정적 서버나 됨. 서버 주소는 `?server=` 또는 지금 페이지 호스트:3100
- `build/` 는 커밋 안 함 (`.gitignore`, 고도가 안 읽게 `.gdignore`)
- 브라우저 스샷: `WEB_GL=mesa xvfb-run -a node godot/prototype/tools/web_shot.cjs <폴더>`. 헤드리스 크로미움 기본(SwiftShader WebGL)에선 고도 화면이 띠·큰 다각형으로 깨져 보임 — 같은 빌드를 Mesa 로 띄우면 멀쩡하고, 고도 데스크톱(리눅스) 렌더도 멀쩡

## 재혁 PC (윈도우) 에서 띄우기 — 실 GPU 비교용

1. https://github.com/godotengine/godot/releases/tag/4.7.2-stable 에서 `Godot_v4.7.2-stable_win64.exe.zip` 받아 풀기 (예: `C:\godot\`). 설치 없음
2. 레포 뿌리에서 PowerShell (처음 한 번 가져오기):
   ```
   C:\godot\Godot_v4.7.2-stable_win64_console.exe --headless --path godot/prototype --import
   ```
3. 서버 (봇 7명 → 8명 판): `C:\godot\Godot_v4.7.2-stable_win64_console.exe --headless --path godot/prototype -- --server --bots 7`
4. 클라 (다른 창): `C:\godot\Godot_v4.7.2-stable_win64.exe --path godot/prototype -- --client` → 내가 8번째. 화면 위 줄에 FPS
5. 웹으로 비교: 편집기(`Godot_v4.7.2-stable_win64.exe`)에서 `godot/prototype/project.godot` 열기 → 편집기 메뉴 › 내보내기 템플릿 관리 › 다운로드 → 프로젝트 › 내보내기 › Web › `build/web/index.html`. 그다음 `node godot/prototype/tools/serve_web.mjs 8060` → 크롬에서 `http://127.0.0.1:8060/?server=ws://127.0.0.1:3100`
6. 윈도우 실행 파일: 같은 내보내기 창에서 Windows (`build/windows/tetrafall.exe`, 약 110MB, pck 포함 한 파일). 이 컨테이너에서도 만들어짐 확인 (실행은 못 해 봄 — wine 없음). `tetrafall.exe -- --client --url ws://<서버>:3100` 처럼 같은 옵션

JS 판은 같은 PC 에서 `npm start` → F3 성능 표시 (FPS·1% low) 와 나란히 보면 됨.

## JS 판과 다른 점 (시제품이라 뺀 것)

- 자동 블록 자리: JS 와 같음 (CLEAR_BIAS 점수, 점수 테스트로 고정). 무작위 수열은 다름 (JS mulberry32/Math.random, 고도 RandomNumberGenerator) → 같은 시드라도 판은 다르게 흘러감
- 캐릭터는 닌자만 (방에선 모두 닌자). 이모트·연습·튜토리얼 없음
- 봇: JS `server/bot.js` (위험 예측·복귀·캐릭터별 전술) 와 달리 아주 단순 → 봇 판 사망 비율은 비교 대상 아님
- 시작 지형(맵)·하늘 계단·조종권·아이템·팀·관전 전환·재접속 없음. 판 중 들어오면 다음 판까지 관전
- 화면 위치 보간 없음 (스냅샷 그대로 그림)
