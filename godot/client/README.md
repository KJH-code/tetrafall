# Tetrafall 고도 클라

고도 4.7.2 GDScript (렌더러 Compatibility — 웹·PC 같은 빌드). 서버는 JS 서버 (`npm start`) 또는 C# 서버 (`godot/server`) — 같은 프로토콜.
지금은 **G0 뼈대**: 접속·재접속(자리 토큰)·핑·스냅샷·보간·입력·키 설정 + 개발용 상자 화면. 묶음 나누기 규칙은 `../PLAN.md` 7절.

## 실행 (레포 뿌리에서, 고도 받기는 `../prototype/README.md`)

```
PORT=3000 npm start                                     # JS 게임 서버 (C# 서버도 됨)
godot --headless --path godot/client --import           # 처음 한 번 (글꼴 등)
godot --path godot/client                               # 창 클라 → ws://127.0.0.1:3000. 방 만들기·봇 추가·시작, 화면 클릭하면 마우스 잡힘 (Esc 풂)
godot --path godot/client -- --server ws://주소:3000 --room ABCD   # 다른 서버·바로 그 방
```

옵션 (`--` 뒤, 웹이면 주소 뒤 `?키=값`): `--server` · `--room` · `--name` · `--profile` (자리 토큰 저장을 나눔 — 같은 PC 에서 사람 둘) ·
자동 확인 `--auto host|guest` `--bots N` `--wait-players N` `--drop-at 초` (연결 끊었다 같은 자리로) `--quit-after-rounds N` `--quit-after 초` `--min-moved 칸` `--shot 파일.png --shot-after 초`

## 테스트·확인

```
godot --headless --path godot/client -s res://tests/run_tests.gd   # 보간·핑·키 설정이 JS 와 같은 값 (tests/fixtures, JS 에서 뽑음)
node godot/client/tools/fixtures.mjs                              # 정답 자료 다시 뽑기 (client/interp.js·shared/net.js·client/keys.js)
node godot/client/tools/gen-config.mjs                            # shared/config.js → core/config.gd (JS config 를 바꾸면)
bash godot/client/tools/e2e.sh                                    # JS 서버 + 헤드리스 클라 둘: 방 만들기·코드로 들어가기·판·중간에 끊고 같은 자리로
xvfb-run -a godot --path godot/client --rendering-driver opengl3 -- --auto host --bots 7 --wait-players 8 --shot /tmp/s.png --shot-after 12 --quit-after 13
```

## 내보내기 (G7)

```
mkdir -p godot/client/build/{web,windows,linux}
godot --headless --path godot/client --export-release Web build/web/index.html
godot --headless --path godot/client --export-release Windows build/windows/tetrafall.exe
godot --headless --path godot/client --export-release Linux build/linux/tetrafall.x86_64
node godot/client/tools/serve_web.mjs 8060      # 브라우저 http://127.0.0.1:8060/?server=ws://127.0.0.1:3000
WEB_PORT=8060 xvfb-run -a node godot/client/tools/web_shot.cjs /tmp "?server=ws://127.0.0.1:3000&auto=host&bots=3&wait-players=4"
```

- 템플릿: `~/.local/share/godot/export_templates/4.7.2.stable/` 에 `web_nothreads_release.zip`·`windows_release_x86_64.exe`·`linux_release.x86_64` (받기는 prototype README)
- 웹 곡 따로 (2026-10-31): 웹 내보내기는 곡 녹음본 15개 (`audio/baked/music.*.ogg`, 3.7MB) 를 pck 에서 빼고 `build/web/music/` 에 복사 (`addons/web_music` 내보내기 플러그인, project.godot 에서 켬). 화면은 방에 들어가면 대기실 곡 → 지금 맵 곡 → 긴장 곡 → 나머지 순으로 받고 (`audio/music_fetch.gd`), 못 받은 곡은 곡 없이. PC 판은 pck 안 그대로. 웹 빌드 폴더를 옮길 땐 `music/` 도 같이
- 크기 (2026-10-31): 웹 wasm 39.5MB (gzip 약 10MB) + pck 0.3MB, 윈도우 exe 110MB, 리눅스 74MB (pck 포함 한 파일). `build/` 는 커밋 안 함
- 웹은 C# 서버가 `/play/` 로 같이 서빙 (같은 호스트라 `?server=` 없이 붙음). 서버·웹·PC 클라 한 zip 은 `node godot/server/tools/package.mjs --godot <고도>` (godot/server/README.md G7, 재혁 PC 순서 docs/godot-play.md)
- 재혁 PC (윈도우): `tetrafall.exe -- --server ws://<서버 IP>:3000` (또는 같은 PC 면 그냥 `tetrafall.exe`)

