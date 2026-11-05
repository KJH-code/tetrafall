# Blender 캐릭터 제작 파이프라인 (W19 — 탱크 시험 제작, 고퀄 스타일화 판)

재혁 결정 (B 방식): 캐릭터 모델은 Blender 를 스크립트로 돌려 우리 규격으로 직접 만듦.
화풍 목표 (2026-11-05 재혁 확정): 로우폴리가 아닌 상용 고퀄 스타일화 (스매시 레전드·오버워치 급), **히어로 비율 (6~7등신 어른 전투원 — 치비 아님)**,
매끈한 곡면 + 단단한 갑옷, 2차 디테일 (리벳·금 테·벨트·띠), 구운 텍스처, 얇은 외곽선, 부분 틴트. 얼굴은 캐릭터에 따라 노출형 / 가림형 (탱크 = 가림형: 투구 안 작은 눈).
**v2 (같은 날 재혁 레퍼런스)**: 둥글둥글 (Mori 식 서브디비전 덩어리·튜브 팔다리) 금지 → **'디테일로 각진' 하드서피스** (평평한 면 + 작은 베벨 + 평면 음영, 판 겹침·패널 라인·능선·리벳·금 테), 덩치 큰 역삼각형 중무장 기사.
**v3 (재혁 지적)**: 옆 지느러미 삭제, 투구 = 둥근 돔 + 세로 슬릿 5 바이저 (슬릿 = 얼굴 재질 → 안 어둠 + 눈 점이 슬릿 사이로) + 양옆 피벗 원판 + 리벳 금 띠 + 볼 가드 + 이마 금 별 + 정수리 금 소켓에서 자라는 깃털,
히터 방패 (평평한 윗변·곧은 옆·아래 뾰족, `_heater`), 등 방패는 등판에 붙임 (`BACK_TARGET` → attach pos), 가죽 멜빵 + 금 버클.
**v4**: 투구 1.25배 (`HS`, 뼈 자리 그대로·메시만), 깃 = 소켓에서 솟아 큰 곡선 (3차 베지어) 으로 뒤·아래로 흐르는 얇은 깃털 6 가닥 (명암 2단 `tint`/`tint_dark`),
굽기 질감 (몸 높이 그라데이션 `hgrad`·얼룩 점 `stain`·짙은 틈 AO `ao_dist`/`ao_min`), 부위별 쇠 (`steel_bright` 어깨·투구 / `steel` / `steel_warm` 정강이·팔 보호대·손등 / `steel_dark` 틈),
흉갑 아래 곡선 장식 홈·패널 라인·허벅지 금 홈, 앞 뾰족한 스커트 판.
**v5 (재혁 '머리가 구처럼 둥긂')**: 투구를 구 대신 팔각 단면 고리 쌓기 (`RINGS`: 높이·앞·뒤·옆 반경·뒤 내림) 로 — 경사 돔·코처럼 나온 쐐기 바이저·각진 턱, 평평한 판 8면 + 이음선 리벳,
정수리 세로 능선 위 소켓, 깃 8 가닥 (낮고 풍성, 끝 2.14 m), 넓은 리벳 목 테. 이름표는 `label_lift` (json) 만큼 올림 (world/bodies.gd).
미리보기 그림 (재혁 확인용, 커밋): `preview/tank_2026-11-05_v5.png` (지금, 위에서·투구 3각도 포함) · `_v4.png` (지난 것). 게임 셰이더로 정면·옆·뒤 확인은 `stage_shot.gd -- a.png stage ext turn`.
이번엔 탱크 1명. 통과하면 나머지 7명을 같은 방식으로 (따로 작업).

## 1. 무엇이 어디에

