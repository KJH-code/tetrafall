# Blender 캐릭터 제작 파이프라인 (W19 — 탱크 1명 시험 제작)

재혁 결정 (B 방식): 캐릭터 모델은 Blender 를 스크립트로 돌려 우리 규격으로 직접 만듦. 화풍은 '중간' (둥글고 굵은 형태 + 단순한 색 + 두꺼운 외곽선 툰).
이번엔 탱크 1명. 통과하면 나머지 7명을 같은 방식으로 (따로 작업).

## 1. 무엇이 어디에

| 파일 | 하는 일 |
| --- | --- |
| `dump_rig.gd` (고도) | 지금 구운 몸의 관절 자리·체형 수치·방패 자리를 `ref/<id>_rig.json` 으로 뽑음 → Blender 가 같은 자리에 뼈를 세움 |
| `build_character.py` | 공통: 부품 (둥근 상자·구·캡슐·고리·호 고리·구 껍데기·늘어진 판·원기둥, 베벨·두께), 꼭짓점 색 + 몸 색 칸, 뼈대, 가중치 (딱딱한 부품 = 뼈 하나, 부드러운 부품 = 부품마다 자동 가중치 뒤 정리), 미리보기 렌더, glb·json 내보내기 |
| `chars/<id>.py` | 캐릭터 모양 `build(k)` + 고도 조정 값 `CFG` (방패 attach 등) + 미리보기 자세 `PREVIEW_POSES` |
| `cost.gd` (고도) | 구운 몸 vs 외부 (Blender) 몸 비용 표 (삼각형·그리기·뼈·만들기 ms·자세 ms·1인칭 팔) |
| 결과 | `godot/client/assets/models/ext/<id>.glb` (몸 + 뼈대) · `<id>_<소품>.glb` (방패 등) · `<id>.json` (조정 값 + 통계) |

예전 시험 로봇 (Quaternius, W14) 은 `ext/robot_test.glb` (+ `.json`) 로 옮김 — 테스트만 씀.

## 2. 설치·실행

```
# Blender 4.5 (화면 없이, GPU 없어도 됨 — 미리보기는 Workbench)
curl -LO https://download.blender.org/release/Blender4.5/blender-4.5.3-linux-x64.tar.xz && tar xf blender-4.5.3-linux-x64.tar.xz   # 레포 밖에
# (관절 자리를 새로 뽑을 때만) 고도
<godot> --headless --path godot/client -s ../../tools/blender/dump_rig.gd -- tank
# 만들기 (레포 뿌리): ext/ 에 tank.glb·tank_shield.glb·tank.json, --preview 면 미리보기 PNG (정면·3/4·옆·뒤·머리·자세 4 + 모음 tank_sheet.png)
blender -b --factory-startup -P tools/blender/build_character.py -- tank --preview <밖 폴더> [--out <폴더>] [--blend <파일.blend>] [--parts]
# 고도 import (.glb.import 갱신) → 테스트 → 비용 표
<godot> --headless --path godot/client --import
<godot> --headless --path godot/client -s tests/run_tests.gd
<godot> --headless --path godot/client -s ../../tools/blender/cost.gd -- tank
# 게임에서 보기 (외부 모델은 기본 끔, --ext 로 켬)
PORT=3119 node server/index.js &
xvfb-run -a -s "-screen 0 1280x720x24" <godot> --resolution 1280x720 --path godot/client -- --ext --auto practice --char tank --view third --server ws://127.0.0.1:3119 --shot a.png --shot-after 14 --quit-after 15
```

`--parts` 는 부품별 삼각형을 많은 순으로 찍음 (예산 맞출 때). 만드는 데 ~3초.
같은 스크립트를 다시 돌리면 같은 모양이 나오지만 glb 바이트는 매번 조금 다름 (glTF 내보내기의 법선 1e-4 잡음·인덱스 순서) — 커밋할 땐 한 번 만든 것만.

## 3. 규격표 (7명 확장 때 지킬 것)

