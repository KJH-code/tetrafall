# W49 NaN·영 스케일 추적: 판 몸 (외부 모델) 의 뼈 지역 자세·부모 사슬 전역 basis 를 Ext.sync 단계마다 (Motion_.probe 훅) 훑어,
# 처음 깨지는 프레임·뼈·직전 단계를 몸마다 기록한다. 깨짐 = 사원수·크기·위치가 유한하지 않음, 지역 크기가 0 에 가까움, 부모 사슬 전역 basis 가 Motion_.basis_ok 가 아님.
# 재연:  godot --headless --path godot/client -- --replay <녹화> --replay-secs 30 --replay-warm 0 --fixed-fps 120 --nan-hunt <출력 폴더>
#        → <폴더>/nan_hunt.json (몸마다 처음 깨짐 + 단계별 깨짐 수 + _add_rot 건너뜀 수) — 깨짐이 없으면 first 가 비어 있음
# 연습 방·판 중에도 (--nan-hunt 만 주면 출력은 콘솔 한 줄 + user://nan_hunt.json). 꺼져 있으면 노드가 없어 비용 0.
extends Node

const Motion_ := preload("res://chars/ext_motion.gd")

var args := {}
var out_dir := ""
var first := {} # 몸 id → 처음 깨짐 기록
var last_ok := {} # 몸 id → 마지막으로 멀쩡했던 단계
var stage_bad := {} # 단계 → 깨짐 수
var skip_count := {} # 단계 (_add_rot 건너뜀 직전) → 수
var skip_bones := {} # 뼈 → 수
var scans := 0
var frame_of := {} # 몸 id → 마지막으로 본 프레임 (같은 프레임 단계 순서)


func _ready() -> void:
	var v = args.get("nan-hunt", "")
	out_dir = str(v) if v is String else ""
	Motion_.probe = Callable(self, "_probe")
	if out_dir != "":
		DirAccess.make_dir_recursive_absolute(out_dir)


func _exit_tree() -> void:
	if Motion_.probe == Callable(self, "_probe"):
		Motion_.probe = Callable()
	write()


# 몸 한 프레임의 단계마다 불림
func _probe(X, stage: String) -> void:
	var id: int = X.body.get_instance_id()
	if stage.begins_with("add_rot_skip:") or stage.begins_with("add_rot_bad_input:"):
		# _add_rot 가 일을 거절함: skip = 부모 사슬 전역 basis 가 영 스케일·NaN, bad_input = 더할 회전이 NaN·inf (W49 가드가 NaN 이 뼈에 써지기 전에 막음)
		var kind := "skip" if stage.begins_with("add_rot_skip:") else "bad_input"
		var bn := stage.substr(stage.find(":") + 1)
		var lk := "%s@%s" % [kind, str(last_ok.get(id, "?"))]
		skip_count[lk] = int(skip_count.get(lk, 0)) + 1
		skip_bones[bn] = int(skip_bones.get(bn, 0)) + 1
		var rk := str(id) + "/거절"
		if not first.has(rk):
			var st0 = X.last_st
			var h0 = st0.get("hit") if st0 is Dictionary else null
			first[rk] = {"frame": Engine.get_process_frames(), "t": snappedf(Motion_.now_s(), 0.001), "char": str(X.body.get("char_id")), "stage": "add_rot_" + kind, "prev_ok_stage": str(last_ok.get(id, "")), "bone": bn,
				"what": "가산 회전 거절 (%s)" % kind, "value": "", "hit": JSON.stringify(h0) if h0 is Dictionary else "없음", "st_t": str(st0.get("t")) if st0 is Dictionary else "?", "clock_virtual": Motion_.clock.is_valid()}
			print("[nan-hunt] 처음 거절: ", JSON.stringify(first[rk]))
			write()
		return
	scans += 1
	var bad := _scan(X)
	if bad.is_empty():
		last_ok[id] = stage
		return
	stage_bad[stage] = int(stage_bad.get(stage, 0)) + 1
	if first.has(id):
		return
	var rec := {"frame": Engine.get_process_frames(), "t": snappedf(Motion_.now_s(), 0.001), "char": str(X.body.get("char_id")), "stage": stage, "prev_ok_stage": str(last_ok.get(id, "")), "bone": bad.bone, "what": bad.what, "value": bad.value}
	var b: Node3D = X.body
	rec["body_scale"] = str(b.scale)
	rec["body_global_scale"] = str(b.global_transform.basis.get_scale()) if b.is_inside_tree() else "트리 밖"
	rec["visible"] = b.visible
	var st = X.last_st
	if st is Dictionary:
		var s := {}
		for k in st:
			var val = st[k]
			if val is float or val is int or val is bool or val is String or val == null or val is Vector2 or val is Vector3:
				s[k] = str(val)
			elif val is Dictionary:
				s[k] = JSON.stringify(val).left(160)
		rec["st"] = s
	rec["clip"] = JSON.stringify(X.clip_info)
	first[id] = rec
	print("[nan-hunt] 처음 깨짐: ", JSON.stringify(rec))
	write()


