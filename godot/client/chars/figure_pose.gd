# 걸음걸이·공중·평소 버릇 자세 (client/figure-pose.js 옮김, 고도 없는 순수 계산, 테스트 tests/test_chars.gd 가 JS 정답 figure_pose.json 과 비교)
# 모두 목표 자세 T 만 바꿈 → 관절 스프링이 그 자세를 따라감
# T: { waistPitch, waistRoll, waistSide, neckPitch, hipsZ, shFwd[2], shOut[2], elbow[2], thFwd[2], thOut[2], knee[2] } ([오른쪽, 왼쪽])
extends RefCounted

const C := preload("res://core/config.gd")


static func ease01(u: float) -> float:
	var x := clampf(u, 0.0, 1.0)
	return x * x * (3.0 - 2.0 * x)


static func gait_of(char_id: String) -> Dictionary:
	var g: Dictionary = C.FIGURE_GAIT_DEFAULT.duplicate()
	if C.FIGURE_GAIT.has(char_id):
		g.merge(C.FIGURE_GAIT[char_id], true)
	return g


# 걷기·달리기: 캐릭터별 보폭·숙임·팔·무릎·통통·뒤뚱·들썩 (g = gait_of). d = 체형 (hunch·spread), hs = 수평 속도, walk = 걸음 위상
static func gait_pose(T: Dictionary, d: Dictionary, hs: float, walk: float, g: Dictionary) -> void:
	var amp := minf(1.0, hs / C.MOVE_SPEED)
	var w := walk
	for i in 2:
		var ph := w + (PI if i else 0.0)
		T.thFwd[i] = sin(ph) * C.FIGURE_WALK_LEG * amp * g.stride + g.crouch * 0.6
		# 뒤로 차 올리는 무릎 (빠를수록 높이) + 웅크림
		T.knee[i] = (maxf(0.0, -cos(ph)) * C.FIGURE_WALK_KNEE + maxf(0.0, -sin(ph)) * 0.4) * amp * g.knee + g.crouch * 1.1
		T.thOut[i] = g.wide
		T.shFwd[i] = (-sin(ph) * C.FIGURE_WALK_ARM * g.arm + 0.15 - g.armBack) * amp
		T.elbow[i] = maxf(0.05, 0.3 + (C.FIGURE_RUN_ELBOW + g.elbow) * amp + maxf(0.0, -sin(ph)) * 0.3 * amp * g.arm) # 앞으로 올 때 더 굽혀 펌프
		T.shOut[i] = d.spread * (1.0 - 0.5 * amp) + g.shrug * amp * (0.6 + 0.6 * absf(sin(w)))
	var step := absf(sin(w)) # 0 = 디딤, 1 = 다리가 가장 벌어짐
	T.waistPitch = d.hunch + (C.FIGURE_RUN_LEAN + g.lean) * amp + g.shrug * amp * 0.5 * (1.0 - step) # 들썩: 디딜 때마다 윗몸이 앞으로 툭
	T.waistRoll = -sin(w) * C.FIGURE_RUN_TWIST * amp * g.twist # 어깨가 다리 반대로 비틂
	T.waistSide = sin(w) * (0.05 + g.sway) * amp # 디딘 다리 쪽으로 (뒤뚱이면 크게)
	T.neckPitch = -d.hunch - (C.FIGURE_RUN_LEAN + g.lean) * amp * 0.6 + g.neck * amp + cos(w * 2.0) * 0.05 * amp # 고개는 앞을 봄
	T.hipsZ = g.bounce * amp * (step - 0.5) * 2.0 # 디딜 때 가장 낮고 (쿵) 다리가 벌어질 때 높음 (통통)


# 공중: 오름 (무릎 접고 팔 위) → 정점 (팔다리 펼침) → 내려옴 (팔 허우적, 다리 뻗어 착지 준비). 공격 중엔 팔을 가만히
const AIR_RISE := {"shFwd": [0.7, 0.7], "shOut": [1.9, 1.9], "elbow": [0.5, 0.5], "thFwd": [1.1, 0.55], "knee": [1.6, 1.1], "thOut": [0.05, 0.05], "waistPitch": 0.12, "neckPitch": -0.2}
const AIR_PEAK := {"shFwd": [0.15, 0.15], "shOut": [1.45, 1.45], "elbow": [0.2, 0.2], "thFwd": [0.35, 0.05], "knee": [0.4, 0.3], "thOut": [0.22, 0.22], "waistPitch": 0.0, "neckPitch": -0.1}
const AIR_FALL := {"shFwd": [0.5, 0.5], "shOut": [1.25, 1.25], "elbow": [0.4, 0.4], "thFwd": [0.45, 0.3], "knee": [0.2, 0.25], "thOut": [0.1, 0.1], "waistPitch": -0.08, "neckPitch": 0.15}


# vz = 위아래 속도 (null·NaN 이면 0), t = 몸 시각 (초)
static func air_pose(T: Dictionary, d: Dictionary, vz, t: float, attacking: bool) -> void:
	var v: float = vz if (vz != null and is_finite(vz)) else 0.0
	var r := ease01(v / C.FIGURE_AIR_VZ)
	var f := ease01(-v / C.FIGURE_AIR_VZ)
	var p := 1.0 - r - f
	for key in AIR_PEAK:
		if AIR_PEAK[key] is Array:
			T[key] = [AIR_RISE[key][0] * r + AIR_PEAK[key][0] * p + AIR_FALL[key][0] * f, AIR_RISE[key][1] * r + AIR_PEAK[key][1] * p + AIR_FALL[key][1] * f]
		else:
			T[key] = AIR_RISE[key] * r + AIR_PEAK[key] * p + AIR_FALL[key] * f
	T.waistPitch += d.hunch
	# 내려오는 동안 팔 허우적 (두 팔 엇갈려)
	for i in 2:
		T.shOut[i] += sin(t * 14.0 + i * 2.1) * 0.35 * f
		T.shFwd[i] += sin(t * 11.0 + i * PI) * 0.45 * f
	if attacking:
		T.shOut = [0.5, 0.5]
		T.shFwd = [0.2, 0.2]
		T.elbow = [0.4, 0.4]
	T.waistRoll = 0.0
	T.waistSide = 0.0
	T.hipsZ = 0.0


