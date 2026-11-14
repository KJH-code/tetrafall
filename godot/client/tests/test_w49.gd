# W49 모션 설정 (런타임 A/B): 가산 층 플래그 표·프리셋·인자 합집합·설정 저장/복원·꺼진 층 비용 0·판 중 토글 안전·모든 조합 순회
extends RefCounted

const Body := preload("res://chars/body.gd")
const Ext := preload("res://chars/external.gd")
const M := preload("res://chars/ext_motion.gd")
const K := preload("res://chars/chars_config.gd")
const C := preload("res://core/config.gd")
const Opts := preload("res://core/opts.gd")
const ViewS := preload("res://core/view.gd")

var errors: Array = []
const CHARS := ["ninja", "tank", "hunter", "hook"]


func check(cond: bool, msg: String) -> void:
	if not cond:
		errors.append(msg)


func _reset() -> void: # 정적 상태를 기본으로 (다른 테스트에 안 남김)
	Opts.override = null
	K.set_flags(null)
	K.refresh()


func _body(ch: String):
	var was: bool = Body.use_ext
	Body.use_ext = true
	var b = Body.new()
	b.build(ch, Color(0.2, 0.5, 1.0), true)
	Body.use_ext = was
	return b


static func _st(over := {}) -> Dictionary:
	var st := {"air": false, "walking": false, "hs": 0.0, "walk": 0.0, "vz": 0.0, "t": 1.0, "stunned": false, "emote": -1, "victory": -1.0, "hit": null, "act": null,
		"tumble": 0.0, "recover": 0.0, "land": 0.0, "flip": -1.0, "idle": 0.0, "airDash": 0.0, "dizzy": 0.0, "whirl": -1.0, "glide": false,
		"accF": 0.0, "accS": 0.0, "mvF": 0.0, "mvS": 0.0, "vw": Vector2.ZERO}
	st.merge(over, true)
	return st


static func _walk(f: float, s: float, run := false) -> Dictionary:
	var v: float = C.MOVE_SPEED * (1.0 if run else 0.6)
	return _st({"walking": true, "hs": v, "walk": 1.1, "mvF": v * f, "mvS": v * s, "vw": Vector2(v * f, v * s)})


func _step(X, st: Dictionary) -> void:
	var now := Time.get_ticks_msec() * 0.001
	X.cloth_t = now - 1.0 / 60.0
	X.extra_t = now - 1.0 / 60.0
	X.last_t = now - 1.0 / 60.0
	X.sync(st)


static func _gq(sk: Skeleton3D, nm: String) -> Quaternion:
	var b := sk.find_bone(nm)
	var t := Transform3D.IDENTITY
	while b >= 0:
		t = sk.get_bone_pose(b) * t
		b = sk.get_bone_parent(b)
	return t.basis.get_rotation_quaternion()


# 뼈 지역 자세가 모두 유한하고 크기가 0 이 아님
static func _sane(sk: Skeleton3D) -> bool:
	for i in sk.get_bone_count():
		var q := sk.get_bone_pose_rotation(i)
		var sc := sk.get_bone_pose_scale(i)
		var p := sk.get_bone_pose_position(i)
		if not (is_finite(q.x + q.y + q.z + q.w) and is_finite(sc.x + sc.y + sc.z) and is_finite(p.x + p.y + p.z)):
			return false
		if sc.x < 1e-3 or sc.y < 1e-3 or sc.z < 1e-3 or absf(q.length() - 1.0) > 1e-2:
			return false
	return true


# ---------- 표 ----------

