# 고도 판 그리기 (G1) 에만 필요한 수치. 게임 수치는 core/config.gd (shared/config.js) 를 씀
extends RefCounted

# 판 화면·1인칭 팔 다중 샘플 (render.js WebGLRenderer({ antialias: true }) — 크롬 기본 4×). 웹·PC 따로 정함 (재혁 2026-11-02: PC 4× 그대로,
# 웹은 지금 PC 와 같은 값 — 웹 성능 작업이 정함). 고르기는 msaa_3d
const MSAA_3D_PC := Viewport.MSAA_4X
const MSAA_3D_WEB := Viewport.MSAA_4X
const MSAA_LOW := Viewport.MSAA_DISABLED # 그래픽 낮춤: 끔 (웹·PC 둘 다. JS 는 낮춤에서 setPixelRatio(1) 로 비용을 줄임. 소프트웨어 GL 8명 판 4× = 프레임 약 2.4배)
const CELL_SIZE := 0.98 # 쌓인 칸·떨어지는 칸 상자 크기 (칸 사이 살짝 틈)
const CHECKER := 0.94 # 이웃 칸 체커보드 명암 (render.js updateGrid)
const FLOOR_THICK := 0.6 # 필드 바닥판 두께 (z 0 아래)
const CLIFF_THICK := 5.0 # 바닥판 아래 섬 절벽 두께
const SHADOW_LIFT := 0.03 # 그림자 칸을 착지 높이 위로 띄움
const SKY_PIECE_ALPHA_SKYVIEW := 0.45 # 하늘 시점일 때 하늘 계단 블록 비침 (render.js skyMats opacity)
const PIECE_SKY_ALPHA := 0.55 # 하늘 시점에선 블록 너머 착지 미리보기가 보이게
const CONTROLLED_COLOR := 0xd040d0 # 누가 조종 중인 블록
const PREVIEW_COLOR := [0xf0a030, 0xff2020, 0.35] # 내 블록 착지 그림자 (놓을 수 있음, 없음, 진하기)
const DANGER_SHADOW := [0xff1010, 0.6] # 내 머리 위로 떨어지는 블록 그림자
const TEAM_COLORS := {"red": [0xe04040, 0xff8c50, 0xc02868, 0xff6090], "blue": [0x3a6ee8, 0x30c0e8, 0x6a50e0, 0x40d8b0]} # render.js TEAM_COLORS
const SEA_SIZE := 600.0 # 위험 표면 판 한 변 (필드 밖 지평선까지 이어진 바다 자리)
const FOAM_SIZE := [1.0, 0.22] # 닿는 곳 거품 띠 칸 (길이, 폭)
const ITEM_SIZE := 0.42 # 아이템 자리 상자 (모델은 나중)
const ITEM_BOB := [0.45, 0.06, 300.0, 2.0] # 높이, 출렁임, 주기 ms, 도는 빠르기 (/초)
# 몸 자세 LOD (W12 성능, world/pose_lod.gd): 자세 (figureAnim·래그돌·묶음 뼈) 를 다시 셈하는 최소 간격. 자리·방향은 매 프레임 그대로.
#   near: 카메라에서 이 거리 (m) 안이면 매 프레임 · far_hz: 그보다 멀면 초당 이만큼 (120fps 면 2프레임에 한 번, 60fps 면 매 프레임)
#   (3인칭 카메라는 내 몸 뒤 ~5m 라 9m 로 두면 8명 판에서 7명이 매 프레임 — 재연 몸 자세 3.7ms. 3m = 화면에 아주 크게 보일 때만 → 2.1ms)
#   off_hz: 화면 밖이면 초당 이만큼 · margin: 화면 안 판정 공 반지름 (m, 몸 크기 + 그림자·카메라 한 프레임 늦음 여유)
#   내 몸 (1인칭 팔이 관절을 베낌) 은 늘 매 프레임
const POSE_LOD := {"near": 3.0, "far_hz": 60.0, "off_hz": 20.0, "margin": 2.5}
const LABEL_PIXEL := 0.0011 # 머리 위 이름표 글자 크기 (fixed_size 화면 크기)
const LABEL_FONT := [40, 10] # 글자 크기, 외곽선
const AMBIENT_DEFAULT := [0x8090c0, 0.7] # 테마 없을 때 주변광
const SUN_ENERGY := 1.0 / PI # 테마 sunIntensity 배율 (three.js 는 램버트에 1/π 가 붙음 → 고도 세기 = three 세기 / π)
const HEMI_ENERGY := 1.0 / PI # 테마 hemi 세기 배율 (같은 까닭)
const OVER_POSE := [1.2, -0.75] # 확인용 --world-view over: 전체 보기 yaw·pitch
const HAZARD_SURF := [0.35, 0.35] # 위험 표면 거칠기, 반사 세기
const HAZARD_LIGHT_DECAY := 1.4 # 위험 빛 거리 감쇠 지수 (hazard.js new THREE.PointLight(…, LAVA_LIGHT_RANGE, 1.4)). 세기·색은 three 값 그대로 툰 셰이더 전역 값으로 (OmniLight 안 씀)
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
const LABEL_GAP := [96.0, 40.0] # 보통 시점 이름표 겹침 판정 크기 (화면 px, 가까운 4명 크기 기준 — 먼 것은 LABEL_FAR_SCALE 배)
const HUNT_PIP_PX := 0.00085 # 머리 위 표식 마름모 글자 크기 (fixed_size). JS sprite pip 0.045 × 마름모 26/32 = 720p 에서 높이 ~17px (고도 ◆ 글자는 font 48 의 ~2/3)
const HUNT_PIP_GAP := 50.0 # 마름모 칸 사이 (글자 px, pixel_size 와 같이 줄어듦 — JS 칸 21px ÷ 마름모 17px 비율)
const HP_BAR := [130.0, 16.0, 64.0] # 체력전 머리 위 HP 막대: 폭·높이·이름 아래로 (이름표 글자 px 단위 — 화면에선 약 절반)
const SPIN_ARC_COLOR := 0xe8ecf4 # 갈고리 스핀 원호 색 (render.js spinArc)