# 공중 대시 슈퍼맨: 오른팔 앞으로 쭉, 왼팔 몸 옆, 다리 뒤로 모음, 고개 들어 앞을 봄 (몸 전체 눕힘은 몸 노드)
const SUPERMAN := {"shFwd": [2.9, -0.2], "shOut": [0.1, 0.25], "elbow": [0.05, 0.2], "thFwd": [-0.3, -0.15], "knee": [0.15, 0.45], "thOut": [0.05, 0.05], "waistPitch": -0.15, "neckPitch": -0.7}


# pose 쪽으로 w 만큼 섞음. 배열 칸이 null 이면 그 쪽은 그대로
static func overlay_t(T: Dictionary, pose: Dictionary, w: float) -> void:
	for key in pose:
		var val = pose[key]
		if val is Array:
			for i in val.size():
				if val[i] != null:
					T[key][i] += (val[i] - T[key][i]) * w
		else:
			T[key] += (val - T[key]) * w


# 가속·멈춤·방향 전환: 몸 기준 가속도만큼 기울임 (출발은 앞으로, 멈추면 관성으로 앞으로 쏠림, 꺾으면 안쪽으로)
static func acc_lean(T: Dictionary, acc_f, acc_s) -> void:
	var L: Dictionary = C.FIGURE_ACC_LEAN
	var af: float = acc_f if (acc_f != null and is_finite(acc_f)) else 0.0
	var a_s: float = acc_s if (acc_s != null and is_finite(acc_s)) else 0.0
	T.waistPitch += clampf(absf(af) * L.fwd, -L["max"], L["max"])
	T.waistSide += clampf(a_s * L.side, -L["max"], L["max"])


# 평소 버릇 (kind = FIGURE_IDLE[char].kind, u = 0~1 진행, s = 시작부터 초, form = 바드 폼)
static func idle_pose(T: Dictionary, kind: String, u: float, s: float, form = null) -> void:
	var env := sin(PI * minf(1.0, u)) # 스르륵 들어갔다 나옴
	var k := minf(1.0, env * 2.5)
	var P := {}
	match kind:
		"tap": # 탱크: 오른손을 넘겨 등 방패를 툭툭 (두 번)
			P = {"shFwd": [1.6, null], "shOut": [0.9, null], "elbow": [2.3 + maxf(0.0, sin(s * 16.0)) * 0.35, null], "neckPitch": 0.15}
		"twirl": # 닌자: 오른손 앞에서 손목째 빙글빙글 (단검 돌리기), 고개는 손을 봄
			P = {"shFwd": [0.75 + sin(s * 18.0) * 0.18, null], "shOut": [0.35 + cos(s * 18.0) * 0.18, null], "elbow": [1.5, null], "neckPitch": 0.3}
		"shoulder": # 건축가: 망치를 어깨에 척 올리고 한 번 툭 (튕김)
			P = {"shFwd": [0.4, null], "shOut": [0.6, null], "elbow": [1.95 + maxf(0.0, sin(s * 9.0)) * 0.2 * (1.0 if u > 0.4 else 0.0), null], "waistSide": -0.06}
		"polish": # 갈고리: 갈고리 든 팔을 앞으로, 다른 손으로 문질러 닦음, 고개 숙여 봄
			P = {"shFwd": [0.85, 0.75], "shOut": [0.05 + sin(s * 14.0) * 0.18, 0.1], "elbow": [1.5, 1.55], "neckPitch": 0.4, "waistPitch": 0.1}
		"fiddle": # 대포수: 왼손으로 어깨 위 포탄을 만지작 (오른손은 대포를 받친 채)
			P = {"shFwd": [null, 1.2], "shOut": [null, 0.6 + sin(s * 11.0) * 0.12], "elbow": [null, 2.0 + sin(s * 13.0) * 0.2], "neckPitch": 0.2, "waistSide": 0.08}
		"flex": # 광전사: 앞 절반은 두 팔 힘주며 씩씩 (어깨 들썩), 뒤 절반은 목을 좌우로 꺾음
			var breath := maxf(0.0, sin(s * 9.0))
			if u < 0.55:
				P = {"shFwd": [0.3, 0.3], "shOut": [1.15, 1.15], "elbow": [1.9, 1.9], "waistPitch": 0.15 + breath * 0.12, "neckPitch": -0.1}
			else:
				P = {"waistSide": (1.0 if u < 0.75 else -1.0) * 0.28, "neckPitch": 0.1}
		"pluck": # 바드: 오른손으로 줄을 툭 튕기고 고개를 까딱 (악기 든 자세 위)
			P = {"elbow": [1.5 + maxf(0.0, sin(s * 20.0)) * 0.7, null], "shOut": [0.3 + maxf(0.0, sin(s * 20.0)) * 0.25, null], "neckPitch": sin(s * 10.0) * 0.3 + (0.15 if form == "metal" else 0.0)}
	overlay_t(T, P, k)