func test_flag_table_and_presets() -> void:
	_reset()
	var names: Array = K.EXT_MOTION_FLAGS.keys()
	check(names.size() == 10, "플래그 10개 (%d)" % names.size())
	check(K.EXT_MOTION_LABELS.keys().size() == 10 and K.EXT_MOTION_LABELS.keys().all(func(k): return names.has(k)), "글 표가 플래그와 같은 이름")
	check(K.EXT_MOTION_FLAGS.values().all(func(v): return v == true), "기본은 모두 켜짐 (지금 동작 그대로)")
	for pn in ["new", "old", "min"]:
		var pr: Dictionary = K.EXT_MOTION_PRESETS[pn]
		check(pr.keys().size() == names.size() and names.all(func(n): return pr.has(n)), "%s 프리셋이 모든 플래그 값을 가짐" % pn)
	check(K.EXT_MOTION_PRESETS["new"] == K.EXT_MOTION_FLAGS, "새 모션 = 표 기본값")
	var old: Dictionary = K.EXT_MOTION_PRESETS["old"]
	check(not old.gait_new and not old.dir and not old.lean and not old.getup and not old.weapon and not old.vm_arm, "옛 모션: 걸음 새값·W43 가산·1인칭 클립 팔 끔")
	check(old.cloth and old.gaze and old.land_breath and old.hit_dir, "옛 모션: W40 가산·천 (W44 수정 포함) 은 유지")
	check(K.EXT_MOTION_PRESETS["min"].values().all(func(v): return v == false), "최소: 가산 층 전부 끔")
	check(K.preset_of(K.preset_flags("new")) == "new" and K.preset_of(K.preset_flags("old")) == "old" and K.preset_of(K.preset_flags("min")) == "min", "프리셋 ↔ 이름 왕복")
	var custom := K.preset_flags("new")
	custom.gaze = false
	check(K.preset_of(custom) == "custom" and K.preset_of(null) == "new", "한 칸만 바꾸면 직접 고름, 값이 없으면 새 모션")
	check(K.toggled_preset(K.preset_flags("new")) == "old" and K.toggled_preset(K.preset_flags("old")) == "new" and K.toggled_preset(custom) == "new" and K.toggled_preset(K.preset_flags("min")) == "new", "단축키: 새 → 옛, 그 밖 → 새")
	check(K.EXT_MOTION_PRESET_NAMES["new"] == "새 모션 (기본)" and K.EXT_MOTION_PRESET_NAMES["old"] == "옛 모션 (v0.1.17 이전)" and K.EXT_MOTION_PRESET_NAMES["min"] == "최소 (코드 자세만)", "프리셋 이름")


# 설정 값 · 실행 인자 (끄는 쪽 합집합, 인자가 우선) · 웹 주소 인자 (Opts 한 길)
func test_flag_sources() -> void:
	_reset()
	check(K.flag("dir") and K.flag("gait_new") and K.flag("vm_arm"), "기본은 켜짐")
	K.set_flags({"dir": false, "gaze": false, "bogus": false})
	check(not K.flag("dir") and not K.flag("gaze") and K.flag("lean"), "설정이 끈 것만 꺼짐, 모르는 이름은 버림")
	Opts.override = PackedStringArray(["--no-w43"])
	K.refresh()
	check(not K.flag("dir") and not K.flag("lean") and not K.flag("getup") and not K.flag("weapon") and K.flag("cloth"), "--no-w43 = W43 넷")
	K.set_flags(null)
	K.refresh()
	check(not K.flag("dir") and K.arg_off_names() == ["dir", "lean", "getup", "weapon"], "설정이 켜도 인자가 끈 건 꺼짐 (합집합), 설정 창 안내 목록 %s" % str(K.arg_off_names()))
	Opts.override = PackedStringArray(["--old-gait", "--no-gaze", "--no-land-breath"])
	K.refresh()
	check(not K.flag("gait_new") and not K.flag("gaze") and not K.flag("land_breath") and K.flag("dir"), "--old-gait·--no-gaze·--no-land-breath")
	Opts.override = PackedStringArray(["--motion", "old"])
	K.refresh()
	check(K.arg_off_names() == ["gait_new", "dir", "lean", "getup", "weapon", "vm_arm"], "--motion old = 옛 모션 프리셋이 끈 것 %s" % str(K.arg_off_names()))
	Opts.override = PackedStringArray(["--motion", "min"])
	K.refresh()
	check(K.arg_off_names().size() == 10, "--motion min = 전부")
	Opts.override = PackedStringArray(["--motion", "new", "--motion-x"])
	K.refresh()
	check(K.arg_off_names().is_empty(), "--motion new·모르는 인자는 아무것도 안 끔")
	Opts.web_override = true # 웹: 주소 ?old-gait=1 → ["--old-gait"] 와 같은 모양 (Opts.args), 같은 플래그
	Opts.override = PackedStringArray(["--old-gait"])
	K.refresh()
	check(not K.flag("gait_new") and K.old_gait(), "웹 인자도 같은 길")
	Opts.web_override = null
	_reset()
	check(K.flag("gait_new") and not K.old_gait(), "비운 뒤 기본")