| 항목 | 규격 |
| --- | --- |
| 좌표 | 부품은 게임 좌표 (앞 +x, 왼쪽 +y, 위 +z, m, 발바닥 z = 0) 로 적음. Blender 로는 (X, Y, Z) = (y, −x, z), 내보내면 glTF 앞 +Z (고도 yaw 90° 로 게임 앞) |
| 키·비율 | 관절 자리 = `ref/<id>_rig.json` (고도 몸 쉬는 자세, `PLAYER_HEIGHT` 1.6 × `FIGURE_SCALE` 1.15, 체형 `FIGURE_BODIES`) — 부품도 이 자리 기준으로. json `height`·`offset` 은 스크립트가 "크기 1·자리 그대로" 가 되게 적음 |
| 뼈 | 16개, 이름 = 우리 관절 그대로 `hips waist torso neck shoulder_R elbow_R hand_R shoulder_L elbow_L hand_L thigh_R knee_R foot_R thigh_L knee_L foot_L` (R = 캐릭터 오른쪽). 손가락·빗장·머리 뼈 없음 (주먹 한 덩어리, 머리는 neck) |
| 쉬는 자세 | 우리 몸 쉬는 자세 그대로 (팔 내림 — T/A 포즈 아님). 외부 모델 맞춤 회전 A 가 거의 0 이 됨 |
| 삼각형 | 몸 1만 이하 (외곽선 껍데기로 그리기는 ×2). 소품 (방패) 은 따로 |
| 재질 | 몸 1개 (`<id>`, 하양 + 꼭짓점 색 `COLOR_0`) + 빛 안 받는 칸이 있으면 `<id>_unlit` 1개 (눈 흰자 — 고도는 이름이 `_unlit` 로 끝나는 재질을 하얀 발광·외곽선 없음으로). 텍스처 없음 |
| 색 | 꼭짓점 색 = JS `figure.js` 옷 색 (sRGB 값 그대로 — 내보내기 전에 선형 → sRGB 로 바꿔 둠). 플레이어 색 칸 = 둘째 UV (고도 UV2) x = 1 + 꼭짓점 하양 → 툰 셰이더 `skin_tint` (json `tint: "mask"`) |
| 가중치 | 딱딱한 부품 (갑옷·투구·장갑·장화) = 뼈 하나 100%. 부드러운 부품 (`blend=[뼈…]`: 몸통 통·소매·허벅지·허리 천) = 그 부품만 자동 가중치 (bone heat) 뒤 허락한 뼈만, 정점당 최대 3, 0.04 아래 버리고 정규화 |
| 눈 | 모델 안에 (흰자 = `_unlit` 재질, 눈동자 = 몸 재질). 코드 몸의 눈은 외부 모델이면 안 그림 (안쪽 몸 메시를 비움). **흰자는 머리 덮개 (투구·모자) 바깥 타원 안에** — 밖으로 나오면 옆·3/4 에서 눈알이 떠 보임 (`test_blender_tank_eyes_in_helmet`) |
| 밝기 | 몸 색 칸 뺀 넓이 평균 색이 구운 몸의 0.92~1.1 배 (`test_blender_tank_brightness`, 탱크 0.95) |
| 분리 소품 | `prop="이름"` 부품은 `<id>_<이름>.glb` 로 따로 (뼈 없음, 안쪽 몸 소품 노드 좌표 — 탱크 방패 = JS 방패 원판 좌표, 돌기 −x). json `attach` 에 `{"glb", "ref": "shields.back"}` (안쪽 몸 소품 노드 아래 → 보이기·1인칭 쥐기는 예전 그대로) |

## 4. 새 캐릭터 만드는 순서

1. `dump_rig.gd -- <id>` → `ref/<id>_rig.json` (관절·체형·소품 자리)
2. `chars/<id>.py`: `build(k)` 에서 JS `figure.js` `dress<Char>` 를 보며 부품을 관절 자리에 (`k.j("elbow_R")`), 색은 JS 값, 플레이어 색 칸은 `skin=True`, 굽는 곳은 `blend=[…]`, 소품은 `prop=`. 좌우는 `k.mirror(fn)`
3. `--preview` 로 정면·옆·뒤·극단 자세 (`PREVIEW_POSES`: 어깨 들기·웅크림·비틂) 를 보고 찌그러짐·삐져나옴 확인, `--parts` 로 1만 이하
4. 고도 import → `--ext --char <id>` 로 3인칭·1인칭·대기실·초상 확인, `cost.gd`
5. 테스트: `tests/test_external.gd` 의 `test_blender_tank_*` 를 그 캐릭터로 (뼈 이름 = 관절·크기 1·뼈 자리·표면 수·그리는 메시)

