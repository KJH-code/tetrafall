# 몸 굽기 (.glb) — W7 시제품 + 계획 (2026-11-02)

재혁 결정: 고도 몸을 코드로 조립하지 말고 파일로 불러오기. 방법 = JS 몸 (three.js `client/figure.js` buildFigure) 을 그대로 .glb 로 구움 → JS 와 같은 모양, 판 시작마다 조립·묶기 없음.
이번엔 **탱크 1명** 시제품. 나머지 7명 + 허수아비는 아래 '남은 일'.

## 1. 무엇이 어디에

| 파일 | 하는 일 |
| --- | --- |
| `tools/bake-bodies.mjs` (레포 뿌리) | `node tools/bake-bodies.mjs [id …]` (기본 tank) → `godot/client/assets/models/<id>.glb` + `<id>.json`. node 에서 buildFigure 를 돌려 glTF 2.0 바이너리를 직접 씀 (GLTFExporter 는 DOM·FileReader 가 필요해서 안 씀). 뽑기는 `godot/client/tools/gen-bodies.mjs` (bodies.bin) 와 같은 규칙 |
| `assets/models/<id>.glb.import` | 고도 import 설정 (커밋함): LOD·그림자 메시·접선·라이트맵·애니·이름 접미사 끔. 새 캐릭터는 tank 것을 복사하고 uid 줄을 지운 뒤 `--import` |
| `chars/baked.gd` | `load_char(id)` → `{manifest, scene}` 또는 null (파일 없음). 한 번 읽어 둠 |
| `chars/baked_batch.gd` | .glb 의 SkinnedMesh 를 몸 노드에 잇기 (G3 `shaders/batch.gd` 와 같은 값·함수 이름 → `body._sync_bones` 그대로) |
| `chars/body.gd` | `build` 가 구운 몸이 있으면 `_build_glb` (장면의 `frame` 을 떼어 붙이고 manifest 순서대로 이름으로 노드를 찾음), 없거나 이름이 안 맞으면 예전 `_build_pieces` (bodies.bin). 그 뒤는 같은 길 (`_after_build`) |
| `chars_config.gd` `GLB` | 끄면 늘 예전 조립. 실행 인자 `--no-glb` 도 (스샷 비교) |
| `tests/test_baked.gd` | 아래 4절 |

### .glb 안

```
<id> (장면 뿌리)
└ frame                       게임 좌표 (앞 +x, 왼쪽 +y, 위 +z) → glTF/고도 Y 위 (x 축 −90°, body.gd 예전 frame 과 같음)
  ├ body ─ rig ─ parts ─ … ─ hips ─ waist ─ … shoulder_R ─ elbow_R ─ hand_R …   관절 나무 (자리·회전·크기 = JS 노드 그대로)
  │        └ <주인>__m<재질>[_ns]       나머지 조각을 주인 노드 아래 재질·그림자마다 하나로 합친 잎 (1인칭 팔용 조각 몸)
  └ Skeleton3D (import 가 B_<노드 번호> 뼈 나무를 바꾼 것) ─ batch   툰 조각 전부 = 정점 색 SkinnedMesh 하나 (판 몸)
```

