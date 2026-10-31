# G2 고도에만 필요한 수치 (PLAN 7절: 묶음 폴더의 <묶음>_config.gd). JS 수치는 core/config.gd
extends RefCounted

# 몸 조각 합치기 (JS client/batch.js 와 같은 뜻): 움직이는 노드마다 그 아래 같이 움직이는 조각을 재질 종류마다 메시 하나로 (색은 정점 색).
# false 면 조각마다 MeshInstance3D (확인용 — 그리기 수가 몸 하나에 약 100+)
# (2026-10-31 Skeleton3D 한 메시 판은 1인칭에서 몸이 화면을 덮고 하얀 조각이 보이고, 숨긴 조각도 삼각형을 그려서 바꿈)
const MERGE := true
# 합칠 때 보이기를 안 바꾸는 관절들은 Skeleton3D 뼈로 몸 한 메시 (재질 종류마다) — 몸 하나 그리기 ~30 → ~10. false 면 관절마다 메시 (예전 판)
# (위 예전 Skeleton3D 판과 다름: 뼈는 늘 보이는 관절만, 1인칭 팔 복제는 합치지 않음, 바인드 단위)
const SKIN := true
const SKIN_AABB := AABB(Vector3(-3, -3, -3), Vector3(6, 6, 6)) # 뼈 메시 컬링 상자 (frame 안 게임 좌표, 몸 + 휘두름 여유)
