# 고도 이전 설계 (0단계, 2026-10-31)

재혁 결정 (2026-10-31): 고도로 간다. 서버 규칙은 전부 C#, 클라는 고도 GDScript (웹 + PC), JS 판은 얼리고 버그만 고침.
첫 목표 = 넘어가는 시점: 규칙 전부 (캐릭터 8명·아이템·모드 3개·체력전·봇·방·재접속) + 기본 화면 (툰·HUD·대기실). 타이틀·래그돌·테마 꾸밈은 다음.

## 1. 결정

| 무엇 | 고른 것 | 왜 |
| --- | --- | --- |
| 서버 | **고도 없는 순수 .NET 10 LTS 콘솔** (ASP.NET Core Kestrel, `System.Net.WebSockets`) | `dotnet test`(xUnit)·병렬 sim(`Parallel`)·배포(`dotnet publish`, 윈도우 한 파일)가 다 쉬움. 고도 .NET 헤드리스는 엔진 75MB+·고도 .NET 판 따로 받기·테스트 러너가 불편, 서버엔 그리기가 없어 얻을 게 없음. .NET 10 = 2028-11 까지 지원 (.NET 8 은 2026-11 끝) |
| 프로토콜 | **JS 서버와 똑같이** (메시지 종류·스냅샷 JSON 키 순서·숫자 글자까지) | ① 기존 JS 화면이 C# 서버에 붙어 서버 이식을 따로 검증 ② 고도 클라는 그동안 JS 서버에 붙어 개발 → 두 일이 서로 안 기다림. 뼈대에서 확인: JS 화면이 C# 서버 대기실에 붙음 (스샷) |
| 이식 완료 기준 | **판 단위 동등성**: `tools/game-hash.js` 시나리오 34개를 C# 이 돌려 틱마다 스냅샷·이벤트·로그가 JS 와 글자까지 같음 | 사람 손 테스트 없이 '같은 게임' 을 보장. 갈라지면 `trace-diff` 가 처음 갈라진 틱·JSON 경로를 짚음 |
| 숫자 | JS 처럼 전부 `double`, 수학은 `JsMath` | 아래 2절 |
| 클라 | 고도 4.7 GDScript, 렌더러 Compatibility (웹), 시제품 측정대로 무거운 계산 없음 | 서버 권위라 클라는 그리기·입력만 |

## 2. 같은 숫자 내기 (뼈대에서 잰 것)

같은 입력 100만 개로 node 22 와 .NET 10 비교:

| 함수 | System.Math | `JsMath` (V8 의 fdlibm 옮김 + V8 hypot) |
| --- | --- | --- |
| sin / cos | 3.3% / 3.4% 가 1 ulp 다름 | 0 |
| exp | 9.9% | 0 |
| atan2 | 17.5% | 0 |
| hypot | 37.9% (최대 2 ulp) | 0 |
| sqrt·floor·abs·min·max | 같음 | (System.Math 그대로) |
| Math.round | C# Math.Round 는 짝수 쪽 반올림 → 다름 | `JsMath.Round` |
| 숫자 → 글자 (JSON.stringify) | .NET "R" 은 3022개 중 942개 다름 (`-0`, `1E-07`, `1E+21`) | `JsNumber.ToJs` 0 |
| toFixed | .NET "F" 는 딱 반이면 짝수 쪽 (0.125 → 0.12) | `JsNumber.ToFixed` 0 |

→ 규칙 코드는 `Math.Sin` 대신 `JsMath.Sin` 등. 테스트 `JsCompatTests` 가 정답 자료(`tools/fixtures.mjs`)로 고정.

## 3. 옮길 때 규칙 (모든 세션 공통)

