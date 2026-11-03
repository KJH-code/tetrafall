# 외부 뼈대 모델 (.glb) 받아들이기 — W14 시제품 (2026-11-03)

(작업 중 — 계획)

1. 시험 모델: CC0 사람형 로봇 (assets/models/ext/tank.glb, CREDITS.md). 몸 메시 대부분이 뼈에 붙은 딱딱한 조각 + 손만 스킨
2. chars/external.gd: .glb → Skeleton3D 찾기 → 뼈 이름 자동 매칭 (Mixamo·Quaternius·Meshy/Tripo·블렌더 .L/.R) + 수동 덮어쓰기 → 크기 (C.PLAYER_HEIGHT)·발바닥 → 우리 관절 노드 (body.gd hips·waist… 그대로, 안 보이게) 의 회전을 뼈로 옮김 (쉬는 자세 맞춤 + 전역 회전 차이)
3. body.gd build: 외부 → 구운 → 코드 조립 (3단)
4. 툰 재질 덮기 (알베도 텍스처 살림·음영 단계·외곽선), 색 틴트 두 가지, 반투명·피격 번쩍
5. 1인칭 팔·래그돌·초상·대기실 확인 + 스크린샷