# 옛 걸음 값 (EXT_GAIT_OLD) 은 gait_new 플래그가 끄면 인자 없이도 나옴
func test_gait_flag_gives_old_values() -> void:
	_reset()
	var cc: Dictionary = Ext.read_cfg("ninja").get("clips", {})
	var new_run = K.stride_of(cc, "run")
	check(new_run == [1.0, -0.14, 0.5], "기본 닌자 달리기 stride 새 값 %s" % str(new_run))
	K.set_flags({"gait_new": false})
	check(K.old_gait() and K.stride_of(cc, "run") == [1.45, -0.14, 1.6] and K.dir_gain() == 0.6 and K.dir_counter().is_empty(), "gait_new 꺼짐 = 옛 걸음")
	_reset()


# 설정 저장·복원: 저장 파일 (JSON) → 정리 → 같은 값, 빠진 이름은 켬, 모르는 이름·값 모양이 틀려도 안 죽음
func test_settings_roundtrip() -> void:
	_reset()
	var d := K.preset_flags("old")
	var back = JSON.parse_string(JSON.stringify(d))
	var cl: Dictionary = ViewS._clean_motion(back)
	check(cl == d and K.preset_of(cl) == "old", "옛 모션 저장 → 복원")
	check(ViewS._clean_motion(null) == K.EXT_MOTION_FLAGS and ViewS._clean_motion("x") == K.EXT_MOTION_FLAGS and ViewS._clean_motion([1]) == K.EXT_MOTION_FLAGS, "값이 없거나 모양이 틀리면 기본 (모두 켬)")
	var partial: Dictionary = ViewS._clean_motion({"dir": false, "junk": 1})
	check(not partial.dir and partial.lean and not partial.has("junk") and partial.size() == 10, "빠진 이름은 켬, 모르는 이름은 버림")
	check(FileAccess.get_file_as_string("res://core/view.gd").contains("\"motionFlags\""), "View 기본 설정에 motionFlags")
	_reset()


# ---------- 몸 ----------

# 꺼진 가산 층은 상태가 0 에 머물고 계산을 안 함 (비용 0), 켜면 움직임
func test_off_layers_stay_idle() -> void:
	for ch in CHARS:
		_reset()
		var b = _body(ch)
		var X = b.ext
		if X == null:
			b.free()
			continue
		K.set_flags(K.preset_flags("min"))
		for i in 80:
			_step(X, _walk(0.0, 1.0, true))
		check(X.dir_y == 0.0 and X.lean_p == 0.0 and X.turn_tw == 0.0, "%s 최소: 방향·기울임 상태 0 (%f %f)" % [ch, X.dir_y, X.lean_p])
		check(X.weapon_w == 0.0 and X.weapon_st.is_empty(), "%s 최소: 무기 상태 비어 있음" % ch)
		check(X.gaze_w == 0.0 and X.breath_w == 0.0 and X.getup_t < 0.0, "%s 최소: 시선·숨쉬기·일어나기 0" % ch)
		for cl in X.cloths:
			check(not cl.ready, "%s 최소: 천 계산 안 함" % ch)
		check(X.cloth_rested or X.cloths.is_empty(), "%s 천이 쉬는 자세로 돌아와 멈춤" % ch)
		K.set_flags(null)
		for i in 80:
			_step(X, _walk(0.0, 1.0, true))
		check(absf(X.dir_y) > 0.1 and absf(X.lean_p) > 0.01, "%s 켜면 방향·기울임이 들어감 (%f %f)" % [ch, X.dir_y, X.lean_p])
		check(X.cloths.is_empty() or X.cloths[0].ready, "%s 천 다시 켬" % ch)
		b.free()
	_reset()