## 소리 (G5, `audio/`)

JS 화면의 합성 소리·곡을 **크로미움에서 그대로 녹음해 구움** (`tools/bake-audio.cjs` → `audio/baked/*.ogg` 314개 7.5MB + `manifest.json`). 고도는 녹음본만 틀어서 실행 중 합성이 없음 → JS 와 같은 소리, 웹에서도 가벼움.

- 왜 굽나 (2026-10-31): GDScript 로 직접 합성하면 데스크톱에선 목소리 8개 1초에 34ms (실시간의 3%) 로 되지만, WebAudio 와 같은 소리를 내려면 필터·띠 제한 파형·엔벌로프를 다 다시 만들어야 하고 웹(wasm)에선 몇 배 느림. 굽는 쪽이 같은 소리 + 비용 0
- 매번 다른 높낮이: 녹음본 여러 개 (효과음 3개, 타격 2개) + 재생할 때 ±SFX_DETUNE/2
- 다시 굽기 (JS 소리를 바꾸면): `PORT=3399 node server/index.js & node godot/client/tools/bake-audio.cjs 3399` (ffmpeg libvorbis, 약 8분)
- `audio/sound_math.gd` 거리·좌우·타격 세기·곡·앰비언트 테마 계산 (JS 와 같은지 tests/test_audio.gd) · `audio/sfx.gd` 재생기·버스 (SFX·SFXDirect·Music·좌우 버스) · `audio/music.gd` 곡 (맵 테마·긴장, 바뀌면 위치 이어서)·앰비언트 (메뉴·대기실)·위험 액체 지속음 · `audio/audio.gd` 이벤트 → 소리 (main.js 의 sound.play 줄 그대로)
- 화면 쪽 소리 (건축가 폭발·화살 박힘·위험 차오름·KO·슬로모션) 는 그리는 쪽이 `View.sound_cue.emit("blast", {x, y, z, big, wood})` 처럼

## 구조 (G0 = core/)

| 파일 | 내용 (JS 원본) |
| --- | --- |
| `core/net.gd` (자동 로드 `Net`) | 접속·보내기·받기·끊기면 다시 붙기·핑 (main.js connect, net.js) |
| `core/store.gd` (`Store`) | 프로토콜 처리·최신 스냅샷·격자·보간 위치 `view_pos` (main.js onmessage) |
| `core/player_input.gd` (`PlayerInput`) | 키보드·마우스 → input·action (input.js) |
| `core/view.gd` (`View`) | 화면 공용 상태: 시점·관전·설정 |
| `core/keys.gd` · `interp.gd` · `net_meter.gd` · `seat.gd` · `coords.gd` | keys.js · interp.js · shared/net.js · seat.js · 좌표/색 |
| `core/config.gd` | 만든 파일 (shared/config.js) |
| `core/dev_view.gd` · `dev_ui.gd` · `autopilot.gd` | 개발용 상자 화면·버튼·자동 조종 (G1·G4 씬이 생기면 안 쓰임) |
| `assets/fonts/ui_font.tres` | 프로젝트 글꼴: Black Han Sans 한글·라틴 (OFL) + 기호 대체 `dejavu-sans-bold-symbols.woff2` (DejaVu Sans Bold 조각 — · — … ← → ↺ ▸ ° 등, 라이선스 `DejaVu-LICENSE.txt`). 웹엔 시스템 글꼴 대체가 없어 여기 없는 글자는 빈 칸 → `tests/test_core.gd` 가 스크립트 글의 글자를 다 확인. 다시 만들기: `pyftsubset DejaVuSans-Bold.ttf --unicodes="U+0020-007E,U+00A0-00FF,U+2010-2027,U+2030-203A,U+2190-21FF,U+2212,U+2460-2473,U+25A0-25FF,U+2600-2606,U+2713-2717,U+2764" --flavor=woff2 --layout-features= --no-hinting` |
| `assets/fonts/body_font.tres` | 본문 글꼴 (JS 에서 system-ui 인 자리 — 설명·표 숫자·안내·체크 글·이름표, `ui_style.BODY`·`body()`·`body_label()`): Noto Sans KR Regular 부분 집합 `noto-sans-kr-body.woff2` (OFL, 약 40KB, 스크립트 글의 글자 + 영문·숫자·기호) + 대체 Black Han Sans·DejaVu 기호. 게임 문구를 바꾸면 `node tools/subset-body-font.mjs <NotoSansKR-Regular.ttf>` (받기·사용법은 파일 머리), 빠진 글자는 `tests/test_ui_nodes.gd` 가 잡음 |

