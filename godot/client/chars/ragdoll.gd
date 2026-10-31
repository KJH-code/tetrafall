# 액티브 래그돌 (JS client/ragdoll.js 옮김, 엔진 물리는 cannon-es 대신 고도 PhysicsServer3D — 판정과 무관한 모습만).
# 자기 물리 공간 (space) 하나에 몸마다 조각 11개 (골반·가슴·머리·위팔·아래팔·허벅지·정강이) = 상자 강체, 관절 = 원뿔 (RAGDOLL_LIMITS) 또는 핀.
# 매 프레임 몸 pose 안에서: restore (지난 물리 회전 지움) → figureAnim → capture (관절 자세 = 목표) → apply (물리 자세 → 관절 회전).
# 물리 걸음 (_physics_process, 고도 물리 틱) 마다 drive: 골반은 판정 위치로 (rootPull), 다른 조각은 자기 목표로 (limbPull), 관절 모터 토크 (pdAngular).
# 중력은 직접 (gravity_scale 0) — 공간 기본 영역을 안 건드림. 좌표: 물리는 고도 전역 좌표, 순수 계산 (ragdoll_math.gd) 은 게임 좌표로 바꿔 부름.
# 바닥·블록은 힘이 빠졌을 때만 부딪힘 (RAGDOLL_COLLIDE_BELOW): 판 크기 바닥 상자 하나 + 래그돌 둘레 RAGDOLL_GROUND_REACH 칸 안 단단한 칸
extends Node

const C := preload("res://core/config.gd")
const RM := preload("res://chars/ragdoll_math.gd")
const Co := preload("res://core/coords.gd")

const GROUND := 1
const PART := 2
const NAME := "TfRagdolls"

static var _inst = null

var space: RID
var cell_shape: RID
var floor_body := RID()
var floor_shape := RID()
var floor_key := ""
var ground := {} # "x,y,z" → 정적 강체
var rags := {} # 몸 (body.gd) → {segs, joints, motor, snap, hit_id, weight, fresh, root_v}
var made := 0 # 만든 래그돌 수 (확인용)
var stats := {"ms": 0.0, "steps": 0, "n": 0} # 마지막 물리 틱 (perf-log)


# 장면 트리 하나에 하나 (root 아래 TfRagdolls). 트리 밖이면 null
static func of(n: Node) -> Node:
	if _inst != null and is_instance_valid(_inst):
		return _inst
	if not n.is_inside_tree():
		return null
	var w: Node = load("res://chars/ragdoll.gd").new() # new() 라야 _init (물리 공간) 이 돎
	w.name = NAME
	n.get_tree().root.add_child.call_deferred(w)
	_inst = w
	return w


func _init() -> void:
	space = PhysicsServer3D.space_create()
	PhysicsServer3D.space_set_active(space, true)
	cell_shape = PhysicsServer3D.box_shape_create()
	PhysicsServer3D.shape_set_data(cell_shape, Vector3(0.5, 0.5, 0.5))


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		for b in rags.keys():
			remove(b)
		for k in ground:
			PhysicsServer3D.free_rid(ground[k])
		if floor_body.is_valid():
			PhysicsServer3D.free_rid(floor_body)
			PhysicsServer3D.free_rid(floor_shape)
		PhysicsServer3D.free_rid(cell_shape)
		PhysicsServer3D.free_rid(space)
		if _inst == self:
			_inst = null


func has(body) -> bool:
	return rags.has(body)


