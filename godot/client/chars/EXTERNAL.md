# 외부 뼈대 모델 (.glb) 받아들이기 — W14 시제품 (2026-11-03)

재혁 결정: 캐릭터 모델은 Meshy·Tripo 같은 AI 3D 생성 도구로 직접 만들어 .glb 로 줌 (뼈대 자동 부여, 사람형, T/A 포즈). 여기는 그 .glb 를 게임 몸에 잇는 길.
애니메이션은 **지금 코드 구동 그대로** — figure_motion·moves·래그돌이 예전처럼 우리 관절 노드 (hips·waist·…·foot_L) 를 돌리고, 그 회전을 매 프레임 모델 뼈에 옮김.

## 1. 무엇이 어디에

| 파일 | 하는 일 |
| --- | --- |
| `assets/models/ext/<캐릭터>.glb` | 외부 모델. 있으면 그 캐릭터 몸이 됨 (아래 '켜기') |
| `assets/models/ext/<캐릭터>.json` | 조정 값 (없어도 됨). 키 설명은 `chars/chars_config.gd` `EXT_DEFAULTS` |
| `chars/external.gd` | 읽기·뼈 이름 매칭·크기·뼈 맞추기·툰 재질·1인칭 팔 메시·클립 (`Ext` = 몸에 붙는 노드) |
| `chars/body.gd` `build` | 3단: **외부 → 구운 (W7 `assets/models/<id>.glb`) → 코드 조립 (`bodies.bin`)**. 외부가 있으면 안쪽 몸은 조각 몸 (관절 노드만, 메시는 비움) 으로 만들고 그 위에 `External.attach` |
| `chars_config.gd` `EXT` | 기본 끔 (지금 든 건 시험 로봇이라). 실행 인자 `--ext` 로 켬, 테스트는 `Body.use_ext` |
| `tests/test_external.gd` | 11개 (4절) |

탱크 자리 `assets/models/ext/tank.glb` (+ `tank.json`) = **자동 리깅 탱크 (W22, `tools/blender/tripo/rig_tank_auto.py`, README 9절)** — 닌자와 같은 길: 스킨 메시 하나 + 뼈 65 (Mixamo 식, `ALIASES` 가 맞춤), 앞 = glTF +X → `yaw: 0`, 몸 색 칸 `tint: "mask"` = 붉은 목도리·허리 천, 판 몸 LOD = 약 8900 하나 (high·medium·low 같은 메시) + stage = 원본 19,429. **방패 (왼팔)·해머 (오른손) 가 몸 메시에 붙어 있음** → `attach`·`keep`·`vm_node` 없음 (W20 의 `tank_shield.glb`·`tank_hammer.glb`·`tank_vm` 닫힌 팔 메시는 뺌). 원본은 방패가 캐릭터 오른손·해머가 왼손이라 좌우를 뒤집음 (게임 규칙: 방패 왼손 viewmodel, 평타 오른손 해머). 1인칭 = 팔꿈치 아래 삼각형 가르기가 방패·해머까지 들고 옴 (방패가 쥔 손 IK 를 따라감, 코드 방패 안 씀). 얼굴 재질·표정 없음 (닫힌 투구).
닌자 자리 `assets/models/ext/ninja.glb` (+ `ninja_dagger.glb`·`ninja.json`) = **자동 리깅 닌자 (W21, `tools/blender/tripo/rig_ninja.py`, README 8절)** — 스킨 메시 하나 + 손가락까지 뼈 65 (Mixamo 식 이름, `ALIASES` 가 그대로 맞춤, `bones` 덮어쓰기 없음), 앞 = glTF +X → `yaw: 0`, 몸 색 칸 `tint: "mask"` = 붉은 목도리·허리띠, 판 몸 LOD = 원본 전체 (stage) + 약 8500 하나 (high·medium·low 가 같은 메시, 이음선 때문에 더 못 줄임), 1인칭 팔 = 닫힌 `vm_node` 없이 **팔꿈치 아래 삼각형 가르기** (소매·장갑이 닫힌 팔이라 깨지지 않음), 단검은 `attach` 로 두 손 뼈에 (`ninja_dagger.glb`, 판 몸만 — 1인칭은 viewmodel 이 표창을 쥐여 줌, 안쪽 몸의 단검·손 구슬은 `keep` 없이 지움).

사냥꾼 자리 `assets/models/ext/hunter.glb` (+ `hunter.json`) = **자동 리깅 사냥꾼 (W24, `tools/blender/tripo/rig_hunter.py`, README 10절)** — 스킨 메시 하나 + 뼈 65, 앞 = glTF +X → `yaw: 0`, 좌우 뒤집기 없음 (소총이 이미 R 관절 팔을 따라감), 몸 색 칸 `tint: "mask"` = 모자 + 붉은 목수건, 판 LOD 3개 (high 4991·medium 3995·low 2999) + stage 18,519, 소품 없음 (소총이 몸에 붙음, 코드 총은 안 남김), 1인칭 팔 = glb 안 `hunter_vm` (`vm_node`, 소총 뺀 아래팔·손).

갈고리 자리 `assets/models/ext/hook.glb` (+ `hook.json`) = **자동 리깅 갈고리 (해적 선장, W25, `tools/blender/tripo/rig_hook.py`, README 12절)** — 스킨 메시 하나 + 뼈 65, 앞 = glTF +X → `yaw: 0`, 좌우 뒤집기 없음 (갈고리 손이 Mixamo `LeftHand` = 게임 L 관절 팔), 몸 색 칸 `tint: "mask"` = 삼각 모자 (14.8%), 판 LOD = 약 8350 하나 (high·medium·low 같은 메시) + stage 약 18,750, 소품 없음 (갈고리가 몸에 붙음, 코드 갈고리는 안 남김), 1인칭 팔 = glb 안 `hook_vm` (`vm_node`, 왼팔 갈고리가 보임), **`rope_bone: "LeftHandMiddle4"`** = 갈고리 밧줄이 모델 갈고리 뿌리에서 나가게 (`Ext.rope_point()` → `world/hook_fx.gd` `hand()`, 코드 손 관절은 모델 손과 20 cm 어긋남). 원본의 코트가 팔 뼈에 매여 팔과 함께 올라오던 가중치를 고침 (README 12절).

**(보관 중: 재혁 결정으로 대포수 파일 전부는 `assets/models/ext_hold/` 에 있음 — 로더가 안 읽어서 대포수는 예전 코드 몸. 대포가 따로 떨어진 모델이 오면 교체. 되살리려면 `ext/` 로 되돌림, 대포수 전용 테스트 3개는 ext 에 cannon.glb 가 있을 때만 돎, 내보내기 제외 `export_presets.cfg`)** 대포수 자리 `assets/models/ext/cannon.glb` (+ `cannon_gun.glb`·`cannon.json`) = **자동 리깅 대포수 (W26, `tools/blender/tripo/rig_cannon.py`, README 13절, 품질 미달 — 기본 켬 비권장)** — 스킨 메시 하나 + **Tripo 뼈 이름 78개** (접두어 없는 `L_Upperarm` 식, `ALIASES` 가 맞춤: 골반 `Pelvis`·허리 `Spine01`·가슴 `Spine02`·목 `NeckTwist01`), 앞 = glTF +X → `yaw: 0`, 몸 색 칸 `tint: "mask"` = 빨간 두건 + 다이너마이트 띠, 판 LOD 하나 (약 7600) + stage 17,000 대, 손대포는 몸에서 떼어 `attach` (`hand_R`, `vm: true`) 로 오른손 뼈에, 코드 대포는 안 남김, 쉬는 자세는 cfg `hold` (코드 어깨 자세 대신 두 손으로 앞에 듦, `body.gd` `_costume_pose`), 1인칭 = 닫힌 전용 팔 `cannon_vm`.

시험 모델: `assets/models/ext/robot_test.glb` = Quaternius 로봇 (three.js 예제 RobotExpressive, CC0 — `assets/CREDITS.md`, W19 에 tank.glb 에서 옮김, 테스트만 씀).
이 모델은 몸 대부분이 **뼈에 붙은 딱딱한 조각** (BoneAttachment3D) + 손만 스킨, 발 뼈가 IK 용으로 뿌리 뼈 밑에 있음 → 일부러 까다로운 경우. Meshy·Tripo 처럼 **스킨 메시 하나** 인 모델은 테스트의 합성 모델 (Mixamo 이름 T 포즈, 뼈마다 쉬는 회전 제각각) 로 확인.

## 2. 어떻게 움직이나

1. **뼈 이름 매칭** (`External.match_bones`): 이름을 정리 (`mixamorig:`·`Armature|` 같은 앞 이름, `Bip01`·`DEF`·`jnt` 같은 군더더기, 대소문자·구분자 `_ . - 공백`·낙타 표기 무시, 좌우 `Left/Right/L/R/.L/_l/L_` 를 따로 뽑음) 뒤 별칭 표 `ALIASES` 에서 앞 순서대로 찾음. 정확히 맞는 게 없으면 끝 숫자를 뺀 이름으로 한 번 더 (`Head_2` → head). 뼈 하나는 한 관절에만.
   - 우리 어깨 관절 = 모델 **위팔** 뼈 (Mixamo `LeftArm`, 빗장 `LeftShoulder` 는 안 씀), 팔꿈치 = 아래팔, 무릎 = 정강이 (`LeftLeg`·`calf`), 목 = `neck` (없으면 `head`)
   - 골반: 고른 골반 뼈가 두 허벅지 뼈의 조상이 아니면 두 허벅지·허리 뼈의 가장 가까운 공통 조상으로 바꿈 (로봇: `Hips` 옆에 다리 → `Body`)
   - 꼭 있어야 하는 뼈 (골반·위팔·아래팔·허벅지·정강이 양쪽) 가 없으면 경고 + 외부 모델 안 씀 (구운 몸으로)