## 몸 굽기 (W7, 2026-11-02 시제품)

JS 몸을 .glb 로 구워 파일로 불러옴 (지금 탱크만, 나머지는 예전 조립 `chars/data/bodies.bin`): `node tools/bake-bodies.mjs tank` (레포 뿌리) → `assets/models/tank.glb` + `tank.json` → `--import`. 구조·숫자·남은 일은 [`chars/BAKE.md`](chars/BAKE.md). 비교 실행 인자 `--no-glb` (예전 조립)

## 성능 재기 (W6·W12)

GPU 가 없는 클라우드 컨테이너에선 렌더 ms·FPS 는 소프트웨어 (llvmpipe) 라 근거가 못 됨 → **스크립트 ms·그리기·물체·삼각형·SubViewport** 를 같은 판으로 A/B. 재혁 PC 는 F3 → Ctrl+C 한 줄.

```
# 판 기록 (자동 조종 8명 판, 받은 글자를 '시각\t글자' 줄로) — 한 번
xvfb-run -a godot --path godot/client --rendering-driver opengl3 -- --auto host --bots 7 --wait-players 8 --server ws://127.0.0.1:3000 --rec /tmp/game8.rec --quit-after 20
# 재연 (서버 없이 같은 판, 가상 시계 1/120초씩): 처음 playing + 3초부터 10초 동안 스크립트·물리 ms/프레임
xvfb-run -a godot --path godot/client --rendering-driver opengl3 -- --replay /tmp/game8.rec --profile replay [--prof] [--replay-render] [--set gfx=medium,third=true] [--shot a.png]
```

- `--census` (W15): 끝에 무리별 3D 물체·외곽선·삼각형, 보이는 2D 노드, viewport 마다 3D·그림자·2D 그리기
- `--prof`: 구간별 ms/프레임 (`core/prof.gd` — world·몸·HUD·net 구간, 느린 프레임 6개). 꺼져 있으면 비용 거의 0 (테스트 `test_prof_off_is_free`)
- `--replay-render`: 그리기 끔 대신 실제로 그리고 마지막에 그리기·물체·삼각형·영상 메모리 · `--set 키=값` 설정을 바꿔 알림만 (파일엔 안 남음 — 외곽선·그림자·화질 A/B)
- `--replay-warm -4 --replay-secs 0.5` 처럼 음수면 판 시작 전 (대기실) 을 잼·찍음
- 같은 판·같은 가상 시각이라 전/후 스크린샷을 화소로 비교할 수 있음 (래그돌 물리만 실제 시간 — 흔들림 바닥은 같은 빌드 두 번)
- 부하 평균이 높은 컨테이너 (다른 일 동시) 에선 한 번 숫자가 ±20% 흔들림 → 전/후를 번갈아 여러 번

### 규칙 (테스트로 고정, `tests/test_perf.gd`)

