# G2 고도에만 필요한 수치 (PLAN 7절: 묶음 폴더의 <묶음>_config.gd). JS 수치는 core/config.gd
extends RefCounted

# 몸 조각 합치기 (JS client/batch.js 와 같은 뜻): 움직이는 노드마다 그 아래 같이 움직이는 조각을 재질 종류마다 메시 하나로 (색은 정점 색).
# false 면 조각마다 MeshInstance3D (확인용 — 그리기 수가 몸 하나에 약 100+)
# (2026-10-31 Skeleton3D 한 메시 판은 1인칭에서 몸이 화면을 덮고 하얀 조각이 보이고, 숨긴 조각도 삼각형을 그려서 바꿈)
const MERGE := true
# 합칠 때 툰 조각 전부를 G3.batch_mesh (뼈 = 조각, 숨김 = 뼈 크기 거의 0) 로 몸 한 메시 — 몸 하나 = 툰 1 + 외곽선 1 + 눈 basic·체크 무늬 조각
# false 면 움직이는 노드마다 재질 종류별 메시 (그리기 3인칭 8명 ~510). (c965e42 의 내 뼈 판은 대기실·초상에서 몸이 찌그러져 버림)
const SKIN := true
# 래그돌 (chars/ragdoll.gd, JS client/ragdoll.js): false 면 끔 (figureAnim 자세 그대로)
const RAGDOLL := true
const RAGDOLL_TIME_MIN := 0.05 # 래그돌 물리 시간 배율 하한 (히트스톱 0 이어도 나눗셈이 안 터지게)
const RAGDOLL_SLEEP_MS := 350.0 # 모터가 다 센 채로 이만큼 지나면 래그돌 강체를 쉼 (물리 비용 없음, 자세는 figureAnim 그대로). 맞음·경직·낙사면 바로 깸
const RAGDOLL_WAKE_BELOW := 0.95 # 모터가 이보다 약할 때만 깨어 있음 (맞음·경직 회복 끝 무렵 0.95~1 은 물리가 목표와 거의 같아 쉼)
# 1인칭 팔 SubViewport 다중 샘플 = 판 화면과 같음 (JS viewmodel 은 판과 같은 캔버스 = antialias) → world/world_config.gd msaa_3d (웹·PC·그래픽 낮춤)
# W7 구운 몸 (assets/models/<캐릭터>.glb, 레포 뿌리 tools/bake-bodies.mjs): 있으면 그 파일로 몸을 만듦 (조립·묶기 없음). false 면 늘 예전 조립 (chars/data/bodies.bin)
const GLB := true
# W14 외부 뼈대 모델 (assets/models/ext/<캐릭터>.glb, chars/external.gd, 안내 chars/EXTERNAL.md): 있으면 그 모델 (→ 없으면 구운 몸 → 코드 조립).
# 지금 들어 있는 건 시험용 로봇 하나 (탱크 자리) 라 기본은 끔 — 실행 인자 --ext 로 켬 (테스트는 Body.use_ext)
const EXT := false
# 조정 값 기본 (모델마다 assets/models/ext/<캐릭터>.json 이 덮음): bones 뼈 이름 덮어쓰기 {우리 관절: 모델 뼈} · yaw 앞 방향 (도, glTF 앞 +Z → 게임 앞 = 90) ·
# height 키 배율 (PLAYER_HEIGHT × FIGURE_SCALE 기준) · offset 몸 기준 옮김 [x, y, z] (고도 좌표, m) · tint 몸 색 "keep" 텍스처 그대로 / "band" + 허리 플레이어 색 띠 / "tint" 곱함 (tint_k) ·
# band 띠 [반지름, 두께, 뼈 따라 올림] (모델 키 비율) · band_joint 띠를 붙일 관절 · keep 안쪽 몸에서 남길 소품 (refs 키, 예 "shields") · attach 따로 받은 물건 [{glb, joint, pos, rot, scale}] ·
# vm_from 1인칭 팔에 남길 부분 ("elbow" 팔꿈치 아래 = 예전 1인칭과 같음, "shoulder") · vm_snap 1인칭에서 우리 관절 자리에 붙일 관절 (팔꿈치 → 손이 예전 1인칭 자리) · clips 동작 이름 → 모델 클립 이름 (play_clip 예)
const EXT_DEFAULTS := {"bones": {}, "yaw": 90.0, "height": 1.0, "offset": [0, 0, 0], "tint": "band", "tint_k": 0.6, "band": [0.17, 0.035, 0.0], "band_joint": "waist",
	"keep": [], "attach": [], "vm_from": "elbow", "vm_snap": ["elbow"], "clips": {}}
const EXT_FLASH := 0.55 # 경직 하얀 깜빡임 (외부 모델은 피부 부위를 몰라서 몸 전체 하얀 발광으로)