1. **파일 = JS 묶음 그대로**: `server/game-pieces.js` → `src/Tetrafall.Core/Game.Pieces.cs` (`partial class Game`), `char-ninja.js` → `Game.CharNinja.cs`, `bot.js` → `Bot.cs`, `rooms.js` → `Tetrafall.Server/Rooms.cs`. 메서드 이름은 JS 이름의 PascalCase (`crushCheck` → `CrushCheck`), 필드는 JS 이름 그대로 (`p.stunUntil`)
2. **수치는 `C.이름`** (`tools/gen-config.mjs` 가 shared/config.js 에서 만든 `Config.g.cs`, JS 와 같은 이름). 표(객체 배열) 37개는 아직 → 그 묶음 세션이 생성기를 늘림. 코드에 숫자 박지 않기
3. **수학**: `JsMath.Sin·Cos·Atan2·Exp·Hypot·Round·Sign`. `Math.Floor·Abs·Min·Max·Sqrt·Ceil` 은 그대로 (JS 와 같음)
4. **숫자는 double** (JS 와 같은 반올림). 정수 변환은 JS 의미대로: `Math.floor(x)` → `Math.Floor`, `x | 0` → `(int)(long)x` 가 아니라 JS ToInt32 (도움 함수 만들 것), `>>> 0` → `(uint)`
5. **순서**: JS `Map`·객체 키는 넣은 순서 → `game.Players()` (넣은 순서 목록). C# `Dictionary` 를 그대로 돌리지 말 것 (지운 뒤 순서가 바뀜). **JS `Array.sort` 는 안정 정렬, C# `List.Sort` 는 아님** → LINQ `OrderBy` (안정) 를 쓸 것
6. **난수 호출 순서**: `rng()` 를 부르는 곳·순서가 JS 와 한 번이라도 다르면 판이 갈라짐. 조건 분기 안의 `rng()` 도 그대로
7. **JSON**: 스냅샷·이벤트는 `JsonOut` 으로 JS 와 같은 키 순서. JS 에서 `undefined` 인 필드는 안 씀, `Infinity`·`NaN` 은 null. 이벤트는 `game.Emit(o => o.P("type","land")...)`
8. **로그 글자**: `${x}` → `JsNumber.ToJs(x)`, `x.toFixed(1)` → `JsNumber.ToFixed(x, 1)`. 로그는 해시에 들어가고 `npm run stats` 가 읽음
9. **검증 순서**: 묶음 하나 옮기면 → 그 묶음 단위 테스트 (JS test/*.test.js 중 해당 부분) → 그 묶음이 들어가는 trace 시나리오 → `trace-diff` 로 처음 갈라진 곳 고침

## 4. 폴더

```
godot/
  PLAN.md            이 문서
  README.md          개요
  server/            C# 서버 (.NET 10)
    Tetrafall.sln
    src/Tetrafall.Core/     규칙 (Game.*.cs, Player, Bot, Config.g.cs, Maps.g.cs, Js/ 호환 부품) — 고도·네트워크 없음
    src/Tetrafall.Server/   Kestrel: 정적 파일(JS 화면)·WebSocket·틱 루프·Rooms·로그 파일
    tests/Tetrafall.Tests/  xUnit (fixtures/ = JS 가 뽑은 정답)
    tools/                  node: gen-config·fixtures·trace·trace-diff·lobby_shot
  client/            (다음) 진짜 고도 클라 — 새 프로젝트
  prototype/         고도 시제품 (1·2단계, 참고용. 규칙 GDScript 는 버림)
```

## 5. 작업 목록 (세션에 나눠 줄 것)

크기는 '세션 × 일' (긴 세션 하루 = 1). JS 줄 수는 옮길 원본.

### 서버 (C#)

| id | 작업 | 원본 (JS 줄) | 크기 | 먼저 끝나야 | 끝 기준 |
| --- | --- | --- | --- | --- | --- |
| S0 | 뼈대 (이 커밋) | — | 끝 | — | 테스트 5개, JS 화면이 대기실에 붙음 |
| S1 | 바닥: 격자·물리·입력·판 크기·시작 위치·맵 지형·config 표 생성기·C# trace 기록기(`Tetrafall.Trace`, trace.mjs 와 같은 JSONL)·`tools/game-hash` C# 판 | game-grid 67, game-physics 192, game-input 99, shared/maps 213, pieces 52, game-util 141 | 2 | S0 | 단위 테스트 (game.test 물리 부분) + 대기실→판 시작 trace 첫 틱 같음 |
| S2 | 판 흐름·블록: 판 시작/끝·사망·부활·점수·모드 3개·체력전·블록 낙하·조종·압사·층 지우기·용암·유령 투하·자리 고르기(하늘 사슬·CLEAR_BIAS) | game-round 474, game-pieces 550, game-placement 387 | 3 | S1 | modes·sky·ghost·hp·master 테스트, 캐릭터 끈 trace 시나리오 (봇 S4 전에는 각본 입력 시나리오) |
| S3 | 전투·캐릭터 8명: 대시·밀치기·평타·스킬/필살기·넉백·콤보·카운터 + tank·ninja·hunter·bard·berserker·cannon·builder·hook | game-combat 580, char-* 1460 | 3~4 (캐릭터 둘로 나눠 2세션 가능) | S1 (S2 와 같이 가도 됨) | characters·windup·quake 테스트, 캐릭터 켠 trace |
| S4 | 아이템·연습·튜토리얼 | game-items 360, game-practice 166, tutorial 190 | 1.5 | S2 | practice·tutorial 테스트, 연습 trace |
| S5 | 봇 (+ 끊긴 사람 봇 대리) | bot.js 1135 | 2~3 | S2·S3 | botpos 테스트, **trace 34개 전부 같음 = 규칙 이식 끝** |
| S6 | 방·네트워크 나머지: 방 안 메시지 전부·재접속(토큰·자리 유지)·연습/튜토리얼 방·공개 방·빈도 제한·방 하나 예외·로그 파일·`npm run stats` 호환·`online.js` 가 C# 서버를 켜게 | rooms 487 (뼈대 250 옮김), index 202, online | 2 | S0 (판 메시지는 S2~S4 와 맞물림) | rooms·rejoin·safety 테스트를 C# 로, **JS 화면으로 C# 서버에서 8명 판 한 판** |
| S7 | sim·배포: `npm run sim` 같은 C# 병렬 sim (summary.json 같은 형식), `dotnet publish` 윈도우·리눅스 한 파일, 실행 안내 | tools/sim 301 | 1~1.5 | S5 | JS sim 과 같은 시드면 같은 summary |

서버 합계 약 **15~17 세션·일**, 동시에 3줄 (S2·S3·S6) 이면 달력으로 약 6~7일.

### 클라 (고도 GDScript, JS 서버에 붙어 개발)

| id | 작업 | 원본 (JS 줄) | 크기 | 먼저 | 끝 기준 |
| --- | --- | --- | --- | --- | --- |
| G0 | 뼈대: `godot/client` 프로젝트, 네트워크(같은 프로토콜·재접속 토큰 `seat.js`)·스냅샷 저장·보간(`interp.js`)·입력·키 설정(`keys.js`, `input.js`)·핑(`net.js`) | net 85, interp 69, input 173, keys 96, seat 27, shared/net 81 | 2 | — | JS 서버 방에 들어가 움직이고 판이 돎 (상자 그림) |
| G1 | 판 그리기: 격자 블록(블록 모습 단순판)·떨어지는 블록·그림자·위험(용암) 기본·카메라 1·3인칭·관전(`camera.js`)·하늘 시점(`sky-view`, `sky-aids`) | render 일부, blocks 401, piece-look, hazard 605 일부, camera 36, sky 128 | 3 | G0 | 8명 판이 보임, 30fps+ |
| G2 | 캐릭터 몸: 8명 체형(`FIGURE_BODIES`)·공격 동작 `MOVES`·포즈·걸음·버릇 (`figure.js`·`figure-pose.js`·`character.js`), 1인칭 팔 (`viewmodel.js`) | figure 2233, figure-pose 118, character 360, viewmodel 357 | 5 (몸 만들기 / 동작 둘로 나눌 수 있음) | G0 | 8명이 JS 판과 같은 모양·동작 (나란히 스샷) |
| G3 | 툰·외곽선 셰이더·테마 색 (`toon.js`, `textures.js` 핵심, `WORLD_THEMES` 색만) | toon 47, textures 401 일부, world 일부 | 2 | G1 | JS 판과 나란히 비슷 |
| G4 | HUD·대기실·메뉴·결과 (빛 사선 스타일, 스매시식 % 판, 캐릭터 고르기·초상, 킬 점수전·체력전 HUD, 설정·키 설정, 전환 슬래시) | main 2917, index.html 791, hud-layout, kills-hud, char-select, wipe, portrait 128, char-stage 124 | 5 (메뉴·대기실 / 판 HUD·결과 둘로) | G0 | JS 판 화면 순서·기능 그대로 |
| G5 | 효과·소리: 타격 파편·KO 연출(`ko.js`)·효과음 파일(`sound.js`)·합성 음악(`music.js` → AudioStreamGenerator) | effects 185, ko 177, sound 586, music 385, hit-tier | 3 | G1·G2 | 소리·KO 연출 같음 |
| G6 | 연습·튜토리얼 화면·건축가 블록 모습(`bblocks.js`)·성능 표시(F3) | tutorial-ui 164, bblocks 281, perf 137 | 2 | G4 | 튜토리얼 끝까지 |
| G7 | 내보내기: 웹 (서버가 같이 서빙) + 윈도우·리눅스 실행 파일 | — | 1 | G0 | 재혁 PC 에서 실행 |
| (다음) | 타이틀·래그돌·테마 꾸밈(섬·무대·판 빛·대기실 어두운 장면) | title* 1300, ragdoll 400, world 1158, lobby-dark, game-light | 6+ | 첫 목표 뒤 | — |

클라 합계 (첫 목표까지) 약 **23 세션·일**, G1·G2·G4 를 동시에 하면 달력으로 약 8~10일.

### 순서·의존 (한눈에)

```
서버: S0 ─ S1 ─┬─ S2 ─┬─ S4 ─┐
               ├─ S3 ─┤      ├─ S5 ── (trace 34개 같음) ── S7
               └─ S6 ─┘──────┘
클라: G0 ─┬─ G1 ─┬─ G3
          ├─ G2 ─┼─ G5
          ├─ G4 ─┴─ G6
          └─ G7
넘어가는 시점 = S5·S6 끝 (C# 서버가 JS 서버를 대신) + G0~G6 끝 (고도 클라가 JS 화면을 대신)
```

- S2 와 S3 는 같은 `Game` 에 손대지만 파일이 달라 (partial) 충돌이 적음. `Player` 필드는 둘 다 더하니 같은 브랜치에서 자주 합칠 것
- S5 (봇) 전에는 trace 시나리오가 봇을 써서 못 돎 → S2·S3 는 각본 입력 시나리오 (`trace.mjs` 에 `--scripted` 추가, 연습 시나리오처럼) 로 먼저 맞춤
- 클라는 서버와 독립 (JS 서버로 개발). 다만 프로토콜을 바꾸는 일은 금지 (바꿔야 하면 JS·C# 둘 다)

## 6. 위험

| 위험 | 대응 |
| --- | --- |
| trace 가 끝없이 갈라짐 (작은 차이 하나가 판 전체를 바꿈) | 묶음마다 바로 맞춤, `trace-diff` 가 처음 틱·경로·ulp 를 짚음. 2절 수학·글자는 이미 맞춤 |
| JS 의 느슨한 타입 (undefined·null·'' 섞임, `||` 기본값) | C# 에선 `?` 타입 + JS 와 같은 기본값. 스냅샷에서 null·undefined 차이는 trace 가 잡음 |
| JS 판이 얼어 있는 동안 버그 고침이 들어옴 | JS 고침 = C# 에도 같은 고침 + fixtures·trace 다시 뽑기. JS 고침 커밋 메시지에 'C# 도' 표시 |
| 고도 웹 크기 (gzip 약 10MB) | 첫 목표엔 PC 실행 파일이 주, 웹은 그대로 (시제품 측정) |
| 헤드리스 크로미움 SwiftShader 에서 고도 웹이 깨져 보임 | 스샷은 Mesa (`WEB_GL=mesa xvfb-run`) — 시제품 README |
