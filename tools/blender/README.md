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


## 7. W20 — Tripo 기사로 탱크 몸 교체 (2026-11-05, `tools/blender/tripo/`) — **W22 (9절) 가 대체함, 이 절은 기록 (rig_tank.py·rig_props.py 는 남김 — 빨강 판정·법선 합침 함수를 W21·W22 가 가져다 씀)**

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
blender -b --factory-startup -P tools/blender/tripo/rig_ninja.py -- --dagger <ext>/ninja_dagger.glb   # 손에 쥐는 단검 소품 (칼날·손잡이·날밑 3 조각을 한 메시·한 재질로 합침, W32)
```

- **뼈대 노드 올림**: 원본은 뼈대 노드가 -0.488 m 내려가 있고 메시는 올라가 있어서 (둘이 합쳐 발바닥 0) 로더의 쉬는 자세 상자 계산이 0.9 m 어긋나 **모델이 허공에 뜸** → 메시·뼈대를 세계 좌표로 굽고 변환을 항등으로.
- **팔 가중치 정리** (`trim_arm_weights`): 허리춤 천이 손 바로 옆에 붙어 있어서 자동 가중치가 천 일부를 손·아래팔에 매어 놓음 → 팔을 뻗으면 천이 따라와 허리에서 손까지 검은 가시가 생김. 팔·손가락 뼈 가중치를 그 뼈 선분에서 `ARM_R` (위팔 8·아래팔 6·손 5·손가락 3.5 cm) 안의 꼭짓점에만 남김 (2651 꼭짓점 정리). 목도리 꼬리는 원본이 오른 빗장·팔에 매어서 몸통 (위로 갈수록 목) 뼈로 옮김 (`TAIL_Z`·`TAIL_SIDE`).
- **몸 색 칸** (`tint: "mask"`): 알베도의 빨강 (목도리·허리띠·칼자루 장식, 텍스처 13% / 넓이 19%) 을 밝기만 남긴 회백 (`GRAY`) 으로 바꾸고 UV2.x = 1 + 꼭짓점 색 (흰). 알베도만 남김 (법선·금속 그림 뺌, 4096 → 2048 jpg), 이음선 법선 합침.
- **LOD**: UV 조각이 너무 잘게 나뉘어 있어 (위치 8875 개 vs 꼭짓점 23270 개) meshopt 가 이음선을 안 넘으면 **약 8500 삼각형** 밑으로 안 내려감 (기사는 3000 까지 내려감). 가장자리를 안 잠그면 (`lockBorder: false`, 기사 방식) 8495 에서 치마·목도리에 검은 구멍이 나서 `LOD_LOCK=1` (가장자리 잠금) 으로 8520. 이음선을 넘게 하는 `Permissive` (meshoptimizer 1.x) 는 5000 에서 몸에 구멍·뒤집힌 삼각형이 생겨 못 씀 → 판 LOD 는 하나 (8500, `lods.mjs` 로 만든 `ninja_lod1`) 를 high·medium·low 가 같이 쓰고, stage = 원본 17,756 그대로. 더 내리려면 새 UV 로 알베도를 다시 굽는 길 (몸 LOD 마다 텍스처 하나) 뿐.
- **단검**: 코드 몸의 단검·손 구슬 (`keep`) 은 모델 손과 팔 길이가 달라 허공에 뜸 → `attach` 두 손 뼈에 `ninja_dagger.glb` (칼날 +Y = 손 뼈 방향, 판 몸만). **W32**: 세 조각 (재질 셋 = 그리기 3 × 색·외곽선) 을 `join_palette` 로 한 메시·한 재질로 합침 — 조각 색은 12×1 팔레트 그림 (조각마다 4 칸, UV 는 칸 가운데라 가장자리 안 섞임, PNG 무손실·밉맵 없음 — 고도 `.import` 에서 `mipmaps/generate=false`). 모양·색·자리 그대로 (삼각형 46 = 칼날 6 + 손잡이 28 + 날밑 12, 색은 선형 값을 sRGB 로 인코딩해 같은 색). 닌자 몸 그리기 14회 → 6회 (단검 둘 × 색·외곽선 4 + 몸 2).
- **1인칭**: 닫힌 팔 메시 (`vm_node`) 를 따로 안 만들고 로더의 팔꿈치 아래 삼각형 가르기 그대로 (소매 끝이 화면 아래 밖이라 열린 단면이 안 보임). 확인 `--act-shots`.
- 확인 그림: `stage_shot.gd`·`move_shot.gd` 에 `SHOT_CHAR=ninja` (동작 목록 `SHOT_MOVES`, 확대 `SHOT_FOV`) 환경 변수.
- 알려진 한계: 목도리 꼬리가 몸통에 붙은 채 늘 뒤로 날린 모양 그대로 (자세에 안 흔들림), 코드 몸과 팔·다리 길이가 달라 서버 판정 위치 (주먹·칼 끝) 와 보이는 칼이 조금 다름, glb 3.4 MB.


## 9. W22 — 자동 리깅 탱크 (2026-11-05, `tools/blender/tripo/rig_tank_auto.py`)

재혁 결정: 탱크도 자동 리깅 결과로 (W20 직접 리깅 대체). 원본 `tripo/src/tank_tripo_rigged.glb` (스킨 메시 하나 19,429 삼각형, Mixamo 식 뼈 65, 알베도 4096, 애니메이션 없음, 방패·해머가 몸 메시에 붙어 있음). 닌자 (8절) 와 같은 길.

```
blender -b --factory-startup -P tools/blender/tripo/rig_tank_auto.py -- --out <폴더>            # → <폴더>/tank_rigged.glb
LOD_LOCK=1 node tools/blender/tripo/lods.mjs <폴더>/tank_rigged.glb <폴더>/tank.glb tank 5000   # 판 LOD 하나 (약 8940), stage = 원본 그대로
blender -b --factory-startup -P tools/blender/tripo/posecheck.py -- <리깅.glb> <폴더> [메시 이름] [자세,…]   # 걷기·팔 들기·쪼그림·점프 앞·옆·뒤 그림 (뼈 이름 Mixamo)
```

- **좌우 뒤집기** (`mirror_lr`): 원본은 방패가 캐릭터 오른손 (Mixamo `Right*` 뼈에 가중치)·해머가 왼손인데, 게임 탱크는 방패 왼손 (1인칭 `viewmodel` 이 왼손으로 방패를 쥠)·평타 오른손 (해머) → 메시·뼈대를 Y 로 뒤집고 면 순서·뼈·가중치 이름 Left↔Right 를 맞바꿈. (지시서는 '방패 왼팔'이라 적었지만 원본 뼈 가중치로는 오른팔이었음.)
- 뼈대 노드·메시 변환은 세계 좌표로 굽고 항등으로 (닌자와 같은 안전장치, 탱크는 어긋남이 거의 없었지만 같은 코드).
- **가중치는 원본 그대로**: 팔 들기·쪼그림·평타·땅 가르기·R·점프 자세에서 갈라짐·가시 없음 (허리 천은 손에 안 묶임 — 닌자 같은 `trim_arm_weights` 불필요, 오히려 방패·해머가 손·아래팔 뼈에 매여 있어서 팔 가중치를 깎으면 안 됨). 방패는 `LeftHandMiddle3` (손가락 끝) + `LeftForeArm`, 해머는 오른 손가락·아래팔 — 로더가 손가락 뼈는 부모 (손) 를 따라가게 해서 단단히 따라감.
- **몸 색 칸** (`tint: "mask"`): 알베도의 빨강 중 **큰 덩어리** (이웃으로 이어진 꼭짓점 `MIN_RED_CLUSTER` = 150 이상: 목도리·앞 허리 천) 만 회백 (`GRAY`) + UV2.x = 1 + 꼭짓점 색 (흰). 허리 주머니·갑옷의 붉은 점·망토 얼룩 (작은 빨강 조각) 은 원래 색 그대로 둠 (몸 색 칸 5.6% — 넓이). 굽는 자리는 몸 색 칸 삼각형의 UV 칸 (+3 텍셀) 안으로 한정.
- 알베도 밝기: 어두운 칠 (검은 팔·장갑) 을 `LIFT` = 0.8 (선형 거듭제곱) 로 끌어올림 — 안 올리면 구운 탱크 대비 0.55 로 시커멓게 뭉침 (테스트 밝기 0.65 이상). 알베도만 (법선·ORM 뺌), 4096 → 2048 jpg.
- **LOD**: 닌자와 같은 한계 — UV 조각이 잘게 나뉘어 meshopt 가 이음선을 안 넘으면 약 8940 아래로 안 내려감 (`LOD_LOCK=1`, 오차를 키워도 같음). 판 LOD 하나 (high·medium·low 같이 씀) + stage 19,429 (대기실·초상·1인칭). glb 3.7 MB.
- **1인칭**: 닫힌 팔 메시 (`vm_node`) 안 만들고 로더의 팔꿈치 아래 가르기 그대로 — 방패가 손가락·아래팔 뼈에 매여 있어서 같이 따라옴. 방패 올려치기·내려치기에서 쥔 손 (IK 로 코드 방패 자리까지 내려감) 과 함께 방패가 움직이고 주먹·끈이 방패 앞에 보임. 코드 방패 (`shields` refs) 는 안 씀. 알려진 한계: 방패 동작 때 모델 방패가 W20 소품 (더 작았음) 보다 커서 화면 가운데를 많이 가림.
- 확인 그림: `stage_shot.gd`·`move_shot.gd` 에 `SHOT_CHAR=tank` (동작 목록 `SHOT_MOVES`, 확대 `SHOT_FOV`), 게임 `--ext --act-freeze`.
- 알려진 한계: 코드 몸과 팔·다리 길이가 달라 서버 판정 위치 (주먹·해머 끝) 와 보이는 해머가 조금 다름, 방패가 몸 옆으로 0.15 m 튀어나와 좁은 틈에선 방패만 벽에 닿아 보일 수 있음 (판정은 서버라 무관).


## 10. W23 — 닌자 1인칭 팔·동작 클립·목도리 뼈 (2026-11-05)

```
blender -b --factory-startup -P tools/blender/tripo/rig_ninja.py -- --out <폴더>   # → ninja_rigged.glb (+ 닫힌 1인칭 팔 ninja_vm, 목도리 꼬리 뼈 Scarf1~3)
LOD_LOCK=1 node tools/blender/tripo/lods.mjs <폴더>/ninja_rigged.glb <폴더>/ninja.glb ninja 5000
blender -b --factory-startup -P tools/blender/tripo/anim_ninja.py -- --rig <폴더>/ninja_rigged.glb --out <폴더>/ninja_anim.glb   # 동작 클립 (뼈대 + 키프레임만)
node tools/blender/tripo/anim_pack.mjs <폴더>/ninja_anim.glb <폴더>/ninja_anim_p.glb   # 키 줄이기 (prune 은 쓰지 말 것 — 뼈대가 지워져 트랙이 뼈에서 떨어짐)
```
- `ninja_vm.py`: 아래팔 축 수직 평면 (팔꿈치에서 12%) 으로 몸 전체를 잘라 손 든 덩어리만 남기고 단면을 메워 오므림. glTF 가져오기가 UV 이음선마다 꼭짓점을 둘로 나눠서 `remove_doubles` 먼저. 꼭짓점 그룹 이름은 메시 데이터에 있어서 오브젝트에 다시 만들어야 내보내기에 스킨이 붙음.
- `anim_ninja.py` / `clips_ninja.py`: 자세 = 관절 각 (도) 표, 뼈마다 부모가 돌아간 뒤 Blender 축 (앞 +X, 왼 +Y, 위 +Z) 으로 FK. 동작 눈금 WIND 0.30 · STRIKE 0.40 · REC 0.80 (`chars/ext_clips.gd MARKS` 와 같아야 함). 손으로 찍은 키라 품질 한계 있음 — Mixamo 라이브러리는 로그인이 필요해 자동화 못 함.
- `ninja_scarf.py`: 붉은 꼬리 꼭짓점 (몸 뒤 x < -0.04) 275 개를 뼈 3개 사슬에 (위쪽은 몸통 가중치와 섞임).

## 11. W24 — 자동 리깅 사냥꾼 (2026-11-05, `tools/blender/tripo/rig_hunter.py`)

원본 `tripo/src/hunter_tripo_rigged.glb` (스킨 메시 하나 18,519 삼각형, Mixamo 식 뼈 65, 알베도 4096, 애니메이션 없음, 소총이 몸에 붙음). 닌자 (8절)·탱크와 같은 길.

```
blender -b --factory-startup -P tools/blender/tripo/rig_hunter.py -- --out <폴더>          # → <폴더>/hunter_rigged.glb (hunter_lod0 + hunter_vm + 뼈대)
LOD_LOCK=1 node tools/blender/tripo/lods.mjs <폴더>/hunter_rigged.glb <폴더>/hunter.glb hunter 5000,4000,3000   # 판 LOD 3개 (4991·3995·2999)
```

- **뼈대 노드 올림**: 닌자·탱크와 같은 세계 좌표 굽기.
- **좌우 뒤집기 안 함**: 소총은 원본에서 Mixamo `Left*` 쪽에 보이지만 (뼈 이름만 보면 왼팔) 게임에서는 `탕`·조준 때 코드가 뻗는 R 관절 팔을 그대로 따라감 (뒤집으면 뻗은 팔은 빈손, 소총은 내린 팔에 매달림 — 눈으로 확인). `MIRROR=1` 로만 뒤집음.
- **몸 색 칸** (`tint: "mask"`, 9.5%): 붉은 목수건 (큰 덩어리 34 꼭짓점) + **모자 전체** (`HAT_Z` = 0.82 m 위 꼭짓점 804개, 챙·위·깃털·띠 — 위에서 내려다보는 판 카메라에 가장 잘 보임, 목수건은 작고 앞에서만 보임). 두 자리는 따로 밝기를 맞춰 회백 (`GRAY`) + UV2.x = 1 + 꼭짓점 색 흰. 0.80 이하는 털 목깃에 번짐. 망토 (초록)·털·가죽은 원래 색.
- 알베도 밝기 `LIFT` = 0.8, 알베도만 (법선·ORM 뺌), 4096 → 2048 jpg.
- **LOD**: 이 모델은 UV 이음선이 덜 잘려 있어 (닌자 8500·탱크 8940 과 달리) 판 LOD 를 5000·4000·3000 세 개로 만들어도 (`LOD_LOCK=1`) 구멍·갈라짐 없음 (앞·쪼그림·베기 자세 확인). stage 18,519 (대기실·초상). glb 2.1 MB.
- **1인칭**: 팔꿈치 아래 가르기를 그대로 쓰면 소총이 화면 가운데를 대각선으로 가로질러 조준을 가림 → glb 안에 `hunter_vm` (stage 몸에서 아래팔·손 뼈가 센 꼭짓점 중 뼈 선분 `VM_R` 안인 것만, 1,645 삼각형, 소총 꼭짓점 뺌) 를 따로 넣고 `hunter.json` `vm_node`. 1인칭에서는 소총이 안 보이고 두 주먹만 보임 (코드 총은 외부 몸이라 안 남김).
- 3인칭 동작 확인 (`SHOT_CHAR=hunter` `stage_shot.gd`·`move_shot.gd`): 베기 3종·탕·조준·추적 도약·쪼그림·점프에서 갈라짐·가시 없음. 알려진 한계: 코드 평타가 칼 베기라 소총 든 손으로 휘두르는 모습, 반동 (탕 S) 에서 소총이 머리 위로 치솟음, 망토는 큰 자세에서 안감이 비침, 코드 몸과 팔 길이가 달라 서버 판정 위치와 보이는 소총 끝이 조금 다름.
- `posecheck.py` 는 W22 와 같은 파일 (자세별 앞·옆·뒤 그림).


## 12. W25 — 자동 리깅 갈고리 (해적 선장, 2026-11-05, `tools/blender/tripo/rig_hook.py`)

원본 `tripo/src/hook_tripo_rigged.glb` (스킨 메시 하나 19,040 삼각형, Mixamo 식 뼈 65, 알베도 4096, 애니메이션 없음, 캐릭터 왼손이 은색 갈고리). 닌자 (8절)·탱크 (9절)·사냥꾼 (11절) 과 같은 길 + 아래 손질.

```
blender -b --factory-startup -P tools/blender/tripo/rig_hook.py -- --out <폴더>          # → <폴더>/hook_rigged.glb (hook_lod0 + hook_vm + 뼈대)
LOD_LOCK=1 node tools/blender/tripo/lods.mjs <폴더>/hook_rigged.glb <폴더>/hook.glb hook 5000   # 판 LOD 하나 (약 8350), stage = 손질한 원본 (약 18,750)
```

- **갈고리 손 확인**: 갈고리는 Mixamo `LeftHand` 쪽 (뼈 가중치·꼭짓점 위치 모두 +Y). 게임 갈고리의 던지기·휘두르기·내려치기는 전부 L 관절 팔 (`moves.gd` `hookThrow`·`갈고리 휘두르기`·`갈고리 내려치기` 의 L 칸) 이고 L 관절 = Mixamo Left* 라서 **좌우 뒤집기 없음** (탱크와 달리).
- **뼈대 노드 올림**: 이 원본은 뼈대 노드·메시 변환이 이미 항등이라 어긋남이 없지만 닌자·탱크와 같은 세계 좌표 굽기를 그대로 둠.
- **팔 가중치 정리** (`trim_arm_weights`, 이 모델의 가장 큰 문제): 원본은 **코트 앞자락·사슬 (오른쪽 3360 꼭짓점, 손에서 최대 0.37 m) 이 손·손가락 뼈에, 왼쪽 치맛자락이 위팔·아래팔·손 뼈에 일부 가중치로 매여 있어서** 팔을 들면 코트 판이 판자처럼 따라 올라옴. 고침: ① 팔 뼈 (위팔·아래팔·손·손가락) 가중치는 그 쪽 팔 뼈가 가장 센 꼭짓점 (또는 뼈 선분 3 cm 안) 에만 남김 ② 오른손은 코트 옆에 붙어 있어서 거리만으로 못 가르므로 살색 판정 (`skin_like`) + 손 선분 4.5 cm 안만 ③ 남는 가중치가 거의 없는 꼭짓점은 가장 가까운 '깨끗한' 꼭짓점 가중치를 베낌 (코트가 허리·다리 뼈를 따라감). 왼손 (갈고리) 은 손 뼈에서 0.143 m 안에 갈고리뿐이라 (수치 확인) 반경을 넉넉히 둠.
- **이음 삼각형 지움**: 오른 주먹이 벨트 위에 얹힌 채 코트와 한 덩어리로 이어져 있음 → ① 오른손 가중치 센 꼭짓점과 몸 쪽 꼭짓점을 잇는 삼각형 209 개 (`cut_bridges`) ② 시험 자세 (고정 시드 무작위 120 자세 + 손으로 고른 자세) 에서 4 배 넘게·8 cm 넘게 늘어나는 팔 쪽 모서리의 삼각형 약 60 개 (`cut_stretched`) 를 지움. 쉬는 자세에선 주먹 안쪽·코트 위라 안 보임, 팔을 크게 돌리면 주먹 둘레에 **작은 찢어진 조각 몇 개가 남음** (오른쪽 무작위 자세 8 장 중 2 장).
- **몸 색 칸** (`tint: "mask"`, 14.8%): **삼각 모자 전체** (`HAT_Z` = 0.775 m 위 꼭짓점 2062 개 — 챙·위·깃털·붉은 꽃·금 테, 위에서 내려다보는 판 카메라에 가장 잘 보임). 모자 칸을 밝기만 남긴 회백 (`GRAY`) 으로 (밝기 기준 `HAT_REF` = 칸 안 60 백분위 — 대부분 검정이라 92 로 하면 팀 색이 거의 검게 나옴) + UV2.x = 1 + 꼭짓점 색 흰. 견장 (금장)·코트 안감 (붉은색) 은 원래 색 그대로 (모자 하나로 5% 넘음). 갈고리 손 (은색) 은 원래 색.
- 알베도 밝기 `LIFT` = 0.8, 알베도만 (법선·ORM 뺌), 4096 → 2048 jpg.
- **LOD**: 닌자·탱크처럼 UV 이음선이 잘게 나뉘어 `LOD_LOCK=1` 로도 약 8350 아래로 안 내려감 (5000·4000·3000 을 목표로 해도 8347~8350) → 판 LOD 하나를 high·medium·low 가 같이 쓰고 stage = 손질한 원본 그대로. glb 3.7 MB.
- **1인칭**: `ninja_vm.py` 의 닫힌 팔 방식 (`make_vm(ob, arm, "hook_vm", arm_only=True)`: 아래팔 축에 수직 평면으로 자르고 단면을 오므려 닫음) — 갈고리 손은 **갈고리가 화면에 보임** (왼팔 755 삼각형), 오른팔은 주먹 (약 820). `arm_only` = 손이 코트·벨트에 닿아 한 덩어리라서 아래팔·손·손가락 뼈가 가장 센 꼭짓점만 이어 붙임 (안 그러면 오른팔이 코트까지 9365 삼각형). 총 약 1,570 삼각형.
- **밧줄 시작점**: 코드 손 관절 (`hand_L`) 은 모델 왼손 뼈와 약 20 cm 어긋남 (모델 팔이 짧음) → `hook.json` `rope_bone` (= `LeftHandMiddle4`, 갈고리 뿌리) 의 뼈 위치를 `Ext.rope_point()` 로 얻어 `world/hook_fx.gd` `hand()` 가 씀 (밧줄 던지기·걸림·감김·블록 덩어리 모두). 없는 캐릭터 (`rope_bone` 비움) 는 예전 그대로. 코드 몸의 갈고리 소품은 외부 몸이라 안 남김 (`keep` 없음).
- 확인 그림: `tools/blender/move_shot.gd` 에 `SHOT_CHAR=hook` (동작 목록 `SHOT_MOVES`).
- 알려진 한계: 오른 주먹 둘레 찢어진 조각 (위), 코트 치맛자락이 다리 사이에서 늘어나는 건 원본 그대로 (큰 다리 자세에서 약간), 모자 틈 (판 LOD 에서 금 테 사이 작은 구멍 몇 개), 코드 평타 '주먹'은 오른팔이 벨트에서 뻗는 모양이라 주먹이 모델과 길이가 다름.

## 13. W26 — 자동 리깅 대포수 (2026-11-05, `tools/blender/tripo/rig_cannon.py`) — **품질 미달, 기본 켬 비권장 (아래 '한계')**

원본 `tripo/src/cannon_tripo_rigged.glb` (스킨 메시 하나 19,028 삼각형, **Tripo 뼈 이름 78개** — 접두어 없음 `BoneRoot·Hip·Pelvis·Waist·Spine01/02·NeckTwist01/02·Head·L_/R_Thigh·Calf·Foot·ToeBase·Clavicle·Upperarm·Forearm·Hand·손가락 1~3·트위스트·ShareBone`, 알베도 4096, 애니메이션 없음, 두 손으로 앞에 든 손대포가 몸 메시에 붙어 있음, 앞 = glTF +X).

```
blender -b --factory-startup -P tools/blender/tripo/rig_cannon.py -- --out <폴더>   # → cannon_rigged.glb (cannon_lod0 + cannon_vm + 뼈대) + cannon_gun.glb (손대포 소품)
LOD_LOCK=1 node tools/blender/tripo/lods.mjs <폴더>/cannon_rigged.glb <폴더>/cannon.glb cannon 5000   # 판 LOD 하나 (약 7600)
```

- **뼈 이름 매칭**: `chars/external.gd` `ALIASES` 만 (cannon.json 에 bones 없음) — 이 규격 전체에 통함 (바드가 같은 이름). 기존 별칭이 이미 `Pelvis`(골반; `Hip` 은 그 부모라 안 씀)·`Spine01/02`(허리·가슴)·`Upperarm`·`Forearm`·`Hand`·`Thigh`·`Calf`·`Foot` 를 맞췄고 (빗장 `Clavicle` 안 씀), 목만 `NeckTwist01` 별칭 (`necktwist01`·`necktwist`) 을 `head` 앞에 추가. 트위스트·ShareBone·눈·손가락은 안 맞춤 = 부모를 따라감. 테스트 `test_match_conventions` 에 78개 이름 전체.
- 원본 손질: 뼈대/메시 세계 좌표로 굽기 (이 모델은 어긋남 없었음), 좌우 뒤집기 없음, 알베도 밝기 `LIFT` 0.8, 알베도만 2048 jpg, 이음선 법선 합침.
- **몸 색 칸** (`tint: "mask"`, 넓이 8.6%): 빨간 두건 (+ 두건 배지) 과 다이너마이트 띠의 빨간 줄 (큰 덩어리 `MIN_RED_CLUSTER` 20 이상) → 회백 + UV2.x = 1. 판 카메라 위에서 두건이 가장 잘 보임. 팀 색 3종 확인 (빨강·파랑·초록, 두건 + 띠).
- **LOD**: UV 이음선 때문에 약 7600 아래로 안 내려감 (5000·4000·3000 목표도 8190 안팎) → 판 LOD 하나 (high·medium·low 같이) + stage 17,000 대. glb 3.4 MB + 손대포 소품 0.8 MB.
- **손대포 (가장 큰 문제)**: 원본은 대포가 몸 메시와 **한 덩어리**로 이어져 있고 가중치는 자동으로 왼손·손가락에 매임, 주먹이 대포에 녹아 있음. 코드 자세는 한 팔씩 움직이므로 (후려치기·포탄·반동) 그대로 쓰면 대포가 두 손 사이로 늘어나 가시 (처음 캡처에서 확인). 오른손 뼈 하나에 가중치 1 로 다시 묶어도 몸과 이어진 삼각형이 늘어남 → `split_gun`: 대포 삼각형 (중심이 손 사이 타원·손 앞 원통 안, 주먹·아래팔 꼭짓점은 지킴 `arm_verts`) 을 몸에서 떼어 소품 `cannon_gun.glb` (오른손 뼈 지역 좌표, 모델 키로 나눔) 로. `cannon.json` `attach` 하나 (`joint: hand_R`, `rot [0, 90, 0]` = 포구가 앞, `vm: true`). 코드 대포 (`refs.cannon`) 는 `keep` 없이 안 남김.
- **자세**: 쉬는 자세가 두 손으로 앞에 든 것이라 코드의 '오른어깨에 멘' 자세 (`_costume_pose` cannon) 대신 `cannon.json` `hold` (우리 관절 값 `shFwd·shOut·elbow`) 를 씀 — `body.gd` 에 `hold` 분기 한 곳 (cfg 에 `hold` 가 없으면 예전 그대로). 평타·스킬 자세는 코드 그대로.
- **1인칭**: 원본 팔·손은 대포에 손가락이 녹아 있어 대포를 떼면 속이 빈 껍질이라 못 씀 → `make_vm` 이 닫힌 전용 팔 (소매 8각 통 + 가죽 띠 + 주먹, 152 삼각형, 뼈에 가중치 1, 색은 알베도 한 점) 을 `cannon_vm` 으로. 손대포는 `vm: true` 로 같은 소품을 쌍둥이 오른손에.
- **한계 (캡처로 확인)**: ① 주먹에 녹은 나무 그루터기 (~120 꼭짓점) 와 대포를 뗀 자리의 속 면이 몸에 남아, 서서 있을 때 손 주변에 **어두운 보라 (외곽선 껍질) 면** 이 보이고 후려치기·반동·점프처럼 팔을 크게 쓰는 동작에서 그 면이 리본처럼 늘어남. ② 대포 소품 가장자리에 가는 가시. ③ 1인칭 팔은 상자꼴 (탱크 W20 과 같은 수준). 서 있기·걷기·포탄 쏘기 자세는 알아볼 만하지만 동작 전반이 쓸 만하지 않아 **기본으로 켜지 말 것** — 고치려면 원본을 대포가 따로 떨어진 모델로 다시 뽑거나 (손은 빈 주먹, 대포는 별도 메시) 손으로 메시 수선이 필요.
- 확인 그림 (`stage_shot.gd`·`move_shot.gd` `SHOT_CHAR=cannon`, `vm_shots.gd <폴더> x cannon --ext`): 코드 어깨 자세 대신 두 손 자세인 것, 팀 색, 동작 contact sheet.


## 14. W28 — 1인칭 팔이 이동·평타 때 공중에 떠 보임 (2026-11-06)

친구 피드백: 1인칭에서 이동하면 팔 위쪽이 안 이어져 공중에 떠 보임. 원인 = 닫힌 팔 메시 (`*_vm`, 탱크는 로더 가르기) 가 **팔꿈치 바로 위에서 끝나** 팔을 앞으로 뻗거나 휘두르면 (평타·대시·점프의 어깨 각) 그 끝 (단면·마개, 탱크·사냥꾼은 들쭉날쭉 열린 가장자리) 이 화면 한가운데에 올라옴. 걷기 흔들림 (`VM_BOB` 1.8 cm) 은 원인이 아님 (걷기·서 있기 프레임은 끝이 화면 아래 밖) — 팔 각이 큰 자세에서 드러남. 재현 그림: `godot/client/tools/move_shot.gd` (`<폴더> <캐릭터> --ext`: 서기·걷기 4 위상·점프·낙하·공중 대시·평타 타격 프레임).

- `ninja_vm.py` `extend_end`: 아래팔 단면 고리를 **어깨 쪽 (-축) 으로 팔 길이의 2.6 배 뽑은 소매 통** (끝이 1.12 배 굵어짐) 으로 늘리고 먼 끝을 가운데 점 부채꼴 (원뿔) 로 닫음 → 팔이 화면 밖 (아래·카메라 뒤) 의 몸에서 이어져 나옴. 통 면의 UV 는 고리 이웃 면 UV 의 가운데값 한 점 (이음선을 가로질러 늘어나 살색이 번지는 것 방지, UV2 몸 색 칸 표시 포함), 가중치는 고리 꼭짓점 것 (아래팔 뼈) 그대로. 고리가 끊긴 사슬 (방패·코트와 단면이 겹침) 이어도 되게 `holes_fill` 대신 부채꼴.
- 닌자·갈고리: 같은 `make_vm` 이 자동으로 (재생성 `rig_ninja.py`·`rig_hook.py`).
- 사냥꾼: `rig_hunter.py` `make_vm` 이 이제 `ninja_vm.make_vm(…, arm_only=True, accept=소총 뺀 뼈 선분 조건, thick=1.0)` — 예전 '삼각형만 남기기' (팔꿈치 쪽 열림) 대신 평면으로 잘라 닫음 (1,645 → 약 1,940 삼각형).
- 탱크: `rig_tank_auto.py` 가 `tank_vm` 을 새로 만듦 (`make_vm(…, arm_only=True, thick=1.0, connected=False)` — 방패·해머가 손가락·아래팔 뼈에 매인 별개 덩어리라 연결 퍼짐 대신 뼈 조건 전부) + `tank.json` `vm_node: "tank_vm"`. 방패·해머는 그대로 따라옴 (`vm_shots.gd tank` 로 방패 올리기·밀치기 확인).
- 재생성: `blender -b --factory-startup -P tools/blender/tripo/rig_<캐릭터>.py -- --out <폴더>` → `LOD_LOCK=1 node tools/blender/tripo/lods.mjs …` (닌자 5000, 사냥꾼 5000,4000,3000, 갈고리 5000, 탱크 5000) → ext/ 에 복사 → `godot --headless --import`. 판 몸·LOD·몸 색 칸은 그대로 (닌자는 같은 크기 3,678,200 B).
- 알려진 한계: 소매 통 색이 고리 둘레 UV 가운데값 한 가지라 팔 모양과 완전히 같진 않음 (탱크 = 짙은 갈색, 갈고리 = 주황 띠 쪽). 사냥꾼 왼팔·갈고리 오른팔은 원래 열린 곳 (소총·코트 자리) 이 소매 통 쪽에 몇 개 남음 (6·2 개, 테스트 기준 ≤ 8).

## 15. W31 — 닌자·탱크·갈고리 판 LOD 를 새 UV 로 다시 굽기 (2026-11-08, `tripo/relod.py`·`relod_merge.mjs`)

PC 최적화 2차 (지속 비용). 8절·9절·12절의 한계 — Tripo UV 가 잘게 나뉘어 meshopt 가 이음선을 못 넘어 판 LOD 가 **8500~8900 삼각형 아래로 안 내려감** — 을 없앰. 이미 리깅해 둔 `ext/<이름>.glb` 만 있으면 되고 (`rig_*.py` 를 다시 돌릴 필요 없음, stage·1인칭 팔·뼈대·재질은 글자 그대로 둠), 판 LOD 셋 (high 5000·medium 4000·low 3000 삼각형) 마다 메시와 1024 알베도를 따로 만듦.

```
# 한 LOD (Blender 4.5, 약 4초): stage → Decimate → Smart UV → 알베도·마스크 굽기 → <폴더>/<이름>_relod.glb
blender -b --factory-startup -P tools/blender/tripo/relod.py -- --glb godot/client/assets/models/ext/ninja.glb --name ninja --out <폴더>/l1 --tris 5000 [--size 1024] [--angle 66] [--margin 0.008] [--ray 0.04]
# (4000, 3000 도 같게 l2·l3 로) 그다음 원래 glb 에 LOD 셋으로 합침 (@gltf-transform/core 가 있는 폴더에서 — ESM 이라 NODE_PATH 가 안 먹으니 그 폴더에 복사해서)
node relod_merge.mjs godot/client/assets/models/ext/ninja.glb ninja <폴더>/ninja.glb <폴더>/l1/ninja_relod.glb <폴더>/l2/ninja_relod.glb <폴더>/l3/ninja_relod.glb
# ext/ 에 덮어쓰고 .json lods 를 high=lod1·medium=lod2·low=lod3 으로, godot --headless --import → 새 아틀라스 *_atlas_lod1~3.jpg.import 의 compress/mode 를 2 (VRAM) 로 고치고 한 번 더 import
```

- **줄이기**: stage 를 복사해 `remove_doubles` (UV 이음선으로 갈라진 꼭짓점 합침, 위치 기준 → 닫힌 메시) → 삼각화 → 맞춤 법선 지움 → Decimate Collapse (비율 = 목표/stage). 꼭짓점 8.9천 → 2.5천 (5000 삼각형), 구멍 없음 (예전 meshopt LOD 는 치마·목도리에 검은 구멍이 보였음).
- **가중치**: Decimate 가 아니라 Data Transfer (`POLYINTERP_NEAREST`, 모든 꼭짓점 그룹, 이름으로) 로 stage 에서 가져옴 → 같은 Mixamo 뼈에 묶임 (4개 제한 + 정규화). `posecheck.py` 로 팔 올리기·쪼그림·몸 비틀기 앞/옆/뒤 stage 와 나란히 확인 (갈라짐·가시 없음).
- **새 UV**: Smart UV Project (각 66°) → 조각 크기 맞춤 → 포장 (여백 0.008). 큰 조각 몇십 개를 노렸으나 Tripo 형태가 덩어리져서 약 960개 (예전 판 LOD 3100, stage 3500). 꼭짓점 6.5천 (5000 삼각형의 1.3배) — 예전 14.7천.
- **알베도 굽기**: Cycles CPU 1 샘플, `DIFFUSE` 색만 (직접·간접 빛 끔) 선택→활성 (stage → 새 메시, 광선 거리 `--ray` 0.04 m), 여백 10 픽셀 늘리기, 1024². **저장할 때 `save_render` 가 장면 색 관리 (AgX) 를 거치면 색이 바램 → 표준 + 보정 없음으로 먼저 맞춤** (처음에 이걸로 탱크 주황이 연한 갈색이 됐음).
- **몸 색 칸 (`tint: "mask"`, UV2.x)**: 셰이더는 `UV2.x > 0.5` 면 몸 색을 입히는 꼭짓점 단위 판정이라, stage 의 칸을 새 꼭짓점마다 가장 가까운 stage 면의 가장 가까운 모서리 값으로 옮김 (BVH). 알베도의 회백 칸과 새 꼭짓점 판정 경계가 삼각형 하나만큼 어긋나므로 (stage 칸 넓이의 약 8%: 닌자 `missing 1.3% / spill 1.2%` 텍스처 비율, 탱크 1.1/1.1, 갈고리 0.2/0.1) 어긋난 곳은 stage 회백 그대로 둠 (빨강으로 되돌리면 파랑 팀에서 빨강 점) — 안 입혀진 곳은 연회색, 더 입혀진 곳은 어두운 팀 색. 눈에 띄는 정도는 `godot/client/tools/lod_shot.gd` (3색 나란히) 로 확인.
- **합치기** (`relod_merge.mjs`): 옛 `<이름>_lod1..N` 메시·노드를 지우고 새 메시를 같은 이름으로 (새 글의 뼈 번호는 뼈 이름으로 원래 스킨 번호로 바꿈), 재질·텍스처는 LOD 마다 하나 (`<이름>_atlas_lodN` → 고도가 `<이름>_<이름>_atlas_lodN.jpg` 로 꺼냄). `prune()` 은 `keepAttributes: true` 로 — 기본값은 안 쓰는 `TEXCOORD_1` (몸 색 칸) 을 지워서 stage 까지 색이 안 입혀짐.
- **결과** (소프트웨어 렌더 환경, `tools/ext_meas.gd --eight --level …`): 8명 판 삼각형 (같은 캐릭터 8명, 외곽선 껍질 포함) 탱크 143.1k → **80.0k (높음)·64.0k (보통)·48.0k (낮음)**, 닌자 137.8k → 81.5k·65.5k·49.5k, 갈고리 133.8k → 80.0k·64.0k·48.0k. 영상 메모리 +6 MB (stage 2048 아틀라스는 그대로 + 1024 LOD 아틀라스, 한 판에서 쓰는 LOD 는 하나). glb 3.7~4.1 MB (+0.5 MB: 아틀라스 jpg 셋). 사냥꾼은 이미 3~5천이라 그대로.
- 못 한 것: `relod.py` 는 Smart UV 라 조각 수가 많음 (큰 조각 몇 개로는 못 만듦). 마스크 경계 어긋남은 위 8% (텍스처 쪽에 마스크를 같이 굽는 길은 셰이더 변경이 필요해 안 함). 대포수 (`ext_hold`, 기본 꺼짐) 는 안 건드림.