# 몸 조각 정의: [이름, 관절 노드, 부모 조각 번호, 반 크기 (몸 좌표), 관절에서 조각 가운데까지 z, 질량 키, 관절 제한 키]
static func seg_defs(b) -> Array:
	var d: Dictionary = b.d
	var depth: float = d.get("depth", 0.75)
	return [
		["pelvis", b.hips, -1, Vector3(d.waistR * depth, maxf(d.waistR, d.hipY + d.legR), 0.1), 0.02, "pelvis", ""],
		["chest", b.waist, 0, Vector3(d.chestR * depth, d.chestR, d.torso / 2.0), d.torso / 2.0, "chest", "waist"],
		["head", b.neck, 1, Vector3(d.headW / 2.0, d.headW / 2.0, d.head / 2.0), d.head / 2.0, "head", "neck"],
		["upperR", b.shoulders[0], 1, Vector3(d.armR, d.armR, d.upper / 2.0), -d.upper / 2.0, "upper", ""],
		["upperL", b.shoulders[1], 1, Vector3(d.armR, d.armR, d.upper / 2.0), -d.upper / 2.0, "upper", ""],
		["foreR", b.elbows[0], 3, Vector3(d.foreR, d.foreR, (d.lower + d.hand) / 2.0), -(d.lower + d.hand) / 2.0, "fore", "elbow"],
		["foreL", b.elbows[1], 4, Vector3(d.foreR, d.foreR, (d.lower + d.hand) / 2.0), -(d.lower + d.hand) / 2.0, "fore", "elbow"],
		["thighR", b.thighs[0], 0, Vector3(d.legR, d.legR, d.thigh / 2.0), -d.thigh / 2.0, "thigh", "hip"],
		["thighL", b.thighs[1], 0, Vector3(d.legR, d.legR, d.thigh / 2.0), -d.thigh / 2.0, "thigh", "hip"],
		["shinR", b.knees[0], 7, Vector3(d.legR * 0.85, d.legR * 0.85, (d.shin + d.foot) / 2.0), -(d.shin + d.foot) / 2.0, "shin", "knee"],
		["shinL", b.knees[1], 8, Vector3(d.legR * 0.85, d.legR * 0.85, (d.shin + d.foot) / 2.0), -(d.shin + d.foot) / 2.0, "shin", "knee"],
	]


# 관절 노드의 전역 회전 (크기 뺀) · 조각 가운데 자리
static func _joint_q(j: Node3D) -> Quaternion:
	return glob(j).basis.orthonormalized().get_rotation_quaternion()


static func _seg_pos(j: Node3D, cz: float) -> Vector3:
	return glob(j) * Vector3(0, 0, cz)


# 전역 자리 (부모 Node3D 를 따라 곱함 — 장면 트리 밖에서도 됨)
static func glob(n: Node3D) -> Transform3D:
	var t := n.transform
	var p := n.get_parent() as Node3D
	while p != null:
		t = p.transform * t
		p = p.get_parent() as Node3D
	return t


