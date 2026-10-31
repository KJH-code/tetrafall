# Tetrafall C# 서버

JS 서버(`server/index.js`)를 옮긴 것. .NET 10 LTS, 고도 없음. 규칙 전부 (S1~S5: 판·블록·전투·캐릭터 8명·아이템·연습·튜토리얼·봇) + 방·네트워크 (S6) + sim·내보내기 (S7). **`node tools/game-hash.js` 의 34판 해시가 C# `Tetrafall.Trace hash` 와 같음** (틱마다 스냅샷·이벤트·로그가 글자까지 같다는 뜻). JS 판은 얼림 — JS 를 고치면 C# 에도 같이 고치고 `node godot/server/tools/fixtures.mjs` 로 정답 자료를 다시 뽑음

## 받기 (리눅스 컨테이너; 윈도우는 https://dotnet.microsoft.com 에서 .NET 10 SDK 설치)

```
mkdir -p /opt/dotnet && curl -sSL https://builds.dotnet.microsoft.com/dotnet/Sdk/10.0.403/dotnet-sdk-10.0.403-linux-x64.tar.gz | tar xz -C /opt/dotnet
ln -sf /opt/dotnet/dotnet /usr/local/bin/dotnet
export DOTNET_ROOT=/opt/dotnet   # 만든 실행 파일 (Tetrafall.Trace 등) 을 바로 돌릴 때 필요 (dotnet run 은 없어도 됨)
```

## 실행·테스트 (이 폴더에서)

```
dotnet test                                         # xUnit: JsMath·숫자 글자·난수·JSON·대기실 프로토콜이 JS 와 같은지
PORT=3200 dotnet run --project src/Tetrafall.Server # 서버 → 브라우저 http://localhost:3200 (기존 JS 화면, 레포 뿌리에서 npm install 한 번)
node godot/server/tools/online-cs.mjs               # (레포 뿌리에서) npm run online 의 C# 판: C# 서버 + Cloudflare 터널
```

환경 변수: `PORT` (0 이면 빈 포트, 시작 줄에 실제 포트), `TF_ROOT` (레포 뿌리), `TF_LOG_DIR` (로그 폴더, 기본 `<뿌리>/logs`), `TF_STDIN_CONTROL=1` (표준 입력 한 줄 `{"type":"publicUrl","url":…}` 로 터널 주소 받기 — online-cs.mjs 가 씀, JS 서버의 node IPC 자리).

JS 화면 파일은 레포 뿌리 `client/`·`shared/`·`node_modules/three` 에서 서빙 (뿌리는 자동으로 찾음, 아니면 `TF_ROOT`). 로그는 JS 서버와 같은 `logs/<서버 시각>/<방 시각>_<코드>.txt`, 줄마다 `[13시 5분 7초] …` (JS `toLocaleTimeString('ko-KR')` 와 같음) → `npm run stats` 가 그대로 읽음.

## 봇 판 시뮬레이션 (`npm run sim` 의 C# 판, S7)

```
dotnet run -c Release --project godot/server/src/Tetrafall.Sim -- --rounds 200 --players 2,4   # 옵션은 tools/sim.js 와 같음 (--maps --chars --level --sky --seed --workers --no-mirror --no-log --out --base)
```