- **남기는 노드** = refs 가 가리키는 노드 (관절·천 자락·방패·총·뿔·폼 부위·눈동자…) + 처음 숨긴 노드 + 닌자 단검 + 맨 위 + 그 조상. 코드가 자세·보이기·재질을 바꾸는 노드는 다 남음. 나머지 (안 움직이는 조각·묶음 노드) 는 주인 아래로 합침
- **이름** = body.gd 관절 이름: `hips·waist·neck·torso·shoulder_R/L·elbow_R/L·hand_R/L·thigh_R/L·knee_R/L·foot_R/L` ([0] 오른쪽·[1] 왼쪽, ragdoll.gd `upperR = shoulders[0]`), 나머지 refs 는 경로 (`flaps_0_obj`·`shields_front`·`formParts_metal_3`), 안 가리키는 노드는 `n<JS 번호>`. 고도 import 는 이름을 장면 전체에서 겹치지 않게 바꾸므로 굽기 도구가 미리 겹치지 않게 함
- **묶음 (판 몸)**: 불투명 툰·그림 없음·발광 없음·외곽선·한 면 재질만 (JS batch.js 처럼 양면·외곽선 없음은 따로). 근육 홈 (`shade` = 피부 × 어둡게, 사람마다 색)·바드 몸통 (폼마다 재질 통째로)·광전사 눈 흰자 (분노 색) 도 따로. 뼈 = 조각 주인 노드 (탱크 27개, 예전 묶음은 조각마다 90개)
- **정점 색**: 재질 sRGB 값 (G3 batch 와 같음). 고도 import 가 glTF COLOR_0 를 '선형' 으로 보고 sRGB→선형으로 바꿔 넣어서 굽기 때 반대로 바꿔 씀 (16비트). 그래서 블렌더 등에선 색이 밝게 보임. 피부 정점은 흰색 + UV2.x = 1 → 툰 `skin_tint` (a = 1, 몸 색) 가 칠함 → **묶음 메시는 같은 캐릭터 몸끼리 같이 씀** (사람마다 색을 굽지 않음)
- **manifest** (`<id>.json`): `nodes` [{name, parent, hidden, noShadow, dagger, mat, batch}] (부모 번호 < 자식 번호, 묶음 잎은 맨 끝 = `batchStart` 부터) · `mats` (gen-bodies 재질 표 그대로 → `body._material` 이 G3 툰·basic 으로) · `refs` (새 번호) · `bones` · `stats` · `source` (JS 원본 해시)

### 고도에서 두 모양

- 판·대기실·초상 몸 (`merge` + `K.SKIN`): 묶음 잎 (manifest 끝) 은 버림, 묶음에 들어간 남긴 메시 노드는 layers 0 (자리만 — G3 batch 와 같음), `BakedBatch` 가 뼈 ↔ 노드 (`B_<번호>`). 예전 batch 처럼 `sync()` 한 번 + 매 프레임 움직이는 뼈만 `_sync_bones`
- 1인칭 팔 쌍둥이 (`merge = false`): 잎 그대로, Skeleton3D 는 버림. viewmodel 은 `twin.cd` 를 읽고, 베낄 노드는 판 몸 노드 표 안 (묶음 잎은 안 움직임)
- 래그돌 (관절 노드)·초상·대기실 큰 캐릭터·잔상 복제 (`snapshot` 이 frame 을 복제 — 뼈·묶음도 같이)·한 겹 더 (`set_overlay`)·반투명 (투명 재질에도 skin_tint)·몸 색 효과 (`_fx_colors` 는 구운 몸이면 skin_tint a 늘 1) 는 같은 길

## 2. 숫자 (탱크, 헤드리스 고도 4.7.2, 몸 하나)

| | 예전 조립 (bodies.bin + G3 batch) | 구운 몸 (.glb) |
| --- | --- | --- |
| 조립 ms (판 몸, 데운 뒤 중앙값 20번) | 13.9 | **0.67** |
| 조립 ms (처음 한 번 — 파일 읽기 포함) | 33.6 (bodies.bin 9명 풀기 포함) | 6.3 (PackedScene 읽기 포함) |
| 조립 ms (1인칭 쌍둥이, 조각 몸) | 1.17 | 0.57 |
| 노드 수 (판 몸) | 125 | **38** |
| 노드 수 (조각 몸) | 122 | 90 |
| 그리는 메시 = 그리기 호출 (같은 장면·같은 자세, 몸 하나) | 6 | **4** |
| 삼각형 (같은 장면) | 8984 | 8984 |
| 묶음 뼈 / 매 프레임 맞추는 뼈 | 90 / 90 | 27 / 22 |
| 매 프레임 뼈 맞추기 (`_sync_bones`) | 108 µs | **8.7 µs** |
| 묶음 정점 (색인) | 14304 (비색인) | 6251 |

파일 크기: `tank.glb` 684 KB (원본, 내보내기엔 안 들어감) · import 된 `.scn` **150 KB** (pck 에 들어가는 것) · `tank.json` 7.6 KB. 비교: `bodies.bin` 275 KB (9명 다).

같은 자세·카메라 픽셀 비교 (640×640, 툰 + 외곽선): 예전 / 구운 몸 차이 > 8 인 픽셀 13개 (테두리 반올림 — import 정점 압축 16비트). 정점 자리·색은 테스트가 8명 다 같음을 확인 (4절).

### 8명 미리 재 봄 (임시로 다 구워서, 커밋 안 함)