func create(b) -> void:
	var weight: float = C.RAGDOLL_WEIGHT.get(C.FIGURE_BODY.get(b.char_id, ""), 1.0)
	var S: float = glob(b.hips).basis.get_scale().x # 몸 전체 크기 (FIGURE_SCALE × 몸 노드)
	var segs: Array = []
	for def in seg_defs(b):
		var j: Node3D = def[1]
		var m: float = C.RAGDOLL_MASS[def[5]] * weight
		var half: Vector3 = def[3] * S
		half.z = maxf(0.02, half.z)
		var shape := PhysicsServer3D.box_shape_create()
		PhysicsServer3D.shape_set_data(shape, half)
		var rb := PhysicsServer3D.body_create()
		PhysicsServer3D.body_set_mode(rb, PhysicsServer3D.BODY_MODE_RIGID)
		PhysicsServer3D.body_set_space(rb, space)
		PhysicsServer3D.body_add_shape(rb, shape)
		PhysicsServer3D.body_set_param(rb, PhysicsServer3D.BODY_PARAM_MASS, m)
		PhysicsServer3D.body_set_param(rb, PhysicsServer3D.BODY_PARAM_GRAVITY_SCALE, 0.0)
		PhysicsServer3D.body_set_param(rb, PhysicsServer3D.BODY_PARAM_LINEAR_DAMP, C.RAGDOLL_DAMPING)
		PhysicsServer3D.body_set_param(rb, PhysicsServer3D.BODY_PARAM_ANGULAR_DAMP, C.RAGDOLL_DAMPING)
		PhysicsServer3D.body_set_param(rb, PhysicsServer3D.BODY_PARAM_FRICTION, C.RAGDOLL_FRICTION)
		PhysicsServer3D.body_set_param(rb, PhysicsServer3D.BODY_PARAM_BOUNCE, 0.05)
		PhysicsServer3D.body_set_collision_layer(rb, PART)
		PhysicsServer3D.body_set_collision_mask(rb, 0)
		PhysicsServer3D.body_set_state(rb, PhysicsServer3D.BODY_STATE_CAN_SLEEP, false) # 모터 힘은 걸음마다 주니 잠들면 안 됨
		var full := half * 2.0
		var inertia := Vector3(full.y * full.y + full.z * full.z, full.x * full.x + full.z * full.z, full.x * full.x + full.y * full.y) * (m / 12.0) # 상자 관성 (조각 축)
		segs.append({"name": def[0], "joint": j, "parent": def[2], "cz": def[4], "lim": def[6], "mass": m, "inertia": inertia, "body": rb, "shape": shape,
			"rest": j.quaternion, "tp": _seg_pos(j, def[4]), "tq": _joint_q(j), "tv": Vector3.ZERO, "tw": Vector3.ZERO, "wq": _joint_q(j)})
	# 관절: 지금 (만든 순간) 자세에서 자식 관절 원점 = 두 조각을 잇는 점. 원뿔이면 비틀림 축 (고도 원뿔 관절의 X 축) = 가운데 방향
	var joints: Array = []
	for sg in segs:
		PhysicsServer3D.body_set_state(sg.body, PhysicsServer3D.BODY_STATE_TRANSFORM, Transform3D(Basis(sg.tq), sg.tp))
	for sg in segs:
		if int(sg.parent) < 0:
			continue
		var pa: Dictionary = segs[int(sg.parent)]
		var pivot: Vector3 = glob(sg.joint).origin
		var xa := Transform3D(Basis(pa.tq), pa.tp)
		var xb := Transform3D(Basis(sg.tq), sg.tp)
		var la: Vector3 = xa.affine_inverse() * pivot
		var lb: Vector3 = xb.affine_inverse() * pivot
		var jr := PhysicsServer3D.joint_create()
		var L = C.RAGDOLL_LIMITS.get(sg.lim)
		if L != null:
			# 가운데 방향: 기본 축 (몸통·목은 위 +z, 팔다리는 아래 -z) 을 부모 y 축으로 rotY 만큼 (figure 관절 rotation.y 와 같은 부호)
			var u := 1.0 if L.get("up", false) else -1.0
			var ax := Vector3(u * sin(L.rotY), 0, u * cos(L.rotY))
			var bx := Vector3(0, 0, u)
			var ba := _frame_x(ax, Vector3.UP if absf(ax.y) < 0.9 else Vector3.RIGHT)
			# 자식 기준틀: X = 자식 축, Y = 부모 기준틀 Y 를 자식 쪽으로 옮겨 X 에 직교 (비틀림 0 = 만든 순간 자세)
			var rel := (sg.tq as Quaternion).inverse() * (pa.tq as Quaternion)
			var yb: Vector3 = rel * ba.y
			yb = (yb - bx * bx.dot(yb)).normalized()
			if yb.length() < 0.5:
				yb = _frame_x(bx, Vector3.UP).y
			var bb := Basis(bx, yb, bx.cross(yb))
			PhysicsServer3D.joint_make_cone_twist(jr, pa.body, Transform3D(ba, la), sg.body, Transform3D(bb, lb))
			PhysicsServer3D.cone_twist_joint_set_param(jr, PhysicsServer3D.CONE_TWIST_JOINT_SWING_SPAN, L.cone)
			PhysicsServer3D.cone_twist_joint_set_param(jr, PhysicsServer3D.CONE_TWIST_JOINT_TWIST_SPAN, L.get("twist", PI)) # 비틀림 제한 없음 = π
		else:
			PhysicsServer3D.joint_make_pin(jr, pa.body, la, sg.body, lb)
		PhysicsServer3D.joint_disable_collisions_between_bodies(jr, true)
		joints.append(jr)
	made += 1
	rags[b] = {"segs": segs, "joints": joints, "motor": 1.0, "snap": 0.0, "hit_id": null, "weight": weight, "fresh": true, "root_v": Vector3.ZERO}


# X 축이 a 인 직교 기준틀
static func _frame_x(a: Vector3, hint: Vector3) -> Basis:
	var x := a.normalized()
	var z := x.cross(hint).normalized()
	var y := z.cross(x)
	return Basis(x, y, z)


# 래그돌 끔: 물리에서 빼고 관절 회전을 처음 값으로
func remove(b) -> void:
	var rag = rags.get(b)
	if rag == null:
		return
	for jr in rag.joints:
		PhysicsServer3D.free_rid(jr)
	for sg in rag.segs:
		PhysicsServer3D.free_rid(sg.body)
		PhysicsServer3D.free_rid(sg.shape)
		if is_instance_valid(b):
			(sg.joint as Node3D).quaternion = sg.rest
	rags.erase(b)


# figureAnim 전에: 관절 회전을 처음 값으로 (지난 프레임 물리 회전이 남지 않게)
func restore(b) -> void:
	var rag = rags.get(b)
	if rag != null:
		for sg in rag.segs:
			(sg.joint as Node3D).quaternion = sg.rest


