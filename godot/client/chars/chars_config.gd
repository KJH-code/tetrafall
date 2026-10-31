# G2 고도에만 필요한 수치 (PLAN 7절: 묶음 폴더의 <묶음>_config.gd). JS 수치는 core/config.gd
extends RefCounted

# 몸 조각을 한 메시로 합침 (JS client/batch.js 와 같은 뜻): 조각마다 뼈 하나 (Skeleton3D), 색은 정점 색, 재질 종류마다 표면 하나.
# false 면 조각마다 MeshInstance3D (확인용 — 그리기 수가 몸 하나에 약 100+)
const MERGE := true
# 숨긴 조각 (손에 안 든 총·활 등) 은 뼈를 이만큼 줄여 안 보이게 (합친 메시에선 조각마다 보이기를 못 끔)
const HIDE_SCALE := 0.0001
