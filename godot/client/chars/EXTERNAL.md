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