2. **크기·자리**: 쉬는 자세 상자 키 = `C.PLAYER_HEIGHT × C.FIGURE_SCALE × height` (예전 몸과 같은 키), 발바닥 = 0, 앞 = glTF +Z 를 yaw 90° 돌려 게임 앞 (+x)
3. **뼈 맞추기** (`Ext.sync`, 매 프레임 `body.pose` 안 래그돌 다음): 뼈 전역 회전 = (관절 지금 회전 × 관절 처음 회전⁻¹) × 맞춤 회전 A × 뼈 쉬는 회전.
   A = 처음에 모델 뼈 방향 (뼈 → 다음 관절 뼈) 을 우리 관절 방향으로 돌리는 최단 회전 → **T 포즈 팔도 우리 내린 팔에 맞음** (A 포즈도 같음). 손·발·목은 부모 관절의 A.
   자리: 골반은 우리 골반 이동 × (모델 골반 높이 / 우리 골반 높이), 나머지 맞춘 뼈는 '우리 부모 관절' 의 뼈에 쉬는 자세 상대 자리로 (뼈 나무가 우리와 달라도 — 로봇 발 뼈), 안 맞춘 뼈 (손가락·빗장·머리) 는 부모를 따라감.
   팔다리 뼈 방향이 우리 관절 방향과 1° 안팎 (테스트: 쉼·팔 들기·무릎 굽힘·래그돌 자세 모두 2° 안).
4. **재질**: 원래 PBR 재질의 알베도 색·텍스처를 그대로 G3 툰 (음영 단계 + 외곽선 next_pass) 로. 표면마다 MeshInstance3D 하나로 나눔 → `material_override` 하나라 반투명 (유령화·무적)·한 겹 더 (`set_overlay`)·스텐실 (내 몸 x-ray)·위험 빛이 예전 몸과 같은 길.
   몸 색 `tint`: `"keep"` 텍스처 그대로 · `"band"` 그대로 + 허리 뼈에 플레이어 색 고리 (기본) · `"tint"` 플레이어 색을 `tint_k` 만큼 곱함.
   번쩍: 부위 구분이 없어 `fx_colors` 의 피부 발광 (경직·조종권·점프 강화·스킬·필살기·F 준비·아머) 을 몸 전체에, 경직 하얀 깜빡임은 하얀 발광 `EXT_FLASH`.
5. **1인칭 팔** (viewmodel 은 안 고침): viewmodel 이 만드는 쌍둥이 몸 (`merge = false`) 에선 모델을 **허리 관절 아래** 에 붙여 viewmodel 이 허리를 카메라 앞으로 옮길 때 같이 가고,
   팔꿈치 아래 뼈 (`vm_from`) 에 붙은 삼각형만 남긴 메시를 씀 (스킨이면 세 정점의 가장 센 뼈가 팔인 삼각형). 쌍둥이는 `pose` 가 안 불려서 `_process` (우선순위 100, viewmodel 다음) 로 맞춤.
   팔꿈치 뼈는 우리 팔꿈치 관절 자리에 붙임 (`vm_snap`) → 모델 어깨 자리·팔 길이가 달라도 손이 예전 1인칭 자리 (화면 아래 구석).
6. **래그돌**: 그대로 우리 관절 노드에 몸 조각 11·관절 10 (ragdoll.gd 안 고침), 래그돌이 관절을 넣은 뒤 뼈 맞추기 → 스킨이 따라감. 뼈마다 충돌 캡슐을 따로 두는 길은 안 감 (관절 조각이 이미 그 일).
7. **클립** (`Ext.play_clip(이름)` / `stop_clip()`): 모델에 든 AnimationPlayer 동작을 그대로 재생, 그동안 뼈 맞추기 쉼. 지금은 함수·테스트만 (어디서 부를지는 안 정함 — `tank.json` `clips` 에 이름표만). 섞기 (코드 자세 + 클립) 는 아직.
8. **소품**: `keep` = 안쪽 (코드) 몸에서 남길 소품 refs 키 (탱크 `"shields"` — 우리 손 관절을 따라감, 모델 손과 조금 어긋날 수 있음). `attach` = 따로 받은 물건 .glb 를 모델 뼈에 (BoneAttachment3D).

## 3. 재혁이 Meshy/Tripo 에서 받은 .glb 를 넣는 순서

1. **뽑기**: 사람형, **T 포즈 또는 A 포즈**, 정면 (+Z 앞), 발이 바닥, 뼈대 자동 부여 (Mixamo 식 뼈) 켬, 무기·방패 없이 맨몸 (손은 펴거나 가볍게 쥔 모양). 애니메이션은 없어도 됨 (코드가 움직임).
   삼각형은 몸 하나 **1만 개 이하** 권장 (5절). 텍스처 1장 1024² 이하.
2. **넣기**: `godot/client/assets/models/ext/<캐릭터 id>.glb` (tank·ninja·hunter·bard·berserker·cannon·builder·hook). 고도 편집기를 한 번 열거나 `godot --headless --path godot/client --import` → `.glb.import` 생김 (커밋).
3. **켜고 보기**: 실행 인자 `--ext` (예 `godot --path godot/client -- --ext --auto practice --char <id>`), 고도 출력 창에 `외부 .glb 에 없는 뼈: …` 경고가 없으면 뼈는 다 찾은 것. 계속 쓰려면 `chars_config.gd` `EXT = true`.
4. **뼈 이름이 안 맞으면**: `assets/models/ext/<id>.json` 의 `"bones"` 에 `{"우리 관절": "모델 뼈 이름"}` (우리 관절 = `hips waist torso neck shoulder_R elbow_R hand_R shoulder_L elbow_L hand_L thigh_R knee_R foot_R thigh_L knee_L foot_L`, R = 캐릭터 오른쪽, 빈 글자 = 안 씀).
   이름은 고도가 바꾼 뒤 이름 (`:` 는 `_` 로 — `mixamorig:Hips` → `mixamorig_Hips`, 메시와 겹치면 `_2`). 자주 보는 규칙이면 `external.gd` `ALIASES` 에 별칭을 더하고 `test_match_conventions` 에 한 줄.
5. **크기·방향·색이 틀리면** (같은 json): `"yaw"` 앞 방향 (도, 기본 90 = glTF 앞 +Z), `"height"` 키 배율, `"offset"` [x, y, z] m, `"tint"` keep/band/tint, `"band"` 띠 [반지름, 두께, 올림] (모델 키 비율), `"keep"` 남길 예전 소품.
   **무기·방패**: 몸과 따로 .glb 로 받아 `"attach": [{"glb": "res://assets/models/ext/<id>_shield.glb", "joint": "hand_L", "pos": [0, 0.05, 0], "rot": [0, 90, 0], "scale": 1.0}]` (pos·scale 은 모델 키 비율, 손 뼈 기준).

## 4. 테스트 (`tests/test_external.gd`, 전부 `run_tests.gd` 에)

정리 이름 (14가지 표기) · 매칭 6규칙 (Mixamo·Quaternius·언리얼·Biped·Meshy 식·Tripo 식) · 덮어쓰기·골반 고침 · 시험 로봇 정보 · 판 몸 (안쪽 메시 비움·띠·툰·키·발바닥·뼈 방향·웅크림·발) ·
3단 (외부 끔 = 구운 몸 그대로, 외부 없는 캐릭터, 구운 몸 끔 = 조립 위 외부, 허수아비) · 합성 스킨 모델 (닌자 자리) · 반투명·번쩍·한 겹 더·유령화 · 1인칭 쌍둥이 · 래그돌 · 클립.
트리 밖 Skeleton3D 는 `get_bone_global_pose` 가 한 번 셈한 뒤 안 갱신돼서 테스트는 지역 자세를 직접 곱함 (판에선 그리기 전에 갱신되니 상관없음).

## 5. 숫자 (시험 로봇, 헤드리스 고도 4.7.2)

| | |
| --- | --- |
| 삼각형 (몸) / 1인칭 팔 | 3237 / 544 (구운 탱크 몸 8984) |
| 그리는 메시 (몸 하나) | 표면 19 + 띠 1 + 남긴 방패 조각 (구운 몸 4) — 외곽선이 next_pass 라 그리기 ×2 |
| 뼈 맞추기 `sync` | ~52 µs / 몸 (뼈 43개, 맞춘 뼈 16개). 구운 몸 묶음 뼈 맞추기 8.7 µs |
| 몸 만들기 | 처음 40 ms (.glb 읽기·표면 나누기·팔 메시), 그 뒤 2.3~2.8 ms (구운 몸 0.67 ms) |

## 6. 못 하는 것·위험

- **그리기 수**: 이 로봇은 조각 19개라 몸 하나 그리기 ~40 (외곽선 포함) — 8명이면 ~320, 구운 몸 (몸당 ~8) 보다 훨씬 많음. Meshy/Tripo 는 보통 메시 1·재질 1 이라 몸당 2 (툰 + 외곽선) 로 오히려 적음. 여러 재질이면 표면 수만큼 늘어남 → 뽑을 때 재질 1개 (텍스처 한 장) 권장
- **삼각형 상한**: W12 는 몸당 상한 숫자를 따로 안 정함 (그리기·스크립트 ms 위주). 지금 구운 몸 9천 × 8명 + 외곽선 껍데기 ×2 ≈ 14만 이 기준이라 **몸당 1만 이하** 를 권장으로 둠 (판단 보류 — 재혁 PC F3 숫자로 정해야 함)
- **스킨 가중치가 나쁜 모델**: 팔꿈치·어깨가 찌그러지거나 (자동 가중치), 한 뼈에만 붙은 넓은 면이 크게 휨. 코드가 고칠 수 없음 → 뽑는 쪽에서 다시 부여
- **비틀림**: 맞춤 회전이 방향만 맞춤 (최단 회전) 이라 손바닥·발끝이 쉬는 자세에서 다른 쪽을 볼 수 있음 (로봇은 괜찮음). 필요하면 관절마다 비틀림 덮어쓰기 값을 더해야 함 (아직 없음)
- **비율 차이**: 모델 팔·다리 길이가 우리 몸과 다르면 손 자리가 달라짐 → 평타 판정과 보이는 주먹이 어긋날 수 있음 (판정은 서버라 무관, 보기만). 1인칭은 `vm_snap` 으로 맞춤
- **표정 모프**: 표면을 나눌 때 모프 (blend shape) 를 버림 → 로봇 클립의 표정 트랙은 경고만 나고 안 움직임
- **초상·큰 캐릭터**: (W27 에서 고침) 얼굴 초상은 외부 모델이면 머리 뼈 (`Ext.bone_point("Head")`) 둘레, 키는 `PLAYER_HEIGHT × FIGURE_SCALE × height`. 모델마다 어긋나면 json `"portrait": {"half": 세로 반 (키 배율, 기본 0.22), "up": 올림 (키 배율, 0.02), "shift": [x, z] m}` (탱크 shift·사냥꾼·갈고리 half). 대기실 큰 캐릭터·초상 몸은 `Portrait.prime_idle` 로 쉬는 자세부터 (처음 pose 호출은 dt 0 이라 관절 처음 값 → 첫 프레임이 팔 벌린 자세로 찍힘)
- **반투명**: 표면마다 따로 투명이라 몸 안쪽 면이 비칠 수 있음 (예전 묶음 몸은 삼각형 정렬)
- **클립 섞기** 없음 (한 동작 통째 재생만), **AnimationTree** 안 씀
- 안쪽 몸 (코드 조립·구운 몸) 은 관절 노드로 여전히 만들어서 그 비용 (조각 몸 0.6~1.2 ms) 은 그대로 듬


