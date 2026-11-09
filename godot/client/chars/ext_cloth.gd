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


# names: 뼈 이름 (머리→꼬리 순), info = model_info (rest_global·rest_local)
func setup(skel: Skeleton3D, names: Array, info: Dictionary, cfg: Dictionary) -> bool:
	sk = skel
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
		var b: Vector3 = (rest_g[i + 1].origin if i + 1 < bones.size() else a + rest_g[i].basis * Vector3(0, _tip_len(i), 0))
		var d := b - a
		rest_len.append(d.length())
		rest_dir.append(d.normalized())
	k_rest = float(cfg.get("rest", k_rest))
	damp = float(cfg.get("damp", damp))
	grav = float(cfg.get("gravity", grav))
	drag = float(cfg.get("drag", drag))
	fwd_lim = float(cfg.get("fwd", fwd_lim))
	return true


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
	if not ready or anchor.distance_to(last_anchor) > 2.0:
		pts = tgt.duplicate()
		prev = tgt.duplicate()
		ready = true
	last_anchor = anchor
	var h := minf(dt, 1.0 / 20.0)
	var scl: float = W.basis.get_scale().x
	var g := Vector3(0, -grav, 0)
	pts[0] = anchor
	prev[0] = anchor
	for i in range(1, pts.size()):
		var v: Vector3 = (pts[i] - prev[i]) * pow(damp, h * 60.0) * (1.0 - drag * h)
		prev[i] = pts[i]
		pts[i] = pts[i] + v + g * h * h
		pts[i] = pts[i] + (tgt[i] - pts[i]) * (1.0 - pow(1.0 - k_rest, h * 60.0))
	if fwd_lim < 1e8: # 앞쪽 한계: 부모 뼈의 앞 (+x, 뼈대 공간) 을 월드로
		var pf: Vector3 = (W.basis * (pg.basis * (rel.basis * Vector3.RIGHT))).normalized()
		for i in range(1, pts.size()):
			var dd: float = (pts[i] - tgt[i]).dot(pf)
			if dd > fwd_lim * scl:
				pts[i] -= pf * (dd - fwd_lim * scl)
	for it in iters:
		for i in range(1, pts.size()):
			var d: Vector3 = pts[i] - pts[i - 1]
			var l := d.length()
			var want: float = rest_len[i - 1] * scl
			if l > 1e-6:
				pts[i] = pts[i - 1] + d / l * want
	# 점 → 뼈 회전: 뼈 방향 (월드) → 뼈대 공간으로, 쉬는 방향에서 그 방향으로 돌리는 최단 회전을 쉬는 회전에 곱함
	var Wi: Transform3D = W.affine_inverse()
	var par: Transform3D = pg
	for i in bones.size():
		var ds: Vector3 = (Wi.basis * (pts[i + 1] - pts[i])).normalized()
		var glob_b: Basis = Basis(Quaternion(rest_dir[i], ds)) * (rest_g[i] as Transform3D).basis
		var origin: Vector3 = par * (rest_l[i] as Transform3D).origin
		var loc_b: Basis = par.basis.orthonormalized().inverse() * glob_b
		sk.set_bone_pose_rotation(bones[i], loc_b.get_rotation_quaternion())
		sk.set_bone_pose_position(bones[i], (rest_l[i] as Transform3D).origin)
		par = Transform3D(glob_b, origin)
