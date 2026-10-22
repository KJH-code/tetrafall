# Tetrafall

3D 폴가이즈식 PC 웹 대전. 격자 필드에 테트리미노가 떨어지고 플레이어끼리 밀어 떨어뜨리거나(낙사) 블록에 깔리게(압사) 한다. LAN 2~4인 + AI 봇.

DevVault: Projects/Tetrafall

## 스택

- Node (서버, `ws`) + three.js (클라이언트). 순수 JS ES 모듈, 빌드 없음
- 서버가 게임 상태의 권위 (30Hz 고정 틱). 클라이언트는 입력 전송 + 렌더링만, 예측 없음
- 물리엔진 없음: 블록은 3D 정수 배열, 플레이어만 AABB 충돌 + 넉백

## 명령

```
npm install
npm start        # 호스트 서버 (포트 3000)
npm test         # 서버 규칙 단위 테스트 (node --test)
npm run stats    # 플레이테스트 로그 요약 (logs/ 최신 파일, 또는 -- 파일 경로)
```

Windows PowerShell 에서 npm 이 막히면 `npm.cmd`.

## 구조

- `shared/config.js` — **튜닝 수치는 전부 여기.** 코드에 숫자를 박지 않는다
- `shared/pieces.js` — 테트리미노 모양·회전
- `server/game.js` — 게임 상태: 격자, 블록 낙하, 플레이어 물리, 넉백, 사망 판정, 용암, 아이템, 로그
- `server/bot.js` — AI 봇 (handleInput / handleAction 만 씀, 판정 특혜 없음)
- `server/index.js` — 정적 서빙 + WebSocket + 틱 루프
- `client/` — 렌더(`render.js`), 캐릭터(`character.js`), 입력(`input.js`), HUD·네트워크(`main.js`), 효과음(`sound.js`), 배경음악(`music.js`), 모델 불러오기(`models.js`, 파일은 `client/assets/` 출처 `CREDITS.md`), 툰 재질·외곽선(`toon.js`), 코드 텍스처(`textures.js`)
- `tools/stats.js` — 서버 로그 요약 (판 길이·압사 비율·구성별·맵별·플레이어별·아이템). 로그 형식을 바꾸면 여기도
- `test/game.test.js` — 단위 테스트, `test/stats.test.js` — 로그 요약이 실제 게임 로그를 읽는지

## 규칙

- 브랜치에서 작업 → main 에는 재혁이 말할 때 fast-forward 로만
- 새 규칙·수치는 테스트로 고정한다. 봇·랜덤이 낀 테스트는 여러 번 돌려 흔들리지 않는지 확인
- 클라이언트 변경은 Playwright(헤드리스 크롬)로 실제 화면을 띄워 확인. 디버그 훅 `window.__tf`
- 판정용 로그(사망 원인, 판 길이)는 서버 콘솔에 남긴다. 플레이테스트 분석의 근거
