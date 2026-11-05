# W23 외부 몸 동작 클립 (chars/ext_clips.gd + external.gd 클립 층, 닌자 ninja_anim.glb):
# ① 클립 파일 (이름·길이·뼈 트랙) ② 상태 → 클립·시각 고르기 (서버 단계 → 클립 눈금, 힘 빠진 상태는 코드) ③ 클립 층이 뼈를 실제로 움직이고 발이 바닥에 맞음
# ④ 래그돌이 힘 빠지면 클립이 빠짐 ⑤ 1인칭 쌍둥이·클립 없는 몸은 그대로
extends RefCounted

const C := preload("res://core/config.gd")
const K := preload("res://chars/chars_config.gd")
const Body := preload("res://chars/body.gd")
const Ext := preload("res://chars/external.gd")
const Clips := preload("res://chars/ext_clips.gd")
const RagW := preload("res://chars/ragdoll.gd")

var errors: Array = []


func check(cond: bool, msg: String) -> void:
	if not cond:
		errors.append(msg)


func _body(ch: String, merge := true):
	var was: bool = Body.use_ext
	Body.use_ext = true
	var b = Body.new()
	b.build(ch, Color(0.2, 0.5, 1.0), merge)
	Body.use_ext = was
	return b


static func _st(over := {}) -> Dictionary:
	var st := {"air": false, "walking": false, "hs": 0.0, "walk": 0.0, "vz": 0.0, "t": 1.0, "stunned": false, "emote": -1, "victory": -1.0, "hit": null, "act": null,
		"tumble": 0.0, "recover": 0.0, "land": 0.0, "flip": -1.0, "idle": 0.0, "airDash": 0.0, "dizzy": 0.0, "whirl": -1.0, "glide": false}
	st.merge(over, true)
	return st


# 뼈대 공간 뼈 높이·앞 (x) 위치 (지역 자세를 부모로 곱함)
static func _bone_pos(sk: Skeleton3D, nm: String) -> Vector3:
	var b := sk.find_bone(nm)
	var t := Transform3D.IDENTITY
	while b >= 0:
		t = sk.get_bone_pose(b) * t
		b = sk.get_bone_parent(b)
	return t.origin


func test_clip_file() -> void:
	var info = Ext.load_char("ninja")
	check(info != null and not info.clipset.is_empty(), "닌자 클립 파일 읽음")
	if info == null:
		return
	var cc: Dictionary = info.cfg.clips
	var names := ["idle", "walk", "run", "jump", "fall", "land", "atk1", "atk2", "atk3", "atk4", "air1", "air2", "dash", "star", "airstar"]
	for n in names:
		check(info.clipset.has(n), "클립 %s 있음" % n)
	for n in (cc.moves as Dictionary).values():
		check(info.clipset.has(n), "moves 가 가리키는 클립 %s 있음" % n)
	for n in ["atk1", "atk2", "atk3", "atk4", "air1", "air2", "dash", "star", "airstar"]:
		var c: Dictionary = info.clipset.get(n, {})
		check(not c.is_empty() and absf(float(c.len) - float(Clips.MARKS[2])) < 0.04, "%s 길이 = 회복 눈금 %.2f (얻음 %.2f)" % [n, Clips.MARKS[2], float(c.get("len", 0.0))])
	for n in ["idle", "run", "walk"]:
		check(info.clipset[n].len > 0.5, "%s 반복 길이" % n)
	var any: Dictionary = info.clipset.run
	check(any.rot.has("mixamorig_Hips") and any.pos.has("mixamorig_Hips") and any.rot.size() >= 20, "뼈 트랙: 골반 회전·이동 + 척추·팔다리·머리 %d" % any.rot.size())
	# 우리 관절에 맞춘 뼈는 다 클립에 있음 (닌자 뼈 이름은 ALIASES 로 매칭)
	for j in ["hips", "waist", "torso", "neck", "shoulder_R", "elbow_L", "thigh_R", "knee_L", "foot_R"]:
		check(any.rot.has(String(info.names[info.map[j]])), "클립이 %s 뼈를 움직임" % j)