func _scan(X) -> Dictionary:
	var sk: Skeleton3D = X.sk
	if sk == null:
		return {}
	# 입력 쪽 먼저: 몸 노드 크기·뼈대 월드 변환·코드 몸 관절 (figure joint) 변환이 멀쩡한가 — 뼈 자세는 이것에서 나옴
	var b: Node3D = X.body
	var bs := b.scale
	if not is_finite(bs.x + bs.y + bs.z) or bs.x < 1e-4 or bs.y < 1e-4 or bs.z < 1e-4:
		return {"bone": "(몸 노드)", "what": "몸 노드 크기가 0 이거나 유한하지 않음", "value": str(bs)}
	for m in X.maps:
		var jn: Node3D = m.joint
		if jn != null and is_instance_valid(jn):
			var jt := jn.transform
			if not (is_finite(jt.origin.x + jt.origin.y + jt.origin.z) and Motion_.basis_ok(jt.basis)):
				return {"bone": sk.get_bone_name(int(m.bone)), "what": "코드 몸 관절 노드 변환이 회전으로 못 씀 (%s)" % str(jn.name), "value": "크기 %s 위치 %s" % [str(jt.basis.get_scale()), str(jt.origin)]}
	return scan_bones(X)


# 뼈 지역 자세를 부모 먼저 순서로 훑음. 처음 깨진 뼈 {bone, what, value}, 멀쩡하면 {} (tools/nan_fuzz.gd 도 씀)
static func scan_bones(X) -> Dictionary:
	var sk: Skeleton3D = X.sk
	if sk == null:
		return {}
	var n := sk.get_bone_count()
	var gb: Array = []
	gb.resize(n)
	for i in n:
		var q := sk.get_bone_pose_rotation(i)
		var sc := sk.get_bone_pose_scale(i)
		var p := sk.get_bone_pose_position(i)
		var nm := sk.get_bone_name(i)
		if not is_finite(q.x + q.y + q.z + q.w):
			return {"bone": nm, "what": "회전 사원수가 유한하지 않음", "value": str(q)}
		if not is_finite(sc.x + sc.y + sc.z):
			return {"bone": nm, "what": "지역 크기가 유한하지 않음", "value": str(sc)}
		if not is_finite(p.x + p.y + p.z):
			return {"bone": nm, "what": "지역 위치가 유한하지 않음", "value": str(p)}
		var loc := Basis(q.normalized() if q.length_squared() > 1e-12 else Quaternion.IDENTITY).scaled(sc)
		var par := sk.get_bone_parent(i)
		var g: Basis = (gb[par] as Basis) * loc if par >= 0 else loc
		gb[i] = g
		if sc.x < 1e-3 or sc.y < 1e-3 or sc.z < 1e-3:
			return {"bone": nm, "what": "지역 크기가 0 에 가까움", "value": str(sc)}
		if absf(q.length() - 1.0) > 0.05:
			return {"bone": nm, "what": "회전 사원수가 단위가 아님", "value": "%s (길이 %.4f)" % [str(q), q.length()]}
		if not Motion_.basis_ok(g):
			return {"bone": nm, "what": "부모 사슬 전역 basis 가 회전으로 못 씀", "value": str(g.get_scale())}
	return {}


func write() -> void:
	var path := (out_dir if out_dir != "" else "user://").path_join("nan_hunt.json")
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"scans": scans, "first": first.values(), "stage_bad": stage_bad, "add_rot_skip_prev_stage": skip_count, "add_rot_skip_bones": skip_bones}, "  "))