- **몸 자세 LOD** (`world/pose_lod.gd`, 수치 `world_config.gd POSE_LOD`): 자세 (figureAnim·래그돌 잡기·묶음 뼈) 만 덜 자주. 자리·방향·이름표는 매 프레임. 카메라 3m 안 = 매 프레임, 그보다 멀면 60Hz (120fps 면 한 프레임 걸러), 화면 밖 20Hz, 내 몸 (1인칭 팔이 관절을 베낌) 은 늘 매 프레임. 끄기 `--no-pose-lod`, 근거리 바꾸기 `--pose-lod-near <m>`
- **(W15) 둘째 LOD 단·SubViewport 상한·같은 스냅샷 건너뜀·투명 판 숨김·외곽선 그림자 빼기**: `test_pose_lod_far2`·`test_subview_rate`·`test_same_snapshot_skips`·`test_clear_overlays_hidden`·`test_outline_not_in_shadow_map`, 쉬는 래그돌은 `test_chars` 래그돌, 자동 화질 RTX 는 `test_gfx`
- **HUD 글자 색·크기는 바뀔 때만** (`ui_style.gd ov_color·ov_font_size`): `add_theme_*_override` 는 같은 값이어도 '테마 바뀜' 알림 → 글자 모양 다시 잡기·다시 배치. 판 중 매 프레임 ~45번 (아래 판 8명 × 5 + 큰 글자·내 %·아이템 시간·R 칸) 이 값이 바뀔 때만으로. 한 번 11µs → 0.6µs
- **설정 '외곽선'·'그림자'** 가 실제로 바뀜 (W12 전엔 듣는 쪽이 없었음): `G3.set_outline_on` (만든 재질 전부 next_pass 를 빼고 끼움, 외곽선 재질 하나를 나눠 씀), `world.shadows_wanted`

### 전/후 (W12, 2026-11-03 — 기준 `bb07ed2` + 재연 도구, 같은 판 `game8.rec` 8명·버섯 맵, 1280×720)

스크립트 ms/프레임 (재연 120fps, 그리기 끔, `--prof`, 기준/지금 번갈아 3번씩 평균 — 컨테이너 부하 평균 22~26, 다른 작업과 같이 돎):

| 항목 | 기준 | 지금 |
| --- | --- | --- |
| **스크립트 합** (평균 · 중앙 프레임) | **6.30 · 4.88** | **4.80 · 4.19** |
| world bodies.update (몸 자세 전체) | 3.93 | 2.73 |
| ·몸 묶음 뼈 | 1.10 | 0.73 |
| ·몸 figureAnim | 1.07 | 0.67 |
| ·몸 래그돌 잡기·넣기 | 0.83 | 0.53 |
| ·몸 움직임 상태 · 재질 | 0.30 · 0.20 | 0.20 · 0.10 |
| ui (HUD) · 그중 아래 판 | 0.47 · (구간 없음) | 0.30 · 0.10 |
| net (받기·JSON·state 신호) | 0.27 | 0.23 |
| world 판 빛 · 격자·건축 블록 | 0.23 · 0.30 | 0.27 · 0.20 |
| 래그돌 물리 (_physics) | 0.20 | 0.13 |
| 몸 자세를 센 몸 (번/프레임, 8명) | 8 | 5.4 (안 셈 2.6) |

(W6 의 '23.2ms' 는 실제 서버·자동 조종을 같이 돌린 판의 프레임 시간 안 스크립트라 재연과 조건이 다름 — 재연은 클라 스크립트만 같은 판으로.)

그리기 (재연 `--replay-render`, 보통 화질, 같은 가상 시각에 잼):

| 장면 | 기준 그리기 · 물체 · 삼각형 · 영상 메모리 | 지금 |
| --- | --- | --- |
| 판 1인칭 | 180 · 303 · 126k · 120.3MB | 179 · 302 · 126k · 120.3MB |
| 판 3인칭 | 212 · 335 · 171k · 101.3MB | 212 · 335 · 171k · 101.2MB |
| 대기실 (수정 테마) | 388 · 879 · 207k · 113.4MB | 387 · 878 · 207k · 113.4MB |