func test_select_maps_server_phases() -> void:
	var cc: Dictionary = Ext.load_char("ninja").cfg.clips
	var m: Array = Clips.MARKS
	var act := func(ph: String, u: float, mv := "찌르기", air := false): return _st({"act": {"id": 1, "move": mv, "phase": ph, "u": u, "air": air}})
	var s: Dictionary = Clips.select(cc, act.call("wind", 1.0), 0.0)
	check(s.clip == "atk1" and absf(s.t - float(m[0])) < 1e-5, "준비 끝 (u=1) = 준비 눈금 %.2f" % m[0])
	s = Clips.select(cc, act.call("wind", 0.5), 0.0)
	check(absf(s.t - float(m[0]) * 0.5) < 1e-5, "준비 중간")
	s = Clips.select(cc, act.call("strike", 0.0), 0.0)
	check(absf(s.t - float(m[0])) < 1e-5, "타격 시작 = 준비 눈금 (판정 순간에 자세가 이어짐)")
	s = Clips.select(cc, act.call("strike", 1.0), 0.0)
	check(absf(s.t - float(m[1])) < 1e-5, "타격 끝 = 타격 눈금")
	s = Clips.select(cc, act.call("rec", 1.0), 0.0)
	check(absf(s.t - float(m[2])) < 1e-5, "회복 끝 = 끝 눈금")
	s = Clips.select(cc, act.call("rec", 0.0, "공중 베기", true), 0.0)
	check(s.clip == "air1" and s.air, "공중 평타 = 공중 클립 (발 바닥 맞추기 안 함)")
	check(Clips.select(cc, act.call("broken", 0.3), 0.0).clip == "", "끊김 (broken) = 코드")
	check(Clips.select(cc, act.call("strike", 0.5, "방패 올려치기"), 0.0).clip == "", "표에 없는 동작 = 코드")
	# 상태: 달리기·서기·공중
	check(Clips.select(cc, _st(), 0.0).clip == "idle", "가만히 = idle")
	var run := Clips.select(cc, _st({"walking": true, "hs": C.MOVE_SPEED, "walk": PI}), 0.0)
	check(run.clip == "run" and absf(run.t - 0.5) < 1e-5 and run.get("norm", false), "달리기 = run, 걸음 위상 π = 한 바퀴의 절반")
	check(Clips.select(cc, _st({"walking": true, "hs": 1.0, "walk": 0.0}), 0.0).clip == "walk", "느리면 walk")
	check(Clips.select(cc, _st({"air": true, "vz": 3.0}), 0.1).clip == "jump", "오르는 중 = jump")
	check(Clips.select(cc, _st({"air": true, "vz": -3.0}), 0.5).clip == "fall", "내리는 중 = fall")
	check(Clips.select(cc, _st({"land": 0.7}), 0.0).clip == "land", "착지 = land")
	# 힘 빠진·특수 상태는 코드 (래그돌)
	for k in [{"stunned": true}, {"tumble": 0.5}, {"recover": 0.4}, {"flip": 0.3}, {"emote": 1}, {"victory": 0.5}, {"airDash": 0.5}, {"dizzy": 0.5}, {"whirl": 0.2}, {"glide": true}, {"hit": {"age": 0.1}}]:
		check(Clips.select(cc, _st(k), 0.0).clip == "", "코드 구동 상태 %s" % [k])
	check(Clips.select(cc, _st({"hit": {"age": 1.0}}), 0.0).clip == "idle", "맞은 지 오래되면 다시 클립")
	check(Clips.select({}, _st(), 0.0).clip == "", "클립 설정 없으면 늘 코드")


func test_clip_layer_moves_bones() -> void:
	var b = _body("ninja")
	check(b.ext != null and not b.ext.clipset.is_empty(), "닌자 몸에 클립이 있음")
	if b.ext == null:
		b.free()
		return
	var X = b.ext
	var sk: Skeleton3D = X.sk
	X.sync()
	var rest_hand := _bone_pos(sk, "mixamorig_RightHand")
	var rest_foot := _bone_pos(sk, "mixamorig_RightFoot")
	# 찌르기 타격 눈금: 오른손이 앞으로 (모델 +x 가 앞) 크게
	X.preview_clip("atk1", float(Clips.MARKS[1]))
	var hand := _bone_pos(sk, "mixamorig_RightHand")
	check(hand.x - rest_hand.x > 0.15, "찌르기 타격 때 오른손이 앞으로 %.2f 이상 (얻음 %.2f)" % [0.15, hand.x - rest_hand.x])
	# 발이 바닥 (쉬는 자세 높이) 에 맞음: 발 뼈 중 가장 낮은 높이가 쉬는 자세와 2cm 안 (모델 키 ~1m 기준)
	var lo := 1e9
	var lo_rest := 1e9
	for nm in ["mixamorig_LeftFoot", "mixamorig_RightFoot", "mixamorig_LeftToeBase", "mixamorig_RightToeBase"]:
		lo = minf(lo, _bone_pos(sk, nm).y)
		lo_rest = minf(lo_rest, (X.info.rest_global[sk.find_bone(nm)] as Transform3D).origin.y)
	check(absf(lo - lo_rest) < 0.02, "발 바닥 맞추기: 가장 낮은 발 %.3f 쉬는 자세 %.3f" % [lo, lo_rest])
	# 클립 끄면 코드 구동으로 돌아옴 (손이 쉬는 자리 근처)
	X.preview_clip("", 0.0)
	X.sync()
	check(_bone_pos(sk, "mixamorig_RightHand").distance_to(rest_hand) < 0.03, "클립을 끄면 코드 구동 (쉬는 자세)")
	b.free()