같은 옵션·시드면 JS 와 같은 판·같은 summary.json (`out` 칸만 다름)·같은 워커 로그 (워커 수도 같으면) — `npm run stats -- sim-logs/<시각>` 그대로. 4코어에서 JS 의 약 1.8배 빠름 (252판: JS 20.3초 / C# 11.1초)

## 한 파일로 내보내기 (S7)

```
dotnet publish godot/server/src/Tetrafall.Server -c Release -r win-x64   --self-contained -p:PublishSingleFile=true -o out/win     # Tetrafall.Server.exe (약 100MB, .NET 설치 필요 없음)
dotnet publish godot/server/src/Tetrafall.Server -c Release -r linux-x64 --self-contained -p:PublishSingleFile=true -o out/linux   # Tetrafall.Server
```

실행은 레포 뿌리에서 (화면 파일 `client/`·`shared/`·`node_modules/three` 를 위로 찾음, 아니면 `TF_ROOT=레포 경로`). `PORT=3000` 이 기본

## 배포 묶음 (G7): 서버 + 고도 웹 + 고도 PC 클라 zip

```
node godot/server/tools/package.mjs --godot <고도 4.7.2> [--targets win,linux] [--cloudflared]   # → dist/tetrafall-win-x64.zip, dist/tetrafall-linux-x64.zip
```

- 폴더: `Tetrafall.Server(.exe)` + `web/` (고도 웹 빌드) + `tetrafall.exe`/`tetrafall.x86_64` (PC 클라) + `start-lan`·`start-online` (.bat/.sh) + `README.txt` (+ `cloudflared` 를 `--cloudflared` 로 GitHub 에서 받아 넣음)
- 서버는 exe 옆에 `web/index.html` 이 있으면 그 폴더가 뿌리 (배포 폴더): `/play/` = `web/`, JS 화면이 없으니 `/` → `/play/` (302, `?room=` 그대로). 레포·배포 어느 쪽도 아니면 exe 폴더로 뜸 (웹소켓만, PC 클라용)
- 웹 미리 압축: `web/` 파일마다 `.br` (brotli 11, 창 24) + `.gz` (gzip 9) → 서버 `StaticFiles.Precompressed` 가 Accept-Encoding 따라 br > gzip > 날것 (`Content-Encoding`·`Vary: Accept-Encoding`, 형식은 날것 이름). 엔진 wasm 39.5MB → br 6.9MB · gz 10.2MB (압축 약 1분 40초)
- `--no-godot` = 이미 내보낸 `godot/client/build/` 를 씀. zip 은 node 만으로 씀 (유닉스 실행 비트 유지)
- 재혁 PC 순서: [docs/godot-play.md](../../docs/godot-play.md)

## 인터넷 대전: `--online` (node 없이)

```
Tetrafall.Server --online          # 또는 dotnet run --project godot/server/src/Tetrafall.Server -- --online,  TF_ONLINE=1 도 같음
```

`Tunnel.cs` = `tools/online.js` 터널 지키기의 C# 판 (cloudflared 켜기 → 주소 찾기 → HTTP 첫 화면 'Tetrafall' + 웹소켓이 열릴 때까지 기다림 → 대기실 링크·클립보드·안내 상자, 열린 뒤에도 `TUNNEL_HEALTH_MS` 마다 확인하고 죽으면 다시 켬, 수치 config `TUNNEL_*`). cloudflared 는 `CLOUDFLARED` 환경 변수 > exe 옆 > PATH. `tools/online-cs.mjs` (node 판) 도 그대로 둠

## 도구 (`tools/`, node — 레포 뿌리에서)

| 명령 | 하는 일 |
| --- | --- |
| `node godot/server/tools/gen-config.mjs` | `shared/config.js`·`shared/maps.js` → `Config.g.cs`·`Maps.g.cs` (값 934개 + 서버가 쓰는 표 6개 — 모양은 값에서 짐작해 클래스 `T<이름>`, 평타 칸은 모두 `TAttack`. 화면 전용 표 29개는 안 만듦, 함수 `spawnPointsFor` 는 `ConfigFns.cs`) |
| `node godot/server/tools/fixtures.mjs` | 테스트 정답 자료 (`tests/Tetrafall.Tests/fixtures/`) 를 JS 에서 다시 뽑음 (방 각본은 `room-scenarios.mjs`) |
| `node godot/server/tools/package.mjs` | 배포 zip (위 G7) |
| `node godot/server/tools/online-cs.mjs` | C# 서버 + 터널 (`tools/online.js` 의 터널 지키기를 그대로 씀, dll 이 있으면 `bin/Release`, 없으면 `dotnet run`) |
| `node godot/server/tools/trace.mjs <번호> js.jsonl` | JS 판 시나리오 하나를 틱마다 기록 (`--list` 로 34개 목록, `tools/game-hash.js` 와 같은 판). `s0`~`s7` = 각본 입력 판 (`tools/scripted.mjs`: 사람만·캐릭터 끔, 봇(S5) 전에 판 흐름·블록을 맞추는 판) |
| `node godot/server/tools/trace-scripted.mjs <캐릭터> js.jsonl` | 봇 없는 각본 판 (S3 전투·캐릭터 검증): 캐릭터마다 사람 둘이 정해진 틱에 평타·스킬·필살기·점프·대시, 킬 점수전·블록 없음, 600틱. `--list`, `--dump scripts.json` (C# 가 같은 각본을 돌릴 자료) |
| `dotnet run --project godot/server/src/Tetrafall.Trace -- trace <번호> cs.jsonl [--ticks N]` | 같은 판을 C# 로 같은 JSONL (아직 안 옮긴 메서드에 닿으면 거기까지 쓰고 멈춤) |
| `dotnet run --project godot/server/src/Tetrafall.Trace -- hash [--verbose]` | `node tools/game-hash.js` 와 같은 해시 (34판 다 돌면 = 규칙 이식 끝) |
| `node godot/server/tools/tutorial-trace.mjs <캐릭터> js.jsonl` | 튜토리얼 판 (자동 조종 `shared/tutorial-pilot.js` 으로 끝까지, S4 검증). C# 는 `Tetrafall.Trace trace tut:<캐릭터>` (`TutorialPilot.cs`) |
| `node godot/server/tools/trace-diff.mjs js.jsonl cs.jsonl` | 두 기록에서 처음 갈라지는 틱·JSON 경로·ulp |
| `xvfb-run -a node godot/server/tools/lobby_shot.cjs <폴더> [주소]` | 기존 JS 화면을 이 서버에 붙여 메뉴·대기실 스샷 |

## 구조

- `src/Tetrafall.Core/` — 규칙 (`Game.cs` + 묶음 `Game.<묶음>.cs` partial, `Player.cs`), `Js/` = JS 와 같은 숫자 부품 (`JsMath` V8 수학, `JsNumber` 숫자 글자·toFixed, `JsonOut` JSON.stringify, `Mulberry32`)
- `src/Tetrafall.Server/` — `Program.cs` (Kestrel·정적 파일 (+ `/play/` = 고도 웹 빌드 godot/client/build/web)·잘못된 주소 400·WebSocket (NET_MAX_PAYLOAD_BYTES 넘으면 그 연결만 1009)·30Hz 루프 스레드 하나·표준 입력 터널 주소), `Rooms.cs` (rooms.js 전부, `OrderedMap` = JS Map 순서), `WsSocket.cs`, `StaticFiles.cs` (resolveFile·배포 폴더 `web/`·방 로그 파일), `Tunnel.cs` (`--online` 터널)
- `src/Tetrafall.Sim/` — 봇 판 시뮬레이션 (`Sim.cs` = tools/sim.js planJobs·runJob·runParallel·summarizeSim·formatSim, summary.json 은 JSON.stringify(…, null, 1) 모양)
- `src/Tetrafall.Trace/` — 판 기록기: `Scenarios.cs` (game-hash.js 시나리오 34개·runScenario 그대로), trace JSONL·해시
- 아직 안 옮긴 메서드는 `Game.Todo.cs` (부르면 NotImplementedException, 괄호 = 작업 id). 옮기면 거기서 지우고 묶음 파일에
- `tests/Tetrafall.Tests/` — `JsCompatTests`, `ProtocolTests` (JS rooms.js 와 같은 각본 → 같은 메시지 25개·로그 12줄), `RoomScenarioTests` (`tools/room-scenarios.mjs` 각본 5개 — 재접속·방 안 설정·상한·예외 격리·빈도 제한 — 를 C# 로 돌려 JS 와 메시지·로그 글자까지 같음), `RoomsUnitTests` (JS 값 바꾸기·이름 정리·긴 글자·빈도·토큰), `ServerProcessTests` (진짜 프로세스: 잘못된 주소 400·큰 메시지 1009·터널 주소·로그 파일 줄 모양), `S1Tests` (시작 지형 70개·물리 21판 비트·판 시작 trace 33판이 JS 정답 자료와 같음, 물리 단위 테스트), `S2Tests` (각본 판 8개 trace 전체가 JS 와 같음 + modes·sky·ghost 테스트 중 전투·봇·연습이 안 끼는 것), `SimTests` (sim.js 작은 판의 요약·화면 표·로그가 JS 와 같음, 워커 수와 상관없음), `S5Tests` (hp·master·킬 점수전·botpos), `S4Tests` (game-hash 34판 중 C# 가 다 도는 판의 해시가 JS 와 같음 — 안 옮긴 곳에 닿는 판은 건너뜀, 튜토리얼 자동 조종 판 trace, practice·tutorial 테스트)
