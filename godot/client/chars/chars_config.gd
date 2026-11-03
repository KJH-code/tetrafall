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

# W11 탱크 1인칭 방패를 왼손에 쥠 (재혁 2026-11-03: 3·4타 때 1인칭에서 방패가 손에 없이 몸에 고정됨 — JS viewmodel 은 허리에 붙은 채, 고도만 고침).
# 방패 자리·방향을 정하고 왼손을 방패 안쪽 손잡이로 IK (viewmodel.gd _hold_shield). false 면 예전 (허리에 붙음, JS 와 같음)
const VM_SHIELD_HAND := true
const VM_SHIELD_GRIP := [0.16, 0.0, 0.0] # 손잡이 점 (방패 좌표, 크기 VM_SHIELD[0] 곱하기 전): 바깥면 (돌기) 이 -x 라 안쪽 +x — 판 반 두께 + 주먹 반지름
# 방패 가운데 (허리 좌표: 앞 +x, 왼쪽 +y, 위 +z, 어깨 높이 z 0.604) · 바깥면 방향 [돌림 (앞에서 왼쪽 +), 들림 (위로 +)]
const VM_SHIELD_GUARD := [0.4, 0.28, 0.57, 0.6, -0.25] # 쥐고 든 자세 (화면 왼쪽 아래 비스듬히 — 예전 자리, 안쪽 면이 카메라 쪽)
const VM_SHIELD_LOW := [0.14, 0.36, 0.17, 0.6, -0.6] # 꺼내기 전·넣은 뒤 (팔을 내린 화면 밖 아래)
const VM_SHIELD_IN_S := 0.18 # 방패 동작이 시작되면 이만큼 동안 손을 내려 방패를 쥐고 들어 올림 (앞 VM_SHIELD_REACH 몫은 빈손으로 내려감)
const VM_SHIELD_OUT_S := 0.2 # 방패 동작이 끝나면 이만큼 동안 방패를 내려 넣고 손이 원래 자리로
const VM_SHIELD_REACH := 0.4
const VM_SHIELD_ARM_SLACK := 0.005 # 팔 길이 (윗팔 + 아래팔) 보다 이만큼 안쪽까지만 (IK 가 늘 닿게)
# 동작별 밀치기 (준비 = W 로 당김, 타격 = W → S 로 밀침, 회복 = S → 0 으로 복귀): [앞, 왼쪽, 위, 돌림, 들림] 을 쥔 자세에 더함
const VM_SHIELD_PUSH := {
	"방패 올려치기": {"W": [-0.08, 0.02, -0.06, 0.0, -0.2], "S": [0.07, 0.0, 0.08, -0.1, 0.5]},
	"방패 내려치기": {"W": [-0.05, 0.0, 0.08, 0.0, 0.35], "S": [0.07, 0.0, -0.08, -0.1, -0.45]},
	"tankCharge": {"W": [0.0, 0.0, 0.0, 0.0, 0.0], "S": [0.06, 0.0, 0.0, -0.15, 0.0]},
}
