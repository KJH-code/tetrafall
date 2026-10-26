# Tetrafall

3D 폴가이즈식 PC 웹 대전. 격자 필드에 테트리미노가 떨어지고 플레이어끼리 밀어 떨어뜨리거나(낙사) 블록에 깔리게(압사) 한다. LAN 또는 인터넷(Cloudflare 터널), 서버 하나에 방 여러 개, 방마다 2~4인 + AI 봇.

DevVault: Projects/Tetrafall

## 스택

- Node (서버, `ws`) + three.js (클라이언트). 순수 JS ES 모듈, 빌드 없음
- 서버가 게임 상태의 권위 (30Hz 고정 틱). 클라이언트는 입력 전송 + 렌더링만, 예측 없음
- 물리엔진 없음: 블록은 3D 정수 배열, 플레이어만 AABB 충돌 + 넉백

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
- `server/game.js` — 게임 상태: 격자, 블록 낙하, 플레이어 물리, 넉백, 사망 판정, 용암, 아이템, 로그, 모드(`mode`: 생존·블록 마스터·킬 점수전). 블록 마스터의 마스터는 살아 있지만 필드에 없음 → 판정 대상은 `onField(p)` 로 고른다. 캐릭터(`char`, 스킬·필살기)는 `new Game(log, { characters: true })` 일 때만 (서버 방은 켬, 예전 규칙 테스트는 끔). 하늘 계단(`sky`, 하늘 블록 사슬·격자 높이 `game.H` 32)도 `{ skyStairs: true }` 일 때만 (방은 `SKY_STAIRS_DEFAULT`)
- `server/bot.js` — AI 봇 (handleInput / handleAction 만 씀, 판정 특혜 없음)
- `server/index.js` — 정적 서빙 + WebSocket + 틱 루프 + 방마다 로그 파일 (`logs/<서버 시각>/<방 시각>_<코드>.txt`)
- `server/rooms.js` — 방 (게임 + 접속 + 로그). 방 밖 메시지(create·join)와 방 안 메시지 처리, 사람 0명이면 삭제. 테스트는 가짜 소켓
- `client/` — 렌더(`render.js`), 캐릭터(`character.js`), 입력(`input.js`), HUD·네트워크(`main.js`), 효과음(`sound.js`), 배경음악(`music.js`), 캐릭터 몸·동작(`figure.js`, 1인칭·3인칭은 `render.js`, 1인칭 팔·무기는 `viewmodel.js`: 내 몸을 복제해 관절을 베낌), 모델 불러오기(`models.js`, 파일은 `client/assets/` 출처 `CREDITS.md`), 툰 재질·외곽선(`toon.js`), 코드 텍스처(`textures.js`), 조작 키 설정(`keys.js`, 설정 창에서 바꿈, `tf-keys`)
- `tools/online.js` — `npm run online` (서버 자식 프로세스 + cloudflared, 출력에서 터널 주소 찾기)
- `tools/stats.js` — 서버 로그 요약 (판 길이·압사 비율·구성별·맵별·캐릭터별·콤보·플레이어별·아이템). 로그 형식을 바꾸면 여기도
- `test/game.test.js` — 단위 테스트, `test/rooms.test.js` — 방, `test/stats.test.js` — 로그 요약이 실제 게임 로그를 읽는지, `test/online.test.js` — 터널 주소 찾기, `test/camera.test.js` — 관전 카메라, `test/modes.test.js` — 게임 모드, `test/characters.test.js` — 캐릭터, `test/keys.test.js` — 조작 키 설정, `test/sky.test.js` — 하늘 계단 (대기실 옵션, 끄면 예전 그대로), `test/windup.test.js` — 이동 스킬 예고 (닌자·탱크·갈고리 F 지상 준비, 갈고리 닿는 순간 판정)

## 규칙

- 브랜치에서 작업 → main 에는 재혁이 말할 때 fast-forward 로만
- 새 규칙·수치는 테스트로 고정한다. 봇·랜덤이 낀 테스트는 여러 번 돌려 흔들리지 않는지 확인
- 클라이언트 변경은 Playwright(헤드리스 크롬)로 실제 화면을 띄워 확인. 디버그 훅 `window.__tf`
- 판정용 로그(사망 원인, 판 길이)는 서버 콘솔에 남긴다. 플레이테스트 분석의 근거
