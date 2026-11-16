# 구운 몸 화풍 맞추기 (c6-u1, 2026-11-15) 수치: 구운 몸 (.glb) 이 외부 모델 (chars/external.gd, tint "mask") 과 같은 규칙으로 보이게 —
# 살은 살색, 플레이어 색은 옷 칸만, 작은 눈, 얇은 선, 부드러운 툰 단. 계산은 chars/baked_look.gd, 설명 chars/BAKE.md '화풍 맞추기'
extends RefCounted

# 선·단: assets/models/ext/<id>.json 의 toon_steps·rim·outline 과 같은 값 (테스트가 json 과 견줌)
const TOON_STEPS := Vector3(0.7, 0.86, 1.0)
const RIM := [0.22, 4.0] # [세기, 지수] (c7-u1: 지수 3 → 4, 림이 가장자리에만)
const RIM_TINT := [0.5, 1.0] # c7-u1 림 틴트 [림 색을 플레이어 색으로 섞는 양, 림 배율 더하기] — json 의 rim_tint 와 같은 값 (toon_common rim_tint)
const RIM_GATE := [0.35, 0.65] # 림 틴트가 걸리는 면 [다 걸림, 안 걸림] — chars_config.gd EXT_DEFAULTS rim_gate 와 같은 값
const OUTLINE := 0.45 # 외곽선 굵기 = C.OUTLINE_THICKNESS × 이 값

# 눈 재질 색 (manifest mats 의 basic 재질, figure.js eyeWhiteMat·pupilMat)
const EYE_WHITE := 0xffffff
const EYE_PUPIL := 0x111111
const EYE_HEAD_MAX := 1.0 / 3.0 # 흰자 지름 ÷ 머리 폭 상한 (테스트)

const PLAYER_AREA := [0.10, 0.40] # 플레이어 칸 넓이 ÷ 처음 보이는 묶음 넓이 (테스트)
const FLESH_MIN_DIST := 0.18 # 살색과 플레이어·팀 색의 RGB 거리 하한 (테스트)
const WELD := 5000.0 # 조각 나누기: 같은 자리 정점 묶는 눈금 (1 ÷ 칸)

