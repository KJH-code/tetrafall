# W23 외부 몸 천·끈 (닌자 목도리 꼬리): 뼈 사슬 (mixamorig:Scarf1~3, tools/blender/tripo/ninja_scarf.py) 을 월드 공간 줄 (verlet) 로 흔듦.
# 점 N+1 개 (뼈마다 머리 + 마지막 꼬리 끝), 맨 앞 점은 부모 뼈를 따라가고 (앵커) 나머지는 관성·중력·거리 제약으로 따라옴 → 달릴 때 뒤로 날리고,
# 맞아 날아가거나 래그돌이 쓰러지면 끌려다님. 쉬는 모양 (몸 따라 도는 사슬) 쪽으로 약하게 당겨서 늘어지지 않음. 순수 계산 (뼈·월드 변환만 받음) + 뼈 쓰기.
extends RefCounted

const Rag := preload("res://chars/ragdoll.gd")

var sk: Skeleton3D
var bones: Array[int] = []
var rest_dir: Array[Vector3] = [] # 뼈 쉬는 방향 (뼈대 공간, 단위)
var rest_len: Array[float] = [] # 뼈 길이 (뼈대 공간)
var rest_g: Array[Transform3D] = [] # 뼈 쉬는 전역 (뼈대 공간)
var rest_l: Array[Transform3D] = [] # 뼈 쉬는 지역
var parent_b := -1
var _info: Dictionary = {}
var pts: Array[Vector3] = [] # 월드
var prev: Array[Vector3] = []
var ready := false
var k_rest := 0.10 # 쉬는 모양 당김 (프레임 0~1)
var damp := 0.94 # 속도 남기기 (프레임)
var grav := 20.0 # 중력 (m/s², 월드)
var drag := 0.0 # 공기 저항 (속도에 비례, /초)
var iters := 3
var fwd_lim := 1e9 # W40: 쉬는 자리보다 몸 앞쪽으로 이만큼 (m) 넘게 못 나옴 — 등 뒤 천이 몸·다리를 뚫고 앞으로 안 오게 (cfg.fwd, 기본 끔)
var last_anchor := Vector3.ZERO
var rest_parent := Transform3D.IDENTITY
const SUB_FRAC := 0.5 # 한 서브스텝에서 앵커가 움직여도 되는 첫 마디 길이 비율
const SUB_MAX := 8
var col_bones: Array = [] # W44 몸 충돌 캡슐: [[뼈 a, 뼈 b, 반지름 (뼈대 공간)]] (cfg.cloth_colliders — 모션 QA 가 스킨 메시에서 잰 값)
var base_pen: Array[float] = [] # 점마다 쉬는 자세에서 이미 캡슐 안인 깊이 (그만큼은 안 밀어냄, 뼈대 공간)
var col_on := not (OS.get_cmdline_args().has("--no-cloth-col") or OS.get_cmdline_user_args().has("--no-cloth-col"))
var max_deg_s := 0.0 if (OS.get_cmdline_user_args().has("--no-cloth-rate")) else 3000.0 # 뼈 회전 최대 속도 (°/초, 60Hz 에서 표본당 50°)
var last_q: Array[Quaternion] = []
var substep := not (OS.get_cmdline_args().has("--no-cloth-sub") or OS.get_cmdline_user_args().has("--no-cloth-sub")) # 확인용 (모션 QA 전후 비교)


# names: 뼈 이름 (머리→꼬리 순), info = model_info (rest_global·rest_local)
func setup(skel: Skeleton3D, names: Array, info: Dictionary, cfg: Dictionary) -> bool:
	sk = skel
	_info = info
	for n in names:
		var bi := sk.find_bone(str(n))
		if bi < 0:
			return false
		bones.append(bi)
	for i in bones.size():
		var bi: int = bones[i]
		rest_g.append(info.rest_global[bi])
		rest_l.append(info.rest_local[bi])
	parent_b = sk.get_bone_parent(bones[0])
	rest_parent = info.rest_global[parent_b] if parent_b >= 0 else Transform3D.IDENTITY
	for i in bones.size():
		var a: Vector3 = rest_g[i].origin
		# 마지막 뼈 끝 = 앞 뼈와 같은 방향·길이 (W40: 뼈 +Y 축이 사슬을 따르지 않는 모델 — cloth_bones.mjs 는 세계 회전 항등 — 에서 끝점이 위로 가던 것)
		var b: Vector3 = (rest_g[i + 1].origin if i + 1 < bones.size() else (a + rest_dir[i - 1] * _tip_len(i) if i > 0 else a + rest_g[i].basis * Vector3(0, _tip_len(i), 0)))
		var d := b - a
		rest_len.append(d.length())
		rest_dir.append(d.normalized())
	for c in info.cfg.get("cloth_colliders", []):
		var ia := sk.find_bone(str(c[0]))
		var ib := sk.find_bone(str(c[1]))
		if ia >= 0 and ib >= 0:
			col_bones.append([ia, ib, float(c[2])])
	for i in range(bones.size() + 1): # 쉬는 점들의 캡슐 속 깊이
		var rp: Vector3 = rest_g[i].origin if i < bones.size() else rest_g[bones.size() - 1].origin + rest_dir[bones.size() - 1] * rest_len[bones.size() - 1]
		var dd := 0.0
		for c in col_bones:
			dd = maxf(dd, _depth(rp, rest_g_of(c[0]), rest_g_of(c[1]), float(c[2])))
		base_pen.append(dd)
	k_rest = float(cfg.get("rest", k_rest))
	damp = float(cfg.get("damp", damp))
	grav = float(cfg.get("gravity", grav))
	drag = float(cfg.get("drag", drag))
	fwd_lim = float(cfg.get("fwd", fwd_lim))
	return true


