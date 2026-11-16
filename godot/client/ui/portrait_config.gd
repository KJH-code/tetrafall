# c8 초상 얼굴 칸 표 (ui/portrait.gd frame·_draw_one 이 읽음): 캐릭터 8명이 아래 판 (96)·결과 승자 (192)·결과 표 (64) 에서 얼굴 앞면을 같은 크기로 칸 가운데에 보이게.
# 예전: 구운·코드 몸은 목 관절 아래 조각 상자 × 1.6 을 0.26~0.4 m 로 자른 값 하나 (머리 조각이 눈 둘뿐인 몸은 전부 0.26 → 뿔·모자가 잘리고 얼굴이 왼쪽으로 쏠림),
# 카메라 쪽은 대포수만 반대 (LEFT_SIDE). 외부 모델 둘 (갈고리·사냥꾼) 은 쉬는 자세가 몸을 틀고 있어 같은 쪽에서 보면 옆얼굴·뒤통수.
# 맞추는 법: tools/portrait_sheet.gd (와 --no-ext) 가 192 칸마다 fill·cx·top 을 출력 → 8명 모두 top 4~18% · fill 0.40~0.75 · cx 0.42~0.58 에 들게.
#   side  = 카메라가 도는 쪽 (앞 +x 에서 옆으로: -1 = 기본, 1 = 반대쪽 — 포신·방패가 얼굴을 가리거나 몸이 튼 쪽)
#   half  = 칸 세로 반 (m) — 작을수록 얼굴이 큼
#   up    = 칸 가운데를 머리 조각 상자 가운데에서 올림 (m) — 클수록 얼굴이 칸 아래로
#   shift = 칸 가운데를 가로로 옮김 [x, z] (m, 고도 좌표) — 화면 오른쪽 = side -1 이면 (0.72, -0.69), side 1 이면 (-0.72, -0.69) 쪽이라 얼굴을 오른쪽으로 보내려면 그 반대로
# 표에 없는 캐릭터는 예전 식 그대로 (side -1, 머리 상자 × HEAD_K 를 HALF_MIN~HALF_MAX 로)
extends RefCounted

# 구운·코드 몸 (웹 기본 = 8명 전부, PC 는 외부 모델이 없는 넷)
const FACE := {
	"tank": {"side": -1.0, "half": 0.29, "up": 0.025, "shift": [-0.012, 0.012]},
	"ninja": {"side": -1.0, "half": 0.226, "up": -0.036, "shift": [-0.068, 0.066]},
	"builder": {"side": -1.0, "half": 0.33, "up": -0.13, "shift": [-0.019, 0.018]},
	"hook": {"side": -1.0, "half": 0.26, "up": 0.0, "shift": [-0.06, 0.058]},
	"hunter": {"side": -1.0, "half": 0.285, "up": 0.10, "shift": [-0.066, 0.031], "ang": 16.0, "rise": -0.6}, # 넓은 모자챙 끝까지. 46도·위에서 보면 긴 코가 옆얼굴로 보이고 챙이 눈을 가림 → 거의 정면 (ang 16), 조금 아래에서 (rise -0.6)
	"cannon": {"side": 1.0, "half": 0.36, "up": -0.05, "shift": [0.0, 0.0]}, # 오른어깨 포신이 얼굴을 가려 반대쪽에서 봄 (JS LEFT_SIDE 그대로)
	"berserker": {"side": -1.0, "half": 0.37, "up": 0.125, "shift": [-0.063, 0.062]}, # 뿔 끝까지 칸 안 (예전엔 잘림) — 그만큼 얼굴이 작음
	"bard": {"side": -1.0, "half": 0.38, "up": -0.10, "shift": [0.0, 0.0]}, # 마른 몸: 모자 끝이 칸 안이면서 fill 0.40 을 넘기려면 어깨·류트까지 (얼굴이 작음). half 를 줄이면 fill 이 0.33 대로 떨어짐
}

# 외부 모델의 카메라 쪽 (half·up·shift 는 모델 옆 json "portrait" — 키 배율이라 모델 키를 따라감)
const SIDE_EXT := {
	"tank": -1.0,
	"ninja": 1.0, # 깊은 두건: 거의 정면 (json ang 8) 에서 봐야 이마 보호대·두 눈·복면이 보임 — 머리가 이쪽으로 살짝 돌아 있음
	"hunter": 1.0, # 쉬는 자세가 몸을 틀어 기본 쪽에선 뒤통수
	"hook": 1.0, # 기본 쪽에선 옆얼굴 (모자챙·깃이 얼굴을 가림)
}

# 온몸 초상 (캐릭터 카드·대기실 — 이번에 안 바꿈): 예전 LEFT_SIDE 그대로 대포수만 반대쪽
const SIDE_FULL := {"cannon": 1.0}

const SIDE_DEFAULT := -1.0 # 표에 없는 캐릭터 (예전 값)
# 얼굴 초상 카메라 (예전 값 — portrait.gd 에 박혀 있던 46도·0.18): 깊은 두건·넓은 모자챙처럼 그 각에선 얼굴이 가려지는 몸만 따로 적음
# (구운·코드 몸은 FACE 의 "ang"·"rise", 외부 모델은 json "portrait" 의 "ang"·"rise" — 없으면 이 값)
const FACE_ANG := 46.0 # 앞 (+x) 에서 옆으로 돌린 각 (도) — 작을수록 정면
const FACE_RISE := 0.18 # 카메라 높이 = 칸 가운데 + 칸 세로 반 × 이만큼 — 음수면 아래에서 올려다봄 (모자챙 밑 얼굴)

const HEAD_K := 1.6 # 표에 없는 구운·코드 몸: 머리 조각 상자 높이 × 이만큼
const HALF_MIN := 0.26 # 그 값의 아래·위 (m)
const HALF_MAX := 0.4


# 카메라 쪽: 외부 모델이면 SIDE_EXT, 아니면 FACE.side. 표에 없으면 SIDE_DEFAULT
static func side_of(char_id: String, ext: bool) -> float:
	if ext:
		return float(SIDE_EXT.get(char_id, SIDE_DEFAULT))
	return float((FACE.get(char_id, {}) as Dictionary).get("side", SIDE_DEFAULT))


# 얼굴 초상 카메라 각·높이: o = 그 몸의 표 줄 (FACE[캐릭터] 또는 json "portrait"). 안 적혀 있으면 예전 값
static func view_of(o: Dictionary) -> Dictionary:
	return {"ang": float(o.get("ang", FACE_ANG)), "rise": float(o.get("rise", FACE_RISE))}


static func side_of_full(char_id: String) -> float:
	return float(SIDE_FULL.get(char_id, SIDE_DEFAULT))


# 구운·코드 몸의 얼굴 칸: 머리 조각 상자 (가운데 center, 높이 head_h) → {at, half}. 표에 없으면 예전 식
static func face_frame(char_id: String, center: Vector3, head_h: float) -> Dictionary:
	if not FACE.has(char_id):
		return {"at": center, "half": clampf(head_h * HEAD_K, HALF_MIN, HALF_MAX)}
	var f: Dictionary = FACE[char_id]
	var sh: Array = f.get("shift", [0.0, 0.0])
	return {"at": center + Vector3(float(sh[0]), float(f.get("up", 0.0)), float(sh[1])), "half": float(f.half)}
