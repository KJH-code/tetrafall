# 몸 자세 계산 (client/figure.js 의 순수 부분 옮김): 기본 자세·관절 스프링·맞은 자세·휘청 스프링·공격 동작 덮어쓰기·도발/승리 포즈 시간 축
# 고도 노드 없음. 테스트 tests/test_chars.gd 가 JS 정답 figure_motion.json 과 비교. 자세 표 (MOVES·BROKEN·POSES) 는 만든 파일 moves.gd
# 자세 P: { waistPitch, waistRoll, waistSide, neckPitch, hipsZ, shFwd[2], shOut[2], shTwist[2], elbow[2], thFwd[2], thOut[2], knee[2] } ([오른쪽, 왼쪽])
extends RefCounted

const C := preload("res://core/config.gd")
const Moves := preload("res://chars/moves.gd")

# 관절 무리별 스프링 (FIGURE_SPRING: w 빠르기 /초, damp 감쇠비)
const SPRING_GROUP := {"waistPitch": "body", "waistRoll": "body", "waistSide": "body", "hipsZ": "body", "neckPitch": "neck", "shFwd": "arm", "shOut": "arm", "shTwist": "arm", "elbow": "arm", "thFwd": "leg", "thOut": "leg", "knee": "leg"}


static func ease01(u: float) -> float:
	var x := clampf(u, 0.0, 1.0)
	return x * x * (3.0 - 2.0 * x)


# d = 체형 (FIGURE_BODIES 한 줄: hunch·spread·bend …)
static func rest_pose(d: Dictionary) -> Dictionary:
	var bend: float = d.get("bend", 0.0)
	return {
		"waistPitch": d.hunch,
		"waistRoll": 0.0,
		"waistSide": 0.0,
		"neckPitch": -d.hunch,
		"hipsZ": 0.0,
		"shFwd": [0.0, 0.0],
		"shOut": [d.spread, d.spread],
		"shTwist": [0.0, 0.0],
		"elbow": [0.15, 0.15],
		"thFwd": [bend * 0.5, bend * 0.5],
		"thOut": [0.0, 0.0],
		"knee": [bend, bend],
	}


static func zero_pose(P: Dictionary) -> Dictionary:
	var V := {}
	for k in P:
		V[k] = [0.0, 0.0] if P[k] is Array else 0.0
	return V


static func _spring_one(x: float, v: float, tg: float, n: int, h: float, kk: float, c: float) -> Array:
	for j in n:
		v += (kk * (tg - x) - c * v) * h
		x += v * h
	return [x, v]


# P 를 T 쪽으로 스프링으로 (속도 V). 작은 걸음으로 나눠 안정하게
static func spring_pose(P: Dictionary, V: Dictionary, T: Dictionary, dt: float, fast: float = 1.0) -> void:
	var n := maxi(1, ceili(dt / C.FIGURE_SPRING_STEP))
	var h := dt / n
	for key in T:
		if not V.has(key):
			V[key] = [0.0, 0.0] if T[key] is Array else 0.0
		var sp: Dictionary = C.FIGURE_SPRING[SPRING_GROUP.get(key, "body")]
		var w: float = sp.w * fast
		var kk := w * w
		var c: float = 2.0 * sp.damp * w
		if T[key] is Array:
			for i in T[key].size():
				var r := _spring_one(P[key][i], V[key][i], T[key][i], n, h, kk, c)
				P[key][i] = r[0]
				V[key][i] = r[1]
		else:
			var r := _spring_one(P[key], V[key], T[key], n, h, kk, c)
			P[key] = r[0]
			V[key] = r[1]