| 파일 | 하는 일 |
| --- | --- |
| `dump_rig.gd` (고도) | 지금 구운 몸의 관절 자리·체형·방패 자리를 `ref/<id>_rig.json` 으로 뽑음 → Blender 가 같은 자리에 뼈를 세움 |
| `build_character.py` | 공통: 부품 (덩어리·둥근 상자·관·고리·원판·껍데기·늘어진 판·별 — 낮은 우리를 서브디비전 2 로 매끈하게), 가중치, UV 펼침, Cycles 굽기, 얼굴 투영, LOD, 내보내기, 미리보기 |
| `face_paint.py` | 얼굴 텍스처 그리기 (numpy): 큰 눈 (홍채 그라데이션·동공·빛 고리·반짝임 두 점·속눈썹)·눈썹·코·볼터치·입, 표정 3종 |
| `chars/<id>.py` | 캐릭터 모양 `build(k)` + 재질 느낌 `B.look(...)` + 고도 조정 값 `CFG` + 미리보기 자세 |
| `cost.gd` (고도) | 구운 몸 vs 외부 몸 (화질 high·medium·low·stage) 비용 표 + 8명 판 합 |
| `stage_shot.gd` (고도) | 대기실 무대 빛으로 몸 나란히 (색 3가지·LOD·표정) PNG — 눈으로 비교 |
| 결과 `godot/client/assets/models/ext/` | `<id>.glb` (뼈대 + LOD 메시 4: `<id>_lod0..3`) · `<id>_<소품>.glb` · `<id>_face_<표정>.png` · `<id>.json` · 고도가 뽑아 둔 텍스처 (`<id>_<id>_atlas.jpg` 등, 커밋) |

예전 시험 로봇 (Quaternius, W14) 은 `ext/robot_test.glb` — 테스트만 씀.

## 2. 설치·실행

```
# Blender 4.5 (화면 없이, GPU 없어도 됨 — 굽기는 Cycles CPU, 미리보기는 Workbench)
curl -LO https://download.blender.org/release/Blender4.5/blender-4.5.3-linux-x64.tar.xz && tar xf blender-4.5.3-linux-x64.tar.xz   # 레포 밖에
# 만들기 (레포 뿌리, ~25초): ext/ 에 tank.glb·tank_shield.glb·tank_face_*.png·tank.json, --preview 면 미리보기 (정면·3/4·옆·뒤·얼굴 둘·자세 3 + 모음 sheet + 아틀라스)
blender -b --factory-startup -P tools/blender/build_character.py -- tank --preview <밖 폴더> [--out <폴더>] [--parts] [--fast]
# 고도 import (새 텍스처·.import 생김 → 커밋) → 테스트 → 비용 표 → 눈 확인
<godot> --headless --path godot/client --import
<godot> --headless --path godot/client -s tests/run_tests.gd
<godot> --headless --path godot/client -s ../../tools/blender/cost.gd -- tank
xvfb-run -a -s "-screen 0 1600x1000x24" <godot> --path godot/client -s ../../tools/blender/stage_shot.gd -- a.png stage ext [faces]
# 게임에서 (외부 모델은 기본 끔, --ext — 배포 묶음은 start-lan-ext.bat)
xvfb-run -a -s "-screen 0 1280x720x24" <godot> --resolution 1280x720 --path godot/client -- --ext --gfx high --auto practice --char tank --view third --server ws://127.0.0.1:3119 --shot a.png --shot-after 13 --quit-after 14
```

`--parts` 부품별 삼각형 (서브디비전 뒤), `--fast` 굽기 256px (모양만 빨리 볼 때). 다시 만들면 모양은 같지만 glb 바이트는 조금 다름 (굽기 잡음·법선).

## 3. 규격표 (7명 확장 때 지킬 것)