# 캐릭터마다 (웹 기본은 외부 넷도 구운 몸이라 8명 전부):
#   flesh     살색 (0xRRGGBB, 정점 색으로 구움)
#   roles     묶음 뼈 이름 (manifest nodes[].name) → "flesh" | "player" | "keep". "*" = 표에 없는 뼈.
#             피부 정점 (흰색 + UV2.x 1) 만 바뀜: flesh = 살색 + UV2.x 0, player·keep = 그대로 (skin_tint 가 플레이어 색으로 칠함)
#   split     한 뼈에 얼굴과 모자가 같이 있을 때 [뼈 기준 높이 문턱, 아래 역할, 위 역할] — 조각 (이어진 삼각형 덩어리) 가운데 높이로 가름 (조각을 반으로 자르지 않음)
#   wide      한 뼈에 팔과 띠가 같이 있을 때 [반폭 문턱, 좁은 역할, 넓은 역할] — 조각의 뼈 기준 x·y 반폭 큰 쪽으로 가름
#   promote   피부가 아닌 조각을 플레이어 칸으로 올림: [뼈, 재질 번호] 또는 [뼈, 재질 번호, 높이 문턱] (조각 가운데 높이가 문턱 이상만)
#   bare      피부가 아닌 조각을 살색으로 (장갑 → 맨손): [뼈, 재질 번호] 또는 [뼈, 재질 번호, 높이 문턱] (조각 가운데 높이가 문턱 **미만**만 — 손목 띠는 남김)
#   eye_scale 눈 (흰자·눈동자) 배율 — 흰자 가운데 기준. 흰자 지름이 머리 폭의 1/3 이하
#   double    (c7-u1) 이 몸의 불투명 툰 재질을 양면으로 — 한 겹 천 (망토·코트 자락·등 천) 안쪽이 외곽선 색 (보라) 으로 통칠되던 것. 외부 모델 json 의 double 과 같은 길 (external.gd Ext.look)
#   outline_push (c7-u1) 외곽선 껍질을 깊이로 뒤로 (0~0.002, json outline_push 와 같은 뜻) — 양면 천 안쪽 면 위로 껍질이 비치지 않게
const LOOK := {
	"bard": {
		"flesh": 0xE6B894,
		# 얼굴·손 살색 / 어깨 망토·등 망토·모자 깃털 플레이어 색 (메탈 폼: 맨팔 살색 / 모히칸·손목 띠)
		"roles": {"*": "flesh", "cape": "player", "formParts_bard_0": "player", "formParts_bard_1": "player", "mohawk": "player"},
		"split": {"formParts_metal_3": [-0.16, "player", "flesh"], "formParts_metal_5": [-0.16, "player", "flesh"]},
		# 메탈 폼은 옷이 다 검정이라 기타 몸통·등 천 조각·장화 줄 (빨강 재질 16) 을 플레이어 색으로
		"promote": [["guitar", 16], ["formParts_metal_1", 16], ["formParts_metal_8", 16], ["formParts_metal_11", 16]],
		"eye_scale": 0.44,
	},
	"berserker": {
		"flesh": 0xE0A882,
		# 머리·팔·몸통 (근육 덩어리) 살색 / 허리 천 (바지·앞뒤 자락) 플레이어 색. 근육 홈은 묶음 밖 재질 (피부 × 어둡게) 그대로
		"roles": {"*": "flesh"},
		"promote": [["hips", 21], ["thigh_R", 21], ["thigh_L", 21], ["flaps_5_obj", 30], ["flaps_6_obj", 30]],
		"eye_scale": 0.54,
	},
	"builder": {
		"flesh": 0xE6B894,
		# 얼굴·코·손 살색 / 안전모 (챙·돔)·소매 플레이어 색
		"roles": {"*": "flesh", "elbow_R": "player", "elbow_L": "player"},
		"split": {"neck": [0.17, "flesh", "player"]},
		"eye_scale": 0.54,
	},
	"cannon": {
		"flesh": 0xD9A07A,
		# 얼굴·팔·주먹 살색 (주먹은 갈색 장갑 공이 피부 손을 다 덮고 있어서 장갑 공을 살색으로, 손목 띠는 그대로) / 몸통·팔 줄무늬·두건 플레이어 색
		"roles": {"*": "flesh", "waist": "player"},
		"wide": {"shoulder_R": [0.08, "flesh", "player"], "shoulder_L": [0.08, "flesh", "player"], "elbow_R": [0.08, "flesh", "player"], "elbow_L": [0.08, "flesh", "player"]},
		"promote": [["neck", 2, 0.15], ["flaps_0_obj", 2], ["flaps_1_obj", 2]],
		"bare": [["hand_R", 6, 0.02], ["hand_L", 6, 0.02]],
		"eye_scale": 0.54,
	},
	"tank": {
		"flesh": 0xE6B894,
		# 얼굴·손 살색 / 갑옷 밑 천·허리 띠·어깨 띠·앞 자락·방패 면·투구 술 플레이어 색
		"roles": {"*": "flesh", "torso": "player", "waist": "player", "flaps_0_obj": "player", "flaps_1_obj": "player", "shields_back": "player", "shields_front": "player"},
		"split": {"neck": [0.29, "flesh", "player"]},
		"wide": {"shoulder_R": [0.1, "flesh", "player"], "shoulder_L": [0.1, "flesh", "player"]},
		"eye_scale": 0.5,
		"double": true, "outline_push": 0.0015,
	},
	"ninja": {
		"flesh": 0xE6B894,
		# 눈가·손 살색 / 머리띠·목도리·허리띠·천 자락 플레이어 색
		"roles": {"*": "flesh", "hips": "player", "flaps_0_obj": "player", "flaps_1_obj": "player", "flaps_2_obj": "player", "flaps_3_obj": "player", "flaps_4_obj": "player", "flaps_5_obj": "player"},
		"split": {"neck": [0.2, "flesh", "player"], "waist": [0.0, "flesh", "player"]},
		"eye_scale": 0.44,
	},
	"hunter": {
		"flesh": 0xE6B894,
		# 얼굴·코·손 살색 / 모자 (챙·머리, 외부 모델 마스크 칸과 같은 자리)·띠·깃털·목도리·망토 안감 플레이어 색
		"roles": {"*": "flesh", "flaps_0_obj": "player", "flaps_1_obj": "player", "flaps_2_obj": "player"},
		"split": {"neck": [0.2, "flesh", "player"], "waist": [0.2, "flesh", "player"]},
		"promote": [["neck", 2]],
		"eye_scale": 0.44,
		"double": true, "outline_push": 0.0015,
	},
	"hook": {
		"flesh": 0xE6B894,
		# 얼굴·손 살색 / 삼각 모자 (수염·안대·두건은 그대로 — 높이 0.2 위 조각만)·조끼·허리 띠·소매 끝·코트 안감 플레이어 색
		"roles": {"*": "flesh", "torso": "player", "flaps_0_obj": "player", "flaps_1_obj": "player", "flaps_2_obj": "player"},
		"split": {"waist": [0.03, "flesh", "player"]},
		"wide": {"elbow_R": [0.08, "flesh", "player"], "elbow_L": [0.08, "flesh", "player"]},
		"promote": [["neck", 1, 0.2]],
		"eye_scale": 0.48,
		"double": true, "outline_push": 0.0015,
	},
}