# 맞은 순간 자세 (히트스톱 동안 이대로 멈칫). dx·dy = 밀려나는 방향 (몸 기준, 앞 +x 왼쪽 +y), power = 세기
static func hit_pose(T: Dictionary, dx: float, dy: float, power: float) -> void:
	var fling := minf(1.6, 0.9 * power)
	T.shFwd = [-dx * fling + 0.3, -dx * fling + 0.3]
	T.shOut = [0.9 + 0.4 * power + dy * 0.5, 0.9 + 0.4 * power - dy * 0.5]
	T.elbow = [0.5, 0.5]
	T.thFwd = [-dx * 0.4 * power + 0.2, -dx * 0.2 * power]
	T.thOut = [maxf(0.0, -dy) * 0.4, maxf(0.0, dy) * 0.4]
	T.knee = [0.6, 0.3]
	T.neckPitch = -dx * 0.35 * power
	T.waistRoll = dy * 0.3


# 휘청 스프링 (허리 앞뒤·좌우 각). sw = { x, y, vx, vy }
static func step_sway(sw: Dictionary, dt: float) -> void:
	var n := maxi(1, ceili(dt / 0.01))
	var h := dt / n
	for i in n:
		for pair in [["x", "vx"], ["y", "vy"]]:
			sw[pair[1]] += (-C.FIGURE_HIT_SPRING_K * sw[pair[0]] - C.FIGURE_HIT_SPRING_DAMP * sw[pair[1]]) * h
			sw[pair[0]] += sw[pair[1]] * h


# 공격·포즈 자세를 P 에 바로 덮어씀 (w = 0~1 섞는 정도). crouch 는 T 의 다리에서 두 무릎을 더 굽힘. V (관절 속도) 는 덮어쓴 만큼 줄임
static func overlay(P: Dictionary, T: Dictionary, pose, w: float, V = null) -> void:
	if pose == null or w <= 0.0:
		return
	var keep := 1.0 - minf(1.0, w)
	var crouch = pose.get("crouch")
	if crouch:
		for i in 2:
			P.thFwd[i] += (T.thFwd[i] + 0.9 * crouch - P.thFwd[i]) * w
			P.knee[i] += (T.knee[i] + 1.6 * crouch - P.knee[i]) * w
			if V != null:
				V.thFwd[i] *= keep
				V.knee[i] *= keep
	for key in pose:
		var val = pose[key]
		if val == null or not P.has(key):
			continue
		if val is Array:
			for i in val.size():
				if val[i] == null:
					continue
				P[key][i] += (val[i] - P[key][i]) * w
				if V != null:
					V[key][i] *= keep
		elif val is float or val is int:
			P[key] += (val - P[key]) * w
			if V != null:
				V[key] *= keep


static func _wob(t: float, hz: float, a: float) -> float:
	return sin(t * hz * PI * 2.0) * a


