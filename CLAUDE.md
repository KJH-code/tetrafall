# Tetrafall

3D 폴가이즈식 PC 웹 대전. 격자 필드에 테트리미노가 떨어지고 플레이어끼리 밀어 떨어뜨리거나(낙사) 블록에 깔리게(압사) 한다. LAN 또는 인터넷(Cloudflare 터널), 서버 하나에 방 여러 개, 방마다 2~4인 + AI 봇.

DevVault: Projects/Tetrafall
캐릭터 설계 (원본): DevVault `Projects/Tetrafall/Characters/` (overview·common·combos·screen + 캐릭터마다 `<char id>.md`)

## 스택

- Node (서버, `ws`) + three.js (클라이언트). 순수 JS ES 모듈, 빌드 없음
- 서버가 게임 상태의 권위 (30Hz 고정 틱). 클라이언트는 입력 전송 + 렌더링만, 예측 없음
- 게임 물리엔진 없음: 블록은 3D 정수 배열, 플레이어만 AABB 충돌 + 넉백. 몸 모습만 클라에서 cannon-es 래그돌 (`client/ragdoll.js`, 판정과 무관, `RAGDOLL_CHARS` 캐릭터 = 지금 8명 전부. 서버는 `/vendor/cannon-es.js` 로 서빙)

## 명령

```
npm install
npm start        # 호스트 서버 (포트 3000)
npm run online   # 서버 + Cloudflare 터널 (cloudflared 필요) → 친구에게 줄 https 주소
npm test         # 서버 규칙 단위 테스트 (node --test)
npm run stats    # 플레이테스트 로그 요약 (logs/ 최신 서버 실행 폴더, 또는 -- 파일·폴더 경로)
```

Windows PowerShell 에서 npm 이 막히면 `npm.cmd`.

## 구조