func test_clip_blend_follows_state_and_ragdoll() -> void:
	var b = _body("ninja")
	if b.ext == null:
		b.free()
		return
	var X = b.ext
	var strike := _st({"act": {"id": 1, "move": "찌르기", "phase": "strike", "u": 0.5, "air": false}})
	# 테스트는 한 순간이라 프레임 시간이 0 → 지난 프레임을 0.5초 전으로 돌려 한 걸음 크게
	X.last_t = Time.get_ticks_msec() * 0.001 - 0.5
	X.sync(strike)
	check(X.cw > 0.5, "공격 상태에서 클립 섞는 정도가 오름 (%.2f)" % X.cw)
	check(X.clip_info.get("clip", "") == "atk1", "고른 클립 atk1")
	# 맞아서 힘 빠짐 (stunned) → 코드
	X.last_t = Time.get_ticks_msec() * 0.001 - 0.5
	X.sync(_st({"stunned": true}))
	check(X.cw < 0.1, "경직이면 클립이 빠짐 (%.2f)" % X.cw)
	# 래그돌이 깨어 있고 모터가 약하면 클립 상태여도 코드
	var rw = RagW.new()
	b.rag_test = true
	rw.create(b)
	var rag: Dictionary = rw.rags[b]
	rag.awake = true
	rag.motor = 0.2
	RagW._inst = rw
	X.cw = 1.0
	X.last_t = Time.get_ticks_msec() * 0.001 - 0.5
	X.sync(strike)
	check(X.cw < 1.0, "래그돌 모터 약함 → 클립 빠지는 중 (%.2f)" % X.cw)
	RagW._inst = null
	rw.remove(b)
	rw.free()
	b.free()


func test_twin_and_no_clip_unchanged() -> void:
	var t = _body("ninja", false) # 1인칭 쌍둥이 (판 몸 아님)
	if t.ext != null:
		t.ext.sync(_st({"act": {"id": 1, "move": "찌르기", "phase": "strike", "u": 0.5, "air": false}}))
		check(t.ext.cw == 0.0 and t.ext.clip_info.is_empty(), "1인칭 쌍둥이는 클립 층 안 씀 (코드 관절을 베낌)")
	t.free()
	var k = _body("tank")
	if k.ext != null:
		k.ext.sync(_st())
		check(k.ext.clipset.is_empty() and k.ext.cw == 0.0, "클립 설정 없는 외부 몸 (탱크) 은 그대로")
	k.free()


# 천 (목도리 꼬리 뼈 3개, chars/ext_cloth.gd): 몸이 앞으로 달리면 뒤로 날리고, 길이는 그대로, 순간이동하면 늘어나지 않고 다시 시작
func test_cloth_scarf_chain() -> void:
	var b = _body("ninja")
	if b.ext == null:
		b.free()
		return
	var X = b.ext
	check(X.cloths.size() == 1, "닌자 목도리 천 사슬 하나 (cfg.cloth)")
	if X.cloths.is_empty():
		b.free()
		return
	var cl = X.cloths[0]
	check(cl.bones.size() == 3, "뼈 3개 (Scarf1~3)")
	var holder := Node3D.new()
	holder.add_child(b)
	var spd := 6.0
	var now := Time.get_ticks_msec() * 0.001
	for i in 90:
		holder.position.x = spd * (i / 60.0)
		X.cloth_t = now - 1.0 / 60.0
		now += 0.0 # 한 걸음 = 1/60 초 (cloth_t 를 매번 그만큼 전으로)
		X.sync()
		X.cloth_t = 0.0
	# 달리는 방향 (월드 +x 쪽 = 몸 앞) 의 반대로 꼬리 끝이 처짐
	var anchor: Vector3 = cl.pts[0]
	var tip: Vector3 = cl.pts[cl.pts.size() - 1]
	check(anchor.x - tip.x > 0.02, "달리면 꼬리 끝이 앵커보다 뒤로 %.3f m" % (anchor.x - tip.x))
	var W: Transform3D = RagW.glob(X.sk)
	var scl: float = W.basis.get_scale().x
	var worst := 0.0
	for i in range(1, cl.pts.size()):
		var l: float = (cl.pts[i] - cl.pts[i - 1]).length()
		worst = maxf(worst, absf(l / (cl.rest_len[i - 1] * scl) - 1.0))
	check(worst < 0.03, "사슬 길이 유지 (가장 어긋남 %.1f%%)" % (worst * 100.0))
	# 순간이동 (2 m 넘게) 하면 다시 시작해서 늘어나지 않음
	holder.position.x += 50.0
	X.cloth_t = Time.get_ticks_msec() * 0.001 - 1.0 / 60.0
	X.sync()
	var worst2 := 0.0
	for i in range(1, cl.pts.size()):
		var l2: float = (cl.pts[i] - cl.pts[i - 1]).length()
		worst2 = maxf(worst2, absf(l2 / (cl.rest_len[i - 1] * scl) - 1.0))
	check(worst2 < 0.03, "순간이동 뒤에도 길이 유지 (%.1f%%)" % (worst2 * 100.0))
	# 뼈가 실제로 돌아감 (쉬는 자세와 다름)
	var q: Quaternion = X.sk.get_bone_pose_rotation(cl.bones[2])
	check(not q.is_equal_approx((X.info.rest_local[cl.bones[2]] as Transform3D).basis.get_rotation_quaternion()), "꼬리 끝 뼈 회전이 쉬는 자세에서 벗어남")
	holder.free()