SubViewport 는 그대로: 판 1인칭 1 (팔, 3인칭이면 꺼짐) · 대기실 3 (팔·거울 호수·큰 캐릭터) · 타이틀 1 (거울, 창의 반).

모습 (같은 가상 시각 화소 차, 차 > 8/255 인 화소 비율 — 래그돌 물리·트윈은 실제 시간이라 같은 빌드끼리도 다름):
판 3인칭 기준↔기준 2.7% · 기준↔지금 4.1% (먼 몸 팔다리 자세 60Hz) · 대기실 기준↔기준 0.9% · 기준↔지금 0.7% · 타이틀 (`tools/title_shot.gd` 6초) 0.4%

설정으로 끌 수 있는 패스 (판 3인칭 보통, 지금): 외곽선 끔 → 그리기 212→191 · 삼각형 171k→122k (몸·칸마다 뒤집은 껍질 한 번 더 = next_pass) · 그림자 끔 → 188 · 108k (해 그림자 지도 1024, 직교 한 장).

### W15 (2026-11-03) — 기준 `fb61ae8` (v0.1.2) ↔ 지금, 같은 재연·번갈아 3번 평균

재연 기록 `game8.rec` (8명·버섯 맵 pillars, 자동 조종 판, 1280×720). 이 컨테이너는 부하가 낮아 (load ~1) W12 표보다 숫자가 다 작음 — 비율로 볼 것 (W12 의 4.80ms = 여기 기준 3.3ms 자리).
재기 도구: `--census` (재연 끝에 무리별 3D 물체·외곽선 패스·삼각형, 보이는 2D 노드, viewport 마다 3D·그림자·2D 그리기 — `core/replay.gd census`).

스크립트 ms/프레임 (120fps 재연, 그리기 끔, `--prof`):

| 항목 | 기준 1인칭 | 지금 1인칭 | 기준 3인칭 | 지금 3인칭 |
| --- | --- | --- | --- | --- |
| **스크립트 합 · 중앙 프레임** | **3.38 · 3.28** | **2.64 · 2.25** (−22%) | **3.21 · 3.47** | **2.47 · 1.90** (−23%) |
| world bodies.update (몸 자세) | 1.73 | 1.28 | 1.61 | 1.14 |
| ·figureAnim · 래그돌 잡기 · 움직임 상태 · 재질 · 묶음 뼈 | 0.58 · 0.43 · 0.17 · 0.11 · 0.10 | 0.47 · 0.17 · 0.14 · 0.09 · 0.09 | | |
| 몸 자세를 센 몸 (번/프레임) | 5.35 | 4.89 | 4.54 | 3.83 |
| ui (HUD) · 판 빛 · 떨어지는 칸 | 0.27 · 0.21 · 0.11 | 0.17 · 0.09 · 0.04 | | |
| 대기실 (재연 −5초부터 3초) | 3.42 | 2.96 | | |

