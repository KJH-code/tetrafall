# Tetrafall C# 서버

JS 서버(`server/index.js`)를 옮기는 중. .NET 10 LTS, 고도 없음. 방·네트워크 (S6) 는 rooms.js·index.js 전부: 방 안 메시지·재접속(자리 토큰)·연습/튜토리얼 방·공개 방 목록·빈도 제한·방 하나 예외 격리·로그 파일. 판(startRound 이후)은 `../PLAN.md` 작업 목록 S1~S5 — 아직 안 옮긴 게임 함수는 `Game.Pending.cs` 자리 (부르면 그 방만 닫힘).

## 받기 (리눅스 컨테이너; 윈도우는 https://dotnet.microsoft.com 에서 .NET 10 SDK 설치)

```
mkdir -p /opt/dotnet && curl -sSL https://builds.dotnet.microsoft.com/dotnet/Sdk/10.0.403/dotnet-sdk-10.0.403-linux-x64.tar.gz | tar xz -C /opt/dotnet
ln -sf /opt/dotnet/dotnet /usr/local/bin/dotnet
```

## 실행·테스트 (이 폴더에서)

```
dotnet test                                         # xUnit: JsMath·숫자 글자·난수·JSON·대기실 프로토콜이 JS 와 같은지
PORT=3200 dotnet run --project src/Tetrafall.Server # 서버 → 브라우저 http://localhost:3200 (기존 JS 화면, 레포 뿌리에서 npm install 한 번)
node godot/server/tools/online-cs.mjs               # (레포 뿌리에서) npm run online 의 C# 판: C# 서버 + Cloudflare 터널
```

환경 변수: `PORT` (0 이면 빈 포트, 시작 줄에 실제 포트), `TF_ROOT` (레포 뿌리), `TF_LOG_DIR` (로그 폴더, 기본 `<뿌리>/logs`), `TF_STDIN_CONTROL=1` (표준 입력 한 줄 `{"type":"publicUrl","url":…}` 로 터널 주소 받기 — online-cs.mjs 가 씀, JS 서버의 node IPC 자리).

JS 화면 파일은 레포 뿌리 `client/`·`shared/`·`node_modules/three` 에서 서빙 (뿌리는 자동으로 찾음, 아니면 `TF_ROOT`). 로그는 JS 서버와 같은 `logs/<서버 시각>/<방 시각>_<코드>.txt`, 줄마다 `[13시 5분 7초] …` (JS `toLocaleTimeString('ko-KR')` 와 같음) → `npm run stats` 가 그대로 읽음.

## 도구 (`tools/`, node — 레포 뿌리에서)

| 명령 | 하는 일 |
| --- | --- |
| `node godot/server/tools/gen-config.mjs` | `shared/config.js`·`shared/maps.js` → `Config.g.cs`·`Maps.g.cs` (값 934개, 표 37개는 아직) |
| `node godot/server/tools/fixtures.mjs` | 테스트 정답 자료 (`tests/Tetrafall.Tests/fixtures/`) 를 JS 에서 다시 뽑음 (방 각본은 `room-scenarios.mjs`) |
| `node godot/server/tools/online-cs.mjs` | C# 서버 + 터널 (`tools/online.js` 의 터널 지키기를 그대로 씀, dll 이 있으면 `bin/Release`, 없으면 `dotnet run`) |
| `node godot/server/tools/trace.mjs <번호> js.jsonl` | JS 판 시나리오 하나를 틱마다 기록 (`--list` 로 34개 목록, `tools/game-hash.js` 와 같은 판) |
| `node godot/server/tools/trace-scripted.mjs <캐릭터> js.jsonl` | 봇 없는 각본 판 (S3 전투·캐릭터 검증): 캐릭터마다 사람 둘이 정해진 틱에 평타·스킬·필살기·점프·대시, 킬 점수전·블록 없음, 600틱. `--list`, `--dump scripts.json` (C# 가 같은 각본을 돌릴 자료) |
| `node godot/server/tools/trace-diff.mjs js.jsonl cs.jsonl` | 두 기록에서 처음 갈라지는 틱·JSON 경로·ulp |
| `xvfb-run -a node godot/server/tools/lobby_shot.cjs <폴더> [주소]` | 기존 JS 화면을 이 서버에 붙여 메뉴·대기실 스샷 |

## 구조

- `src/Tetrafall.Core/` — 규칙 (`Game.cs` + 묶음 `Game.<묶음>.cs` partial, `Player.cs`), `Js/` = JS 와 같은 숫자 부품 (`JsMath` V8 수학, `JsNumber` 숫자 글자·toFixed, `JsonOut` JSON.stringify, `Mulberry32`)
- `src/Tetrafall.Server/` — `Program.cs` (Kestrel·정적 파일 (+ `/play/` = 고도 웹 빌드 godot/client/build/web)·잘못된 주소 400·WebSocket (NET_MAX_PAYLOAD_BYTES 넘으면 그 연결만 1009)·30Hz 루프 스레드 하나·표준 입력 터널 주소), `Rooms.cs` (rooms.js 전부, `OrderedMap` = JS Map 순서), `WsSocket.cs`, `StaticFiles.cs` (resolveFile·방 로그 파일)
- `tests/Tetrafall.Tests/` — `JsCompatTests`, `ProtocolTests` (JS rooms.js 와 같은 각본 → 같은 메시지 25개·로그 12줄), `RoomScenarioTests` (`tools/room-scenarios.mjs` 각본 5개 — 재접속·방 안 설정·상한·예외 격리·빈도 제한 — 를 C# 로 돌려 JS 와 메시지·로그 글자까지 같음), `RoomsUnitTests` (JS 값 바꾸기·이름 정리·긴 글자·빈도·토큰), `ServerProcessTests` (진짜 프로세스: 잘못된 주소 400·큰 메시지 1009·터널 주소·로그 파일 줄 모양)
