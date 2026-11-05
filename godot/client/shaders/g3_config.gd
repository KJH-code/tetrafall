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
const STENCIL_MY_BODY := 7 # 스텐실 값: 3인칭 내 몸 (사냥꾼의 눈 x-ray 가 이 값 위엔 안 그림 — JS 는 몸을 복사본 뒤에 그려 renderOrder 로 가름)
const GRADE_LUT := 32 # 판 빛 색 보정 LUT 한 변 (game_light.gd grade_lut: CSS saturate·contrast·brightness 를 구움, 32³ RGB8 = 96KB)