한 일 (모습 그대로, 렌더러와 무관):
- 래그돌 잡기: 관절 전역 자리를 GDScript 부모 사슬 곱 (조각마다 두 번) 대신 엔진 `global_transform` 한 번 · 쉬는 몸 (모터 다 셈, 대부분) 은 골반 목표만 셈 — 깨는 프레임만 팔다리 목표 속도 0 · 쉬는 몸은 `restore` 안 함 (`_apply` 가 어차피 덮음)
- figureAnim: 관절 스프링·휘청 스프링을 배열 없이 (칸마다 `[x, v]` 를 만들던 것), 걸음걸이 표·자동 로드 노드는 한 번만 찾음, 발밑 모서리 상수
- 같은 값 다시 쓰기 제거: 몸 재질 발광·피부 색 (`set_shader_parameter` — 값·재질이 같으면 건너뜀), 이름표 글자·색·크기 (예전엔 update 가 a = 1, thin_labels 가 다시 흐리게 → 이름표마다 매 프레임 두 번 다시 만듦), 핑 칸 (글자 색 덮어쓰기·바탕색·reset_size 가 HUD 비용의 절반), 판 빛 Environment 색 보정 5값 (켬·프리셋이 바뀔 때만), 빛 무리 목록·인스턴스·떨어지는 칸 (스냅샷이 바뀔 때만 — 120fps 면 같은 목록을 4번씩 쓰던 것, 하늘 블록은 반짝임 색만 매 프레임)
- 몸 자세 LOD 둘째 단 `POSE_LOD.far2` 10m 밖 30Hz (3m 안 매 프레임 · 10m 까지 60Hz · 화면 밖 20Hz 그대로)
- 거울 반사·대기실 큰 캐릭터 SubViewport 다시 그리기 60Hz 상한 (`WC.SUBVIEW_HZ`, `pose_lod.frame_due` — 60fps 이하 화면은 그대로, 120fps 면 한 프레임 걸러). 큰 캐릭터는 자세도 같이
- 투명한 화면 전체 판 안 그림: 타이틀 하얀 막 (메뉴·대기실·판 내내 a = 0 으로 그리던 것), 대기실 맵 번쩍, 판 번쩍 (`hud_extra.flash`) — 색 a = 0 은 modulate a = 0 과 달리 그리기를 안 건너뜀 (실측)
- 외곽선 껍질 (next_pass) 은 해 그림자 지도 (직교 투영) 에 안 그림 — 고도가 next_pass 도 그림자 패스에 넣어 그림자가 껍질만큼 커지고 그림자 지도 삼각형이 한 벌 더 들던 것. JS OutlineEffect 처럼. 그리기 수 세기엔 안 보임 (셰이더가 클립 밖으로 납작하게 → 래스터만 빠짐)
- 자동 화질: 고성능 외장 (`gfx_calc.FAST_RE` NVIDIA RTX·Radeon RX 네 자리) 이면 `GFX_BIG_PX_FAST` 3200×2000 까지 높음 (재혁 노트북 2880×1800 RTX 5070 = 높음, 4K = 보통, GTX·옛 RX·Quadro 는 예전 2560×1440)

그리기 (보통 화질, `--replay-render --census`, 3D + 그림자 + 2D):

| 장면 | 기준 그리기 · 물체 · 삼각형 | 지금 | 창 viewport 3D · 2D 그리기 (지금) |
| --- | --- | --- | --- |
| 판 1인칭 | 185 · 308 · 153k | 183 · 306 · 153k | 77 · 82 (+ 1인칭 팔 SubViewport 24) |
| 판 3인칭 | 188 · 311 · 172k | 187 · 310 · 172k | 106 · 81 |
| 대기실 (버섯) | 320 · 810 · 261k | 318 · 808 · 261k | 70 · **210** (2D 물체 **692**) + 거울 10 + 팔 24 + 큰 캐릭터 4 |

- **대기실이 판보다 무거운 건 3D 가 아니라 2D 화면 판**: 3D 그리기는 판과 비슷 (대기실 108 = 창 70 + 거울 10 + 팔 24 + 큰 캐릭터 4, 판 1인칭 101). 2D 는 대기실 판 131 그리기 (캐릭터 카드 9 × 4·버튼마다 바탕·외곽선 글자·글자, 글꼴 대체 (· 기호 DejaVu) 마다 묶음이 끊김 — 상태 글 한 줄이 12), 플레이어 관리 58, 위 점수 띠 16. 화면 모습을 안 바꾸고 줄일 길이 없어 (UI 모습 범위 밖) 그대로 — 목표 387 → 250 은 2D 를 굽거나 (SubViewport 에 한 번 그려 바뀔 때만) 화면 판을 다시 짜야 함
- 거울·큰 캐릭터 60Hz 상한·투명 판은 재연 (소프트웨어 GL, 4fps) 에선 매 프레임 그리는 셈이라 위 숫자에 안 보임 — 120fps 화면에서 거울 (창의 0.35×3D 배율, 그림자 지도까지 다시) 이 반으로
- 외곽선 끔 (설정) 이면 3인칭 그리기 187 → 169 · 삼각형 172k → 123k (그중 그림자 지도 63k → 38k — 이번에 껍질을 그림자에서 뺀 몫이 이만큼, 셈에는 남음), 대기실 318 → 296. 먼 몸 외곽선 생략은 외곽선 굵기가 화면 비율 고정 (720p 2.3px · 1800p 5.9px) 이라 작은 먼 몸일수록 테두리가 크게 보여 빼면 눈에 띔 → 안 함. 화면 공간 가장자리 한 패스는 지형 칸 가장자리·겹친 팔 안쪽까지 선이 생겨 모습이 바뀜 → 안 함