## 9. W23 — 래그돌·1인칭 팔·동작 클립·목도리 (닌자 기준, 2026-11-05)

재혁 피드백 (v0.1.7 `--ext` 닌자): 래그돌 뻣뻣함 · 1인칭 팔 깨짐 · 코드 자세를 뼈에 옮기는 걸로는 어색함. 원인 측정과 고침 (공용 코드는 모든 외부 몸에 통함, 탱크 파일은 안 건드림):

- **래그돌**: 외부 몸도 래그돌이 켜지고 (진짜 판에서 '래그돌 켠 몸 1') 뼈 방향이 우리 관절 방향과 0° 로 맞음 (`tools/rag_shot.gd` 맞음·KO·낙사 코드 몸 vs 외부 몸 나란히 + CSV). 쓰러짐·일어남은 코드 몸과 같음 (골반 높이 차 ≈ 몸 비율 차 6 cm 그대로). 뻣뻣해 보이던 것은 **몸통에 굳어 있던 목도리 꼬리** (W21 이 꼬리를 몸통 뼈에 붙임) → 꼬리 뼈 3개 (`mixamorig:Scarf1~3`, `tools/blender/tripo/ninja_scarf.py`) + 월드 줄 시뮬레이션 `chars/ext_cloth.gd` (cfg `cloth`): 달리면 뒤로 날리고 맞아 날아가면 끌려다님.
- **1인칭 팔**: 원인 = 로더의 '팔꿈치 아래 삼각형 가르기' 가 뼈 가중치 섞임 따라 들쭉날쭉 열린 가장자리를 남김 (팔꿈치 끝이 화면에 보이는 자세에서 가시·잘린 단면). `tools/blender/tripo/ninja_vm.py` 가 아래팔 축에 수직인 평면으로 잘라 닫힌 메시 `ninja_vm` (좌우, 끝 마개 오므림, 1.3 배 굵게) 을 glb 안에 만듦 → `ninja.json` `vm_node`. 열린 모서리 11 개 (원본 구멍 몇 곳).
- **동작 클립** (`chars/ext_clips.gd` + `external.gd` 클립 층, cfg `clips`): `ninja_anim.glb` (뼈대 + 키프레임만, `tools/blender/tripo/anim_ninja.py` + 자세 표 `clips_ninja.py`, `anim_pack.mjs` 로 줄임) 에 idle·walk·run·jump·fall·land·atk1~4·air1·air2·dash·star·airstar.
  판 몸만: 코드 구동 위에 뼈 회전을 클립 쪽으로 섞음 (`cw`). 평타·스킬은 서버 단계 (준비·타격·회복 u) 를 클립 눈금 (0.30·0.40·0.80 초) 에 구간별로 맞춰서 타격 순간이 판정과 같음. 맞음·경직·낙사·일어나기·도발·승리·공중 대시 등은 늘 코드 (래그돌), 래그돌이 깨어 있고 모터 < 0.9 면 클립이 빠짐. 클립 바뀔 때 0.10 초 크로스페이드, 발 바닥 맞추기 (가장 낮은 발 뼈를 쉬는 자세 높이에, 달리기는 파묻힘만). 1인칭 쌍둥이는 클립 안 씀 (코드 관절을 베낌). `clips` 없으면 예전 그대로.
- 확인 그림: `tools/clip_shot.gd` (클립 contact sheet), `tools/rag_shot.gd` (래그돌 비교), `tools/vm_shots.gd <폴더> x ninja --ext` (1인칭 팔).
- 안 한 것: 맞음 전용 클립 (코드 + 래그돌 그대로), 도발·승리 포즈 클립, 발 IK (발 미끄러짐 가능), 손가락·표정.


## 10. W28 — 1인칭 팔이 이동·평타 때 공중에 떠 보이던 문제 (2026-11-06)

원인: 닫힌 팔 메시가 팔꿈치 바로 위에서 끝나 (탱크는 로더 가르기라 열린 가장자리) 팔을 앞으로 뻗는 자세 (평타·대시·점프) 에서 끝이 화면 가운데에 올라옴. 고침: 네 모델 모두 `*_vm` (탱크도 `tank_vm` + `tank.json` `vm_node`) 을 팔꿈치에서 어깨 쪽으로 팔 길이의 2.6 배 뻗은 닫힌 소매 통으로 (`tools/blender/tripo/ninja_vm.py` `extend_end`, README 14절). 로더·viewmodel 은 안 고침. 테스트 `test_vm_arm_reaches_shoulder` (통 길이·열린 가장자리)·`test_vm_arm_tip_offscreen` (서기·걷기·점프·낙하·대시·평타 자세에서 통 먼 끝이 시야 밖). 확인 그림 `tools/move_shot.gd <폴더> <캐릭터> --ext`.


## 11. W30 — 새 모델 랙 측정과 고침 (2026-11-07, PC 최적화)

재혁: 새 모델 (탱크·닌자·사냥꾼·갈고리) 이 들어온 뒤 PC 에서 랙이 되살아남. 지속 저FPS 인지 순간 끊김인지, 언제인지 불분명 → **히치 로거** 를 만들고 (재혁 PC 에서 다음 판 뒤 한 줄로 원인 확인) 헤드리스·소프트웨어 렌더로 후보를 가름.

- **히치 로거** (`core/hitch.gd`, 켜기: F3 성능 표시를 켜면 같이, 또는 실행 인자 `--hitch` — 꺼져 있으면 비용 0): 프레임 간격이 `max(최근 프레임 중앙값 × 2, 20ms)` 를 넘으면 `user://hitches.txt` (윈도우 `%APPDATA%\Godot\app_userdata\Tetrafall\hitches.txt`) 에 한 줄 — 시각·프레임 ms·화면·**원인**·스크립트/렌더 CPU ms·가장 긴 구간 (`Prof` 구간 프레임별 합)·그 사이 태그 (방 입장·판 단계·KO·부활·스킬·필살기·몸 만들기·모델 불러오기·외부 몸 연결·래그돌 만들기·미리 그리기·초상, 새 캐릭터 첫 등장 직후 3프레임은 '첫 그리기 지연 의심'). F3 패널 맨 아래와 '복사' 한 줄 끝에 `히치 N회 · 최악 xxms · 원인 상위: …`. 지속 저FPS 는 FPS·프레임 평균·1% low 가 말해 주고 (중앙값이 같이 올라서 히치로 안 셈), 히치는 그 위의 튐만 셈. 태그 달기: `Hitch.tag("KO", "x")`, 시간 재기 `var t := Hitch.t() … Hitch.span("몸 만들기", id, t)`.
- **원인 1 (고침)**: 새 모델 텍스처 아틀라스 (2048², jpg) 가 **무손실 가져오기** (`compress/mode=0`) 라 처음 읽을 때 CPU 로 풀기만 100~120ms (한 캐릭터당, 메인 스레드) + 영상 메모리 21MB (4명 85MB). 가져오기를 `VRAM 압축` (S3TC, `project.godot` `import_s3tc_bptc=true`) 으로: 읽기 2.4ms, 영상 메모리 5.6MB/명 (4명 15MB 포함 모든 것), 모습 차이 눈으로 안 보임 (`tools/lobby_shot.gd` 전후 비교). 테스트 `test_atlas_vram_compressed`.
- **원인 2 (고침)**: 몸이 **처음** 나오는 순간 읽기·정보 셈·첫 그리기가 한 프레임에 몰림. `External.request_all` 이 메뉴에서 쉴 때 모든 .glb·클립 파일을 스레드로 요청하고 (`ResourceLoader.load_threaded_request`), `External.warm_step` 이 캐릭터마다 진짜 몸을 아주 작게 카메라 앞에 두 프레임 그려 셰이더·메시를 올려 둠 (`world.gd`, G3 prewarm 다음, 실행 인자 `--no-ext-warm` 로 끔). 새 캐릭터 첫 프레임 133~363ms → 9~21ms (소프트웨어 렌더, `tools/ext_meas.gd --warm`).
- **측정 도구**: `tools/ext_meas.gd` (캐릭터별 읽기·만들기·첫 프레임·그리기·삼각형·영상 메모리, `--eight` 8명 합, `--warm`, `--no-ext`, `--order`), 재연 (`--replay … --prof --hitch`) 끝에 객체·메모리 늘어남 한 줄 (`core/replay.gd`).
- **못 가른 것**: GPU ms (소프트웨어 렌더). 판 중 8명 새 모델은 삼각형 +50% (208k vs 139k, 그림자·외곽선 포함 몸 하나 ~26.7k) 이고 CPU 는 +1.4ms/프레임 (`Ext.sync` 0.6 + 자세) — 재혁 PC 의 GPU 가 내장이면 이쪽이 지속 랙의 후보. 외곽선 껍질을 먼 몸에서 끄는 건 화면이 달라져서 측정 근거 없이는 안 함.

## 12. W31 — 지속 비용 (GPU) 줄이기 (2026-11-08, PC 최적화 2차)

W30 에서 남긴 것: 8명 판 삼각형 208k (새 모델 몸 하나 26.7k = 색 + 외곽선 껍질 + 그림자), 판 LOD 가 8.5~9천 아래로 안 내려감, 화질 프리셋은 있으나 프레임 시간을 보고 조절하진 않음. 소프트웨어 렌더라 GPU ms 는 못 재서 **삼각형·그리기 수·영상 메모리·픽셀 수** 로 환산하고, 재혁 PC 에서 스스로 조절하는 장치를 만듦.