# figureAnim 뒤에: 지금 관절 자세를 목표로. st = RM.motor 입력, hit = {id, x, y, pow} (게임 방향) 또는 null
func capture(b, st: Dictionary, hit, dt: float) -> void:
	var rag = rags.get(b)
	if rag == null:
		return
	for sg in rag.segs:
		var j: Node3D = sg.joint
		var q := _joint_q(j)
		var tp := _seg_pos(j, sg.cz)
		if rag.fresh or dt <= 0.0:
			sg.tw = Vector3.ZERO
			sg.tv = Vector3.ZERO
		else:
			sg.tw = RM.quat_diff_vec(q, sg.tq) / dt
			sg.tv = (tp - sg.tp) / dt
		sg.tq = q
		sg.tp = tp
	rag.root_v = rag.segs[0].tv
	var m := RM.motor(st)
	rag.motor = m.motor
	rag.snap = m.snap
	var mask := GROUND if m.motor < C.RAGDOLL_COLLIDE_BELOW else 0 # 힘이 빠졌을 때만 바닥·블록과 부딪힘
	for sg in rag.segs:
		PhysicsServer3D.body_set_collision_mask(sg.body, mask)
	if rag.fresh:
		_snap_all(rag)
	rag.fresh = false
	if hit != null and hit.id != rag.hit_id:
		rag.hit_id = hit.id
		# 맞음: 가슴·머리를 밀린 쪽으로 툭 (골반은 판정 위치를 따라가니 윗몸이 포개짐)
		for k in [1, 2]:
			var sg: Dictionary = rag.segs[k]
			var jj: float = C.RAGDOLL_HIT_IMPULSE * float(hit.pow) * float(sg.mass) / float(rag.weight)
			PhysicsServer3D.body_apply_central_impulse(sg.body, Co.gpos(Vector3(float(hit.x) * jj, float(hit.y) * jj, C.RAGDOLL_HIT_UP * jj)))


# 몸 전체를 목표 자세로 순간 맞춤 (처음·순간이동·너무 멀어짐)
func _snap_all(rag: Dictionary) -> void:
	for sg in rag.segs:
		PhysicsServer3D.body_set_state(sg.body, PhysicsServer3D.BODY_STATE_TRANSFORM, Transform3D(Basis(sg.tq), sg.tp))
		PhysicsServer3D.body_set_state(sg.body, PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY, rag.root_v)
		PhysicsServer3D.body_set_state(sg.body, PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY, Vector3.ZERO)


# 물리 자세 → 관절 회전 (부모부터). snap 만큼 목표 자세 쪽으로 섞음
func apply(b) -> void:
	var rag = rags.get(b)
	if rag == null:
		return
	for sg in rag.segs:
		var x: Transform3D = PhysicsServer3D.body_get_state(sg.body, PhysicsServer3D.BODY_STATE_TRANSFORM)
		var wq := x.basis.get_rotation_quaternion()
		if not (is_finite(wq.x) and is_finite(wq.w)):
			_snap_all(rag) # 안전장치
			return
		if rag.snap > 0.0:
			wq = wq.slerp(sg.tq, rag.snap)
		sg.wq = wq
		var j: Node3D = sg.joint
		var pq := glob(j.get_parent() as Node3D).basis.orthonormalized().get_rotation_quaternion()
		j.quaternion = (pq.inverse() * wq).normalized()


func _physics_process(_delta: float) -> void:
	var t0 := Time.get_ticks_usec()
	stats.n = rags.size()
	if rags.is_empty():
		stats.ms = 0.0
		return
	_update_ground()
	for b in rags.keys():
		if not is_instance_valid(b):
			remove(b)
			continue
		_drive(rags[b])
	stats.steps = 1
	stats.ms = (Time.get_ticks_usec() - t0) / 1000.0


