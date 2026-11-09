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
- 배포 묶음: `node godot/server/tools/package.mjs --godot <고도> --web-template <zip>` (또는 환경 변수 `GODOT_WEB_TEMPLATE`) — 웹 내보내기 동안만 `custom_template/release` 를 바꾸고 끝나면 (실패해도) 되돌림, 안 주면 공식 템플릿. GitHub Release (`.github/workflows/release.yml`) 는 **기본 끔** (변수 `WEB_TEMPLATE_BUILD=true` 또는 수동 실행 `web_template` 로 켬) — 켜면 `web-template` job 이 이 스크립트로 빌드해 넘김 (캐시 키 = 고도·emsdk 버전 + 스크립트 해시, 첫 빌드 40~60분, 실패하면 공식 템플릿으로 묶음). 버전은 환경 변수 `GODOT_VERSION`·`EM_VERSION` (기본 4.7.2·4.0.11)
- 더 줄이려면: 클래스 단위 build profile (편집기 → 도구 → 엔진 컴파일 구성 → '프로젝트에서 찾기', 헤드리스 명령 없음 — 편집기에서 만들어 `build_profile=` 로). `optimize=size_extra`·`deprecated=no` 는 안 써 봄 (wasm 실행 속도·옛 API)
- pck 쪼개기 (보류, W5): 첫 pck (br 6.04MB) 의 소리 녹음 중 판 효과음 262개 = br 2.12MB (10Mbps 약 1.7초), 타이틀·앰비언트 녹음 7테마 몫 = br 2.64MB (그 판에 쓰는 한 테마만 먼저면 약 2.3MB 더). 뒤로 미루려면 `audio/sfx.gd` 가 아직 없는 녹음을 건너뛰고 따로 받은 팩을 `ProjectSettings.load_resource_pack` 해야 함 (audio 는 W5 범위 밖)

## 렌더러 시험 (W12, 2026-11-03 — 결정은 재혁 PC 숫자 뒤)

기본은 그대로 **GL Compatibility** (웹과 같은 빌드, `client/project.godot`). PC 만 Forward+·Mobile (Vulkan) 로 바꿀 수 있게 준비만 함:

- `project.godot` 에 `rendering_method.web = gl_compatibility` 를 박아 둠 → 나중에 PC 기본 (`rendering_method`) 을 바꿔도 웹은 Compatibility 그대로 (테스트 `test_renderer_web_pinned`)
- 배포 묶음 (윈도우, `server/tools/package.mjs`) 에 시험용 `start-lan-compat.bat`·`start-lan-forward.bat`·`start-lan-mobile.bat`: 서버 + `tetrafall.exe --rendering-method <방식> --rendering-driver <드라이버>`. 8명 판에서 F3 (렌더러·어댑터 이름이 첫 줄) → Ctrl+C 복사한 줄을 셋 다 보내 주면 기본값을 정함
- 셰이더 확인 `xvfb-run -a godot --path godot/client --rendering-method forward_plus --rendering-driver vulkan -s tools/shader_check.gd` (mobile·`gl_compatibility --rendering-driver opengl3` 도): `.gdshader` 전부 + G3 툰 재질 (불투명·투명·꼭짓점 색, 외곽선 next_pass) 을 그 렌더러로 실제로 그림
- 클라우드 컨테이너에서 확인한 범위: GPU 없음, lavapipe (Mesa 소프트웨어 Vulkan 1.4) 가 있어 Forward+·Mobile 로 켜짐. 셰이더 19개 + G3 재질 3개 **셋 다 SHADER ERROR 0**. Vulkan 은 끝날 때 프로세스가 안 끝나는 일이 있음 (lavapipe — `timeout` 으로 감쌈). 렌더 ms·FPS 는 소프트웨어라 비교 근거가 못 됨 → 재혁 PC 숫자로
- **렌더러 비교표 (W32, 2026-11-08, 소프트웨어 lavapipe — GPU ms 는 못 잼, 기본 렌더러는 안 바꿈)**: 같은 8명 재연 (`game8.rec` 7~8초, 3인칭, 1280×720, 보통 화질, `--replay-render --census`) + 8명 (닌자·탱크·사냥꾼·갈고리 ×2) + 떨어지는 칸 12 + 쌓인 칸 60 장면 (`tools/shadow_meas.gd`). 같은 코드로 `--rendering-method`·`--rendering-driver` 만 바꿈, 셋 다 화면 삼각형·그림자 삼각형은 같음 (코드가 같은 장면을 냄).

  | | GL Compatibility (opengl3) | Mobile (vulkan) | Forward+ (vulkan) |
  | --- | --- | --- | --- |
  | 재연 그리기 · 물체 (전체) | 174 · 300 | 163 · 286 | 177 · 300 |
  | 창 3D 그리기 (화면 + 그림자 패스) | 93 + (그림자는 안 세어 줌) | 55 + 27 | 74 + 22 |
  | 삼각형 (화면 + 그림자 패스) | 95.3k + 40.3k | 95.3k + 40.3k | 95.2k + 40.3k |
  | 영상 메모리 | 130.7MB | 219.3MB (+68%) | 258.1MB (+97%) |
  | 스크립트 ms/프레임 (잡음 ±10%) | 4.85 | 4.54 | 4.46 |
  | 8명 + 칸: 그리기 (화면 + 그림자) | 47 + (안 셈) | 16 + 17 | 30 + 17 |
  | 8명 + 칸: 처음 그리기 ms (셰이더 컴파일 포함) | 799 | 4187 (2·3째 프레임 753·56) | 2363 (2·3째 158·78) |
  | 8명 + 칸: 이후 프레임 중앙값 ms (CPU 래스터 — GPU 아님) | 51 | 50 | 65 |
  | 셰이더 확인 (`shader_check.gd`) | 오류 0 (2.8초, 끝남) | 오류 0 (그린 뒤 프로세스가 안 끝나 `timeout` 으로 끊음) | 오류 0 (같음) |

  - 읽는 법: 그리기 수는 Mobile 이 가장 적고 (그림자 패스 따로 셈) Compatibility 는 그림자 패스 수를 안 알려 줌 → 숫자끼리 직접 비교하지 말 것. **영상 메모리는 Vulkan 쪽이 1.7~2.0배**, **처음 그릴 때 셰이더 컴파일은 Compatibility 가 가장 짧음** (llvmpipe 에서 Mobile 4.2초·Forward+ 2.4초 — 진짜 GPU 드라이버는 파이프라인 캐시가 있어 이 숫자와 다름, 상대 순서만 참고). 프레임 ms 는 소프트웨어 래스터라 렌더러 비교 근거가 못 됨.
  - 결론: **기본 렌더러는 그대로 (GL Compatibility)**. 바꾸려면 재혁 PC 의 F3 숫자 (`start-lan-compat/forward/mobile.bat` 각각 8명 판에서 F3 → Ctrl+C 복사) 가 필요함 — 특히 GPU ms·1% low·히치 로거 (셰이더 컴파일이 GL 보다 길어 첫 장면 히치 후보).
- 바꿀 때 볼 것: Forward+ 는 MSAA·그림자 필터·색 공간이 조금 달라 보일 수 있음 (툰 셰이더는 같은 코드), 웹은 영향 없음