1. **적응형 3D 해상도** (`world/adapt_calc.gd` 순수 계산 · `world/gfx.gd` 적용 · 수치 `WC.ADAPT`): 판 중 (`playing`) 에만 프레임 시간을 20프레임 (60fps 에서 0.33초) 씩 모아 느린 쪽 20% 를 버린 평균 (히치 무시) 으로 판단. 목표 = 모니터 주사율을 30~60 으로 (144Hz 여도 60fps) 의 프레임 시간. **GPU 병목일 때만** (렌더 GPU 시간이 있으면 그것이 목표 초과, 없으면 프레임 − CPU 일 (스크립트 + 렌더 CPU) 이 80% 넘게 남음 = 기다리는 중) 배율 (`scaling_3d_scale`) 을 천장 (화질이 정한 배율, 높음 1.0) 에서 바닥 0.6 (천장이 더 낮으면 천장) 사이로: 내릴 땐 다음 창에 곧바로 `sqrt(목표×0.92/실제)` (한 번에 0.05~0.15), 올릴 땐 목표를 맞춘 창이 6개 (2초) 연속이고 올린 뒤 예상도 여유 안일 때만 0.05씩, **올렸다가 곧 도로 내리면 (프로브 실패) 그 배율을 기다림 2^실패 횟수 ×10초 동안 다시 안 올림** — V-Sync 로 프레임이 목표에 붙어 여유를 알 수 없을 때도 진동이 점점 드물어짐. 바닥에서도 3초 넘게 느리면 MSAA 한 단계 (4×→2×, 2×→끔), 판이 끝나면 되돌림. 대기실·메뉴·카운트다운·결과는 천장 고정, 2D (UI) 는 원래 해상도 (`scaling_3d` 는 3D 만), 1인칭 팔 SubViewport 도 같은 배율. 새 설치 기본 켬 (설정 창 '시점' 줄 '3D 해상도 자동', 예전 설정 파일에서 화질을 높음·보통·낮음으로 직접 골라 둔 사용자는 끔 — `View.migrate_adapt`), 웹 (W29 프리셋 그대로)·소프트웨어 렌더 (llvmpipe 등) 는 자동으로 안 함. F3·설정 창 화질 글에 지금 배율 (`3D 80%`) + '자동 해상도 (천장 100%)'.
   - **가짜 GPU 부하 시험** (`tests/test_adapt.gd`): 프레임 시간 = max(CPU, 가득 그릴 때 GPU ms × 배율²) + 잡음 (V-Sync 면 16.7ms 칸으로 올림) 을 계산기 입력으로 — 30ms 부하 4가지 (V-Sync 유무 × GPU 시간 알림 유무) 가 1초 안에 0.6~0.75 근처로 내려오고, 정착 뒤 마지막 20초 배율 변화 ≤ 8번, V-Sync 에 붙은 경우 프로브 간격이 점점 늘고 느린 프레임 비율 6% 미만, CPU 병목이면 배율 그대로, 가끔 튀는 프레임 무시, 바닥·천장·MSAA 낮춤·판 끝 되돌림. 엔진 안에서는 `--adapt --adapt-fake-gpu 40` (소프트웨어에서도 켜고 배율 1 에서 GPU 40ms 인 척) 으로 8명 재연이 3D 배율 0.60 + MSAA 낮춤까지 내려감 확인.
2. **판 LOD 다시 굽기** (`tools/blender/tripo/relod.py`·`relod_merge.mjs`, README 15절): 닌자·탱크·갈고리 판 LOD 를 stage → Decimate → 새 UV → 알베도 굽기 (1024) 로 high 5000·medium 4000·low 3000 삼각형 (예전 8500~8900 하나). 8명 판 삼각형 (같은 캐릭터 8명, 외곽선 포함, `ext_meas.gd --eight --level …`): 탱크 143.1k → 80.0k (높음)·64.0k (보통)·48.0k (낮음), 닌자 137.8k → 81.5k·65.5k·49.5k, 갈고리 133.8k → 80.0k·64.0k·48.0k (사냥꾼은 그대로 79.9k·64.0k·48.0k). 몸 하나 `tris +17.9k → +10.0k` (높음). 영상 메모리 +6 MB (1024 아틀라스 추가). 모습은 `tools/lod_shot.gd` 로 3색 나란히 전후 (예전 LOD 의 치마 검은 구멍이 없어지고 색·팀 색 칸 같음, 낮음 (3000) 에서만 가는 장식 선이 조금 뭉개짐). 테스트 `tests/test_relod.gd`.
3. **외곽선 거리** (`world/outline_far.gd`·`chars/body.gd set_outline_far`·`shaders/outline.gdshader`, 수치 `WC.OUTLINE_FAR`): 외곽선은 화면 일정 굵기라 먼 몸은 상대적으로 굵었음. 카메라 거리 (시야각 70° 기준으로 환산) 8m 부터 굵기가 줄어 16m 에서 0.25 배 (0.4px) 가 되고 그 너머 (켜고 끄는 문턱 ±1m) 는 외곽선 껍질 (next_pass) 을 아예 뗌 → 먼 몸은 한 번만 그려짐 (몸 자세 LOD 둘째 단 10m 는 그 사이). 재연 (`game8.rec` 8명, 소프트웨어 렌더, `--no-outline-far` 전후): **전체 보기 (몸이 전부 멀리) 삼각형 198.8k → 141.2k (−29%), 그리기 224 → 207, 물체 360 → 343** · 3인칭 (다른 몸이 대부분 16m 안) 199.0k → 191.9k (−3.5%), 그리기 235 → 233 — 지속 이득은 시점·필드 크기에 따라 다름 (큰 판에서 멀리 있는 몸이 많을 때). 내 몸·가까운 몸·1인칭·대기실·초상은 그대로, 블록·아이템 외곽선도 그대로 (몸 외곽선 재질만 사본 `far_taper`), 몸마다 재질을 따로 가질 때만 (나눠 쓰는 재질은 안 건드림). `--no-outline-far` 로 끄고 비교. 테스트 `tests/test_outline.gd`.
4. **그 밖의 지속 비용 점검** (`replay --census` 8명 3인칭, 소프트웨어 렌더): 3D 삼각형 = 보이는 것 114.8k + **해 그림자 패스 71.7k (38%)** + 2D 1.4k. 그림자 패스는 몸 (몸마다 그림자 몸 = 보이는 LOD 와 같은 삼각형, 외곽선 껍질은 W15 부터 뺌) + 지형 블록·장식이 대부분이고 그림자 지도는 이미 1024 (JS 와 같음)·그림자 거리는 필드 대각선/2 + 16 으로 판 크기에 맞춰짐 — 줄일 근거 (GPU ms) 가 없어 **안 건드림** (다음 후보: 먼 몸의 그림자 끄기 — 모습이 바뀜). 텍스처: 새 판 LOD 아틀라스 1024 (VRAM 압축·밉맵), 이방성은 프로젝트 기본. MSAA 4× × 2880×1800 (5.2M 픽셀) 은 위 적응형 규칙에 넣음 (바닥 배율에서도 느리면 MSAA 한 단계). 닌자는 몸 하나 그리기 14회 (단검 둘 × 세 조각 × 색·외곽선 + 몸) — 단검 조각을 합치면 8회 줄지만 닌자 한두 명에 8회라 안 함. 히치 로거는 배율·MSAA 가 바뀌는 순간 `해상도 변경` 태그 (원인 1순위) 를 붙임.

## 13. W33 — 동작 클립이 팔다리에 안 먹던 결함과 새 모델 이동 클립 (2026-11-08)

- **결함 고침**: 판 몸의 `Ext._process` 가 (고도가 `_ready` 때 다시 켬 — `setup` 의 `set_process(false)` 는 트리에 들어가기 전이라 안 먹음) `body.pose` 의 `sync(st)` (코드 + 클립) 직후 st 없는 `sync()` (코드만) 로 맞춘 뼈를 덮어쓰고 있었음 → 닌자 클립이 척추·머리·목도리에만 먹었음. `sync(st)` 가 부른 프레임을 `st_frame` 에 적고 같은 프레임 `_process` 는 건너뜀 (판 몸만). 테스트 `test_process_does_not_overwrite_clip`. 이 고침으로 닌자 평타·대시·표창 클립이 처음으로 게임 길에서 적용됨.
- **새 이동 클립**: 탱크·사냥꾼·갈고리에 idle·walk·run·jump·fall·land (`assets/models/ext/<id>_anim.glb`, `<id>.json` `clips`, `moves` 는 비어 있음 = 공격·스킬·맞음·도발·승리는 코드 구동 그대로, 서버 타이밍 불변). 만드는 법: `tools/blender/tripo/clips_loco.py` (공용 생성기) + `clips_tank.py`·`clips_hunter.py`·`clips_hook.py` (캐릭터별 스타일 표) → `blender -b --factory-startup -P tools/blender/tripo/anim_ninja.py -- --rig godot/client/assets/models/ext/<id>.glb --out <raw>.glb --clips clips_<id>` → `anim_pack.mjs` 로 키 줄이기 → `godot --headless --import`. 뼈대는 최종 `<id>.glb` 를 그대로 `--rig` 로 쓰면 됨 (뼈 이름·쉬는 자세가 같아야 클립이 맞음).
- 도구: `tools/pose_sheet.gd` (상태별 contact sheet, `--noclip`·`--only`), `tools/foot_slide.gd` (발 미끄러짐 비), `tools/blender/tripo/model_audit.py` (모델 자동 검사). 검토·점수표·보류 사유는 `docs/model-review-2026-11.md`.

## 14. W32 — 해 그림자·CPU 소소한 비용·렌더러 점검·하이브리드 GPU (2026-11-08, PC 최적화 3차)

W31 이 남긴 후보 (해 그림자 패스 = 3D 삼각형의 38%) 를 실제로 줄이고, 닌자 단검 그리기를 합치고, 렌더러 비교표와 하이브리드 노트북 경고를 넣음. 새 모델 모습·PC 동작은 그대로 (캡처 전후 화소 차 4명 408/921600, 닌자 확대 단검 위치·색 같음). 소프트웨어 렌더 (llvmpipe) 라 GPU ms 는 못 재서 **그리기·삼각형·영상 메모리** 로 환산.

