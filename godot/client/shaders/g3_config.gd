# G3 (툰·셰이더·테마) 고도 전용 수치 — JS 값이 있는 건 core/config.gd (C.*) 를 쓰고, 여기는 three 에만 있던 값·고도 변환 값.
extends RefCounted

# three MeshToonMaterial 3단 명암 (client/toon.js TOON_GRADIENT [110, 175, 255] / 255)
const TOON_STEPS := Vector3(110.0 / 255.0, 175.0 / 255.0, 1.0)
# 외곽선 색 (render.js OutlineEffect defaultColor, 선형 값)
const OUTLINE_COLOR := Color(0.08, 0.05, 0.1, 1.0)
# 테마 없는 화면 (예전 노을, render.js 생성자): 하늘빛 위·아래·세기, 해 세기 (색·방향은 C.SUN_COLOR·C.SUN_DIR)
const SUNSET_HEMI := [0xffe2d2, 0x8a90b8, 1.15]
const SUNSET_SUN := 1.25
# 대기실 큰 캐릭터·초상 무대 빛 (JS client/char-stage.js·portrait.js: AmbientLight 0xffffff 1.05 + 앞 DirectionalLight 0xffffff 1.5 — 판·대기실 테마와 상관없이 늘 같은 밝기).
# 고도는 툰 셰이더 빛이 전역 값이라 그대로 두면 대기실 어두운 장면 (lobby_dark) 빛을 받아 어둡고 탁해짐 (W19 재혁 캡처) → 재질마다 이 빛 (toon_local_light)
const STAGE_HEMI := [0xffffff, 0xffffff, 1.05]
const STAGE_SUN := [0xffffff, 1.5]
# 해 그림자: three (render.js bias -0.0008) 와 단위가 달라 고도 값으로 맞춤 — 빛을 비스듬히 받는 옆면이 제 그림자로 어두워지지 않게 (JS 와 나란히 재서 정함)
const SUN_SHADOW_BIAS := 0.1
const SUN_SHADOW_NORMAL_BIAS := 2.0
# 하늘 구 (render.js skyDome): 반지름, 노을 기본 해 번짐·원반 색 (선형 Vector3 그대로)·원반 크기
const SKY_RADIUS := 150.0
const SKY_GLOW := Vector3(1.0, 0.65, 0.35)
const SKY_DISC := Vector3(1.0, 0.93, 0.75)
const SKY_DISC_SIZE := 0.0005
# 해 그림자 거리 (판 대각선 반 + 여백, render.js reach = hypot(W, D) / 2 + 4)
const SHADOW_REACH_PAD := 4.0
const SHADOW_MAX_DISTANCE := 60.0
# c8-u3 가까운 몸 깎기 (toon_common·outline near_cut): 눈에서 x m 안의 몸 화소는 다 버리고 y m 까지 디더로 점점 덜 버림 (m — 카메라에서 화소까지 거리).
# 1인칭·관전 카메라 앞을 지나는 남의 몸이 화면을 덮던 것. 판 몸 재질 (외부·구운 몸 — chars/external.gd Ext.look) 과 그 몸 외곽선 사본 (g3.gd far_outline) 에만 넣음
const NEAR_CUT := Vector2(0.3, 0.75)
# 몸 두께 어림 (m): 몸 앞면이 빠진 화소 뒤로 보이는 몸 반대편 외곽선 껍질 (앞면보다 그 화소의 몸 두께만큼 멂) 을 같이 버리려고, 껍질 화소 거리를 이만큼 가깝게 침 (outline.gdshader near_shell).
# 작으면 두꺼운 몸통 가운데에 잉크색이 남고, 크면 그만큼 먼 몸까지 외곽선이 점점이 빠짐 — 외곽선은 NEAR_CUT.y + 이 값 (1.35 m) 밖에서 예전 그대로, NEAR_CUT.x + 이 값 (0.9 m) 안에서 다 빠짐 (몸 면은 NEAR_CUT 그대로).
# 그 사이 (0.9~1.35 m) 는 몸 면은 그대로인 채 선만 점점 옅어짐 (선 화소가 1.0 m 에서 78 %, 1.2 m 에서 33 % 빠짐) — 몸 면이 그대로인 0.75 m 밖에서도 선은 1.35 m 까지 예전과 다름 (알고 받아들인 절충)
const NEAR_CUT_SHELL := 0.6
const STENCIL_MY_BODY := 7 # 스텐실 값: 3인칭 내 몸 (사냥꾼의 눈 x-ray 가 이 값 위엔 안 그림 — JS 는 몸을 복사본 뒤에 그려 renderOrder 로 가름)
const GRADE_LUT := 32 # 판 빛 색 보정 LUT 한 변 (game_light.gd grade_lut: CSS saturate·contrast·brightness 를 구움, 32³ RGB8 = 96KB)

# W37: 위험 표면 (필드 판) 정점 격자 수 [보통, 그래픽 낮춤]. JS 값 (C.HAZARD_SEG = 120) 은 three 가 정점 처리가 싸서였고, 고도에선 삼각형 28.8k (용암 판 8명 장면 화면 삼각형의 12%).
# 정점 격자 64 (19×19 판의 둘레 여백 포함 31m 에서 칸 0.48m) 도 파도 모양·닿는 곳 거품 테 (조각 셰이더의 닿는 곳 거리 그림) 가 눈으로 같음 (캡처 전후, 화소 차 3.5%·대부분 파도 위상).
const HAZARD_SEG := [64, 40]