# 판 중 토글: 같은 걸음에서 프리셋을 바꿔 (새 → 옛 → 새 → 최소 → 새) 가도 한 프레임 뼈 회전이 안 튄다 (바꾸지 않은 같은 걸음의 최대 + 여유 안),
# 가산 층 (방향·기울임·무기·시선) 은 follow 로 서서히 풀리고 천은 쉬는 자세로 부드럽게. 걸음 박자 (gait_new) 는 클립 속도가 바뀌어 한 번 발 위상이 어긋남 — 그 몫이 여유
func _walk_worst(X, seq: Array) -> float:
	var bones := ["mixamorig_Hips", "mixamorig_Spine2", "mixamorig_LeftUpLeg", "mixamorig_RightUpLeg", "mixamorig_LeftArm", "mixamorig_RightHand"]
	var prev := {}
	var worst := 0.0
	var n := 0
	for pn in seq:
		K.set_flags(K.preset_flags(pn))
		for i in 70:
			_step(X, _walk(0.3, 1.0, true))
			for bn in bones:
				var q := _gq(X.sk, bn)
				if n > 3 and prev.has(bn):
					worst = maxf(worst, rad_to_deg(q.angle_to(prev[bn])))
				prev[bn] = q
			n += 1
		if not _sane(X.sk):
			return 999.0
	return worst


func test_toggle_midway_is_smooth() -> void:
	for ch in CHARS:
		_reset()
		var b0 = _body(ch)
		var base := _walk_worst(b0.ext, ["new", "new", "new", "new", "new"])
		b0.free()
		_reset()
		var b = _body(ch)
		var worst := _walk_worst(b.ext, ["new", "old", "new", "min", "new"])
		check(worst < base + 14.0, "%s 새↔옛↔최소 왕복 한 프레임 최대 뼈 회전 %.1f° (토글 없이 %.1f°)" % [ch, worst, base])
		b.free()
	_reset()


# 맞음 방향별 움찔: 같은 맞음 상태로 켠 몸과 끈 몸을 비교 — 옆에서 맞으면 (dy) 비틂·기울기 몫이 달라지고, 정면에서 맞으면 (뒤로 젖힘만) 같음
func test_hit_dir_flag() -> void:
	_reset()
	var b = _body("hunter")
	var X = b.ext
	var diff := func(hit_st: Dictionary) -> float:
		var out := []
		for on in [false, true]:
			K.set_flags(null if on else {"hit_dir": false})
			for i in 4:
				_step(X, _st())
			_step(X, hit_st)
			out.append(_gq(X.sk, "mixamorig_Spine2"))
		return rad_to_deg((out[0] as Quaternion).angle_to(out[1]))
	var side: float = diff.call(_st({"hit": {"id": 1, "age": 0.05, "stop": 0.0, "dx": 0.0, "dy": 1.0, "pow": 1.5}}))
	var front: float = diff.call(_st({"hit": {"id": 2, "age": 0.05, "stop": 0.0, "dx": -1.0, "dy": 0.0, "pow": 1.5}}))
	check(side > 1.0, "옆 맞음: 켜면 윗몸이 더 돌아감 (%f°)" % side)
	check(front < 2.0 and front < side * 0.5, "정면 맞음: 켜도 끄도 같음 (뒤로 젖힘만, %f°)" % front)
	b.free()
	_reset()