| 항목 | 규격 |
| --- | --- |
| 좌표 | 부품은 게임 좌표 (앞 +x, 왼쪽 +y, 위 +z, m, 발바닥 0). Blender 로는 (X, Y, Z) = (y, −x, z), glTF 앞 +Z |
| 비율 | **히어로 비율**: 뼈 자리를 `chars/<id>.py` `HERO` 로 새로 정함 (탱크: 골반 0.93·어깨 1.47·목 1.56 m, 깃 끝 ~2.0 m, 머리 ~0.33 m → 6등신). 쉬는 **방향** (팔 내림 각·다리 곧게) 은 우리 코드 몸 (`ref/<id>_rig.json`) 과 같게 — 고도 external.gd 는 관절 **회전** 만 옮기고 뼈 길이·자리는 모델 것 (골반 오르내림은 `root_k` = 모델 골반 / 우리 골반 배율), 그래서 다리·팔 길이가 달라도 걷기·평타·래그돌이 그대로 붙음. 1인칭 팔은 `vm_snap` (팔꿈치를 우리 팔꿈치 자리에) 로 화면 구석 자리 유지. 안쪽 몸 노드에 붙는 소품 (방패) 은 `attach.pos` 로 모델 허리 높이만큼 올림 (`_shield_pos`) |
| 뼈 | 16개, 이름 = 우리 관절 그대로 (`hips waist torso neck shoulder_R elbow_R hand_R … foot_L`), 손가락·머리 뼈 없음 (머리 = neck). 쉬는 자세 = 우리 몸 (팔 내림) |
| 부품 | `HARD = True` (chars/<id>.py): 서브디비전 없이 각진 면 + 베벨 (모서리 각 30° 넘는 곳, 7 mm, 1단) + 평면 음영 — 면이 보이는 하드서피스. 껍데기는 정육면체 구 (cuts 2~4) 를 잘라 면진 판, 팔다리 속은 8각 관, 리벳만 `sub=1` (둥근 머리). `HARD = False` 면 예전 매끈 (서브디비전 2). 딱딱한 것 (갑옷·투구·장갑) = 뼈 하나 100%, 굽는 것 (`blend=[뼈…]`: 옷 몸통·소매·허벅지·허리 천) = 자동 가중치 → 허락 뼈만 3개까지 |
| LOD | 한 glb 안 메시 4 (같은 뼈·같은 UV·같은 텍스처, Decimate): **lod0 = 대기실 큰 캐릭터·초상·1인칭 팔 (≤ 4만)**, lod1 = 판 화질 높음, lod2 = 보통, lod3 = 낮음. `<id>.json` `lods` 가 화면·화질 → 메시 이름. 판 LOD 는 '8명 판 합 (몸 + 방패) ≤ 구운 몸 × 높음 2.5·보통 1.8·낮음 1.0' (탱크: 10.5k·7.2k·3.4k + 방패 1.4k) |
| 텍스처 | 몸 알베도 아틀라스 1024² (JPEG, glb 안) = Cycles 굽기: look 색 × AO × 위쪽 빛 × 붓 얼룩 + 모서리 빛 (pointiness) + 쇠 광택 띠. 소품 512². 얼굴 512² PNG (표정마다) |
| 재질 | 2개: `<id>` (아틀라스, 꼭짓점 색 하양) · `<id>_face` (얼굴 — 외곽선 없음, 표정 교체). 고도에서 몸 그리기 = 몸 2 (툰 + 외곽선) + 얼굴 1 + 방패 2 = 5 |
| 몸 색 (틴트 마스크) | 둘째 UV (고도 UV2) x = 1 인 면만 플레이어 색을 **곱함** (`skin_multiply` — 굽은 그늘이 남음). 그 면은 회백 (0xeeeeee) 으로 굽힘. **몸 전체 틴트 금지** — 탱크는 깃·허리 천·방패 판만 (몸 넓이의 ~10%, 테스트 2~25%) |
| 얼굴 (두 가지) | 머리 덩어리 = `face=True` 부품, 앞쪽 면에 정면 평면 투영 (얼굴 칸 [-1,1] = 머리 반지름), 뒤쪽 면은 구석 색. 코드 몸의 눈 (addEyes) 은 외부 모델이면 안 그림. **가림형** (탱크 투구·닌자 복면·광전사 마스크): 얼굴 덩어리를 어두운 안쪽 (`visor` look) 으로, 투구 껍데기에 눈 틈을 뚫고 `k.face_painter = face_paint.paint_visor` (어둠 + 작은 빛나는 눈, 256²), json `face_glow` 로 눈이 제 색으로 빛남. **노출형** (바드·사냥꾼 등 얼굴이 보이는 캐릭터): `face_paint.paint_face` (512², 눈·눈썹·입) — 히어로 비율이면 눈을 작고 어른스럽게 다시 그려야 함 |
| 표정 | `faces {idle, hit, attack}`: 경직·맞은 직후 `EXT_HIT_FACE_S` = hit, 공격 동작 = attack, 나머지 idle (external.gd `expression()`). 가림형은 눈만 바뀜 (둥근 빛 점 / > < / 눈꼬리 올라간 가는 눈) |
| 그림 손질 (json) | `toon_steps` [0.66, 0.84, 1.0] (칠한 그늘이 있으니 부드럽게) · `outline` 0.45 (외곽선 굵기 배율 — 얇게) · `rim` [0.35, 3] (가장자리 빛) |
| 분리 소품 | `prop="이름"` 부품 → `<id>_<이름>.glb` (자기 아틀라스, `PROP_TRIS` 1400), json `attach` `{"glb", "ref": "shields.back"}` (안쪽 몸 소품 노드 아래 → 보이기·1인칭 쥐기는 예전 그대로) |
| 밝기 | 몸 색 칸 뺀 넓이 평균 밝기 (텍스처 포함) ≥ 구운 몸 × 0.92 (`test_blender_tank_brightness`). 대기실·초상은 무대 흰 빛 (`portrait.gd stage_light`) |

