# W49 NaN 원인 후보 훑기 (재연에서 안 나오는 깨짐을 입력 쪽에서 만들어 봄): 몸 상태 (st) 의 숫자 칸마다 NaN·inf·0·큰 값을 넣고, 몸 노드 크기를 0·0.001 로 하고,
# 시간 간격을 0·극소·큰 값으로 해서 Ext.sync 를 돌린 뒤 뼈가 깨졌는지 (유한하지 않음·크기 0) 를 본다. 깨지면 '입력 → 처음 깨진 단계·뼈' 를 찍음.
# godot --headless --path godot/client -s res://tools/nan_fuzz.gd -- [캐릭터 ,로, 기본 4명]
extends SceneTree

const Motion_ := preload("res://chars/ext_motion.gd")

var hits := {}
var cur_done := {}
var cur := ""
var T


func _initialize() -> void:
	_run.call_deferred()


func _probe(X, stage: String) -> void:
	if stage.begins_with("add_rot_skip:"):
		_note("add_rot 건너뜀 (%s)" % stage.substr(13), stage)
		return
	var bad: Dictionary = load("res://tools/nan_hunt.gd").scan_bones(X)
	if not bad.is_empty():
		_note("%s: %s" % [bad.bone, bad.what], stage)


# 시험 하나 (cur) 에서 처음 깨진 단계만 적음 (뒤 단계는 같은 깨짐이 이어진 것)
func _note(what: String, stage: String) -> void:
	if cur_done.has(cur):
		return
	cur_done[cur] = true
	hits["%s | 처음 깨진 단계 %s | %s" % [cur, stage, what]] = 1


func _run() -> void:
	T = load("res://tests/test_w49.gd").new()
	var a := OS.get_cmdline_user_args()
	var chars: PackedStringArray = (a[0] if a.size() > 0 else "ninja,tank,hunter,hook").split(",")
	Motion_.probe = Callable(self, "_probe")
	var vals := {"nan": NAN, "inf": INF, "-inf": -INF, "0": 0.0, "1e9": 1e9, "-1e9": -1e9}
	var keys := ["hs", "walk", "vz", "t", "recover", "land", "tumble", "accF", "accS", "mvF", "mvS", "idle", "airDash", "dizzy", "whirl", "flip", "victory"]
	for ch in chars:
		var b = T._body(ch)
		var X = b.ext
		if X == null:
			b.free()
			continue
		# 몸 상태 숫자 칸
		for k in keys:
			for vn in vals:
				cur = "%s st.%s=%s" % [ch, k, vn]
				for st0 in [T._walk(0.7, 0.7, true), T._st({"hit": {"id": 1, "age": 0.05, "stop": 0.0, "dx": -1.0, "dy": 0.0, "pow": 2.0}}), T._st({"land": 0.9, "air": false})]:
					var st: Dictionary = st0.duplicate(true)
					st[k] = vals[vn]
					for i in 6:
						T._step(X, st)
				_reset(X)
		# 맞음 값
		for k2 in ["age", "dx", "dy", "pow"]:
			for vn in vals:
				cur = "%s hit.%s=%s" % [ch, k2, vn]
				var hit := {"id": 1, "age": 0.05, "stop": 0.0, "dx": -0.6, "dy": 0.8, "pow": 2.0}
				hit[k2] = vals[vn]
				for i in 6:
					T._step(X, T._st({"hit": hit}))
				_reset(X)
		# 속도 벡터
		for vn in vals:
			cur = "%s st.vw=Vector2(%s)" % [ch, vn]
			for i in 6:
				T._step(X, T._st({"walking": true, "hs": 4.0, "mvF": 4.0, "vw": Vector2(vals[vn], vals[vn])}))
			_reset(X)
		# 몸 노드 크기·시간 간격
		for sc in [0.0, 0.001, 1e-5, -1.0]:
			cur = "%s body.scale=%s" % [ch, str(sc)]
			b.scale = Vector3.ONE * sc
			for i in 8:
				T._step(X, T._walk(0.5, 0.5, true))
				T._step(X, T._st({"hit": {"id": 2, "age": 0.04, "stop": 0.0, "dx": -1.0, "dy": 0.0, "pow": 2.0}}))
			b.scale = Vector3.ONE
			_reset(X)
		for gap in [0.0, 1e-7, 1e-4, 0.5, 100.0]:
			cur = "%s 프레임 간격=%s" % [ch, str(gap)]
			for i in 12:
				var now := Time.get_ticks_msec() * 0.001
				X.cloth_t = now - gap
				X.extra_t = now - gap
				X.last_t = now - gap
				X.sync(T._walk(0.7, 0.7, true))
			_reset(X)
		b.free()
	Motion_.probe = Callable()
	print("== NaN 훑기 결과: 깨진 조합 %d" % hits.size())
	for k in hits:
		print("  ", k, " x", hits[k])
	quit()


func _reset(X) -> void:
	# 깨진 몸을 다음 시험에 끌고 가지 않게: 뼈 자세를 쉬는 자세로
	var rl: Array = X.info.rest_local
	for i in X.sk.get_bone_count():
		var t: Transform3D = rl[i]
		X.sk.set_bone_pose_position(i, t.origin)
		X.sk.set_bone_pose_rotation(i, t.basis.get_rotation_quaternion())
		X.sk.set_bone_pose_scale(i, Vector3.ONE)
	X.dir_y = 0.0
	X.lean_p = 0.0
	X.turn_tw = 0.0
	X.gaze_w = 0.0
	X.gaze_y = 0.0
	X.weapon_w = 0.0
	X.weapon_st.clear()
	X.getup_t = -1.0
	for cl in X.cloths:
		cl.ready = false
		cl.last_q.clear()
