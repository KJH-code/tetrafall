# Tetrafall 고도 이전

2026-10-31 재혁 결정: 고도로 옮김. 서버 규칙은 C# (.NET 10), 클라는 고도 GDScript. JS 판(레포 뿌리 `server/`·`client/`)은 얼리고 버그만 고침.
설계·이식 규칙·작업 목록은 [`PLAN.md`](PLAN.md).

| 폴더 | 내용 | 안내 |
| --- | --- | --- |
| `server/` | C# 서버 (JS 서버와 같은 프로토콜 — 기존 JS 화면이 그대로 붙음) | [`server/README.md`](server/README.md) |
| `client/` | 고도 클라 (G0 뼈대: 접속·재접속·핑·보간·입력·키 설정, 내보내기) | [`client/README.md`](client/README.md) |
| `prototype/` | 고도 시제품 (1·2단계 판단용, GDScript 규칙·측정) | [`prototype/README.md`](prototype/README.md) |

## 웹 템플릿 직접 빌드 (보류, 2026-10-31)

공식 웹 템플릿 wasm 은 39.5MB (br 6.9MB) — 웹 첫 실행 받기의 대부분. 안 쓰는 모듈을 빼고 직접 빌드하면 br 약 4–4.5MB 추정 (10Mbps 첫 화면 −2~2.5s). 클라우드 세션에선 github (고도 소스·emsdk) 받기가 막혀 보류.

- 준비: 고도 4.7.2-stable 소스 + emsdk (고도 4.7 문서 '웹 컴파일' 의 emscripten 버전), Python scons
- 편집기 프로젝트 → 도구 → 엔진 컴파일 구성 → '프로젝트에서 찾기' 로 `tetrafall.gdbuild` (쓰는 클래스만)
- `scons platform=web target=template_release threads=no optimize=size_extra lto=full deprecated=no build_profile=tetrafall.gdbuild` + 안 쓰는 모듈 끔 (`module_<이름>_enabled=no`: navigation·csg·gridmap·openxr·enet·webrtc·mbedtls·theora·… ). 남길 것: GL Compatibility 3D·websocket·vorbis·QOA·text_server_adv (한글)·3D 물리 (래그돌)
- 결과 `bin/godot.web.template_release.wasm32.nothreads.zip` → `export_presets.cfg` 웹 `custom_template/release`. 4코어 ~40–60분

## 렌더러 시험 (W12, 2026-11-03 — 결정은 재혁 PC 숫자 뒤)

기본은 그대로 **GL Compatibility** (웹과 같은 빌드, `client/project.godot`). PC 만 Forward+·Mobile (Vulkan) 로 바꿀 수 있게 준비만 함:

- `project.godot` 에 `rendering_method.web = gl_compatibility` 를 박아 둠 → 나중에 PC 기본 (`rendering_method`) 을 바꿔도 웹은 Compatibility 그대로 (테스트 `test_renderer_web_pinned`)
- 배포 묶음 (윈도우, `server/tools/package.mjs`) 에 시험용 `start-lan-compat.bat`·`start-lan-forward.bat`·`start-lan-mobile.bat`: 서버 + `tetrafall.exe --rendering-method <방식> --rendering-driver <드라이버>`. 8명 판에서 F3 (렌더러·어댑터 이름이 첫 줄) → Ctrl+C 복사한 줄을 셋 다 보내 주면 기본값을 정함
- 셰이더 확인 `xvfb-run -a godot --path godot/client --rendering-method forward_plus --rendering-driver vulkan -s tools/shader_check.gd` (mobile·`gl_compatibility --rendering-driver opengl3` 도): `.gdshader` 전부 + G3 툰 재질 (불투명·투명·꼭짓점 색, 외곽선 next_pass) 을 그 렌더러로 실제로 그림
- 클라우드 컨테이너에서 확인한 범위: GPU 없음, lavapipe (Mesa 소프트웨어 Vulkan 1.4) 가 있어 Forward+·Mobile 로 켜짐. 셰이더 19개 + G3 재질 3개 **셋 다 SHADER ERROR 0**. Vulkan 은 끝날 때 프로세스가 안 끝나는 일이 있음 (lavapipe — `timeout` 으로 감쌈). 렌더 ms·FPS 는 소프트웨어라 비교 근거가 못 됨 → 재혁 PC 숫자로
- 바꿀 때 볼 것: Forward+ 는 MSAA·그림자 필터·색 공간이 조금 달라 보일 수 있음 (툰 셰이더는 같은 코드), 웹은 영향 없음
