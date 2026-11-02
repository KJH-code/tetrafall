# Tetrafall 고도 이전

2026-10-31 재혁 결정: 고도로 옮김. 서버 규칙은 C# (.NET 10), 클라는 고도 GDScript. JS 판(레포 뿌리 `server/`·`client/`)은 얼리고 버그만 고침.
설계·이식 규칙·작업 목록은 [`PLAN.md`](PLAN.md).

| 폴더 | 내용 | 안내 |
| --- | --- | --- |
| `server/` | C# 서버 (JS 서버와 같은 프로토콜 — 기존 JS 화면이 그대로 붙음) | [`server/README.md`](server/README.md) |
| `client/` | 고도 클라 (G0 뼈대: 접속·재접속·핑·보간·입력·키 설정, 내보내기) | [`client/README.md`](client/README.md) |
| `prototype/` | 고도 시제품 (1·2단계 판단용, GDScript 규칙·측정) | [`prototype/README.md`](prototype/README.md) |

## 웹 템플릿 직접 빌드 (W5 2026-11-02, 클라우드 세션에서 github 받기 됨)

공식 웹 템플릿 wasm 은 39.5MB (br 6.9MB) — 웹 첫 실행 받기의 대부분. 안 쓰는 모듈을 빼고 직접 빌드: **wasm 32.9MB (br 5.39MB)**, 10Mbps 흉내 첫 화면 14.9·14.6 → 13.4·13.2초 (받는 양 13.07 → 11.56MB, `tools/web_first.cjs`). 게임 판·한글·래그돌 확인.

- `bash godot/client/tools/build-web-template.sh <작업 폴더>` — 고도 4.7.2-stable 소스 + emsdk 4.0.11 (고도 CI `web_builds.yml` EM_VERSION) + scons, `production=yes optimize=size threads=no`, 끄는 모듈 목록은 스크립트 안. 4코어 약 25분
- 쓰기: 웹 내보내기 전에 `export_presets.cfg` 웹 `custom_template/release` 에 결과 zip 절대 경로 (커밋 안 함 — 없는 기계에선 내보내기 실패) 또는 `~/.local/share/godot/export_templates/4.7.2.stable/web_nothreads_release.zip` 을 바꿔 넣음
- 배포 묶음: `node godot/server/tools/package.mjs --godot <고도> --web-template <zip>` (또는 환경 변수 `GODOT_WEB_TEMPLATE`) — 웹 내보내기 동안만 `custom_template/release` 를 바꾸고 끝나면 (실패해도) 되돌림, 안 주면 공식 템플릿. GitHub Release (`.github/workflows/release.yml`) 는 `web-template` job 이 이 스크립트로 빌드해 넘김 (캐시 키 = 고도·emsdk 버전 + 스크립트 해시, 첫 빌드 40~60분, 실패하면 공식 템플릿으로 묶음). 버전은 환경 변수 `GODOT_VERSION`·`EM_VERSION` (기본 4.7.2·4.0.11)
- 더 줄이려면: 클래스 단위 build profile (편집기 → 도구 → 엔진 컴파일 구성 → '프로젝트에서 찾기', 헤드리스 명령 없음 — 편집기에서 만들어 `build_profile=` 로). `optimize=size_extra`·`deprecated=no` 는 안 써 봄 (wasm 실행 속도·옛 API)
- pck 쪼개기 (보류, W5): 첫 pck (br 6.04MB) 의 소리 녹음 중 판 효과음 262개 = br 2.12MB (10Mbps 약 1.7초), 타이틀·앰비언트 녹음 7테마 몫 = br 2.64MB (그 판에 쓰는 한 테마만 먼저면 약 2.3MB 더). 뒤로 미루려면 `audio/sfx.gd` 가 아직 없는 녹음을 건너뛰고 따로 받은 팩을 `ProjectSettings.load_resource_pack` 해야 함 (audio 는 W5 범위 밖)