## 4. 새 캐릭터 만드는 순서

1. `dump_rig.gd -- <id>` → `ref/<id>_rig.json`
2. `chars/<id>.py`: JS `figure.js` `dress<Char>` 의 정체성 (무기·모자·색) 을 보며 `B.look(이름, 색, kind)` (metal·cloth·leather·skin·tint) 로 재질을 정하고, 부품을 관절 자리에 (`k.j("elbow_R")`, 곡면 위 자리는 `_on(가운데, 반지름, 방향)`). 머리 덩어리는 `face=True` + `k.face_frame`, 플레이어 색은 `tint` look 으로 일부만, 굽는 곳 `blend=[…]`, 소품 `prop=`
3. `--fast --preview` 로 모양을 보며 고침 → 실루엣·비율·디테일 3~4번 반복 → `--preview` (굽기 1024) → `stage_shot.gd` 로 게임 셰이더에서 색 3가지·LOD·표정 확인
4. 고도 import → `--ext --char <id>` 3인칭·1인칭·대기실·초상, `cost.gd` (8명 합 배율)
5. 테스트: `tests/test_external.gd` 의 `test_blender_tank_*` 를 그 캐릭터로 (뼈 이름·LOD 예산·몸 색 칸 넓이·표정·밝기·크기 1·뼈 자리)

## 5. 탱크 결과 (2026-11-05)

모양 (히어로 비율 6등신): 닫힌 투구 (가로 눈 틈·T 바이저·얼굴 능선·이마 금 테·볼 리벳·아래 테·쇠 마루·플레이어 색 깃, 안쪽 어둠에 빛나는 작은 눈 — 표정 3),
넓은 흉갑 (가운데 능선·금 별·리벳·금 테) + 플레이어 색 어깨띠 (금 고리), 겹친 배 가리개 3, 큰 두 겹 어깨 갑옷 (금 테·리벳), 위팔 갑옷·팔꿈치·팔 보호대·금 손목 테·가죽 장갑 + 쇠 손등,
가죽 벨트·금 버클·주머니, 플레이어 색 허리 천 (앞·뒤, 금 단), 쇠 치마판 두 겹, 허벅지 갑옷·무릎 받이·정강이 갑옷·장화, 짙은 청회 사슬 속옷, 큰 둥근 방패 (따로).

`cost.gd` (헤드리스, 판 몸 하나):

| | 구운 몸 | 외부 high | 외부 medium | 외부 low | 외부 stage |
| --- | --- | --- | --- | --- | --- |
| 삼각형 (몸 + 보이는 방패) | 4840 | 11900 | 8600 | 4773 | 21330 (하드서피스 원본 1.99만 — 줄이지 않음) |
| 그리기 (외곽선 포함) | 6 | 5 | 5 | 5 | 5 |
| 뼈 | 27 | 16 | 16 | 16 | 16 |
| 몸 만들기 처음 / 그 뒤 | 5.8 / 0.71 ms | ~75 / 1.9 ms | | | |
| 자세 + 뼈 맞추기 | 0.14 ms | 0.19 ms | | | |
| 1인칭 팔 삼각형 / 그리기 | 2832 / 66 | 2376 / 2 | | | |
| **8명 판 삼각형 (구운 대비)** | 38.7k (1.00×) | 95.2k (2.46×) | 68.8k (1.78×) | 38.2k (0.99×) | (한 명만) |

