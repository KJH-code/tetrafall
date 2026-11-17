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

환경 변수: `PORT` (0 이면 빈 포트, 시작 줄에 실제 포트), `TF_ROOT` (레포 뿌리), `TF_LOG_DIR` (로그 폴더, 기본 `<뿌리>/logs`), `TF_STDIN_CONTROL=1` (표준 입력 한 줄 `{"type":"publicUrl","url":…}` 로 터널 주소 받기 — online-cs.mjs 가 씀, JS 서버의 node IPC 자리), `TF_BALANCE=off` (방 밸런스 표 끔 — 아래).

방은 기본으로 밸런스 표 (`ConfigBalance.cs` `C.BALANCE` — 캐릭터별 넉백 배율 `kbTaken`·`kbDealt` 만, 층은 `Tune.cs`): 대전·연습·튜토리얼 방의 판마다 `new Game(…, tune:)` 로 넘김 (고도 판 전용, JS 와 다른 규칙). 킬 점수전 판은 그 위에 `C.BALANCE_KILLS` (주는 넉백 `kbDealt` 만, Tune 모드 덮기 — 같은 캐릭터·키를 곱하지 않고 바꿈) 를 덮음: 방은 Game 하나를 계속 쓰고 판마다 `StartRound` 가 `tuneBase.For(mode)` 로 그 모드 표를 고름. 시작할 때 콘솔에 `밸런스 표: … · 킬 점수전: …` 한 줄 (`ServerBalance.cs`), `TF_BALANCE=off` 면 표 없는 예전 판 (킬 덮기도 같이 꺼짐). sim·Trace·테스트가 만드는 Rooms 는 표 없음 (`new Rooms(tune:)` 를 안 줌) → 34판 해시·JS 정답 자료는 그대로.

JS 화면 파일은 레포 뿌리 `client/`·`shared/`·`node_modules/three` 에서 서빙 (뿌리는 자동으로 찾음, 아니면 `TF_ROOT`). 로그는 JS 서버와 같은 `logs/<서버 시각>/<방 시각>_<코드>.txt`, 줄마다 `[13시 5분 7초] …` (JS `toLocaleTimeString('ko-KR')` 와 같음) → `npm run stats` 가 그대로 읽음.

## 봇 판 시뮬레이션 (`npm run sim` 의 C# 판, S7)

```
dotnet run -c Release --project godot/server/src/Tetrafall.Sim -- --rounds 200 --players 2,4   # 옵션은 tools/sim.js 와 같음 (--maps --chars --level --sky --seed --workers --no-mirror --no-log --out --base --mode --hp --hp-mult)
```

`--events on` (고도 판 전용, 기본 off): 돌발 이벤트 (블록 폭우·돌풍·보급·저중력·빙판·번개 — `Game.Events.cs`, 수치 `ConfigEvents.cs`) 를 켠 판. 로그에 `  [이벤트] …` 줄, summary.json `options.events`. 끄면 예전과 같은 판

`--items on` (고도 판 전용, 기본 off): 방 옵션 '필드 아이템' (`Game.SetFieldItems` — `Game.Items.cs`) 을 켠 판. 판마다 `ITEM_POOL` 6종이 필드에 나옴 (첫 `ITEM_FIRST_SPAWN_MS` 4초, 다음까지 `ITEM_RESPAWN_MS` 6초, 동시에 `ItemMax()` = round(2 × 면적비) 개 — 블록 마스터 판에도, 연습·튜토리얼은 안 나옴. 전역 `ITEMS_ENABLED` 는 끈 채). 로그에 `  [아이템] …`·`[투척]`·`[발사]`·`[폭탄]` 줄, summary.json `options.items`. 끄면 예전과 같은 판 (rng 도 안 부름 — `FieldItemTests`)