## 5. 탱크 결과 (2026-11-05)

모양: 둥근 투구 (얼굴 앞만 뚫림) + 이마 띠·가로 쇠 띠 둘·코 가드 + 몸 색 볏 (금 받침), 왕눈알 (JS addEyes 자리·크기, 흰자 빛 안 받음), 가슴 갑옷 껍데기 + 금 장식·배 띠·허리띠·금 버클,
두 겹 어깨 갑옷 + 금 징, 몸 색 소매, 쇠 장갑·주먹, 허리 천 (타바드 앞·뒤, 몸 색 + 금 테), 옆 치마판 두 겹, 사슬 바지·가죽 허벅지·무릎 받이·정강이 갑옷·쇠 장화, 큰 둥근 방패 (몸 색 판 + 쇠 테 + 금 고리·돌기·징, 따로).

| | 구운 탱크 (지금) | Blender 탱크 |
| --- | --- | --- |
| 삼각형 (보이는 몸 + 방패 하나) | 4840 | 11384 (몸 9792 + 방패 1592) |
| 그리기 (외곽선 next_pass 포함) | 6 | 5 (몸 2 + 눈 흰자 1 + 방패 2) |
| 메시 | 4 | 3 |
| 뼈 | 27 | 16 |
| 몸 만들기 처음 / 그 뒤 | 5.5 / 0.72 ms | 7.2 / 1.68 ms |
| 자세 + 뼈 맞추기 (프레임당) | 0.14 ms | 0.18 ms |
| 1인칭 팔 삼각형 / 그리기 | 2832 / 66 | 1158 / 2 |

8명 판 추정 (모두 이 규격일 때): 그리기 48 → 40, 삼각형 (외곽선 껍데기 ×2) ~7.7만 → ~18만, 자세 ms 8 × 0.04 = +0.3 ms/프레임, 몸 만들기 +1 ms/명 (판 시작·캐릭터 바꿀 때만).
그리기는 줄고 삼각형이 2.3배 — 내장 GPU 에서 버틸지는 재혁 PC F3 로 봐야 함 (삼각형 줄이는 손잡이: 구·고리 seg/rings, `--parts`).

## 6. 한계·못 한 것

- 허리 천은 JS 처럼 따로 흔들리지 않고 허벅지 가중치로 다리를 따라 휨 (큰 걸음·발차기에서 천이 늘어남)
- 볏·방패는 플레이어 색 칸이라 빨강은 '빨간 플레이어' 일 때만 (JS 와 같음). 늘 빨강으로 하려면 `skin=False` + RED 색
- 표정 없음 (눈동자 고정), 클립 (춤 등) 없음 — 움직임은 전부 코드 자세
- 반투명 (유령화) 때 표면 2개 (몸·눈) 가 따로 투명이라 겹침 정렬은 예전 묶음 몸보다 거침
- glb 바이트가 매번 조금 다름 (2절)

## 7. 재혁 캡처 고침 (2026-11-05, v0.1.6 뒤)

- 눈알이 투구 위로 떠 보임 → 눈을 작게 (반지름 0.071 → 0.064) 뒤로 (투구 얼굴 구멍 안). 원인: JS addEyes 자리 그대로라 흰자가 투구 겉면보다 앞·옆으로 나와 3/4·옆에서 투구 밖에 떠 보였음
- 대기실 큰 캐릭터·초상이 어둡고 탁함 → 원인은 모델이 아니라 무대: 고도 툰 셰이더 빛이 전역 값이라 대기실 어두운 장면 (lobby_dark) 빛을 그대로 받음 (구운 탱크도 같은 맵 테마에선 똑같이 어두움 — 테마마다 달라 보였던 것). JS 처럼 무대는 늘 흰 빛 (앰비언트 1.05 + 앞 빛 1.5): `ui/portrait.gd` `stage_light` (재질마다 `toon_local_light`, 값 `shaders/g3_config.gd` `STAGE_*`). 모델 쪽은 장화·주먹을 쇠 색으로 (몸 밝기 0.92 → 0.95)
- 방패: 평소엔 등, 공격 동안 앞 — 구운 탱크·JS 와 같음 (대기실 기본 자세도 등)