# ---- 화질 (W6 2026-11-02, 재혁 PC 랙): 설정 '화질' 자동·높음·보통·낮음 (View.settings.gfx). 계산은 world/gfx_calc.gd, 적용은 world/gfx.gd
# 높음 = 예전 그대로 (MSAA 4×, 3D 해상도 1). 보통 = 모습은 거의 같음 (MSAA 2×, 거울 반사 작게, 창이 아주 크면 3D 해상도를 GFX_MAX_PX 까지).
# 낮음 = 예전 '그래픽 낮춤' (lowGfx: MSAA 끔·그림자·블룸·거울·장식 줄임) + 3D 해상도를 GFX_MAX_PX.low 까지 (JS 낮춤 setPixelRatio(1) 자리)
# 자동: 내장 그래픽 (Intel·AMD APU 등) 이면 낮음, 창 픽셀이 GFX_BIG_PX 보다 많으면 보통, 아니면 높음 (소프트웨어 GL 은 개발 확인용이라 높음 그대로)
const GFX_CHOICES := ["auto", "high", "medium", "low"]
const GFX_LABEL := {"auto": "자동", "high": "높음", "medium": "보통", "low": "낮음"}
const GFX_BIG_PX := 2560 * 1440 # 자동: 이보다 큰 창이면 보통
const GFX_MAX_PX := {"high": 0, "medium": 2560 * 1440, "low": 1920 * 1080} # 3D 를 그리는 픽셀 상한 (0 = 창 그대로). 넘으면 scaling_3d_scale 로 줄여 늘림
const GFX_MIN_SCALE := {"high": 1.0, "medium": 0.75, "low": 0.5} # 3D 해상도 배율 하한 (보통은 흐려 보이지 않게 0.75 까지만)
const MSAA_MEDIUM := Viewport.MSAA_2X # 보통: 판·1인칭 팔 다중 샘플 (4× 의 반 — 모서리 모습은 거의 같음)
const MIRROR_SCALE := {"high": 0.5, "medium": 0.35} # 타이틀·대기실 거울 반사 SubViewport = 창 크기 × 이 값 × 3D 배율 (낮음은 거울 없음). 반사는 흐리게 덮여 해상도가 잘 안 보임
# 지금 적용된 화질 (world/gfx.gd 가 정함, msaa_3d·mirror_scale 이 읽음). 테스트·헤드리스는 기본 high = 예전 값
static var level := "high"


# 다중 샘플 고르기: 그래픽 낮춤 → MSAA_LOW, 아니면 보통 화질이면 MSAA_MEDIUM, 웹이면 MSAA_3D_WEB, PC 면 MSAA_3D_PC (web 기본 = 지금 실행이 웹 내보내기인가)
static func msaa_3d(low: bool, web: bool = OS.has_feature("web"), lv: String = level) -> Viewport.MSAA:
	if low or lv == "low":
		return MSAA_LOW
	if lv == "medium":
		return MSAA_MEDIUM
	return MSAA_3D_WEB if web else MSAA_3D_PC


# 거울 반사 크기 배율 (창 크기에 곱함). scale_3d: 판 3D 해상도 배율
static func mirror_scale(scale_3d := 1.0, lv: String = level) -> float:
	return float(MIRROR_SCALE.get(lv, MIRROR_SCALE.medium)) * scale_3d