- `shared/config.js` — **튜닝 수치는 전부 여기.** 코드에 숫자를 박지 않는다
- `shared/pieces.js` — 테트리미노 모양·회전
- `shared/camera.js` — 관전 궤도 카메라 (three.js 없는 순수 계산, `render.js` 가 씀)
- `client/ragdoll.js` — 액티브 래그돌 (cannon-es): figure 관절마다 몸 조각, 관절 모터가 figureAnim 자세를 따라가고 맞음·경직·낙사엔 힘이 빠져 쓰러졌다 일어남 (골반이 `RAGDOLL_SLUMP` 까지 처짐). 골반은 판정(보간) 위치를 따라감. 관절 각도 제한 `RAGDOLL_LIMITS`, 체형별 무게 `RAGDOLL_WEIGHT`. 1인칭 내 몸은 끔. 순수 계산(모터 세기·PD·끌어당김)은 `client/ragdoll-math.js`
- `client/interp.js` — 플레이어 화면 위치 보간 (three.js 없는 순수 계산, `render.js` 가 씀). 스냅샷을 서버 시각(`state.time`)으로 쌓고 조금 늦은 시각(남 `INTERP_DELAY_MS`, 나 `INTERP_DELAY_SELF_MS`)을 두 스냅샷 사이에서 보간
- `server/game.js` — 게임 상태: 격자, 블록 낙하, 플레이어 물리, 넉백, 사망 판정, 용암, 아이템, 로그, 모드(`mode`: 생존·블록 마스터·킬 점수전). 블록 마스터의 마스터는 살아 있지만 필드에 없음 → 판정 대상은 `onField(p)` 로 고른다. 캐릭터(`char`, 스킬·필살기)는 `new Game(log, { characters: true })` 일 때만 (서버 방은 켬, 예전 규칙 테스트는 끔). 하늘 계단(`sky`, 하늘 블록 사슬·격자 높이 `game.H` 32)도 `{ skyStairs: true }` 일 때만 (방은 `SKY_STAIRS_DEFAULT`). 연습 모드는 `mode: 'practice'` (`startPractice`, 판이 안 끝남, 허수아비 `dummy`, 방 `practice` 는 로그 파일 없음)
- `shared/maps.js` — 시작 지형 (맵 7개 칸 배치, 서버 `server/maps.js` 는 다시 내보내기만, 메뉴 배경도 씀)
- `server/bot.js` — AI 봇 (handleInput / handleAction 만 씀, 판정 특혜 없음)
- `server/index.js` — 정적 서빙 + WebSocket + 틱 루프 + 방마다 로그 파일 (`logs/<서버 시각>/<방 시각>_<코드>.txt`)
- `server/rooms.js` — 방 (게임 + 접속 + 로그). 방 밖 메시지(create·join)와 방 안 메시지 처리, 사람 0명이면 삭제. 테스트는 가짜 소켓
- `client/` — 렌더(`render.js`), 캐릭터(`character.js`), 입력(`input.js`), HUD·네트워크(`main.js`), 효과음(`sound.js`: 몸에 닿는 소리는 `client/assets/sfx/` Kenney CC0 파일 `SFX_BANKS`, 캐릭터 무기 `SFX_WEAPONS`, 남 소리는 카메라 기준 거리·좌우, 위험 액체 지속음 `SFX_HAZARD`, 나머지는 합성), 배경음악(`music.js`: 합성, 대기실 + 맵 테마별 `MUSIC_THEMES`, 위험이 차오르면 `MUSIC_TENSION`), 캐릭터 몸·동작(`figure.js`, 체형 표는 config `FIGURE_BODIES`, 공격 `MOVES`·도발/승리 포즈 `POSES`, 걸음걸이·공중·평소 버릇 자세는 `figure-pose.js` — 순수 계산, 캐릭터별 표 config `FIGURE_GAIT`·`FIGURE_IDLE`, 1인칭·3인칭은 `render.js`, 1인칭 팔·무기는 `viewmodel.js`: 내 몸을 복제해 관절을 베낌), 모델 불러오기(`models.js`, 파일은 `client/assets/` 출처 `CREDITS.md`), 툰 재질·외곽선(`toon.js`), 코드 텍스처(`textures.js`), 조작 키 설정(`keys.js`, 설정 창에서 바꿈, `tf-keys`). 맵 테마(`world.js`: 하늘·바닥·지형 블록 재질·떠 있는 섬·먼 배경·위험 모습, 맵 id → 테마는 config `WORLD_MAP_THEME`·`WORLD_THEMES`, 표에 없는 맵은 예전 노을. 설정 '그래픽 낮춤') 상승하는 위험(용암 자리) 모습(`hazard.js`: 파도 표면·닿는 곳 거품/불꽃 테·잠긴 블록 물들임·차오름 번쩍·화면 가장자리 경고·빠질 때 튀김과 잠김, 소리 훅 `renderer.onHazardRise`. 순수 계산은 `hazard-field.js`) 메뉴(방 목록) 뒤 3D 대기 장면(`menu-scene.js`: 서버 없이 가짜 state — 무작위 맵 섬 + 캐릭터 대기·이모트 + 도는 카메라, renderer 가 state 없을 때 그림, 방에 들어가면 버림) 연습 방 화면(연습 창·허수아비 콤보 기록)은 `main.js`, 허수아비 모양은 `character.js`. KO 연출(스매시 줄기·마지막 킬 슬로모션·압사)은 `ko.js` (소리는 `ko.on`), 접속 상태(핑·렉 알림)는 `net.js` (계산은 `shared/net.js`)
- GUI (2026-10-27 전면 개편, 스매시브라더스식): 화면 모양·애니메이션은 전부 `client/index.html` 의 `<style>` (색·모서리 자르기 등 토큰은 `:root`), 글꼴은 Black Han Sans (OFL, `client/assets/fonts/`, 출처 `CREDITS.md`). 화면 아래 사람마다 초상+큰 % 판은 `main.js` `updatePlayers` (`#players`), 판 끝 승자 초상·결과 표는 `updateResults` (`#results`, 끝나고 `RESULTS_HERO_MS` 동안만 가운데 크게 — 그동안 대기실 판은 숨김, 그 뒤 대기실 판), 대기실 캐릭터 초상 카드는 `updateCharCards` (`#char-cards`, 누르면 숨은 `#char-select` 값을 바꿈). 초상은 `client/portrait.js` — 3D 몸을 화면 밖 캔버스에 그려 dataURL 로 캐시 (게임 장면과 따로). 판이 떠 있으면 `body.cards` 가 켜져 아래 줄(스킬·관전 안내)이 그 위로 올라감. 메뉴 배경 3D 섬 자리는 `#menu-bg`. 접속 표시 `#net` (net.js) 모양도 index.html
- `tools/online.js` — `npm run online` (서버 자식 프로세스 + cloudflared, 출력에서 터널 주소 찾기 → 서버에 IPC 로 알려 대기실 링크 복사가 터널 주소로, 콘솔 주소는 클립보드에 자동 복사. 터널 지키기 `TunnelKeeper`: 실제로 열린 뒤에 알리고, 안 열리거나 죽으면 cloudflared 다시 켬. 설명·고정 주소 안내 `docs/online.md`)
- `tools/prep-sfx.mjs` — 강타 몸통·휘두름 효과음 재료 다듬기 (OpenGameArt CC0 원본 → `client/assets/sfx/hit*`·`swish*`, 원본 목록·필터는 파일 안 표). 약·중타 '퍽' 은 Kenney impactPunch 그대로, 콤보 1·2·3타 점점 묵직하게 (`client/hit-tier.js` `hitStep` + config `SFX_HIT_COMBO`), 강타·치명은 `hitTier` + `SFX_HIT_TIERS`
- `tools/stats.js` — 서버 로그 요약 (판 길이·압사 비율·구성별·맵별·캐릭터별·콤보·플레이어별·아이템). 로그 형식을 바꾸면 여기도
- `test/game.test.js` — 단위 테스트, `test/rooms.test.js` — 방, `test/stats.test.js` — 로그 요약이 실제 게임 로그를 읽는지, `test/online.test.js` — 터널 주소 찾기·터널 지키기 (가짜 cloudflared·가짜 요청), `test/camera.test.js` — 관전 카메라, `test/modes.test.js` — 게임 모드, `test/characters.test.js` — 캐릭터, `test/keys.test.js` — 조작 키 설정 (+ 이모트 바퀴 5칸 고르기), `test/sky.test.js` — 하늘 계단 (대기실 옵션, 끄면 예전 그대로), `test/windup.test.js` — 이동 스킬 예고 (닌자·탱크·갈고리 F 지상 준비, 갈고리 닿는 순간 판정), `test/practice.test.js` — 연습 모드 (혼자 방·토글·허수아비 콤보 기록·판 중 캐릭터 바꾸기), `test/quake.test.js` — 탱크 R 솟는 땅 이벤트 id (quakeRise·quakeFall 짝), `test/ghost.test.js` — 유령 투하 (죽은 사람이 1칸 블록, 생존 모드), `test/colors.test.js` — 플레이어 색 고르기 (팔레트·중복 거절·판 중 거절·봇 자동), `test/botpos.test.js` — 봇 위치·복귀 (공중 대시·2단 점프로 안쪽, 가장자리 여유), `test/ko.test.js` — KO 이벤트 (finalKill·낙사 방향)·핑·터널 링크, `test/interp.test.js` — 화면 위치 보간 (들쭉날쭉 도착해도 고른 속도), `test/ragdoll.test.js` — 래그돌 순수 계산 (모터 세기·관절 모터·골반 끌어당김), `test/world.test.js` — 맵 테마 표 (맵·테마 id, 값 빠짐 없음), `test/hazard.test.js` — 위험 화면 계산 (닿는 곳 거리·깊이·차오름 단계·경고 세기, 테마 위험 값), `test/menu.test.js` — 메뉴 배경 가짜 대기 장면 (지형·서는 자리·이모트), `test/sound.test.js` — 소리 표 (효과음 파일·출처·크기, 8명 무기 소리, 위험 액체 종류, 테마 곡·긴장 버전), `test/figure.test.js` — 몸 모양 수치 (공격 비틂 골반 나눔·광전사 근육 홈·전용 도발 이름·포즈 시간·걸음걸이·공중·평소 버릇 자세)

## 규칙

- 브랜치에서 작업 → main 에는 재혁이 말할 때 fast-forward 로만
- 새 규칙·수치는 테스트로 고정한다. 봇·랜덤이 낀 테스트는 여러 번 돌려 흔들리지 않는지 확인
- 클라이언트 변경은 Playwright(헤드리스 크롬)로 실제 화면을 띄워 확인. 디버그 훅 `window.__tf`
- 판정용 로그(사망 원인, 판 길이)는 서버 콘솔에 남긴다. 플레이테스트 분석의 근거