v2 모양: 十 슬릿 닫힌 면진 투구 (금 이마 테·정수리 금 능선·옆 지느러미·숨구멍·볼 리벳, 안 어둠에 작은 빛나는 눈) + 플레이어 색 깃, 두 겹 흉갑 (가운데 능선·4갈래 금 별·금 테 둘·리벳),
3겹 어깨 갑옷 (능선·금 테·리벳) + 플레이어 색 안감, 판 겹친 위팔·허벅지 (3겹), 팔꿈치·무릎 날개, 큰 장갑 주먹 (쇠 손등·손마디), 금 능선 정강이 갑옷·육중한 장화,
방패꼴 앞 허리 천·넓은 뒤 천·무릎 보석 (플레이어 색), 어두운 사슬 관절 틈, 면진 팔각 방패 (플레이어 색 판·쇠 안판·금 十·두꺼운 테·리벳 8).

처음 75 ms = 판 처음 몸 하나 만들 때 한 번 (.glb·텍스처 읽기, LOD 4 표면 나누기, 1인칭 팔 메시) — 그 뒤는 1.9 ms. 이 컨테이너는 소프트웨어 렌더라 프레임 ms 는 의미 없음 → **재혁 PC F3 로 8명 판 FPS 확인** 필요.

## 6. 한계·못 한 것

- **프로시저럴 한계**: 부품 조립 + 서브디비전이라 '손으로 조각한' 유기적 형태 (머리카락 가닥·천 주름·근육·얼굴 입체 (코·볼 볼륨)) 는 못 냄 — 탱크처럼 갑옷·둥근 물건 위주 캐릭터는 잘 맞고, 머리카락·옷 주름이 핵심인 캐릭터 (바드·사냥꾼) 는 단순해 보일 수 있음. 대안: 그 부분만 AI 생성 (Meshy·Tripo) 메시를 받아 Blender 스크립트에서 붙이기 (EXTERNAL.md 의 외부 모델 길과 섞기)
- 텍스처는 '굽기' 라 붓 자국·손그림 무늬 (천 바느질·흠집) 는 약함 — 필요하면 look 에 무늬 노드를 더하거나 손그림 텍스처를 덮어야 함
- LOD 는 Decimate 라 낮은 단계 (3.4k) 에서 UV 이음매 근처 색 얼룩·각이 보임 (화질 낮음 전용)
- 허리 천은 따로 흔들리지 않고 허벅지 가중치로 따라 휨, 깃도 고정
- 표정은 텍스처 3장 교체만 (눈 깜빡임·입 모양 섞기 없음)
- 히어로 비율은 모델 뼈 길이가 코드 몸과 달라 **판정·효과 자리 (주먹 끝·방패 앞) 와 보이는 손 자리가 조금 어긋남** (서버 판정은 그대로, 보기만), 모델이 코드 몸보다 큼 (깃 끝 2.0 m vs 1.84 m) — 이름표·카메라는 그대로
- 방패는 안쪽 몸 허리 노드 아래 + 고정 올림 (attach pos) 이라 허리를 크게 비틀면 모델 등과 조금 뜰 수 있음
- glb 4 LOD + 아틀라스로 tank.glb ~4 MB (웹 첫 로딩 +) — 8명이면 ~30 MB, 줄이려면 lod0 을 따로 파일로 (대기실에서만 받기) 또는 텍스처 512
- 판 중 플레이어 색이 대기실에서 바꾼 색을 늦게 따라가는 경우 (자동 조종 `--color` 로 볼 때) — 구운 몸도 같아서 이번 범위 밖


## 7. W20 — Tripo 기사로 탱크 몸 교체 (2026-11-05, `tools/blender/tripo/`)