| 캐릭터 | 조립 ms 예전 → glb | 노드 | 그리는 메시 | 묶음 뼈 | .glb |
| --- | --- | --- | --- | --- | --- |
| tank | 14.63 → 0.74 | 125 → 38 | 6 → 4 | 90 → 27 | 668 KB |
| ninja | 12.24 → 0.68 | 108 → 43 | 6 → 4 | 72 → 32 | 605 KB |
| builder | 10.66 → 0.67 | 106 → 36 | 11 → 8 | 71 → 21 | 655 KB |
| hook | 13.54 → 0.73 | 124 → 46 | 6 → **12** | 87 → 27 | 650 KB |
| hunter | 13.43 → 0.77 | 120 → 39 | 6 → 4 | 85 → 28 | 756 KB |
| cannon | 15.60 → 0.69 | 117 → 40 | 6 → 4 | 85 → 29 | 924 KB |
| berserker | 12.54 → 1.24 | 175 → 67 | 10 → 8 | 118 → 48 | 657 KB |
| bard | 21.82 → 1.27 | 225 → 76 | 7 → **14** | 162 → 53 | 953 KB |

8명 합: .glb 6.0 MB (원본), import .scn 1.19 MB (pck). 8명 판 시작 조립 약 115ms → 7ms.
갈고리·바드 그리기 수가 늘어난 건 양면 툰 조각 (갈고리 망토 자락, 바드 메탈 폼 부위) 을 JS 처럼 따로 그려서 — 예전 고도 묶음은 이것도 한 면으로 묶어 뒷면이 안 보였음 (JS 와 다름). 아래 남은 일 1.

## 3. 스크린샷 (확인용, 레포 밖)

`/tmp/claude-0/-home-user/8deab670-0f99-5600-9c8d-a97e79b14e53/scratchpad/out-W7/`: `compare-tank.png` (대기실 큰 캐릭터·판 3인칭: JS / 고도 예전 / 고도 .glb), `still-compare.png` (같은 자세 예전 / .glb / 차이 ×8), `js-*.png`·`gd-*-{old,glb}.png` 원본, `gd-game-first-glb.png` (1인칭).
대기실 큰 캐릭터가 JS 보다 어둡고 푸르게 보이는 건 고도 예전·.glb 둘 다 같음 → 굽기와 상관없는 `ui/char_stage` 빛 차이 (G4 쪽 일).

## 4. 테스트 (`tests/test_baked.gd`, 구운 캐릭터마다)

- manifest·장면: 이름 겹침 없음, 관절 이름, 부모 번호 < 자식, 묶음 잎은 맨 끝, frame 돌림, 장면에서 이름으로 다 찾음·메시 여부, 뼈 이름 `B_<노드>`
- **예전 조립과 같음**: 판 몸 (묶음 정점 = 뼈 자세 × bind × 정점) 과 조각 몸 모두, 보이는 정점 자리 (2e-3 안)·색 (sRGB, 피부 = 몸 색) 이 양쪽에 다 짝이 있음 — 처음·초상 길·도발·관절 비튼 자세·rig 숨김
- 가벼움: 노드 절반 아래, 그리는 메시 ≤ 예전, 뼈 절반 아래, 묶음 메시 공유, 몸마다 재질·외곽선, skin_tint, 효과 뒤·반투명·복제
- 1인칭: 쌍둥이 = 구운 조각 몸, 베낄 노드 ⊂ 판 몸 노드 표, 팔 자세·그리는 정점 = 예전 1인칭
- 예전 조립으로 떨어지기: `use_glb` 끔, manifest 이름이 장면과 안 맞음
- `test_chars` 몸 테스트 6개를 예전 조립 (`use_glb` 끔) 으로 한 번 더 (= .glb 없을 때)

## 5. 남은 일 (8명 전부로 넓힐 때)

