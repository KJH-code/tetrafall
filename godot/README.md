# Tetrafall 고도 이전

2026-10-31 재혁 결정: 고도로 옮김. 서버 규칙은 C# (.NET 10), 클라는 고도 GDScript. JS 판(레포 뿌리 `server/`·`client/`)은 얼리고 버그만 고침.
설계·이식 규칙·작업 목록은 [`PLAN.md`](PLAN.md).

| 폴더 | 내용 | 안내 |
| --- | --- | --- |
| `server/` | C# 서버 (JS 서버와 같은 프로토콜 — 기존 JS 화면이 그대로 붙음) | [`server/README.md`](server/README.md) |
| `client/` | 고도 클라 (G0 뼈대: 접속·재접속·핑·보간·입력·키 설정, 내보내기) | [`client/README.md`](client/README.md) |
| `prototype/` | 고도 시제품 (1·2단계 판단용, GDScript 규칙·측정) | [`prototype/README.md`](prototype/README.md) |
