# Tetrafall C# 서버

JS 서버(`server/index.js`)를 옮기는 중. .NET 10 LTS, 고도 없음. 지금은 뼈대: 방 만들기·들어가기·나가기·핑·대기실 스냅샷까지 (판은 `../PLAN.md` 작업 목록).

## 받기 (리눅스 컨테이너; 윈도우는 https://dotnet.microsoft.com 에서 .NET 10 SDK 설치)

```
mkdir -p /opt/dotnet && curl -sSL https://builds.dotnet.microsoft.com/dotnet/Sdk/10.0.403/dotnet-sdk-10.0.403-linux-x64.tar.gz | tar xz -C /opt/dotnet
ln -sf /opt/dotnet/dotnet /usr/local/bin/dotnet
```

## 실행·테스트 (이 폴더에서)

```
dotnet test                                         # xUnit: JsMath·숫자 글자·난수·JSON·대기실 프로토콜이 JS 와 같은지
PORT=3200 dotnet run --project src/Tetrafall.Server # 서버 → 브라우저 http://localhost:3200 (기존 JS 화면, 레포 뿌리에서 npm install 한 번)
```

JS 화면 파일은 레포 뿌리 `client/`·`shared/`·`node_modules/three` 에서 서빙 (뿌리는 자동으로 찾음, 아니면 `TF_ROOT`). 로그는 JS 서버와 같은 `logs/<시각>/`.

## 도구 (`tools/`, node — 레포 뿌리에서)

| 명령 | 하는 일 |
| --- | --- |
| `node godot/server/tools/gen-config.mjs` | `shared/config.js`·`shared/maps.js` → `Config.g.cs`·`Maps.g.cs` (값 934개 + 서버가 쓰는 표 6개 — 모양은 값에서 짐작해 클래스 `T<이름>`, 평타 칸은 모두 `TAttack`. 화면 전용 표 29개는 안 만듦, 함수 `spawnPointsFor` 는 `ConfigFns.cs`) |
| `node godot/server/tools/fixtures.mjs` | 테스트 정답 자료 (`tests/Tetrafall.Tests/fixtures/`) 를 JS 에서 다시 뽑음 |
| `node godot/server/tools/trace.mjs <번호> js.jsonl` | JS 판 시나리오 하나를 틱마다 기록 (`--list` 로 34개 목록, `tools/game-hash.js` 와 같은 판) |
| `dotnet run --project godot/server/src/Tetrafall.Trace -- trace <번호> cs.jsonl [--ticks N]` | 같은 판을 C# 로 같은 JSONL (아직 안 옮긴 메서드에 닿으면 거기까지 쓰고 멈춤) |
| `dotnet run --project godot/server/src/Tetrafall.Trace -- hash [--verbose]` | `node tools/game-hash.js` 와 같은 해시 (34판 다 돌면 = 규칙 이식 끝) |
| `node godot/server/tools/trace-diff.mjs js.jsonl cs.jsonl` | 두 기록에서 처음 갈라지는 틱·JSON 경로·ulp |
| `xvfb-run -a node godot/server/tools/lobby_shot.cjs <폴더> [주소]` | 기존 JS 화면을 이 서버에 붙여 메뉴·대기실 스샷 |

## 구조

- `src/Tetrafall.Core/` — 규칙 (`Game.cs` + 묶음 `Game.<묶음>.cs` partial, `Player.cs`), `Js/` = JS 와 같은 숫자 부품 (`JsMath` V8 수학, `JsNumber` 숫자 글자·toFixed, `JsonOut` JSON.stringify, `Mulberry32`)
- `src/Tetrafall.Server/` — `Program.cs` (Kestrel·정적 파일·WebSocket·30Hz 루프 스레드 하나), `Rooms.cs` (rooms.js), `WsSocket.cs`, `StaticFiles.cs` (resolveFile·방 로그 파일)
- `src/Tetrafall.Trace/` — 판 기록기: `Scenarios.cs` (game-hash.js 시나리오 34개·runScenario 그대로), trace JSONL·해시
- 아직 안 옮긴 메서드는 `Game.Todo.cs` (부르면 NotImplementedException, 괄호 = 작업 id). 옮기면 거기서 지우고 묶음 파일에
- `tests/Tetrafall.Tests/` — `JsCompatTests`, `ProtocolTests` (JS rooms.js 와 같은 각본 → 같은 메시지 25개·로그 12줄), `S1Tests` (시작 지형 70개·물리 21판 비트·판 시작 trace 33판이 JS 정답 자료와 같음, 물리 단위 테스트)
