# Blender 캐릭터 제작 파이프라인 (W19, 진행 중)

재혁 결정 (B 방식): 캐릭터 모델은 Blender 를 스크립트로 돌려 우리 규격으로 직접 만듦. 이번엔 탱크 1명 시험 제작.

## 계획 (WIP)

1. `dump_rig.gd` (고도): 지금 구운 탱크 몸의 관절 자리·방패 자리를 `tools/blender/ref/tank_rig.json` 으로 뽑음 → Blender 가 같은 관절 자리로 뼈를 세움
2. `build_character.py` 공통 (둥근 상자·캡슐·구 + 베벨·서브디비전, 꼭짓점 색 `COLOR_0`, 몸 색 칸 표시 UV2, 뼈대·자동 가중치·가중치 정리, 미리보기 렌더, glb 내보내기)
3. `chars/tank.py`: 둥근 투구 + 빨간 깃, 넓은 어깨 갑옷, 장갑, 왕눈알, 방패 (따로 `tank_shield.glb`)
4. 고도: 외부 모델 (external.gd) 이 뼈 이름 그대로 (`shoulder_R` …) 를 받고, 꼭짓점 색 + 몸 색 칸 (UV2.x = 1 → `skin_tint`) 재질을 쓰게 최소 수정, 방패는 안쪽 몸 방패 노드 (`shields.front/back`) 자리에 붙임
5. 게임 안 스크린샷·비용 표