func rest_g_of(bi: int) -> Vector3:
	return (_info.rest_global[bi] as Transform3D).origin


# 점이 캡슐 (선분 a–b, 반지름 r) 속으로 들어간 깊이 (밖이면 0)
static func _depth(p: Vector3, a: Vector3, b: Vector3, r: float) -> float:
	var ab := b - a
	var l2 := ab.length_squared()
	var t := clampf((p - a).dot(ab) / l2, 0.0, 1.0) if l2 > 1e-12 else 0.0
	return maxf(0.0, r - p.distance_to(a + ab * t))


# 마지막 뼈의 길이: 앞 뼈와 같게 (Blender 뼈 꼬리는 가져올 때 사라짐)
func _tip_len(i: int) -> float:
	if i > 0:
		return (rest_g[i].origin - rest_g[i - 1].origin).length()
	return 0.1


# 뼈 전역 (뼈대 공간): 지역 자세를 부모로 곱함 (get_bone_global_pose 는 트리 밖에서 안 갱신)
func _gl(bi: int) -> Transform3D:
	var t := Transform3D.IDENTITY
	var b := bi
	while b >= 0:
		t = sk.get_bone_pose(b) * t
		b = sk.get_bone_parent(b)
	return t


# 부모 (몸통) 가 이번 프레임 자세로 정해진 뒤에 부름. dt 초
func step(dt: float) -> void:
	if sk == null or dt <= 0.0:
		return
	var W: Transform3D = Rag.glob(sk) # 트리 밖 (테스트·초상) 에서도 부모 변환을 곱해 셈
	var pg: Transform3D = _gl(parent_b) if parent_b >= 0 else Transform3D.IDENTITY
	# 쉬는 모양 목표 (월드): 부모의 지금 자세에 쉬는 상대 자리를 곱함
	var rel: Transform3D = rest_parent.affine_inverse()
	var tgt: Array[Vector3] = []
	for i in bones.size():
		tgt.append(W * (pg * (rel * rest_g[i].origin)))
	var tip_dir: Vector3 = pg.basis * (rel.basis * rest_dir[bones.size() - 1])
	tgt.append(tgt[bones.size() - 1] + W.basis * (tip_dir * rest_len[bones.size() - 1]))
	var anchor: Vector3 = tgt[0]
	var a0: Vector3 = last_anchor
	if not ready or anchor.distance_to(last_anchor) > 2.0:
		pts = tgt.duplicate()
		prev = tgt.duplicate()
		ready = true
		a0 = anchor
	var h := minf(dt, 1.0 / 20.0)
	var scl: float = W.basis.get_scale().x
	# W44 서브스텝: 앵커 (몸) 가 한 걸음에 첫 마디 길이의 절반 넘게 움직이면 (돌진·넉백·회전 공격) 한 번에 건너뛰어 사슬이 앵커 반대쪽으로 뒤집히던 것
	# (tools/motion_qa: 천 뼈 한 표본 170~180° 회전) → 앵커를 나눠 따라가며 여러 번 돌림
	var moved: float = anchor.distance_to(a0) if a0 != Vector3.INF else 0.0
	var seg: float = maxf(rest_len[0] * scl, 1e-3)
	var nsub: int = clampi(int(ceil(moved / (SUB_FRAC * seg))), 1, SUB_MAX) if substep else 1
	var cols: Array = []
	if col_on and not col_bones.is_empty():
		for c in col_bones:
			cols.append([W * _gl(c[0]).origin, W * _gl(c[1]).origin, float(c[2]) * scl])
	var a_from: Vector3 = a0 if a0 != Vector3.INF else anchor
	for sidx in nsub:
		var fa: float = float(sidx + 1) / float(nsub)
		var anc: Vector3 = a_from.lerp(anchor, fa)
		var shift: Vector3 = anc - anchor
		_verlet(h / float(nsub), anc, tgt, shift, scl, W, pg, rel, cols)
	last_anchor = anchor
	# 점 → 뼈 회전: 뼈 방향 (월드) → 뼈대 공간으로, 쉬는 방향에서 그 방향으로 돌리는 최단 회전을 쉬는 회전에 곱함
	var Wi: Transform3D = W.affine_inverse()
	var par: Transform3D = pg
	for i in bones.size():
		var ds: Vector3 = (Wi.basis * (pts[i + 1] - pts[i])).normalized()
		var glob_b: Basis = Basis(Quaternion(rest_dir[i], ds)) * (rest_g[i] as Transform3D).basis
		var origin: Vector3 = par * (rest_l[i] as Transform3D).origin
		var loc_b: Basis = par.basis.orthonormalized().inverse() * glob_b
		var qn: Quaternion = loc_b.get_rotation_quaternion()
		if max_deg_s > 0.0:
			# W44 회전 속도 제한: 사슬이 앵커 반대쪽으로 순식간에 뒤집혀도 (한 표본 170°) 뼈는 이만큼씩만 돌아가 따라옴
			if last_q.size() <= i:
				last_q.append(qn)
			else:
				var lq: Quaternion = last_q[i]
				if lq.dot(qn) < 0.0:
					qn = Quaternion(-qn.x, -qn.y, -qn.z, -qn.w)
				var ad: float = rad_to_deg(lq.angle_to(qn))
				var mx: float = max_deg_s * minf(dt, 1.0 / 20.0)
				if ad > mx:
					qn = lq.slerp(qn, mx / ad)
				last_q[i] = qn
		sk.set_bone_pose_rotation(bones[i], qn)
		sk.set_bone_pose_position(bones[i], (rest_l[i] as Transform3D).origin)
		par = Transform3D(glob_b, origin)