# 모든 조합 (전부 켬·전부 끔·하나씩 끔·프리셋 셋 = 14개) × 4명 × 여러 상태: 뼈가 늘 멀쩡 (NaN·영 스케일 없음), 크래시 없음
func test_all_combinations_sane() -> void:
	var combos := [{"name": "전부 켬", "f": K.preset_flags("new")}, {"name": "전부 끔", "f": K.preset_flags("min")}, {"name": "옛", "f": K.preset_flags("old")}]
	for n in K.EXT_MOTION_FLAGS:
		var f := K.preset_flags("new")
		f[n] = false
		combos.append({"name": n + " 끔", "f": f})
	check(combos.size() == 13, "조합 13개 (%d)" % combos.size())
	var states := [
		_st(), _walk(1.0, 0.0), _walk(0.0, 1.0, true), _walk(-1.0, 0.0), _walk(0.7, -0.7, true),
		_st({"hit": {"id": 1, "age": 0.03, "stop": 0.0, "dx": -1.0, "dy": 0.0, "pow": 2.0}}),
		_st({"hit": {"id": 2, "age": 0.1, "stop": 0.0, "dx": 0.5, "dy": -1.0, "pow": 1.0}}),
		_st({"land": 0.8}), _st({"recover": 0.6}), _st({"stunned": true}), _st({"air": true, "vz": 3.0}), _st({"idle": 3.0}),
	]
	for ch in CHARS:
		var b = _body(ch)
		var X = b.ext
		if X == null:
			b.free()
			continue
		for cb in combos:
			_reset()
			K.set_flags(cb.f)
			for st in states:
				for i in 24:
					var s2: Dictionary = st.duplicate(true)
					if s2.get("hit") is Dictionary:
						s2.hit.age = float(s2.hit.age) + i / 60.0
					_step(X, s2)
				if not _sane(X.sk):
					check(false, "%s [%s] 뼈 자세가 깨짐 (NaN·영 스케일)" % [ch, cb.name])
					break
		b.free()
	_reset()


# ---------- NaN 원인 (tools/nan_hunt.gd·nan_fuzz.gd 로 찾음) ----------
# 원인: 가산 층 (_hit_flinch·숨쉬기 …) 이 깨진 입력 (NaN·inf, 또는 맞은 지 −10.6초보다 오래: exp(−age/0.015) 가 INF 가 되어 (1−INF)·INF = NaN) 으로 회전을 셈해
# _add_rot 가 그 NaN 을 척추 뼈 회전에 씀 → 자식 뼈의 _add_rot 은 부모 전역 basis 가 NaN 이라 경고 (W47 은 이 경고만 막았음). 입구에서 막음.

var _probe_events: Array = []


func _on_probe(_X, stage: String) -> void:
	if stage.begins_with("add_rot_skip") or stage.begins_with("add_rot_bad_input"):
		_probe_events.append(stage)


func test_nan_math_fact_and_helpers() -> void:
	var age := -11.0 # 시계가 바뀌면 (재연 가상 시계·반복 재생) 맞은 지 음수가 됨
	var env := (1.0 - exp(-age / 0.015)) * exp(-age / K.EXT_HIT_FLINCH_DECAY_S)
	check(not is_finite(env), "고침 전 식: 맞은 지 −11초면 움찔 세기가 유한하지 않음 (%s)" % str(env))
	check(M.fin(NAN) == 0.0 and M.fin(INF, 1.0) == 1.0 and M.fin(2.5) == 2.5, "fin")
	check(M.quat_ok(Quaternion.IDENTITY) and not M.quat_ok(Quaternion(NAN, 0, 0, 1)) and not M.quat_ok(Quaternion(0, 0, 0, 0)) and not M.quat_ok(Quaternion(INF, 0, 0, 1)), "quat_ok")
	var r: Dictionary = M.hit_react({"dx": NAN, "dy": INF, "pow": NAN, "age": 0.1})
	check(is_finite(float(r.back)) and is_finite(float(r.side)) and is_finite(float(r.twist)), "깨진 맞음 값도 hit_react 는 유한한 값")


