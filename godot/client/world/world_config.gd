# 고도 판 그리기 (G1) 에만 필요한 수치. 게임 수치는 core/config.gd (shared/config.js) 를 씀
extends RefCounted

const CELL_SIZE := 0.98 # 쌓인 칸·떨어지는 칸 상자 크기 (칸 사이 살짝 틈)
const CHECKER := 0.94 # 이웃 칸 체커보드 명암 (render.js updateGrid)
const FLOOR_THICK := 0.6 # 필드 바닥판 두께 (z 0 아래)
const CLIFF_THICK := 5.0 # 바닥판 아래 섬 절벽 두께
const SHADOW_LIFT := 0.03 # 그림자 칸을 착지 높이 위로 띄움
const PIECE_SKY_ALPHA := 0.55 # 하늘 시점에선 블록 너머 착지 미리보기가 보이게
const CONTROLLED_COLOR := 0xd040d0 # 누가 조종 중인 블록
const PREVIEW_COLOR := [0xf0a030, 0xff2020, 0.35] # 내 블록 착지 그림자 (놓을 수 있음, 없음, 진하기)
const DANGER_SHADOW := [0xff1010, 0.6] # 내 머리 위로 떨어지는 블록 그림자
const TEAM_COLORS := {"red": [0xe04040, 0xff8c50, 0xc02868, 0xff6090], "blue": [0x3a6ee8, 0x30c0e8, 0x6a50e0, 0x40d8b0]} # render.js TEAM_COLORS
const SEA_SIZE := 600.0 # 위험 표면 판 한 변 (필드 밖 지평선까지 이어진 바다 자리)
const FOAM_SIZE := [1.0, 0.22] # 닿는 곳 거품 띠 칸 (길이, 폭)
const ITEM_SIZE := 0.42 # 아이템 자리 상자 (모델은 나중)
const ITEM_BOB := [0.45, 0.06, 300.0, 2.0] # 높이, 출렁임, 주기 ms, 도는 빠르기 (/초)
const LABEL_PIXEL := 0.0011 # 머리 위 이름표 글자 크기 (fixed_size 화면 크기)
const LABEL_FONT := [40, 10] # 글자 크기, 외곽선
const AMBIENT_DEFAULT := [0x8090c0, 0.7] # 테마 없을 때 주변광
const SUN_ENERGY := 1.0 / PI # 테마 sunIntensity 배율 (three.js 는 램버트에 1/π 가 붙음 → 고도 세기 = three 세기 / π)
const HEMI_ENERGY := 1.0 / PI # 테마 hemi 세기 배율 (같은 까닭)
const OVER_POSE := [1.2, -0.75] # 확인용 --world-view over: 전체 보기 yaw·pitch
const HAZARD_SURF := [0.35, 0.35] # 위험 표면 거칠기, 반사 세기
const HAZARD_GLOW := [0.4, 0.2] # 위험 표면 스스로 빛남 (용암, 물·기타)
const FOAM_ALPHA := 0.85 # 닿는 곳 거품 띠 진하기
const LABEL_LIFT := 0.2 # 이름표를 머리 위로 더 (두 줄 글자 가운데 자리)
const LABEL_LIGHTEN := 0.35 # 이름표 글자 색을 몸 색보다 밝게
const CAM_CLIP := [0.05, 900.0] # 카메라 가까운·먼 자름
const BLOCK_ROUGH := [0.9, 0.6] # 쌓인 칸, 떨어지는 칸 거칠기
const ITEM_GLOW := 0.4 # 아이템 스스로 빛남
const CLIFF_COLOR := 0x6a5a4a # 테마 없을 때 섬 절벽
const SEA_RINGS := 8 # 구름 바다 판 끝 투명해지는 고리 수
const CAM_ABOVE_HAZARD := 0.8 # 승자·셀카 카메라를 위험 표면 위 이만큼 이상으로
const VICTORY_PULL := [0.3, 0.6] # 승자 카메라가 막히면: 막힌 칸 앞 여백, 승자에서 가장 가까운 거리
const MARK_CELL := 0.94 # 스킬 예고 칸 판 크기 (render.js markBox)
