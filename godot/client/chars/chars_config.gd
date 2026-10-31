# G2 고도에만 필요한 수치 (PLAN 7절: 묶음 폴더의 <묶음>_config.gd). JS 수치는 core/config.gd
extends RefCounted

# 몸 조각 합치기 (JS client/batch.js 와 같은 뜻): 움직이는 노드마다 그 아래 같이 움직이는 조각을 재질 종류마다 메시 하나로 (색은 정점 색).
# false 면 조각마다 MeshInstance3D (확인용 — 그리기 수가 몸 하나에 약 100+)
# (2026-10-31 Skeleton3D 한 메시 판은 1인칭에서 몸이 화면을 덮고 하얀 조각이 보이고, 숨긴 조각도 삼각형을 그려서 바꿈)
const MERGE := true