모습 (같은 가상 시각, 보통 화질, 차 > 8/255 인 화소 비율, 두 번씩):

| 장면 | 기준↔기준 | 지금↔지금 | 기준↔지금 |
| --- | --- | --- | --- |
| 판 3인칭 | 1.4% | 0.8~1.8% | 2.4~3.0% (먼 몸 30Hz·래그돌·빛 가루 — W12 기준 흔들림 2.7%) |
| 대기실 | 1.4% | 2.8% | 1.6~3.0% |
| 타이틀 (버섯 6초) | 0.15% | 0.24% | 0.14~0.28% |
| 메뉴 (수정, 메뉴 카메라 6초) | 0% | 0% | 0% |

자동 화질 비용 (2880×1800 = 5.18M 화소, 화소 일 = 3D 화소 × MSAA, 거울 화소):

| 화질 | 3D 배율 | 3D 화소 × MSAA | 거울 | 비고 |
| --- | --- | --- | --- | --- |
| 높음 | 1.0 | 5.18M × 4 = 20.7M | 0.5² → 1.30M | RTX 자동 (W15) |
| 보통 | 0.84 (2560×1440 상한) | 3.66M × 2 = 7.3M (35%) | (0.35×0.84)² → 0.45M | 예전 RTX 자동 |
| 낮음 | 0.71 (1920×1080) | 2.07M × 1 | 없음 | 내장 그래픽 자동 |

'높음' 이 필요한 기준 (제안): 화소 일 = 화면 화소 × 4. RTX 노트북 120fps 를 4K (33M) 까진 장담 못 해 3200×2000 (25.6M) 에서 끊음 — 재혁 PC F3 숫자 (높음·보통 각각) 로 다시 정할 것.

### 남은 큰 비용과 다음 후보 (순위, W15 재연 근거)

1. **몸 자세 1.28ms (스크립트의 48%)** — 센 몸 하나 ~0.26ms, figureAnim 0.47 이 가장 큼: 사전 (P·V·T) 기반 GDScript 라 연산 수 자체 (몸 하나 ~1000 연산). 다음: 자세 표를 PackedFloat64Array 로 (JS 정답 테스트 `test_chars` 를 같이 옮겨야 함) · 3~10m 도 120fps 에선 60Hz 라 더 줄이려면 가까운 몸도 60Hz (모습 확인 필요)
2. **대기실 2D 화면 판** — 그리기 210 · 물체 692 (판 HUD 82 · 205). 위 '대기실이 판보다 무거운 건 2D' 참고. 다음: 대기실 판을 SubViewport 에 굽고 바뀔 때만 (입력 넘기기·UI 배율·글자 빛 모습 확인 필요)
3. **외곽선 패스** — 화면 쪽은 삼각형의 ~15% (그림자 쪽은 W15 에 뺌). 먼 몸 생략·화면 공간 한 패스는 모습이 바뀜 (위). 남은 길: 떨어지는 칸 모양 (테마 칸 메시) 삼각형 줄이기
4. HUD 0.17 · net 0.23 (JSON 파싱 0.11 = 엔진) · 표식·투사체·갈고리 0.12 · 격자·건축 블록 0.10 — 작음
5. 렌더러: Forward+·Mobile 숫자는 재혁 PC (`start-lan-forward/mobile.bat`, `../README.md`)
