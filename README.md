# Tetrafall 고도 시제품 스샷 (2026-10-30)

코드: `claude/awesome-babbage-0witv7` 브랜치 `godot/` (고도 4.7.2, GDScript)

| 파일 | 내용 |
| --- | --- |
| `web-1.png`, `web-2.png` | 웹 내보내기를 크로미움(ANGLE→Mesa llvmpipe)에서 열어 고도 헤드리스 서버에 접속. 헤드리스 봇 클라 2명 + 브라우저(판 중 들어와 관전) |
| `desktop-linux.png` | 고도 리눅스 데스크톱 렌더 (편집기 실행 파일, 봇 클라, 판 끝) |
| `linux-export.png` | 내보낸 리눅스 실행 파일 하나로 서버 + 클라 (대기 화면) |
| `web-swiftshader-broken.png` | 같은 웹 빌드를 헤드리스 크로미움 기본 SwiftShader WebGL 로 연 것 — 띠·큰 다각형으로 깨짐 (브라우저 소프트웨어 렌더러 문제로 봄, 실제 GPU 확인 필요) |
| `web8-1.png`, `web8-2.png` | 2단계: 8명 판 (서버 봇 7명 + 브라우저 1명은 판 중 들어와 관전, 18×18), 모두 닌자, 자동 블록 자리 고르기 CLEAR_BIAS. 웹 내보내기 + Mesa |
| `cs-server-menu.png`, `cs-server-lobby.png` | 0단계 (2026-10-31): 기존 JS 화면을 C# 서버 뼈대 (godot/server, .NET 10) 에 붙임 → 메뉴·방 만들기·대기실 (핑 2ms) |
| `g0-desktop.png`, `g0-web.png` | G0 (2026-10-31): 고도 클라 뼈대가 JS 서버에 붙어 4명 판 (개발용 상자 화면, 보간 위치, 핑). 데스크톱 (리눅스, xvfb) · 웹 내보내기 (크로미움 Mesa) |