func test_broken_inputs_never_write_nan() -> void:
	var cases := []
	for age in [-30.0, -11.0, -1e9, NAN, -INF, INF]:
		cases.append(["hit.age=%s" % str(age), _st({"hit": {"id": 1, "age": age, "stop": 0.0, "dx": -0.6, "dy": 0.8, "pow": 2.0}})])
	for k in ["dx", "dy", "pow"]:
		for v in [NAN, INF, -INF]:
			var h := {"id": 1, "age": 0.05, "stop": 0.0, "dx": -0.6, "dy": 0.8, "pow": 2.0}
			h[k] = v
			cases.append(["hit.%s=%s" % [k, str(v)], _st({"hit": h})])
	for v in [NAN, INF, -INF]:
		cases.append(["st.t=%s" % str(v), _st({"t": v})])
		cases.append(["st.land=%s" % str(v), _st({"land": v})])
	for ch in CHARS:
		var b = _body(ch)
		var X = b.ext
		if X == null:
			b.free()
			continue
		M.probe = Callable(self, "_on_probe")
		for c in cases:
			_probe_events.clear()
			for i in 6:
				_step(X, c[1])
			check(_sane(X.sk), "%s %s: 뼈에 NaN·영 스케일이 안 써짐" % [ch, c[0]])
			check(not _probe_events.any(func(e): return str(e).begins_with("add_rot_skip")), "%s %s: 깨진 부모 뼈 때문에 건너뜀이 없음 (입구에서 막아 NaN 이 안 생김)" % [ch, c[0]])
		M.probe = Callable()
		b.free()
	_reset()


# 맞은 지 음수 (시계 바뀜) 의 움찔은 없음: _hit_flinch 만 따로 불러 척추 회전 변화를 잼 (정상 맞음은 움직이고, 음수·깨진 값은 0)
func test_negative_hit_age_means_no_flinch() -> void:
	_reset()
	var b = _body("tank")
	var X = b.ext
	for i in 4:
		_step(X, _st())
	var flinch := func(age: float) -> float:
		X._reset_extra()
		var q0 := _gq(X.sk, "mixamorig_Spine2")
		X._hit_flinch(_st({"hit": {"id": 1, "age": age, "stop": 0.0, "dx": -1.0, "dy": 0.0, "pow": 2.0}}))
		return rad_to_deg(q0.angle_to(_gq(X.sk, "mixamorig_Spine2")))
	check(float(flinch.call(0.04)) > 1.0, "정상 맞음 (age 0.04) 은 움찔")
	for age in [-30.0, -11.0, -1e9, -INF, NAN]:
		check(float(flinch.call(age)) < 0.01, "age %s 는 움찔 없음" % str(age))
	check(_sane(X.sk), "그 뒤에도 뼈가 멀쩡")
	b.free()
	_reset()


# 몸 월드 크기가 0 (숨김·깨진 찌그러짐) 이어도 천·가산 층이 경고 없이 건너뜀 (테스트 러너는 엔진 오류가 나면 실패로 침)
func test_degenerate_world_scale_is_skipped() -> void:
	for ch in CHARS:
		_reset()
		var b = _body(ch)
		var X = b.ext
		if X == null:
			b.free()
			continue
		var holder := Node3D.new()
		holder.add_child(b)
		for i in 4:
			_step(X, _walk(1.0, 0.0, true))
		for sc in [Vector3.ZERO, Vector3(1, 0, 1), Vector3.ONE * NAN]:
			holder.scale = sc
			for i in 4:
				_step(X, _walk(1.0, 0.0, true))
				_step(X, _st({"hit": {"id": 3, "age": 0.03, "stop": 0.0, "dx": -1.0, "dy": 0.0, "pow": 2.0}}))
			check(_sane(X.sk), "%s 월드 크기 %s 에도 뼈가 멀쩡" % [ch, str(sc)])
		holder.scale = Vector3.ONE
		for i in 6:
			_step(X, _walk(1.0, 0.0, true))
		check(_sane(X.sk), "%s 다시 정상 크기로 돌아와도 멀쩡" % ch)
		holder.free()
	_reset()