# 한 서브스텝 (anc = 이 걸음의 앵커, shift = 목표 점을 앵커 따라 옮길 만큼)
func _verlet(h: float, anc: Vector3, tgt: Array, shift: Vector3, scl: float, W: Transform3D, pg: Transform3D, rel: Transform3D, cols: Array) -> void:
	var g := Vector3(0, -grav, 0)
	pts[0] = anc
	prev[0] = anc
	for i in range(1, pts.size()):
		var v: Vector3 = (pts[i] - prev[i]) * pow(damp, h * 60.0) * (1.0 - drag * h)
		prev[i] = pts[i]
		pts[i] = pts[i] + v + g * h * h
		pts[i] = pts[i] + ((tgt[i] as Vector3) + shift - pts[i]) * (1.0 - pow(1.0 - k_rest, h * 60.0))
	if fwd_lim < 1e8: # 앞쪽 한계: 부모 뼈의 앞 (+x, 뼈대 공간) 을 월드로
		var pf: Vector3 = (W.basis * (pg.basis * (rel.basis * Vector3.RIGHT))).normalized()
		for i in range(1, pts.size()):
			var dd: float = (pts[i] - ((tgt[i] as Vector3) + shift)).dot(pf)
			if dd > fwd_lim * scl:
				pts[i] -= pf * (dd - fwd_lim * scl)
	for it in iters:
		for i in range(1, pts.size()):
			var d: Vector3 = pts[i] - pts[i - 1]
			var l := d.length()
			var want: float = rest_len[i - 1] * scl
			if l > 1e-6:
				pts[i] = pts[i - 1] + d / l * want
	if not cols.is_empty(): # W44 몸 충돌: 캡슐 속으로 들어간 점을 밖으로 (쉬는 자리에서 이미 안인 만큼은 빼고), 그 뒤 마디 길이 한 번 더
		for i in range(1, pts.size()):
			var p: Vector3 = pts[i]
			var bp: float = base_pen[i] * scl if i < base_pen.size() else 0.0
			for c in cols:
				var ab: Vector3 = c[1] - c[0]
				var l2 := ab.length_squared()
				var t := clampf((p - c[0]).dot(ab) / l2, 0.0, 1.0) if l2 > 1e-12 else 0.0
				var q: Vector3 = c[0] + ab * t
				var dv: Vector3 = p - q
				var dl := dv.length()
				var r: float = float(c[2]) - bp
				if dl < r and dl > 1e-6:
					p = q + dv / dl * r
			pts[i] = p
		for i in range(1, pts.size()):
			var d2: Vector3 = pts[i] - pts[i - 1]
			var l3 := d2.length()
			if l3 > 1e-6:
				pts[i] = pts[i - 1] + d2 / l3 * rest_len[i - 1] * scl