재혁 결정: 탱크 몸 = Tripo 로 만든 기사 (`src/tank_tripo_15k.glb`), W19 의 프로시저럴 탱크 (`chars/tank.py`·`build_character.py tank`) 는 쓰지 않음 (파일은 남김). 원본은 판금 조각이 **한 덩어리로 붙은 메시 하나** (위치로 합치면 조각이 따로 안 떨어짐) 라 조각 단위 단단한 가중치가 안 되고, 꼭짓점마다 뼈 캡슐까지 거리로 가중치.

```
# 몸: 리깅 → tank_rigged.glb (lod0 한 메시), 그다음 LOD 3개 (meshopt, UV 이음선 안 찢김 — Blender Decimate 는 찢어짐)
blender -b --factory-startup -P tools/blender/tripo/rig_tank.py -- --out <폴더> [--preview <폴더>] [--dbg]
node tools/blender/tripo/lods.mjs <폴더>/tank_rigged.glb <폴더>/tank.glb        # npm i @gltf-transform/core@4 @gltf-transform/functions@4 meshoptimizer@0.22 (레포 밖, NODE_PATH)
# 소품: 방패·망치 (src/cellB_60k.glb 에서 UV 덩어리를 방패 판 평면 거리·위치로 골라 떼어 냄) → 줄이기
blender -b --factory-startup -P tools/blender/tripo/rig_props.py -- --out <폴더>
node tools/blender/tripo/lods.mjs prop <폴더>/tank_shield_hi.glb <폴더>/tank_shield_s.glb 1500   # 망치 900 (tank_hammer.glb)
blender -b --factory-startup -P tools/blender/tripo/rig_props.py -- --plate <폴더>/tank_shield_s.glb <폴더>/tank_shield.glb   # 방패 뒷판
# 자세별 확인 (걷기·팔 들기·쪼그림·점프, 앞·옆·뒤)
blender -b --factory-startup -P tools/blender/tripo/verify_glb.py -- <tank.glb> <폴더> lod0,lod2
```

- 뼈 16 (우리 관절 이름), 키 1.9 m, 앞 -Y (glTF +Z). 관절 자리·캡슐 `rig_tank.py` `JL`·`CAPS`, 가중치 부드러움 `TAU`.
- 몸 색 칸 (`tint: "mask"`) = 빨강 칸 (망토·앞 천·목도리, 몸 넓이 ~31%): 텍스처의 빨강을 밝기만 남긴 회백으로 바꾸고 (`GRAY`) UV2.x = 1 로 표시 → 플레이어 색을 곱함. 꼭짓점 색 (흰) 필요.
- 망토 = 몸통 뼈 (아래는 허리·골반으로 섞임), 망토와 팔을 잇는 삼각형은 팔을 들 때 가시처럼 늘어나서 뗌 (`CUT`).
- 텍스처 알베도 한 장 (원본 4096 → 2048 jpg, 법선·금속 그림 뺌). 표정·얼굴 재질 없음 (닫힌 투구가 텍스처에 구워짐) → `tank.json` 에 `faces` 없음.
- LOD: stage = 원본 1.49만, 판 높음·보통·낮음 = 5000·4000·3000 (`lods.mjs` `TARGETS`). 방패 2500·망치 900 (소품은 meshopt 한계로 목표보다 큼).
- **1인칭 팔** (`vm_node: "tank_vm"`): 원본 팔을 가르는 방식은 열린 껍질·가시가 나와서 버리고, `rig_tank.py` `make_vm_arms` 가 닫힌 팔 메시 (8각 앞팔 보호대 + 금 띠 + 주먹 + 손등판, 두 팔 160 삼각형, 뼈 elbow·hand 에 단단히) 를 glb 안에 `tank_vm` 노드로 따로 만듦. 색은 원본 팔 텍스처의 텍셀 한 점씩 (`VM_STEEL_PCT`·`VM_GLOVE_PCT`). 로더 (`external.gd`) 는 `vm_node` 가 있으면 1인칭에서 그 메시만 그리고 판 몸에선 안 그림.
- **해머**: `tank.json` attach 2개 (`joint: hand_R`) — 판 몸 (scale 0.526 = 1/키) 과 1인칭 (`vm: true`, `third: false`, scale 0.3). 오른손 뼈를 따라 들리고 휘두름. 확인 `tools/blender/move_shot.gd` (동작별 자세 나란히).
- **방패 뒷판**: 방패를 줄인 뒤 (`lods.mjs prop`) `rig_props.py --plate <줄인.glb> <출력.glb>` 가 뒷면 윤곽 볼록 껍질 한 장을 더함 (원본 뒷면에 쥔 팔이 가렸던 구멍을 막음, meshopt 가 평평한 판을 찌그러뜨려서 줄인 뒤에 더함).
- **다리 갈라짐**: `smooth_leg_weights` (z < 0.78 가중치를 이웃과 4번 섞음) 로 쪼그림·점프에서 판 조각이 따로 노는 것이 줄었지만 정강이 가장자리가 들쭉날쭉함은 남음.
- 알려진 한계: 주먹·앞팔은 상자꼴로 단순화됨 (원본 갑옷 모양 아님). 1인칭에서 방패는 뒷판 (어두운 평면) 만 보임. 쪼그림·점프 때 정강이 가장자리가 거칠다.