# 도발·승리 포즈의 작은 반복 (figure.js POSES 의 loop(t)). who = 캐릭터 또는 'metal', kind = 'taunt'|'victory'. [값, null] 은 한쪽만
static func pose_loop(who: String, kind: String, t: float) -> Dictionary:
	match who + "/" + kind:
		"tank/taunt":
			return {"shFwd": [0.9 + maxf(0.0, _wob(t, 2.2, 0.6)), null], "elbow": [1.9 - maxf(0.0, _wob(t, 2.2, 0.7)), null]}
		"tank/victory":
			return {"neckPitch": -0.5 + maxf(0.0, _wob(t, 0.9, 0.2))}
		"ninja/taunt":
			return {"elbow": [1.95 + _wob(t, 3.0, 0.08), 1.95 - _wob(t, 3.0, 0.08)]}
		"ninja/victory":
			return {"neckPitch": 0.3 + _wob(t, 0.5, 0.05)}
		"builder/taunt":
			return {"neckPitch": -0.1 + maxf(0.0, _wob(t, 1.6, 0.25))}
		"builder/victory":
			return {"shFwd": [2.85 + _wob(t, 1.4, 0.18), null], "elbow": [0.25 - _wob(t, 1.4, 0.15), null]}
		"hook/taunt":
			return {"elbow": [null, 1.0 + maxf(0.0, _wob(t, 2.4, 0.75))]}
		"hook/victory":
			return {"shFwd": [2.95 + _wob(t, 0.8, 0.12), null]}
		"hunter/taunt":
			return {"shFwd": [1.6 + _wob(t, 3.0, 0.05), null]}
		"hunter/victory":
			return {"waistRoll": _wob(t, 0.35, 0.35)}
		"cannon/taunt":
			return {"shOut": [1.75, 2.5 + maxf(0.0, _wob(t, 2.5, 0.35))]}
		"cannon/victory":
			return {"waistPitch": -0.35 + absf(_wob(t, 2.2, 0.12)), "neckPitch": -0.3 - absf(_wob(t, 2.2, 0.12))}
		"berserker/taunt":
			return {"elbow": [1.6 + _wob(t, 9.0, 0.07), 1.6 - _wob(t, 9.0, 0.07)], "neckPitch": -0.55 + _wob(t, 7.0, 0.04)}
		"berserker/victory":
			return {"shFwd": [2.9 + maxf(0.0, _wob(t, 1.2, 0.2)), null], "elbow": [null, 1.9 + _wob(t, 8.0, 0.06)], "neckPitch": -0.5 + _wob(t, 6.0, 0.04)}
		"bard/taunt":
			return {"elbow": [0.2 + maxf(0.0, _wob(t, 1.5, 0.35)), null]}
		"bard/victory":
			return {"shFwd": [0.55 + _wob(t, 4.0, 0.35), null], "elbow": [1.5 + _wob(t, 4.0, 0.6), null], "waistPitch": -0.7 + absf(_wob(t, 1.0, 0.15)), "neckPitch": -0.4 - absf(_wob(t, 1.0, 0.25)), "waistSide": _wob(t, 0.5, 0.12)}
		"metal/taunt":
			return {"neckPitch": -0.3 + maxf(0.0, _wob(t, 2.5, 0.7)), "waistPitch": -0.2 + maxf(0.0, _wob(t, 2.5, 0.2))}
		"metal/victory":
			return {"elbow": [1.6 + _wob(t, 7.0, 0.3), null], "neckPitch": -0.5 + maxf(0.0, _wob(t, 2.2, 0.75))}
	return {}


# loop 의 [값, null] (한쪽만) 이 S 의 다른 쪽을 지우지 않게
static func merge_sides(S: Dictionary, add: Dictionary) -> Dictionary:
	var out := {}
	for k in add:
		var v = add[k]
		if v is Array and S.get(k) is Array:
			out[k] = [S[k][0] if v[0] == null else v[0], S[k][1] if v[1] == null else v[1]]
		else:
			out[k] = v
	return out


# 도발·승리 포즈 시간 축: t = 시작부터 초, end = 끝나는 초 (승리는 INF = 결정 포즈 유지). who/kind 로 POSES 표와 loop 를 고름
static func pose_at(P: Dictionary, T: Dictionary, V, who: String, kind: String, t: float, end: float) -> void:
	var set_: Dictionary = Moves.POSES[who][kind]
	var tin: float = C.POSE_IN_S
	var tsnap: float = tin + C.POSE_SNAP_S
	if t < tin:
		overlay(P, T, set_.W, ease01(t / tin), V)
		return
	var S: Dictionary = set_.S
	if set_.loop and t >= tsnap:
		S = S.duplicate()
		S.merge(merge_sides(set_.S, pose_loop(who, kind, t - tsnap)), true)
	var out := 1.0 - ease01((t - (end - C.POSE_OUT_S)) / C.POSE_OUT_S) if is_finite(end) else 1.0
	if t < tsnap:
		var u := (t - tin) / C.POSE_SNAP_S
		overlay(P, T, set_.W, 1.0 - u, V)
		overlay(P, T, S, ease01(u), V)
	else:
		overlay(P, T, S, minf(1.0, out), V)