1. **그림자 비용** (`world/shadow_calc.gd`·`chars/ext_shadow.gd`·`world/pieces_view.gd`·`world/grid_view.gd`·`world/world.gd`, 수치 `WC.SHADOW`, 끄기 `--no-shadow-opt` · 먼 몸만 `--no-shadow-far`):
   - **보이는 몸 ≠ 그림자 몸**: 판 몸 (외부 모델) 은 보이는 LOD 메시의 그림자를 끄고 (`cast_shadow` OFF) **가장 낮은 LOD (3천) 를 같은 뼈대·스킨으로 하나 더 두어 그림자만** 던짐 (`SHADOWS_ONLY`, 재질 없음). 높음 5000 → 3000, 보통 4000 → 3000, 낮음은 이미 그 LOD 라 안 함 (그림자도 꺼짐), 대기실 큰 캐릭터·초상·1인칭 쌍둥이는 그대로. **재질이 없어서 외곽선 next_pass 도 그림자 패스에 안 따라감** — 고도 그림자 패스는 next_pass 도 한 번 더 제출 (셰이더가 화면 밖으로 납작하게 눌러 래스터만 빠지지만 정점 처리와 삼각형 수는 셈) 해서 몸 하나가 그림자 패스에 10.0k (5000 × 2) 로 잡히던 것이 3.05k 로 줆.
   - **먼 몸·시야 밖 몸 그림자 끄기** (`bodies.gd` → `body.set_shadow_off`): 카메라 거리 (시야각 70° 환산, 외곽선 거리와 같은 식) 22m 넘거나 (문턱 ±1.5m), **몸도 그 몸 그림자가 떨어지는 자리 (해 반대쪽 바닥) 도 시야 밖**이면 그 몸의 그림자 메시를 끔 (내 몸 늘 켬). 그림자 전용 메시는 `visible=false` 로 끔 (cast OFF 로 끄면 오히려 화면에 그려짐 — 처음 구현에서 화면 삼각형이 12k 늘던 걸 `_drawn` 테스트로 막음). 3인칭 8명 판에서는 대부분 22m 안이라 이득이 작고, 큰 판 전체 보기·하늘 시점에서 커짐.
   - **블록 칸 그림자는 상자로** (`pieces_view.gd` 떨어지는 칸·`grid_view.gd` 쌓인 모양 칸): 테마 칸 모양은 168~432 삼각형 (+ 외곽선 패스) 인데 그림자는 상자면 충분 → 보이는 칸은 그림자를 끄고 같은 자리 상자 MultiMesh (12 삼각형, `SHADOWS_ONLY`) 가 대신 던짐 (상자 칸 모양이면 그대로). 쌓인 칸이 늘수록 커지던 비용이라 판 후반에 가장 큼.
   - **그림자 거리** (`ShadowCalc.reach_next`): 판 크기로 정한 값 (대각선/2 + 16) 이하로, 카메라에서 판 가장 먼 모퉁이까지 (+높이) + 8m 를 4m 단위로 올림 — 늘 땐 곧바로, 줄 땐 한 단계 반 넘게 여유일 때만 (경계에서 거리가 떨면 그림자 지도 픽셀이 흔들림). 방향광은 ORTHOGONAL 한 겹이라 캐스케이드는 따로 없음.
   - **정적 블록·지형 그림자 갱신 줄이기는 안 함**: 고도에 방향광 그림자 캐시가 없음. 대신 쌓인 칸이 상자 그림자라 (지형 칸은 원래 12삼각형) 같은 효과.
   - **재연·측정 도구**: `--census` 표에 '그림자 던지는 삼각형' 열, 끝에 `해 그림자: 켬 · 거리`, `tools/shadow_meas.gd` (8명 + 떨어지는 칸 + 쌓인 칸을 해 그림자 켠 장면에 놓고 그림자 패스 삼각형·그리기·프레임 ms, `--no-shadow-opt`·`--level`·`--far`·`--close`·`--zoom`·`--shot`).
2. **CPU 소소한 비용**:
   - **닌자 단검 합치기** (`tools/blender/tripo/rig_ninja.py --dagger`, README 8절): 칼날·손잡이·날밑 세 조각을 한 메시·한 재질 (12×1 팔레트 PNG) 로 → 닌자 몸 그리기 14회 → 6회 (손마다 색·외곽선 2). 모양·색·자리 그대로.
   - **몸 만들기 분산** (`bodies.gd`, `WC.BODY_BUILDS_PER_FRAME` 2): 방 입장·봇 8명이 한 프레임에 몸을 만들면 (만들기 1.6~2.6ms + 처음 그리기 9~12ms 씩) 크게 끊김 → 한 프레임에 2개씩 (내 몸은 바로), 못 만든 몸도 자리는 알려 줌.
   - **먼 몸 자세 셋째 단** (`pose_lod.gd`, `POSE_LOD.far3` 18m 밖 15Hz·웹 10Hz): 뼈 맞추기·천·figureAnim 이 몸마다 덜 돎. 재연 game8.rec 은 18m 밖 몸이 거의 없어 차이 없음 (자세 함/안 함 3.86/4.14 → 3.85/4.14) — 큰 판 전체 보기에서만 이득. `Ext._process` 의 sync 는 1인칭 쌍둥이만 (판 몸은 `pose` 안에서 LOD 간격으로만) 이라 따로 안 고침.
   - **래그돌 먼 몸 끄기 확인**: 쉬는 몸은 이미 kinematic (`RAGDOLL_SLEEP_MS` 뒤, 목표 자세 계산도 골반만) 이라 먼 몸을 따로 안 끔 (끄면 다시 켤 때 쓰러짐 자세가 끊김).
3. **렌더러 비교표**: 아래 (README 렌더러 시험 절). 기본 렌더러는 **안 바꿈**.
4. **하이브리드 GPU** (`gfx_calc.gd`·`gfx.gd`·`perf.gd`·`settings.gd`, `server/tools/package.mjs`): `.bat` 이 등록하는 exe 이름 (`tetrafall.exe`) = 묶음에 들어가는 윈도우 클라 = 내보내기 프리셋 이름 (테스트), 값 이름은 `%~dp0` 전체 경로. 내장 판정에 UHD·Iris 추가, 시작 로그 `[GPU] 이름 (제조사) · 내장`, 하이브리드를 알아내면 (`reg query` 로 외장 GPU 를 찾았을 때만) F3·화면 구석·설정 창에 '내장 GPU 로 도는 것 같음 (X 있음) — 설정 > 시스템 > 디스플레이 > 그래픽에서 tetrafall.exe 를 고성능으로 지정' + 로그 경고, F3·구석 GPU 이름 뒤 `(내장)`, 설정 창 화질 줄 아래 도움말 한 줄 (늘 보임).

**W32 전후 (소프트웨어 렌더, 같은 장면·같은 코드에서 `--no-shadow-opt` 전 / 후, 닌자 그리기는 W32 이전 커밋 0e9b3c8 과 비교):**

| 장면 | 항목 | 전 | 후 |
| --- | --- | --- | --- |
| 8명 (닌자·탱크·사냥꾼·갈고리 ×2, 높음) + 쌓인 칸 60 + 떨어지는 칸 12 (castle) | 그림자 패스 삼각형 | 142.6k | **25.3k (−82%)** |
| 같은 장면, 화질 보통 | 그림자 패스 삼각형 | 126.6k | 25.3k |
| 같은 장면 | 화면 삼각형 · 그리기 (닌자 2명 포함) | 143.7k · 71 | 143.7k · **47** |
| 8명만 | 그림자 패스 삼각형 · 그리기 | 80.4k · 65 | **24.4k** · 41 |
| 8명, 절반을 카메라에서 44~50m | 그림자 패스 삼각형 (그림자 끈 몸 4/8) | 40.2k | **12.2k** |
| 4명 (닌자·탱크·사냥꾼·갈고리) 가까이 | 그림자 패스 삼각형 · 그리기 | 40.2k · 33 | **12.2k** · 21 |
| 닌자 한 명 확대 | 그림자 패스 삼각형 · 그리기 | 10.2k · 24 | 3.2k · 12 |
| 재연 `game8.rec` 3인칭 (코드 몸 + 탱크 3, 보통) | 그림자 패스 삼각형 · 전체 삼각형 | 52.3k · 148.9k | 40.3k (−23%) · 136.9k |
| 〃 | 화면 삼각형 · 그리기 · 영상 메모리 | 95.3k · 173 · 134.3MB | 95.3k · 174 · 130.8MB |

- 화면 삼각형은 그대로 (그림자만 줄임). 영상 메모리는 상자 그림자·그림자 전용 메시·팔레트 그림으로 +0.8MB (8명 + 칸 장면). 재연의 몸 대부분이 코드 몸 (`body.gd/batch`, 13k) 이라 이득이 작음 — 코드 몸은 합친 메시 하나에 외곽선 next_pass 가 있어 그림자 패스에 두 번 잡히는데 따로 줄이지 않음 (다음 후보: 코드 몸도 그림자 전용 메시).
- 모습: 4명 캡처 (`shadow_meas.gd --close`) 화소 차 (>8) 408 / 921,600 (그림자 가장자리 모양 + 닌자 단검 한 점), 닌자 확대 (`--zoom`) 단검 위치·색 같음, 블록 칸 그림자 (상자 vs 칸 모양) 눈으로 구별 안 됨.

## 15. W34 — 새 모델 다듬기 (2026-11-09, 자세한 전후는 `docs/w34/README.md`)

- **몸 색 칸 마스크 텍스처**: json `skin_mask {메시 노드: 마스크 png}` → 툰 재질 `skin_mask_tex`·`use_skin_mask` (`External.Ext.skin_mask_for`·`toon_for`). 마스크는 `tripo/relod.py` (판 LOD, 알베도와 같은 UV) / `tripo/maskbake.py` (사냥꾼 stage UV) 가 굽는다. 없는 메시는 예전 꼭짓점 UV2.x 판정.
- **걷기·달리기 보폭**: json `clips.stride {걷기·달리기: [k, c, 박자]}` — k 배 발 앞뒤 (c = 한 바퀴 평균 자리) 2본 IK (`Ext._stride_ik`, `leg_ik`) + 클립 박자 배율 (`ext_clips.gd select`). 측정 `tools/foot_slide.gd`.
- **공중 대시 손목**: json `dash_wrist {관절: [x,y,z 도]}` (`Ext._dash_wrist`, `st.airDash > 0` 때만). 확인 `tools/air_dash_shot.gd`.
- **1인칭 전용**: json `vm_bone_scale {뼈: 배율}` (`Ext._vm_bone_scale`, 탱크 방패), 사냥꾼 소총은 `attach` 의 `vm: true`·`third: false` (`hunter_rifle.glb`, `tripo/hunter_rifle.mjs`).
- **갈고리 부스러기·이음 삼각형**: `tripo/drop_shards.mjs`·`hook_bridge.py` (README 18절).
- **서버 판정 vs 보이는 타격**: `tools/hit_reach.gd` (표 `docs/w34/7_hit_reach.csv`).