## 8. W21 — 자동 리깅 닌자 (2026-11-05, `tools/blender/tripo/rig_ninja.py`)

재혁 결정: 캐릭터는 모델 생성 도구의 **자동 리깅** 결과를 받아 게임에 넣음. 닌자가 첫 번째. 원본 `tripo/src/ninja_tripo_rigged.glb` (스킨 메시 하나 17,756 삼각형, Mixamo 식 뼈 65, 텍스처 3장 — 알베도 4096).
기사 (7절) 와 달리 **뼈·가중치는 원본 그대로** 쓰고 (뼈 이름 매칭은 로더 `ALIASES`), 아래만 손봄.

```
blender -b --factory-startup -P tools/blender/tripo/rig_ninja.py -- --out <폴더>           # → <폴더>/ninja_rigged.glb
LOD_LOCK=1 node tools/blender/tripo/lods.mjs <폴더>/ninja_rigged.glb <폴더>/ninja.glb ninja 5000   # 판 LOD 하나 (아래), 4번째 인자 = 이름, 5번째 = 판 LOD 삼각형 목표 (쉼표로 여러 개), 6번째 = stage 도 줄일 때, LOD_LOCK=1 = 가장자리 고정
blender -b --factory-startup -P tools/blender/tripo/rig_ninja.py -- --dagger <ext>/ninja_dagger.glb   # 손에 쥐는 단검 소품 (칼날·손잡이·날밑 3 조각)
```

