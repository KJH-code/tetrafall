# W47 영벡터 가드: 천 사슬 점이 겹쳐도 "cannot be normalized"·"must be normalized" 오류 없이 쉬는 방향으로 (run_tests 의 ErrorLog 가 엔진 오류를 잡아 실패시킴).
extends RefCounted

const Body := preload("res://chars/body.gd")
const Motion_ := preload("res://chars/ext_motion.gd")
const K := preload("res://chars/chars_config.gd")
const Opts := preload("res://core/opts.gd")
const Ext := preload("res://chars/external.gd")

var errors: Array = []


func check(cond: bool, msg: String) -> void:
	if not cond:
		errors.append(msg)


func test_safe_dir() -> void:
	var fb := Vector3(0, 1, 0)
	check(Motion_.safe_dir(Vector3.ZERO, fb) == fb, "영벡터 → 대체 방향")
	check(Motion_.safe_dir(Vector3(1e-6, 0, 0), fb) == fb, "아주 짧으면 → 대체 방향")
	var v := Vector3(0.3, -0.4, 1.2)
	check(Motion_.safe_dir(v, fb) == v.normalized(), "정상 벡터는 normalized() 와 같은 값")
	var tiny := Vector3(0.001, 0, 0) # 1 mm — 천 한 칸 길이 근처는 그대로 정규화
	check(Motion_.safe_dir(tiny, fb) == Vector3.RIGHT, "1 mm 는 가드에 안 걸림")


func test_rot_between() -> void:
	check(Motion_.rot_between(Vector3.ZERO, Vector3.UP) == Quaternion.IDENTITY, "한쪽이 영벡터면 항등")
	check(Motion_.rot_between(Vector3.UP, Vector3.ZERO) == Quaternion.IDENTITY, "반대쪽 영벡터도 항등")
	var a := Vector3(0.2, 1.0, -0.3)
	var b := Vector3(-0.5, 0.4, 0.8)
	var q := Motion_.rot_between(a, b)
	check((q * a.normalized()).is_equal_approx(b.normalized()), "정상 값은 a 를 b 쪽으로 돌림")
	check(q.is_equal_approx(Quaternion(a.normalized(), b.normalized())), "정상 값은 예전 Quaternion(a, b) 와 같음")


# 천 점이 전부 겹쳐도 (순간이동·0 길이) 오류 없이 한 걸음이 돌고 뼈 회전이 유한함
func test_cloth_coincident_points() -> void:
	var was: bool = Body.use_ext
	Body.use_ext = true
	var b = Body.new()
	b.build("ninja", Color(0.2, 0.5, 1.0), true)
	Body.use_ext = was
	if b.ext == null or b.ext.cloths.is_empty():
		b.free()
		return
	var X = b.ext
	var holder := Node3D.new()
	holder.add_child(b)
	X.sync()
	var cl = X.cloths[0]
	# 당김·중력·충돌을 꺼서 점이 겹친 채로 남게 함 (아니면 verlet 이 쉬는 자리로 당겨 영벡터 경로를 안 탐)
	cl.step(1.0 / 60.0) # 첫 걸음은 앵커를 잡느라 점을 쉬는 자리로 놓음 — 한 번 돌려 둠
	cl.k_rest = 0.0
	cl.grav = 0.0
	cl.col_on = false
	for i in cl.pts.size():
		cl.pts[i] = cl.pts[0]
		cl.prev[i] = cl.pts[0]
	cl.step(1e-6)
	for i in cl.bones.size():
		var qr: Quaternion = X.sk.get_bone_pose_rotation(cl.bones[i])
		check(is_finite(qr.x) and is_finite(qr.w) and absf(qr.length() - 1.0) < 1e-3, "뼈 회전이 유한한 단위 사원수 (%d)" % i)
	holder.free()


# --old-gait: 기본은 W46 새 값, 인자를 주면 (웹 ?old-gait=1 도 Opts 한 길) W46 전 값. 끝에 Opts.override 를 꼭 비움 (정적 상태에 참조를 안 남김)
func test_old_gait_switch() -> void:
	var now := {"ninja": [1.0, -0.14, 0.5], "tank": [1.0, -0.07, 0.75], "hunter": [1.0, -0.08, 0.55], "hook": [1.0, -0.08, 0.65]}
	var old := {"ninja": [1.45, -0.14, 1.6], "tank": [1.45, -0.07, 1.6], "hunter": [1.45, -0.08, 1.6], "hook": [1.45, -0.08, 1.6]}
	Opts.override = null
	check(not K.old_gait(), "기본은 old-gait 꺼짐")
	for ch in now:
		var cc: Dictionary = Ext.read_cfg(ch).get("clips", {})
		check(K.stride_of(cc, "run") == now[ch], "%s 기본 달리기 stride 는 새 값 %s" % [ch, str(K.stride_of(cc, "run"))])
	check(K.dir_gain() == K.EXT_DIR_GAIN and K.dir_max_deg() == K.EXT_DIR_MAX_DEG, "기본 방향 이득·한계는 새 값")
	check(K.dir_counter() == K.EXT_DIR_COUNTER and K.dir_counter().size() == 3, "기본은 윗몸 되돌림 척추 셋")
	Opts.override = PackedStringArray(["--old-gait"])
	check(K.old_gait(), "인자를 주면 old-gait 켜짐")
	for ch in old:
		var cc2: Dictionary = Ext.read_cfg(ch).get("clips", {})
		check(K.stride_of(cc2, "run") == old[ch], "%s old-gait 달리기 stride 는 옛 값" % ch)
		check(K.stride_of(cc2, "walk")[2] == 1.6, "%s old-gait 걷기 박자 1.6" % ch)
	check(K.dir_gain() == 0.6 and K.dir_max_deg() == 45.0 and K.dir_counter().is_empty(), "old-gait 방향 이득 0.6·한계 45°·되돌림 없음")
	check(is_equal_approx(Motion_.hip_yaw(deg_to_rad(60.0)), deg_to_rad(36.0)), "old-gait 골반 yaw = 60° × 0.6")
	# 표에 없는 캐릭터는 old-gait 이어도 JSON 값 그대로
	Opts.override = PackedStringArray(["--old-gait"])
	var other: Dictionary = {"char": "bard", "stride": {"run": [1.0, 0.0, 0.9]}}
	check(K.stride_of(other, "run") == [1.0, 0.0, 0.9], "표 밖 캐릭터는 JSON 값")
	Opts.override = null
	check(not K.old_gait() and Motion_.hip_yaw(deg_to_rad(90.0)) > deg_to_rad(60.0), "되돌린 뒤 새 값")