`--tune <캐릭터.키=값,…>` (고도 판 전용, 예 `--tune ninja.kbTaken=0.95,hook.kbDealt=1.1`): 이 실행의 판들만 캐릭터별 수치를 덮어씀 (`Tune.cs` — 판마다 `new Game(…, tune:)`, 전역 표 `C.*` 는 안 고침). 키 6개: 배율 `kbTaken` (받는 넉백)·`kbDealt` (주는 넉백)·`dmgDealt` (주는 피해 %)·`skillCd` (F 쿨타임)·`ultGain` (필살기 게이지 — 건축가 블록 폭발 패시브 `BUILDER_BLAST_ULT` 는 제외) — 없으면 1, 그리고 `hpMult` (체력전 HP — 배율이 아니라 `HP_CHAR_MULT` 대신 쓰는 값, `--hp-mult` 와 같은 뜻. 같은 캐릭터가 둘 다에 있으면 `--tune` 이 이김). 모르는 캐릭터·키, 0 이하는 종료 코드 1. `모드:캐릭터.키=값` (예 `kills:ninja.kbDealt=1.6`, 모드는 survival·master·kills) 은 그 모드 판에서만 바꿈 (모르는 모드도 종료 코드 1). 우선순위 (`--balance on` 일 때): 모드 없는 `--tune` 값은 모든 모드에서 이김 (표의 킬 덮기 같은 자리도), `모드:` 값은 그 모드에서만 이김. summary.json `options.tune` (줬을 때만, 모드 값이 있으면 끝에 `modes`). 안 주면 예전과 같은 판

`--balance on` (고도 판 전용, 기본 off): 서버 방과 같은 밸런스 표 (`ConfigBalance.cs` `C.BALANCE` + 킬 점수전 덮기 `C.BALANCE_KILLS`) 로 돌림 — 킬 점수전 밖은 `--tune <C.BALANCE 글자>` 와 같은 판. `--tune` 을 같이 주면 표 위에 덮음 (같은 캐릭터·키면 `--tune` 이 이김), 그 위에 `--hp-mult`. summary.json `options.balance` (켰을 때만). 끄면 예전과 같은 판·같은 summary.json. 표를 고치면 `--rounds 1000 --players 2,4,8 --balance on` 을 시드 1·2·3 으로 돌려 ×기대 평균을 봄 (킬 표는 `--rounds 300 --players 4,8 --mode kills --balance on`)