## 16. W37 — PC 최적화 4차: 프레임 구성 분류별 측정과 고침 (2026-11-09, 표는 `docs/w37/README.md`)

- **도구**: `replay --budget` (`core/budget.gd`, 분류마다 그 물체만 끄고 그려 그리기·삼각형·그림자 삼각형 몫 + 그림·CPU ms·SubViewport), `tools/frame_budget.cjs` (장면 여럿 표), `tools/rec_chars.mjs`·`rec_loop.mjs`·`replay --mon-every` (긴 판 누수), `tools/leak_probe.gd`.
- **고침**: 1인칭 팔 SubViewport MSAA 4×→2× (영상 메모리 −14MB), 코드 몸 그림자 쌍둥이 (예전 몸 8명 삼각형 −17.5%), **G3 재질 기록 누수** (몸 하나당 객체 +10~29 → 0), 위험 표면 격자 120→64 (용암 판 삼각형 −12.5%). 끄기 `--no-vm-msaa-cap`·`--no-batch-twin`.
- **안 한 것 (측정 근거)**: 칸 거리 LOD (<1% 라 되돌림), 이펙트 풀 (상한 안), 대기실 리소스 해제 (2.7MB), 새 모델 LOD 아틀라스 상주 (glb 쪼개기 필요 — 보류).


## 17. W38 — 새 모델 평타·스킬·도발·승리 클립, 맞음 움찔, 1인칭 휘두름 (2026-11-09, 전후 그림 `docs/w38/`)

- 클립: 탱크 `t_*` 6·사냥꾼 `h_*` 6·갈고리 `k_*` 8 평타·스킬 + 도발·승리 (`<id>_anim.glb`, 자세 표 `tools/blender/tripo/clips_<id>.py` 의 `define_attacks`·`define_poses`, 만들기는 16절 W33 과 같은 명령). `<id>.json` `clips.moves {서버 동작 이름: 클립}`·`clips.taunt`·`clips.victory`. 눈금 `marks` 0.30/0.40/0.80 (서버 준비·타격·회복 u 를 구간별로 맞춤, `ext_clips.gd select`), 도발 클립 길이 = `EMOTE_MS` (끝은 쉬는 자세), 승리는 반복.
- `select`: 전용 도발 (`C.EMOTE_CHAR`)·승리는 힘 빠진 상태·방금 맞음이 아니면 클립. 맞음·경직·낙사·일어남은 여전히 코드 + 래그돌.
- 맞음 움찔 `Ext._hit_flinch` (config `EXT_HIT_FLINCH_*`): 가산 (척추 둘·머리), 모든 외부 몸 (닌자 포함), 래그돌 모터 약하면 빠짐.
- 1인칭: `viewmodel.gd act_swing` + config `VM_ACT_STYLE`·`VM_ACT_SWING`.
- 테스트 (`test_ext_clips.gd`): `W38_MOVES` 표 (캐릭터별 클립 만든 동작) — 클립을 늘리면 표도 늘림. 단계→눈금·클립 길이·타격 순간 손·골반 앞으로·움찔·도발·승리·1인칭 곡선.


## 18. W39 — PC 최적화 5차 (2026-11-10, 표는 `docs/w39/README.md`)

- 합친 뒤 영상 메모리 +21MB 는 회귀 아님 (같은 녹화 W37 151.2 = 합친 151.2MB, 조건 차이).
- 알베도 지연 로드 (`External.lazy_tex`, `Ext.tex_of`, `--no-lazy-tex`): 메뉴 47.6→30.9MB, 판 8명 55.1→43.1MB.
- 칸 LOD (`world/cell_lod.gd`, `--no-cell-lod`·`--cell-lod-far`): 먼 칸은 108삼각형 낮은 모양, 판 후반 합계 141.8k→126.9k.
- 섬·바위 해 그림자 끔 (`--no-scenery-opt`): 그림자 지형 6.0k→1.8k.
- 몸 자세: `_code_maps`·`_code_bones` ext.sync 0.064→0.023ms/몸. 도구 `tools/tex_meas.gd`·`pose_cpu.gd`·`--budget-split`.


## 19. W41 — 렉 사냥: 메뉴 직후·판 시작 직후·블록 이벤트 (2026-11-10, 표는 `docs/w41/README.md`)

- 측정 도구 (재혁 PC 에서도 씀): `--hitch --lag-log <파일>` (프레임마다 한 줄: 시각·프레임 ms·스크립트 ms·렌더 CPU·화면·구간·태그), `--first-use [--first-out 파일 --first-min ms]` (구간·시간 잰 일마다 처음·둘째 부름 ms 표), `--boot-log` (켜는 동안 단계 ms), `--menu-wait <초>` · `--start-delay <초>` (메뉴·대기실에 이만큼 있다 진행), `--sched-log`, `--mat-census`.
- 프레임 예산 스케줄러 `world/prewarm_sched.gd` (`PSched.main`): 메뉴·대기실 미리 하기를 조각으로, 프레임당 3ms 예산·조각 4개 상한·입력 뒤 150ms 쉼 (굶으면 2.5초마다 한 조각)·평소보다 느린 프레임 뒤 쉼 (평소 프레임에 상대)·판 중 쉼·`WAIT` (기다림은 조각으로 안 셈). 끄기 `--no-prewarm-sched` (예전 방식).
- world 는 타이틀·메뉴 동안 숨겨짐 (`title.gd`) → 그때 그리는 일은 셰이더를 안 만듦. 그리기 작업 (G3.prewarm 조각·재질 미리 그리기 `world/warm_scan.gd`·몸 데우기 그리기·판 빛·위험 경고 가장자리) 은 world 가 보일 때 (대기실) 로 미루고, 메뉴에선 읽기·정보 셈·텍스처 요청·LUT 만.
- `chars/tex_prefetch.gd`: 대기실 사람들의 캐릭터 알베도·마스크 (큰 캐릭터·초상 = stage LOD, 판 몸 = 화질 LOD) 를 스레드로 미리 요청, 몸·초상을 만들 때 `Ext.tex_of`·`skin_mask_for` 가 받음. 판이 playing 이 되면 안 받은 것 놓음. 끄기 `--no-tex-prefetch`.
- 적응형 해상도: 판 시작 4초 유예·스파이크 (중앙값 3배·25ms↑) 프레임 판단에서 뺌·바꾼 직후 한 창 건너뜀 (`WC.ADAPT` `grace_ms`·`spike`·`settle`).
- 히치 로거: 이벤트 태그 (스킬·필살기 = 캐릭터 + 종류, 처음 본 이벤트 종류 = '첫 이벤트', '블록 낙하 시작 <모양>', '미리 하기'), 한 판 끝에 원인 상위 5개 + 최악 ms + 시점을 `hitches.txt` 에 `# ---- 판 요약` 줄로, F3 맨 아래에 상위 3개.

## 20. W40 — 모션 개선 2차: 천 뼈·시선·숨쉬기·착지·맞음 방향·타격 끝 (2026-11-09, 전후 그림·표 `docs/w40/`)

- **천 뼈 (`tools/blender/tripo/cloth_bones.mjs`)**: 이미 만든 `ext/<id>.glb` (stage + 판 LOD) 에 뼈 사슬을 더함. Blender·relod 를 다시 안 돌리고 gltf-transform 으로 새 뼈를 스킨 **끝에** 붙이고 (기존 65 뼈 번호·애니메이션 클립 호환), 천 꼭짓점 (규칙은 캐릭터별 `sel`) 의 가중치를 높이·가로 hat 으로 새 뼈에 옮김 (위쪽은 몸 가중치와 부드럽게 섞음, 꼭짓점당 4개 제한). 선택은 꼭짓점 단위 규칙이라 stage·LOD 가 같은 천을 가리킴 (모델 점검 `model_audit.py`: 가중치 합·정점당 뼈 4·삼각형 수 그대로). 재생성: `node cloth_bones.mjs <in.glb> <out.glb> hunter|tank|hook [--debug <폴더>]` (한 번만 — 이미 천 뼈가 있으면 거절).
  - 사냥꾼 **망토**: 올리브 칸 (+ 몸 뒤) 에 `Cape1~3` × 3 마디. 탱크 **등 뒤 천** (몸 뒤 x < -0.115 얇은 판): `Tabard1~2` × 3. 갈고리 **코트 자락**: 엉덩이 아래·다리 축에서 먼 꼭짓점 (팔·갈고리는 팔 뼈 가중치로 뺌, 앞자락은 다리를 따라감) `Skirt1~3` × 3. 탱크의 붉은 목도리 (몸 색 칸) 는 목 둘레뿐이라 꼬리·**허리 앞 천은 없어서 보류**.
  - `ext/<id>.json` `cloth` (사슬마다 `bones`·`rest`·`damp`·`gravity`·`fwd`). `ext_cloth.gd`: 사슬 끝 점 방향을 앞 뼈와 같게 (뼈 +Y 가 사슬을 안 따르는 모델), `fwd` = 쉬는 자리보다 몸 앞으로 이만큼 넘게 못 나옴 (등 뒤 천이 몸을 뚫고 오지 않게). 판 몸만, 먼 몸은 `pose` 가 안 불려 시뮬도 건너뜀.
  - 확인: `tools/cloth_shot.gd` (달리기·맞아 날아감·점프·돌기 시뮬 프레임 줄), `docs/w40/cloth/`.