| # | 일 | 크기 |
| --- | --- | --- |
| 1 | **양면·외곽선 없는 툰을 묶음 둘째 표면으로**: 같은 SkinnedMesh 에 표면 하나 더 (양면 툰, 외곽선 없음/있음) → 갈고리 12 → 5, 바드 14 → 6 쯤. 굽기 도구 primitive 두 개 + baked_batch 표면별 재질 + `_fx_colors`·`_apply_opacity` 가 묶음 재질 둘을 다룸 | 0.5 |
| 2 | 7명 굽기 + `.glb.import` 복사 (uid 줄 지움) + 고도 `--import`, 테스트 `test_baked_lighter` 그리기 조건을 1 뒤에 다시 | 0.3 |
| 3 | 캐릭터별 특수 부품 화면 확인 (스샷 JS / 예전 / glb): 바드 폼 바꾸기 (formParts 보이기·몸통 재질 `torsoMat` 바꾸기·폼 튀기기 `formParts[0].position`) · 광전사 뿔 (매 프레임 굽힘 → 뼈) · 분노 (눈 흰자 재질은 묶음 밖이라 이제 색을 바꿀 수 있음 — 아직 안 만든 효과) · 근육 홈 (shade, 따로 그림) · 대포수 포탄 (`balls` 보이기, 1인칭이 메시를 베낌) · 갈고리 총·장전·불꽃 · 닌자 단검 (1인칭이 숨김 — 지금은 단검이 메시 노드라 됨, 묶음 노드면 자식까지 숨겨야 함) · 사냥꾼 활·코 · 건축가 망치·체크 무늬 (따로 그림) · 손에 든 아이템 (`held`) · 기다림 표시 (`waitMark`) | 1 |
| 4 | 허수아비 (`character.js buildDummy`, figure 없음) 굽기: 도구에 `buildCharacter(…, 'dummy')` 길 | 0.3 |
| 5 | 크기 줄이기: 지금 .glb 에 조각 (1인칭용) 과 묶음이 둘 다 → 8명 pck +1.19 MB (bodies.bin 0.27 MB). 1인칭 쌍둥이를 묶음에서 뼈 숨기기로 만들거나 조각을 따로 .glb 로 (내 캐릭터만 읽음), 묶음 UV0 (0 만) 빼기 | 0.5~1 |
| 6 | 다 구운 뒤 예전 길 정리: bodies.bin·gen-bodies.mjs·`_build_pieces`·`_merge`·G3 batch 몸 묶기를 뺄지 (대체 경로로 남길지) 재혁과 정함. JS 원본 해시 (`manifest.source`) 를 테스트가 다시 계산해 '다시 구우세요' 를 알림 | 0.3 |
| 7 | (원하면) 블렌더에서 손질: 지금 manifest 는 JS 에서 나옴 → .glb 를 손으로 고치면 이름·노드 순서·`B_` 뼈·재질 이름 `m<번호>` 를 지켜야 함. 손질을 허락하려면 manifest 를 .glb (노드·재질 이름) 에서 다시 읽는 검사기 + 손질본을 덮어쓰지 않는 굽기 | 1+ |

합계 약 3~4 세션·일 (1~4 = 2~2.5, 5·6 = 1, 7 은 따로).

## 6. 위험

| 위험 | 대응 |
| --- | --- |
| 고도 glTF import 가 몰래 바꾸는 것 (COLOR_0 sRGB→선형, 이름 겹침 바꾸기, 정점 합침·16비트 압축, 뼈 순서) | 굽기 도구가 맞춰 씀 + `test_baked` 가 예전 조립 (= JS 자료) 과 정점·색을 비교해서 잡음. 고도 판을 올리면 이 테스트부터 |
| JS 몸이 바뀌었는데 .glb 를 안 다시 구움 (bodies.bin 과 둘이 어긋남) | JS 는 얼림. 바꾸면 `gen-bodies.mjs` + `bake-bodies.mjs` 둘 다 — test_baked 비교가 어긋남을 잡음 (bodies.bin 기준) |
| 뼈 자리에 비뚤림 (부모 크기 × 자식 돌림 — 뼈는 자리·돌림·크기만) | 굽기 도구가 경고 (8명 다 지금 없음). 생기면 그 노드를 묶음 밖으로 |
| pck 크기 (웹 첫 받기) | 5번. 지금 탱크만 +150 KB |
| manifest 와 .glb 가 어긋남 (한쪽만 다시 굽기·손질) | `_build_glb` 가 이름을 못 찾으면 경고 후 예전 조립 (테스트), 메시 여부도 봄 |
| 묶음 메시를 몸끼리 같이 씀 → 누가 메시를 고치면 다 바뀜 | 몸 코드는 메시를 안 고침 (재질만 몸마다). 고칠 일이 생기면 `duplicate()` |