# 걸음마다: 골반 끌어당김 + 조각 끌어당김 + 관절 모터 토크 + 중력 (모두 이 걸음 동안만)
func _drive(rag: Dictionary) -> void:
	var root: Dictionary = rag.segs[0]
	var rx: Transform3D = PhysicsServer3D.body_get_state(root.body, PhysicsServer3D.BODY_STATE_TRANSFORM)
	var rv: Vector3 = PhysicsServer3D.body_get_state(root.body, PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY)
	var pull := RM.root_pull(Co.game(rx.origin), Co.game(rv), Co.game(root.tp), Co.game(rag.root_v), rag.motor)
	if pull.snap:
		_snap_all(rag)
		return
	var pa: Vector3 = Co.gpos(pull.a)
	var share: float = C.RAGDOLL_ROOT_SHARE * (1.0 - minf(1.0, rag.motor))
	var grav := Vector3(0, -C.RAGDOLL_GRAVITY, 0)
	for sg in rag.segs:
		var rb: RID = sg.body
		var m: float = sg.mass
		var x: Transform3D = PhysicsServer3D.body_get_state(rb, PhysicsServer3D.BODY_STATE_TRANSFORM)
		var v: Vector3 = PhysicsServer3D.body_get_state(rb, PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY)
		var w: Vector3 = PhysicsServer3D.body_get_state(rb, PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY)
		var acc: Vector3
		if int(sg.parent) < 0:
			acc = pa
		else:
			acc = Co.gpos(RM.limb_pull(Co.game(x.origin), Co.game(v), Co.game(sg.tp), Co.game(sg.tv), rag.motor)) + pa * share
		PhysicsServer3D.body_apply_central_force(rb, (acc + grav) * m)
		# 토크 = R · I · Rᵀ · 각가속도 (조각 관성 축 기준)
		var q := x.basis.get_rotation_quaternion()
		var a := RM.pd_angular(q, sg.tq, w, sg.tw, rag.motor)
		var la: Vector3 = q.inverse() * a
		PhysicsServer3D.body_apply_torque(rb, q * (la * (sg.inertia as Vector3)))


# 판 바닥 상자 하나 + 래그돌 둘레의 단단한 칸만 정적 상자로
func _update_ground() -> void:
	var store = Engine.get_main_loop().root.get_node_or_null("Store") if Engine.get_main_loop() is SceneTree else null
	if store == null:
		return
	var f: Dictionary = store.state.get("field", {})
	if f.is_empty():
		return
	var w := int(f.w)
	var dd := int(f.d)
	var hh := int(f.get("h", C.GRID_H))
	var key := "%d,%d" % [w, dd]
	if key != floor_key:
		floor_key = key
		if floor_body.is_valid():
			PhysicsServer3D.free_rid(floor_body)
			PhysicsServer3D.free_rid(floor_shape)
		floor_shape = PhysicsServer3D.box_shape_create()
		PhysicsServer3D.shape_set_data(floor_shape, Vector3(w / 2.0, 0.5, dd / 2.0))
		floor_body = _static(floor_shape, Co.gxyz(w / 2.0, dd / 2.0, -0.5))
	var grid: PackedByteArray = store.grid
	var need := {}
	var R := int(C.RAGDOLL_GROUND_REACH)
	for rag in rags.values():
		var p := Co.game((PhysicsServer3D.body_get_state(rag.segs[0].body, PhysicsServer3D.BODY_STATE_TRANSFORM) as Transform3D).origin)
		var bx := floori(p.x)
		var by := floori(p.y)
		var bz := floori(p.z)
		for x in range(bx - R, bx + R + 1):
			for y in range(by - R, by + R + 1):
				for z in range(maxi(0, bz - R), bz + 2):
					if x < 0 or y < 0 or x >= w or y >= dd or z >= hh:
						continue
					var i := (z * dd + y) * w + x
					if i < grid.size() and grid[i] != 0:
						need["%d,%d,%d" % [x, y, z]] = Vector3i(x, y, z)
	for k in ground.keys():
		if not need.has(k):
			PhysicsServer3D.free_rid(ground[k])
			ground.erase(k)
	for k in need:
		if not ground.has(k):
			var c: Vector3i = need[k]
			ground[k] = _static(cell_shape, Co.gxyz(c.x + 0.5, c.y + 0.5, c.z + 0.5))


func _static(shape: RID, pos: Vector3) -> RID:
	var sb := PhysicsServer3D.body_create()
	PhysicsServer3D.body_set_mode(sb, PhysicsServer3D.BODY_MODE_STATIC)
	PhysicsServer3D.body_set_space(sb, space)
	PhysicsServer3D.body_add_shape(sb, shape)
	PhysicsServer3D.body_set_state(sb, PhysicsServer3D.BODY_STATE_TRANSFORM, Transform3D(Basis(), pos))
	PhysicsServer3D.body_set_collision_layer(sb, GROUND)
	PhysicsServer3D.body_set_collision_mask(sb, PART)
	PhysicsServer3D.body_set_param(sb, PhysicsServer3D.BODY_PARAM_FRICTION, C.RAGDOLL_FRICTION)
	return sb