- **가산 층 (`chars/ext_motion.gd` 순수 계산 + `external.gd _extra_layer`)**: 시선 (가장 가까운 다른 몸 ±`EXT_GAZE_MAX_DEG` 35°, 척추 2·목·머리에 나눔, 맞음·경직·공격·도발·승리·대시 중 끔), 숨쉬기 (캐릭터마다 주기·위상), 착지 (무릎 굽힘 + 윗몸 숙임, 엉덩이는 발이 올라간 만큼 잰 값으로 내림). 수치는 `chars_config.gd EXT_*`. 정적 목록 `Motion_.bodies` (판 몸).
- **맞음 방향** (`_hit_flinch`): 앞·뒤·옆 (머리가 앞으로/뒤로, 옆은 몸통 비틂), 치명·강타 (pow ≥ `EXT_HIT_CRIT_POW`) 는 머리 채찍 진동 + 쥔 손 흔들림, 탱크 방어구 깨짐 (`armor_break_react_at`) 은 방패 쥔 (왼) 팔 반동. **고침**: 코드 구동이 안 맞추는 뼈 (머리·Spine1 등) 에 가산이 매 프레임 쌓이던 문제 → `_reset_extra`.
- **1인칭 팔 = 클립 곡선 (보류)**: `arm_delta` (클립이 코드 자세에서 벗어난 팔 뼈) 를 쌍둥이 팔에 `K.VM_CLIP_ARM` 비율로 더하는 길은 있으나 0.3·0.55 로 켜 보니 팔이 솟거나 왼손이 세로로 서서 기본 끔 (`docs/w40/vm_clip/`). 확인 `tools/vm_clip_shot.gd`.
- **타격 끝**: 사냥꾼·갈고리 클립의 타격 자세 (`hips_x`·상체·팔 뻗기) 키움, `tools/hit_reach.gd` 전후 `docs/w40/reach/`.
- 테스트 `tests/test_w40.gd` (12). 비용 `tools/ext_cost.gd`.

## 21. W43 — 모션 개선 3차: 방향 이동·기울임·일어나기·무기 흔들림·클립 이음 (2026-11-10, 표·전후 `docs/w43/README.md`)

- 전부 `chars/ext_motion.gd` (순수 계산) + `external.gd` 가산 층 (`_dir_update`·`_move_layer`·`_getup_layer`·`_weapon_layer`, 판 몸만), 수치 `chars_config.gd` `EXT_DIR_*`·`EXT_LEAN_*`·`EXT_TURN_*`·`EXT_GETUP_*`·`EXT_WEAPON`·`EXT_FADE_*`·`VM_CLIP_ARM_K`. 서버 판정·moves·figure_motion 불변. 끄기: 실행 인자 `--no-w43` (`Ext.move_off`).
- `body.gd _anim_state` 에 몸 기준 이동 `mvF`·`mvS` (앞·왼쪽 m/s)·월드 이동 `vw` 추가 (몸은 조준 yaw 를 보고 이동은 따로).
- 방향 이동: 뒤로 걸음 = 걷기·달리기 클립 거꾸로 (`select` 의 `rev`, 크로스페이드 키 `이름~r`), 옆·대각 = 골반 yaw + 척추 반대. 일어나기: 경직 뒤 웅크림 (`st.recover`)·부활 (0.5초 숨음) 에 0.7초 가산, 래그돌 모터로 가중. 무기: 손뼈 가속도 → 용수철. 클립 이음: `Clips_.fade_s` 종류별 크로스페이드 (공격 진입은 0.10 그대로), `tools/clip_pops.gd` 가 이음 자세 차이 측정.
- 1인칭 팔 클립 곡선 켬 (`VM_CLIP_ARM` 1.0): 손 전역 회전 고정 + 어깨·팔꿈치만 (`VM_CLIP_ARM_K`).
- 확인 도구: `tools/pose_sheet.gd` 에 묶음 `dir`·`getup` 과 `--w43off`, `tools/ext_cost.gd` 에 'W43 끔' 줄. 테스트 `tests/test_w43.gd`.
- 보류: 탱크 허리 앞 천·어깨 장갑 (단독 뼈 없음 — 가중치 실측), 닌자 등 칼 단독 흔들림 (몸 메시 하나), 발 미끄러짐 방향 이동 측정.


## 22. W44 — 모션 QA 자동화와 고침 (2026-11-11, 표·전후·상위 20 `docs/w44/README.md`)

재혁 눈 피드백 없이 **재연 전체에서 새 모델 4명의 뼈·메시를 60Hz 로 표본해** 튐 (팝)·떨림·발 미끄러짐·천/무기 뚫림·삼각형 늘어남·관절 한계·상태 전환 이음새를 자동으로 세는 도구.
- 도구: `core/motion_qa.gd` (표본기 노드, `--motion-qa <폴더>` → `motion_qa.json`·`.csv`), `core/motion_qa_math.gd` (순수 검출기·임계, `tests/test_motion_qa.gd` 가 합성 뼈 열로 시험), `tools/motion_qa.mjs` (결과 합치기·전후 표). 판 중 가벼운 모드 (`--motion-qa` 만) = 팝 카운터만 + 한 판 끝에 `user://motion_qa.txt` 에 상위 5개. 꺼져 있으면 노드 없음 (비용 0).
- **가상 시계**: 몸 동작 층·천·`body.gd` 몸 시간·래그돌 재우기가 `Motion_.now_s()/now_ms()` (`ext_motion.gd`, 재연에선 `Net.virt`) 를 씀 — 느린 기계에서도 같은 시뮬 시간 (`--fixed-fps` 와 함께). `Ext.last_st` = 마지막 몸 상태 (QA 가 읽음).
- 고침 (전후 수치는 docs/w44): 천 서브스텝·뼈 회전 속도 제한 (`ext_cloth.gd`, 천 팝 61~166 → 0), 천 몸 충돌 (`cloth_colliders` — 반지름은 QA 가 스킨 메시에서 잰 값, 천 뚫림 → 0), 같은 공격 클립 재시작 크로스페이드 (`_clip_layer`, 닌자 표창 137° 튐), 걷기↔달리기 히스테리시스 (`EXT_RUN_HYS`). 끄기 스위치 `--no-cloth-sub|rate|col` · `--no-run-hys` · `--no-clip-restart` (+ `--no-w43` 는 이제 `--` 뒤 인자도 먹음).
- 보류: 공격 strike·wind 의 빠른 타격 (moves 시간 설계값), 달리기 다리 (W34 박자 배율), 발 미끄러짐 (판정 한계), 탱크 허리 웨이트, 래그돌 복귀·닌자 대시 크로스페이드 분해.

## 23. W45 — PC 최적화 7차: 입장 첫 프레임 쪼개기·몸 압박·메모리 (2026-11-13, 표·전후는 `docs/w45/README.md`)

- **외부 몸 붙이기 네 조각** (`External.attach_job` → `AttachJob.step`, `Ext.setup_a/b/c/d`): ① 장면 인스턴스·크기·쉬는 자세 맞춤 ② 재질·텍스처·LOD 표면·그림자 쌍둥이 ③ 안쪽 몸 숨기기·허리 띠·소품 ④ 클립 재생기·천·모션 층 연결·처음 자세. `Body.split_ext` 가 켜진 동안 (world/bodies.gd `_make` 만) 만든 판 몸은 바로 안 붙이고 `body.ext_job`, `bodies.update` 가 프레임마다 `ext_step()` (한 프레임 `BODY_JOBS_PER_FRAME` 몸까지). **다 붙기 전엔 몸을 안 보이고 (`body.visible = false`) pose 도 안 부름** — ① 의 쉬는 자세 맞춤이 관절의 처음 자세를 읽기 때문 (T 포즈·코드 몸이 안 보이게). 알베도·마스크 스레드 읽기가 안 끝났으면 ① 앞에서 기다림 (`game_tex_ready`, 최대 45프레임) — 동기로 읽으면 5~7ms. 끄기 `--no-body-split`. 1인칭 쌍둥이·초상·큰 캐릭터·몸 데우기는 옛 길 (`External.attach`, 한 번에).
- **모션 층 (`ext_motion/ext_clips/ext_cloth`) 은 안 건드림.** 단 이 때문에 알아 둘 점: 새 모델 몸의 클립 층·천은 **실제 시계** (`Motion_.now_s`) 로 도니 `pose` 를 부르는 시각 간격이 모습에 영향. 초상·큰 캐릭터의 자세 굳히기 (`Portrait.prime_idle` 50번) 를 여러 프레임에 나눠 불렀더니 탱크 방패가 얼굴을 가림 (캡처 전후 91% 화소 차) → 50번은 한 조각 (`PRIME_CHUNK == PRIME_STEPS`), 몸은 굳히는 프레임에 나무에 넣음 (먼저 넣으면 `Ext._process` 가 한 프레임 먼저 돌아 천이 프레임 시간만큼 한 번에 움직임).
- 확인용: `--sched-log` 끝에 `[몸 단계]` (단계별 횟수·합·최대 ms)·`[gate 표]` (입장문 일마다 돌린 수·평균·최소·최대), `--hitch` 태그 `입장 첫 바퀴 끝`·`몸 다 보임 N명`, `--mem-log` (영상 메모리 2초마다).


## 24. W46 — 모션 개선 4차: 탱크 허리 늘어남·걸음 박자 재조정·발 미끄러짐 새 판정 (2026-11-13, 표·그림 `docs/w46/README.md`)

- **탱크 허리 장갑·벨트 삼각형 늘어남 ×18.2 → ×3.5** (`tools/blender/tripo/waist_reweight.mjs`): 골반 둘레 가중치 라플라스 평활 + 겨드랑이 높이까지 번진 허벅지 가중치를 가슴으로. stage + 판 LOD 3단계 모두, 뼈 71·UV·텍스처 그대로 (Blender·relod 다시 안 돌림). 원인 찾기용 `QA_STRETCH_DBG=1` (motion_qa).
- **걸음 새 QA** `core/gait_qa.gd` (측정) · `tools/gait_qa.gd` (표·`--sweep`·`--cloth`): 접지 = 두 발 중 낮은 쪽이 두 발 최저 + 2cm 안인 구간, 비 = 접지 동안 발 월드 속도 중앙값 ÷ 몸 속도. 옛 판정 (낮은 발목 + 이동 거리, `test_w34`) 은 스치는 발을 디딤으로 오판해 박자 ×1.6·보폭 IK ×1.4 를 고르게 했음 (실제 비 1.4~3.7).
- **`clips.stride`** `[k, c, 박자]` = `[1.0 (IK 끔), c, 0.5~1.3]` (캐릭터·걷기·달리기별, 표 `docs/w46`). 달리기 다리 팝 20~60 → 0, 앞·뒤 비 0.08~0.21 (닌자 걷기 0.59). 한 바퀴 몸 이동 거리가 속도와 무관해서 '속도 비례 연속 박자' 는 필요 없음.
- **옆걸음** `EXT_DIR_GAIN` 1.0 · `EXT_DIR_MAX_DEG` 70 · 윗몸 되돌림 `EXT_DIR_COUNTER` (척추 셋 0.5/0.3/0.2). 옆 달리기 비 0.73~0.9 → 0.3~0.4.
- 천 끝 떨림은 걸음이 앵커를 흔든 것이라 같이 사라짐 (갈고리 직선 달리기 3.48° → 0.64°).
- **보류**: 슬러프 180° 팝 (고정 부호 호는 닌자 대시 129° → 74° 지만 사냥꾼 팝 94 → 122 로 되돌림), 탱크 허리 앞 천·어깨 장갑 2차 모션 (판 LOD 에 지오메트리 없음 — 텍스처), 닌자 걷기 클립 (비 0.6 아래 불가).
- 테스트 `tests/test_w46.gd` (4), `test_motion_qa.gd` 팝 상한 4~8. 합 400.