- **뼈대 노드 올림**: 원본은 뼈대 노드가 -0.488 m 내려가 있고 메시는 올라가 있어서 (둘이 합쳐 발바닥 0) 로더의 쉬는 자세 상자 계산이 0.9 m 어긋나 **모델이 허공에 뜸** → 메시·뼈대를 세계 좌표로 굽고 변환을 항등으로.
- **팔 가중치 정리** (`trim_arm_weights`): 허리춤 천이 손 바로 옆에 붙어 있어서 자동 가중치가 천 일부를 손·아래팔에 매어 놓음 → 팔을 뻗으면 천이 따라와 허리에서 손까지 검은 가시가 생김. 팔·손가락 뼈 가중치를 그 뼈 선분에서 `ARM_R` (위팔 8·아래팔 6·손 5·손가락 3.5 cm) 안의 꼭짓점에만 남김 (2651 꼭짓점 정리). 목도리 꼬리는 원본이 오른 빗장·팔에 매어서 몸통 (위로 갈수록 목) 뼈로 옮김 (`TAIL_Z`·`TAIL_SIDE`).
- **몸 색 칸** (`tint: "mask"`): 알베도의 빨강 (목도리·허리띠·칼자루 장식, 텍스처 13% / 넓이 19%) 을 밝기만 남긴 회백 (`GRAY`) 으로 바꾸고 UV2.x = 1 + 꼭짓점 색 (흰). 알베도만 남김 (법선·금속 그림 뺌, 4096 → 2048 jpg), 이음선 법선 합침.
- **LOD**: UV 조각이 너무 잘게 나뉘어 있어 (위치 8875 개 vs 꼭짓점 23270 개) meshopt 가 이음선을 안 넘으면 **약 8500 삼각형** 밑으로 안 내려감 (기사는 3000 까지 내려감). 가장자리를 안 잠그면 (`lockBorder: false`, 기사 방식) 8495 에서 치마·목도리에 검은 구멍이 나서 `LOD_LOCK=1` (가장자리 잠금) 으로 8520. 이음선을 넘게 하는 `Permissive` (meshoptimizer 1.x) 는 5000 에서 몸에 구멍·뒤집힌 삼각형이 생겨 못 씀 → 판 LOD 는 하나 (8500, `lods.mjs` 로 만든 `ninja_lod1`) 를 high·medium·low 가 같이 쓰고, stage = 원본 17,756 그대로. 더 내리려면 새 UV 로 알베도를 다시 굽는 길 (몸 LOD 마다 텍스처 하나) 뿐.
- **단검**: 코드 몸의 단검·손 구슬 (`keep`) 은 모델 손과 팔 길이가 달라 허공에 뜸 → `attach` 두 손 뼈에 `ninja_dagger.glb` (칼날 +Y = 손 뼈 방향, 판 몸만).
- **1인칭**: 닫힌 팔 메시 (`vm_node`) 를 따로 안 만들고 로더의 팔꿈치 아래 삼각형 가르기 그대로 (소매 끝이 화면 아래 밖이라 열린 단면이 안 보임). 확인 `--act-shots`.
- 확인 그림: `stage_shot.gd`·`move_shot.gd` 에 `SHOT_CHAR=ninja` (동작 목록 `SHOT_MOVES`, 확대 `SHOT_FOV`) 환경 변수.
- 알려진 한계: 목도리 꼬리가 몸통에 붙은 채 늘 뒤로 날린 모양 그대로 (자세에 안 흔들림), 코드 몸과 팔·다리 길이가 달라 서버 판정 위치 (주먹·칼 끝) 와 보이는 칼이 조금 다름, glb 3.4 MB.



## 9. W23 — 닌자 1인칭 팔·동작 클립·목도리 뼈 (2026-11-05)

```
blender -b --factory-startup -P tools/blender/tripo/rig_ninja.py -- --out <폴더>   # → ninja_rigged.glb (+ 닫힌 1인칭 팔 ninja_vm, 목도리 꼬리 뼈 Scarf1~3)
LOD_LOCK=1 node tools/blender/tripo/lods.mjs <폴더>/ninja_rigged.glb <폴더>/ninja.glb ninja 5000
blender -b --factory-startup -P tools/blender/tripo/anim_ninja.py -- --rig <폴더>/ninja_rigged.glb --out <폴더>/ninja_anim.glb   # 동작 클립 (뼈대 + 키프레임만)
node tools/blender/tripo/anim_pack.mjs <폴더>/ninja_anim.glb <폴더>/ninja_anim_p.glb   # 키 줄이기 (prune 은 쓰지 말 것 — 뼈대가 지워져 트랙이 뼈에서 떨어짐)
```
- `ninja_vm.py`: 아래팔 축 수직 평면 (팔꿈치에서 12%) 으로 몸 전체를 잘라 손 든 덩어리만 남기고 단면을 메워 오므림. glTF 가져오기가 UV 이음선마다 꼭짓점을 둘로 나눠서 `remove_doubles` 먼저. 꼭짓점 그룹 이름은 메시 데이터에 있어서 오브젝트에 다시 만들어야 내보내기에 스킨이 붙음.
- `anim_ninja.py` / `clips_ninja.py`: 자세 = 관절 각 (도) 표, 뼈마다 부모가 돌아간 뒤 Blender 축 (앞 +X, 왼 +Y, 위 +Z) 으로 FK. 동작 눈금 WIND 0.30 · STRIKE 0.40 · REC 0.80 (`chars/ext_clips.gd MARKS` 와 같아야 함). 손으로 찍은 키라 품질 한계 있음 — Mixamo 라이브러리는 로그인이 필요해 자동화 못 함.
- `ninja_scarf.py`: 붉은 꼬리 꼭짓점 (몸 뒤 x < -0.04) 275 개를 뼈 3개 사슬에 (위쪽은 몸통 가중치와 섞임).