같은 옵션·시드면 JS 와 같은 판·같은 summary.json (`out` 칸만 다름)·같은 워커 로그 (워커 수도 같으면) — `npm run stats -- sim-logs/<시각>` 그대로. 4코어에서 JS 의 약 1.8배 빠름 (252판: JS 20.3초 / C# 11.1초)

## 한 파일로 내보내기 (S7)

```
dotnet publish godot/server/src/Tetrafall.Server -c Release -r win-x64   --self-contained -p:PublishSingleFile=true -o out/win     # Tetrafall.Server.exe (약 100MB, .NET 설치 필요 없음)
dotnet publish godot/server/src/Tetrafall.Server -c Release -r linux-x64 --self-contained -p:PublishSingleFile=true -o out/linux   # Tetrafall.Server
```

실행은 레포 뿌리에서 (화면 파일 `client/`·`shared/`·`node_modules/three` 를 위로 찾음, 아니면 `TF_ROOT=레포 경로`). `PORT=3000` 이 기본

## 배포 묶음 (G7): 서버 + 고도 웹 + 고도 PC 클라 zip

```
node godot/server/tools/package.mjs --godot <고도 4.7.2> [--targets win,linux] [--cloudflared] [--web-template <zip>]   # → dist/tetrafall-win-x64.zip, dist/tetrafall-linux-x64.zip
```

- 폴더: `Tetrafall.Server(.exe)` + `web/` (고도 웹 빌드) + `tetrafall.exe`/`tetrafall.x86_64` (PC 클라) + `start-lan`·`start-online` (.bat/.sh) + `README.txt` (+ `cloudflared` 를 `--cloudflared` 로 GitHub 에서 받아 넣음)
- 서버는 exe 옆에 `web/index.html` 이 있으면 그 폴더가 뿌리 (배포 폴더): `/play/` = `web/`, JS 화면이 없으니 `/` → `/play/` (302, `?room=` 그대로). 레포·배포 어느 쪽도 아니면 exe 폴더로 뜸 (웹소켓만, PC 클라용)
- 웹 미리 압축: `web/` 파일마다 `.br` (brotli 11, 창 24) + `.gz` (gzip 9) → 서버 `StaticFiles.Precompressed` 가 Accept-Encoding 따라 br > gzip > 날것 (`Content-Encoding`·`Vary: Accept-Encoding`, 형식은 날것 이름). 엔진 wasm 39.5MB → br 6.9MB · gz 10.2MB (압축 약 1분 40초)
- 서버 한 파일 약 52MB (`PUBLISH_FLAGS`: 안에서 압축·InvariantGlobalization, 트리밍 안 함 — ASP.NET), IIS 용 aspnetcorev2_inprocess.dll·web.config·staticwebassets.endpoints.json 은 뺌, web/ 에 고도 `*.import` 안 넣음, zip 파일 날짜 = 묶은 시각
- `--web-template <zip>` (또는 `GODOT_WEB_TEMPLATE`) = 직접 빌드한 웹 템플릿 (`godot/client/tools/build-web-template.sh`, wasm br 6.9 → 5.4MB): 웹 내보내기 동안만 `export_presets.cfg` 웹 `custom_template/release` 를 바꾸고 되돌림 (Ctrl+C 로 끊기면 옆의 `.orig` 를 다음 실행이 먼저 되돌림). 안 주면 공식 템플릿
- `--no-godot` = 이미 내보낸 `godot/client/build/` 를 씀. zip 은 node 만으로 씀 (유닉스 실행 비트 유지)
- GitHub Release: `.github/workflows/release.yml` 이 같은 묶음을 Actions 에서 만들어 Release 에 zip 두 개를 올림. 태그 `v*` 를 push 하거나, 아무 브랜치에 커밋 메시지로 `[release v0.1.0]` 를 넣어 push (태그는 GitHub 쪽에서 그 커밋에 만들어짐), 또는 main 에 이 파일이 있으면 Actions 탭 'Run workflow'. 이름에 `-` 가 있으면 미리보기(prerelease). 약 10분. **작은 웹 템플릿 직접 빌드는 기본 끔** (공식 템플릿): 켜려면 저장소 변수 `WEB_TEMPLATE_BUILD=true` (Settings > Secrets and variables > Actions > Variables, 이후 모든 릴리스) 또는 'Run workflow' 의 `web_template` 체크 (그 실행만). 켜면 `web-template` job 이 캐시가 없을 때만 40~60분 (캐시는 그 브랜치·main 것만 보임, 빌드가 실패하면 공식 템플릿으로 묶음) — 한 번 캐시에 들어가면 다음부터 몇 분이라 그때 변수를 켜 두면 됨
- 배포 안정성 (W36): cloudflared 는 `--cloudflared-cache <폴더>` (환경 변수 `CLOUDFLARED_CACHE`, 플랫폼별 `<폴더>/<rid>/<이름>`) 에 보관돼 있으면 네트워크를 안 씀. 못 받으면 (한 번 최대 60초 × 3번, 전체 `--cloudflared-budget` 기본 600초) 그 플랫폼 zip 은 cloudflared 없이 만들고 경고 + `README.txt` 맨 앞에 '직접 설치' 안내 + `dist/release-notes.md` (워크플로가 릴리스 노트에 덧붙임). 실패로 만들려면 `--require-cloudflared`. 워크플로는 `actions/cache` 로 cloudflared 를 태그별 보관 (`cloudflared-<최신 태그>`; 태그 조회가 안 되면 가장 최근 캐시만 꺼냄)
- Actions 로그 읽는 법 (W36): 릴리스 실행 → `package` job → 단계 '묶기' 로그에서 `받는 중:` / `받기 실패 (n/3)` / `cloudflared 캐시 사용` / `cloudflared 를 못 넣음` (Actions 주석 경고) 을 찾음. 실행 요약(Summary) 에 '웹 템플릿: 직접 빌드/공식' 한 줄과 cloudflared 안내가 있음. '고도 + 내보내기 템플릿' 단계의 `내려받기 실패 (i/5)` 는 재시도 중이고 `포기` 가 나오면 그때 실패
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
| `node godot/server/tools/trace.mjs <번호> js.jsonl` | JS 판 시나리오 하나를 틱마다 기록 (`--list` 로 34개 목록, `tools/game-hash.js` 와 같은 판). `h<번호>` = 그 판을 체력전 켜고 (캐릭터별 HP 검증, 34판 해시엔 안 들어감). `s0`~`s7` = 각본 입력 판 (`tools/scripted.mjs`: 사람만·캐릭터 끔, 봇(S5) 전에 판 흐름·블록을 맞추는 판) |
| `node godot/server/tools/trace-scripted.mjs <캐릭터> js.jsonl` | 봇 없는 각본 판 (S3 전투·캐릭터 검증): 캐릭터마다 사람 둘이 정해진 틱에 평타·스킬·필살기·점프·대시, 킬 점수전·블록 없음, 600틱. `--list`, `--dump scripts.json` (C# 가 같은 각본을 돌릴 자료) |
| `dotnet run --project godot/server/src/Tetrafall.Trace -- trace <번호> cs.jsonl [--ticks N]` | 같은 판을 C# 로 같은 JSONL (아직 안 옮긴 메서드에 닿으면 거기까지 쓰고 멈춤). `c<번호>` = CS 판 (아래 `cshash`, `--list` 끝에 목록) |
| `dotnet run --project godot/server/src/Tetrafall.Trace -- hash [--verbose]` | `node tools/game-hash.js` 와 같은 해시 (34판 다 돌면 = 규칙 이식 끝) |
| `dotnet run --project godot/server/src/Tetrafall.Trace -- cshash [--verbose] [--write <경로>]` | 고도 판 전용 C# 자체 기준선: `Scenarios.CS` 14판 (시드 2001~, 맵 7개, 캐릭터·하늘 계단·밸런스 표 + 돌발 이벤트 — 생존·킬 점수전·팀·체력전·봇 대리, 블록 마스터는 이벤트 켜도 안 돎, 연습은 밸런스 표만, 끝 두 판은 필드 아이템 옵션 켬) 의 틱별 해시 (`hash` 와 같은 방식, JS 와 비교 안 함). 끝 줄 `cs 판 N개 해시 … (틱 합 T, X초)`, `--verbose` 판마다 `해시16 틱 phase 이름`, `--write` = `[[이름, 해시, 틱, phase], …]` 한 판 한 줄 → `tests/Tetrafall.Tests/fixtures/cs-hash.json` (`CsHashTests`) |
| `node godot/server/tools/tutorial-trace.mjs <캐릭터> js.jsonl` | 튜토리얼 판 (자동 조종 `shared/tutorial-pilot.js` 으로 끝까지, S4 검증). C# 는 `Tetrafall.Trace trace tut:<캐릭터>` (`TutorialPilot.cs`) |
| `node godot/server/tools/scenario-logs.mjs <폴더>` · `dotnet …Tetrafall.Trace.dll logs <폴더>` | 34판 로그를 방 로그 파일 모양으로 (양쪽 같은 파일 → `npm run stats -- <폴더>` 비교) |
| `node godot/server/tools/load.mjs [틱]` · `dotnet …Tetrafall.Server.dll load [틱] [--serial] [--prof]` | 서버 부하: 진짜 Rooms·가짜 소켓, 방 4개 × 8명 (사람 1 + 봇 7) 의 서버 루프 한 번 (rooms.tick + broadcast) 시간 평균·중앙값·99%·최대·16ms/33ms 넘은 틱 수. `--serial` 방을 한 스레드에서 차례로 (예전), `--prof` 구간 표 (봇·블록 자리 고르기 spawn·낙하·착지·물리·전투·나머지·스냅샷) + 느린 틱 10개 (`Profiler`, Game.prof) |
| `xvfb-run -a node godot/server/tools/cs-e2e.cjs <스샷 폴더> [주소]` | 실전 확인: JS 화면을 서버에 붙여 8명 판 모드 3개 끝까지·결과·다음 판, 연습·튜토리얼 (페이지 에러 0) |
| `node godot/server/tools/trace-diff.mjs js.jsonl cs.jsonl` | 두 기록에서 처음 갈라지는 틱·JSON 경로·ulp |
| `xvfb-run -a node godot/server/tools/lobby_shot.cjs <폴더> [주소]` | 기존 JS 화면을 이 서버에 붙여 메뉴·대기실 스샷 |

**C# 기준선 다시 고정 규칙** (`cs-hash.json`): 규칙·봇·돌발 이벤트를 의도해 바꾼 커밋만 `cd godot/server && dotnet run --project src/Tetrafall.Trace -- cshash --write tests/Tetrafall.Tests/fixtures/cs-hash.json` 로 다시 고정하고, 커밋 메시지에 바뀐 판 이름과 까닭을 적는다. 성능·정리 커밋은 해시가 그대로여야 하며 다시 고정하지 않는다 (떨어지면 그 커밋이 길을 바꾼 것). 34판 `game-hash.json` 은 JS 정답 자료라 여기서 다시 뽑지 않음

- 2026-11-17 c10 방 옵션 '필드 아이템' (`fieldItems`, 기본 끔) 때 다시 고정: 필드 아이템 옵션 판 2개 추가 (기존 12판 값 그대로), 14판으로 다시 고정. 끝에만 더함 — `cs 4명 생존 필드 아이템` (시드 2013, 맵 `MAP_IDS[12 % 7]`, 이벤트 끔·아이템 켬, 3322틱)·`cs 8명 킬 점수전 필드 아이템 이벤트` (시드 2014, 맵 `MAP_IDS[13 % 7]`, 이벤트·아이템 켬, 2597틱에 목표 킬). 앞 12판은 이름·시드·맵·해시·틱이 한 글자도 안 바뀜 (옵션을 끈 판은 `FieldItemsRun()` 이 false 라 새 길을 안 탐 — 스냅샷에 `fieldItems` 키도 없음), 34판 해시 `bf2e2951…` 그대로. `cs 판 14개 해시 ed260619…46db9b` (틱 합 25413 → 31332). 규칙은 `FieldItemTests`
- 2026-11-17 c9 리뷰 지적 고치기 (번개 F3·F4·F7) 때 다시 고정: 번개가 도는 3판이 바뀜 (`cs 8명 생존 팀 이벤트` 틱 3035 → 3010 · `cs 4명 킬 점수전 이벤트` · `cs 8명 킬 점수전 이벤트`, 틱 합 25438 → 25413). 까닭 — F3: 예고 높이가 기둥 꼭대기 (`ColumnTop`) 가 아니라 대상 발 높이 (`BoltWarnZ`: 서 있으면 발 높이, 공중이면 발밑 아래 첫 블록 윗면) → 머리 위 처마 밑에 선 대상이 이제 맞고 `boltWarn`·`bolt` 이벤트의 `z` 가 달라짐. F4: 봇이 발 높이 차가 판정 밖 (`EVENT_BOLT_HEIGHT` 넘음) 인 예고는 안 피함. F7: 탱크 아머가 번개를 버틴 로그의 때린 쪽이 `?` → `번개`. 나머지 9판 (번개가 안 뽑히거나 처마·높이 차·아머에 안 걸린 판, 블록 마스터·연습) 과 34판 해시 `bf2e2951…` 는 그대로. 규칙은 `EventBoltTests` (처마 +2·+3·+5칸, 공중, 봇 높이, 탱크 아머)
- 2026-11-17 c9 돌발 이벤트 '번개' (`EVENT_KINDS` 5→6, 끝에 `bolt`) 때 다시 고정: 종류 고르기가 floor(r×5)·floor(r×4) → floor(r×6)·floor(r×5) 로 바뀌어 이벤트가 도는 9판 중 6판이 바뀜 (`cs 8명 생존 이벤트`·`cs 8명 생존 팀 이벤트`·`cs 4명 킬 점수전 이벤트`·`cs 8명 킬 점수전 이벤트`·`cs 4명 킬 점수전 팀 체력전 이벤트`·`cs 4명 생존 체력전 이벤트` — 뽑히는 종류가 달라지고 번개가 섞임, 봇이 번개 예고를 피함). `cs 2명 생존 이벤트`·`cs 4명 생존 이벤트`·`cs 4명 생존 끊긴 사람 봇 대리 이벤트` 는 그 판에서 뽑힌 종류가 6종에서도 같아 그대로, 블록 마스터 2판·연습 (이벤트가 안 돎) 도 그대로. 34판 해시 `bf2e2951…` 그대로 (이벤트를 끈 판은 새 길을 안 탐). 번개 규칙은 `EventBoltTests`
- 2026-11-15 병합 (최신 고도 작업 `6ba2e4d` 를 합침) 때 다시 고정: 최신 쪽 규칙 변경 둘 때문에 12판 중 3판이 바뀜 (틱 수·끝 phase 는 그대로, 34판 해시는 최신 쪽 값 `bf2e2951…` 과 같음 = 이벤트·밸런스 표를 끈 규칙은 온전). `cs 8명 생존 이벤트`·`cs 8명 킬 점수전 이벤트` — 마지막 틱 한 줄만 다름: 판이 끝날 때 바드 폼이 metal → bard 로 돌아감 (`fffd995` '바드 판 끝 음유시인 폼'). `cs 4명 생존 이벤트` — 틱 2067 부터: 판 밖 (y < 0) 에 나간 봇의 yaw 가 달라짐 (`bd2dc9e` S10 `columnTop` 판 밖 검사 — 예전엔 판 밖 칸이 옆 칸 높이로 읽혀 봇이 엉뚱한 쪽으로 돎) + 마지막 틱은 위 바드 폼 변경 (`fffd995`) 도 같이 받음 — 이 판에 바드가 있어 둘 중 하나만 넣어도 판 해시가 달라짐 (2×2 확인: 둘 다 없음 `35b5…` · 바드 폼만 `ce96…` · S10 만 `04de…` · 둘 다 `416f…`). 확인: 병합 전·뒤 `trace c<번호>` 를 `tools/trace-diff.mjs` 로 비교

## 구조

- `src/Tetrafall.Core/` — 규칙 (`Game.cs` + 묶음 `Game.<묶음>.cs` partial, `Player.cs`), `Js/` = JS 와 같은 숫자 부품 (`JsMath` V8 수학, `JsNumber` 숫자 글자·toFixed, `JsonOut` JSON.stringify, `Mulberry32`)
- `src/Tetrafall.Server/` — `Program.cs` (Kestrel·정적 파일 (+ `/play/` = 고도 웹 빌드 godot/client/build/web)·잘못된 주소 400·WebSocket (NET_MAX_PAYLOAD_BYTES 넘으면 그 연결만 1009)·30Hz 루프 스레드 하나·표준 입력 터널 주소), `Rooms.cs` (rooms.js 전부, `OrderedMap` = JS Map 순서. 방마다 게임 틱·스냅샷 글자는 병렬 `Parallel.For` — 방끼리 공유 상태 없음, 끊김 만료·방 닫기·보내기는 루프 스레드에서 방 순서대로), `WsSocket.cs`, `StaticFiles.cs` (resolveFile·배포 폴더 `web/`·방 로그 파일), `Tunnel.cs` (`--online` 터널)
- `src/Tetrafall.Sim/` — 봇 판 시뮬레이션 (`Sim.cs` = tools/sim.js planJobs·runJob·runParallel·summarizeSim·formatSim, summary.json 은 JSON.stringify(…, null, 1) 모양)
- `src/Tetrafall.Trace/` — 판 기록기: `Scenarios.cs` (game-hash.js 시나리오 34개·runScenario 그대로), trace JSONL·해시
- 아직 안 옮긴 메서드는 `Game.Todo.cs` (부르면 NotImplementedException, 괄호 = 작업 id). 옮기면 거기서 지우고 묶음 파일에
- `tests/Tetrafall.Tests/` — `JsCompatTests`, `ProtocolTests` (JS rooms.js 와 같은 각본 → 같은 메시지 25개·로그 12줄), `RoomScenarioTests` (`tools/room-scenarios.mjs` 각본 5개 — 재접속·방 안 설정·상한·예외 격리·빈도 제한 — 를 C# 로 돌려 JS 와 메시지·로그 글자까지 같음), `RoomsUnitTests` (JS 값 바꾸기·이름 정리·긴 글자·빈도·토큰), `ServerProcessTests` (진짜 프로세스: 잘못된 주소 400·큰 메시지 1009·터널 주소·로그 파일 줄 모양), `S1Tests` (시작 지형 70개·물리 21판 비트·판 시작 trace 33판이 JS 정답 자료와 같음, 물리 단위 테스트), `S2Tests` (각본 판 8개 trace 전체가 JS 와 같음 + modes·sky·ghost 테스트 중 전투·봇·연습이 안 끼는 것), `SimTests` (sim.js 작은 판의 요약·화면 표·로그가 JS 와 같음, 워커 수와 상관없음), `S5Tests` (hp·master·킬 점수전·botpos), `AuditTests` (2026-10-30 코드 감사 S1·S3~S10·T3~T5 — JS `test/w1-audit.test.js` 와 같은 내용), `S4Tests` (game-hash 34판 중 C# 가 다 도는 판의 해시가 JS 와 같음 — 안 옮긴 곳에 닿는 판은 건너뜀, 튜토리얼 자동 조종 판 trace, practice·tutorial 테스트), `CsHashTests` (고도 판 전용 C# 자체 기준선: `Scenarios.CS` 판 해시·틱이 `fixtures/cs-hash.json` 과 같음, 돌발 이벤트 `EVENT_KINDS` 의 모든 종류(지금 6종)가 다 나오고 블록 마스터 판엔 0번, 밸런스 표를 빼면 해시가 달라짐, 고정 파일 이름 = CS 순서 그대로)