## 25. W47 — 영벡터 가드·걸음 되돌리기 `--old-gait` (2026-11-13)

- **영벡터 가드**: 천 점이 겹치면 `Vector3.normalized()` 뒤 `Quaternion(a, b)` 가 "The vectors must not be zero" 를 프레임마다 찍던 것 (로그 출력이 CPU 비용). `Motion_.safe_dir(v, 대체)` (길이² ≤ 1e-8 이면 대체 방향, 아니면 `normalized()` 와 같은 값)·`Motion_.rot_between(a, b)` (영벡터면 항등) 를 `ext_cloth.gd` (점→뼈 회전·쉬는 방향·앞쪽 한계) 와 `external.gd` (정렬 회전·스윙 축·다리 IK 보폭·극점) 에 씀. 정상 프레임 값은 그대로.
- **`-- --old-gait`** (웹 `?old-gait=1`): W46 이전 걸음 (stride 박자 1.6 · 보폭 k 1.4~1.45 · 골반 yaw 이득 0.6·한계 45°·윗몸 되돌림 waist 한 뼈) 로 되돌려 눈으로 비교. 표 `chars_config.gd EXT_GAIT_OLD`, 읽는 쪽 `K.stride_of`·`K.dir_gain/dir_max_deg/dir_counter` (`Opts.args()`, 호출 때마다 읽음 — 캐시 없음). `read_cfg` 가 `clips.char` 를 심어 캐릭터별 표를 찾음. 표 밖 캐릭터는 JSON 값 그대로.
- `_add_rot` (맞음 움찔 등 가산 회전) 은 부모 전역 basis 가 영 스케일·NaN·inf 면 `Motion_.basis_ok` 로 건너뜀 (재연 20초에 경고 20건 → 0). 테스트 `tests/test_w47.gd` (4).


## 26. W49 — 모션 설정 창 (런타임 A/B)·가산 층 플래그·NaN 근원 (2026-11-14, 표·캡처 `docs/w49/README.md`)

- **가산 층 플래그 한 표** `chars_config.gd` `EXT_MOTION_FLAGS` (이름 → 기본값, 전부 켬 = 지금 모습): `gait_new` (걸음 박자·보폭·옆걸음 새값, 끄면 옛값 = `--old-gait`) · `dir` (방향 이동 블렌드) · `lean` (이동 기울임·방향 전환) · `getup` · `weapon` · `cloth` · `gaze` · `land_breath` · `hit_dir` (맞음 방향별 움찔, 끄면 W38 처럼 뒤로 젖힘만) · `vm_arm` (1인칭 팔 클립 구동). 프리셋 `EXT_MOTION_PRESETS` = 이 값 묶음: `new` (전부 켬), `old` (= v0.1.17 이전: `gait_new`·W43 넷 (`dir`·`lean`·`getup`·`weapon`)·`vm_arm` 끔, W40 가산·천·W44 천 수정은 유지), `min` (전부 끔 = 클립 + 코드 자세만). 읽는 길은 하나: `K.flag(이름)` (= `Motion_.flag`) — 설정 (`View.settings.motionFlags` → `K.set_flags`) ∧ 실행 인자가 끈 것이 아님 (`K.refresh()` 가 `Opts.args()` 에서 읽음: `--motion old|min`, `--no-w43` (W43 넷), `--old-gait`, `--no-<플래그 이름, 밑줄은 ->`; 웹 `?motion=old`·`?old-gait=1`·`?no-gaze=1` 도 같은 길). 인자가 우선 (끄는 쪽 합집합).
- **끄면 비용 0**: 층마다 꺼진 걸 알면 계산을 건너뜀 (`_move_layer`·`_getup_layer`·`_weapon_layer`·시선·숨쉬기·착지·천 `cl.step`·`arm_delta`). 이미 들어가 있던 값은 `follow` 로 서서히 0 까지 (판 중 토글에 뼈가 튀지 않게), 다 풀린 뒤에만 건너뜀. 천은 `Cloth.rest_step` 으로 쉬는 자세로 돌아가 멈추고 (다시 켜면 처음부터). 걸음 모드가 바뀌면 걷기·달리기 클립을 짧게 크로스페이드하고 보폭 k·c 를 앞·뒤 모드 값으로 섞음 (`gait_blend`) — 안 하면 박자 배율 (0.5 ↔ 1.6) 이 바뀌며 클립 시각이 확 달라져 뼈가 한 프레임 50° 튐. `Ext.move_off` (몸 하나만 W43 끔) 는 확인 도구·테스트용으로 남음 (`_fl`).
- **설정 창** `ui/settings.gd`: 세 탭 [일반 | 모션 | 조작 키] (한 줄 더하면 960×540 에서 넘쳐서 — 실제 글꼴로는 W49 전에도 35px 넘쳤음). 모션 탭 = 프리셋 셋 + 지금 프리셋 이름·'어색하면 옛 모션으로 비교' 도움말 + 개별 토글 10개 (2열) + 인자로 꺼진 것 안내 (주황). 판 중 단축키 `motionToggle` (기본 F6, `Keys.GODOT_ONLY` — JS 에 없는 행동이라 기본 키 대조 테스트가 뺌) = 새 모션이면 옛 모션으로, 그 밖이면 새 모션으로 + 알림 (`ui.gd motion_toggle`, 설정 창이 떠 있어도 됨). 기본값 버튼은 새 모션으로.
- **NaN 근원** (도구 `tools/nan_hunt.gd` `--nan-hunt <폴더>` = 재연·판 중 둘 다, `Motion_.probe` 훅으로 Ext.sync 단계마다 뼈를 훑어 몸마다 '처음 깨진 프레임·뼈·직전 멀쩡했던 단계' 를 `nan_hunt.json` 에 / `tools/nan_fuzz.gd` = 입력을 깨 보는 퍼저): 재연 (new8·lava8·game8)·판 중 8명 (스캔 ~130만 번) 에서는 **깨진 뼈 0, `_add_rot` 거절 0** 이라 W47 때 경고가 어떤 입력에서 났는지는 못 다시 만들었다. 퍼저가 보인 **입구**: 가산 층이 깨진 입력으로 회전을 셈하면 `_add_rot` 가 그 NaN 을 척추 뼈 회전에 써 넣고, 그 자식 뼈의 `_add_rot` 은 '부모 전역 basis 가 NaN' 이라 경고 (W47 은 이 경고만 막아 NaN 자체는 남았음 — 그 뼈는 `_reset_extra` 가 다음 프레임에 되돌려 줘서 눈에는 안 보였을 뿐). 입력: `hit.age` 가 **−10.6초보다 오래** (`exp(−age/0.015)` 가 INF → (1−INF)·INF = NaN — 시계 바탕이 바뀌면 (재연 가상 시계·반복 재생) 맞은 시각이 옛 시계 값이라 음수가 됨, `_hit_for` 는 age > 2초만 버려서 음수는 통과) · `hit.dx/dy/pow`·`st.t` 의 NaN·inf · 몸 월드 크기 0 (천 `step`·무기 월드 가속도의 `affine_inverse`·`orthonormalized` 경고). 고침 (입구에서): `_hit_flinch` 는 age 가 유한하지 않거나 −0.05초 아래면 움찔 없음, `Motion_.hit_react` 가 깨진 값을 0 으로 (`Motion_.fin`), `_add_rot` 는 더할 회전이 단위 사원수가 아니면 (`Motion_.quat_ok`) 쓰지 않고 이미 깨진 뼈는 쉬는 회전에서 다시 시작, 숨쉬기 `t` 는 `fin`, `_extra_layer`·`Cloth.step` 은 몸 월드 변환·부모 basis 가 `basis_ok` 가 아니면 그 프레임 건너뜀. W47 가드는 남김. 테스트 `tests/test_w49.gd` (깨진 입력 20여 종 × 4명 → 뼈 멀쩡·거절 0, 맞은 지 음수 움찔 없음, 영 월드 크기).
- 확인 도구: `tools/settings_shot.gd` (설정 창 캡처 + 화면 안인지), `tools/motion_combos.mjs` (재연을 프리셋·플래그 조합마다 돌려 튐 수·SCRIPT ERROR·rc 표), `core/motion_qa.gd --motion-script "4:old,8:new"` (재연 중 프리셋 전환 + 직후 1초 튐 수), `tools/ext_cost.gd` 의 '옛 모션 프리셋'·'최소 프리셋' 줄, `tools/pose_sheet.gd --preset new|old|min`.


## 27. W52 — 모션 개선 5차: 크로스페이드·래그돌 복귀 튐 (2026-11-14, 표·원인 `docs/w52/README.md`)

- 플래그 `pop_fix` (설정 모션 탭·`--no-pop-fix`, 옛·최소 프리셋은 끔): ① 클립 크로스페이드가 호를 안 뒤집음 (`Motion_.slerp_cont`) + 이음 자세 차이 (도) ÷ `EXT_FADE_ADAPT_DPS` 로 페이드 길이 늘림 (`fade_len_for`, 상한 `EXT_FADE_ADAPT_MAX_S`) — 닌자 대시 팔 129° → 53° ② 낙하가 끝난 뒤 래그돌 모터 완화 (`ragdoll_math` `sinceFall`, `RAGDOLL_FALL_RECOVER_S`) ③ 래그돌 쉬기 전 목표 15° 안 기다림·쉴 때 블렌드 (`RAGDOLL_SLEEP_*`) ④ 물리가 멀면 snap 오르는 속도 제한 (`RAGDOLL_SNAP_*`). 재연 4명 팝 223 → 180, 90° 넘는 팝 17 → 0.
- 남은 strike 팝은 서버 `moves` 설계값. 탱크 천·장갑 2차 모션은 타당성만 (docs/w52 4절). 테스트 `tests/test_w52.gd` (8).
