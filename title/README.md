# 타이틀 엔딩 아트 시안 (B3)

로고 완성 순간 (빛 터짐 0.35초 뒤), 1280×720, 보통 그래픽 (블룸·반사 켬). 코드: claude/tf-b3-world2

| 파일 | 테마 |
|---|---|
| crystal | 자수정 동굴 |
| volcano | 화산 용암 균열 |
| desert | 별빛 사막 피라미드 |
| mushroom | 빛 버섯 숲 |
| skycastle | 밤 구름 위 성 |
| castle | 횃불 성벽 |
| meadow | 반딧불 밤 초원 |
| all | 7개 한 장 |

## 2단계 (step2/) — 1차 모습 기준 (2차 3D·굵게는 되돌림)

| 파일 | 내용 |
|---|---|
| title_crystal.gif | 800×450, 10fps: 캄캄 → 블록 쌓기 → 빛 터짐 → Enter 안내 → Enter → 빠져나가며 하얗게 → 메뉴 섬 |
| flow.png | gif 중 8칸 (0.5초·3초·4초·5.7초·Enter 뒤 0.6초·1초·메뉴) |
| title_crystal_low.png | 그래픽 낮춤: 블룸·거울 반사·렌즈 플레어 끔, 완성 로고로 바로 |
| title_crystal_reduced.png | 움직임 줄이기: 완성 로고로 바로 (블룸은 켬), Enter 면 하얀 페이드만 |

## B4 테마 칸 모습 연결 (piece/)

로고 블록 = 그 테마 PieceLook (모양·면 텍스처·결) + 타이틀 빛 (1차만큼). 코드 claude/tf-b3-world2 2eabc38
