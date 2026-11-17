# 돌발 이벤트 '번개' 그리기 (c9): 서버 이벤트 boltWarn → 바닥 예고 고리 (8조각으로 끊긴 흰 심 + 잉크 테 고리, 안에서 연노랑 원이 차오르다 고리에 닿으면 떨어짐),
# bolt → 하늘에서 그 자리로 꺾인 띠 3단 (잉크 테 · 연노랑 · 흰 심) 이 잠깐 + 바닥 고리 한 번 (world/ring_look.gd aura).
# 스스로 Store.game_event 를 잇고 스스로 돎 (_process) — world.gd 는 만들어 넣기만. 스냅샷엔 예고가 없어 이벤트로만 알고, 판 중이 아니면 다 비움.
# 그리기: 예고 = MultiMesh 하나 (고리·원을 한 메시에 — bolt_fx_math.warn_mesh), 번개 띠 = MultiMesh 하나 (토막마다 인스턴스). 평소엔 둘 다 숨김 (그리기 0), 그래픽 낮춤에서도 켬.
# 재질은 ring_look.material (world/warm_scan.gd STD_KEYS 에 있는 모양 — 새 셰이더 없음). 순수 계산·수치는 world/bolt_fx_math.gd
extends Node3D

const M := preload("res://world/bolt_fx_math.gd")
const RL := preload("res://world/ring_look.gd")
const Co := preload("res://core/coords.gd")

var warns := [] # 아직 안 떨어진 예고 (bolt_fx_math.warn_add 항목)
var strikes := [] # 떨어진 번개 {x, y, z, t0, pts (지그재그 점)}
var flashes := [] # 바닥 고리 {node, mat, t0, r}
# 그리는 것은 트리에 들어갈 때 (_ready) 만듦 — world.gd 가 이 노드를 변수 선언에서 만들어, 트리에 안 넣는 테스트 (World 만 만들어 _process 를 부름) 에서 메시·재질이 떠돌지 않게
var warn_mm: MultiMesh
var warn_mmi: MultiMeshInstance3D
var bolt_mm: MultiMesh
var bolt_mmi: MultiMeshInstance3D

# 견본 도구 (tools/bolt_sheet.gd) 가 시각을 손으로 정할 수 있게 — 비어 있으면 판 시계 Net.now_ms (실제 시각, 녹화 재연이면 가상 시계 —
# 느린 기계에서 재연해도 예고가 스냅샷과 같은 빠르기로 흐름. 실제 시각을 쓰면 재연 한 프레임 사이에 예고가 다 지나가 버림)
static var clock := Callable()


static func now_ms() -> float:
	return float(clock.call()) if clock.is_valid() else Net.now_ms()


func _ready() -> void:
	warn_mm = MultiMesh.new()
	warn_mmi = MultiMeshInstance3D.new()
	bolt_mm = MultiMesh.new()
	bolt_mmi = MultiMeshInstance3D.new()
	_pool(warn_mmi, warn_mm, M.warn_mesh(), int(M.WARN.max) * 2, RL.material(1.0, int(M.WARN.priority)))
	_pool(bolt_mmi, bolt_mm, M.quad_mesh(), int(M.STRIKE.max) * int(M.STRIKE.joints) * M.STRIKE.layers.size(), RL.material())
	Store.game_event.connect(on_event)


func _exit_tree() -> void:
	M.clear_static()
	RL.clear_static()


func _pool(mmi: MultiMeshInstance3D, mm: MultiMesh, mesh: Mesh, n: int, mat: Material) -> void:
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = n
	mm.visible_instance_count = 0
	mmi.multimesh = mm
	mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.extra_cull_margin = 16384.0 # 필드 어디든 (인스턴스가 움직여도 잘리지 않게 — fx/effects.gd 풀과 같음)
	mmi.visible = false
	add_child(mmi)


func on_event(e: Dictionary) -> void:
	match str(e.get("type", "")):
		"boltWarn":
			M.warn_add(warns, e, now_ms())
		"bolt":
			M.warn_remove(warns, e.get("id")) # 모르는 id (판 중에 들어옴) 여도 번개는 그림
			if e.get("x") == null or e.get("y") == null or not M.keep(Store.phase()):
				return
			var now := now_ms()
			var r := float(e.get("r", 0.0))
			var at := Vector3(float(e.x), float(e.y), float(e.get("z", 0.0)))
			if strikes.size() >= int(M.STRIKE.max):
				strikes.pop_front()
			strikes.append({"x": at.x, "y": at.y, "z": at.z, "t0": now, "pts": M.zigzag(int(e.get("id", 0)), float(M.STRIKE.height))})
			if r > 0.0:
				_flash(at, r, now)


# 떨어진 자리 바닥 고리 한 번 (스킬 고리와 같은 메시·재질, 색만 번개 연노랑)
func _flash(at: Vector3, r: float, now: float) -> void:
	var mat := RL.material(float(M.STRIKE.flash_alpha))
	var n := MeshInstance3D.new()
	n.mesh = RL.mesh("aura", int(M.STRIKE.glow))
	n.material_override = mat
	n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	n.position = Co.gxyz(at.x, at.y, at.z + float(M.WARN.lift))
	var s := M.flash(0.0, r).x
	n.scale = Vector3(s, 1, s)
	add_child(n)
	flashes.append({"node": n, "mat": mat, "t0": now, "r": r})


func clear() -> void:
	warns.clear()
	strikes.clear()
	for f in flashes:
		f.node.queue_free()
	flashes.clear()
	if warn_mmi != null:
		warn_mmi.visible = false
		bolt_mmi.visible = false


func _process(_dt: float) -> void:
	frame(now_ms(), get_viewport().get_camera_3d())


# 한 프레임: 예고·번개·바닥 고리를 지금 시각 (ms) 모습으로. cam 이 없으면 (테스트) 화면 상한 없이
func frame(now: float, cam: Camera3D) -> void:
	if warns.is_empty() and strikes.is_empty() and flashes.is_empty():
		if warn_mmi.visible or bolt_mmi.visible:
			clear()
		return
	if not M.keep(Store.phase()):
		clear()
		return
	M.warn_expire(warns, now)
	_warns(now)
	_strikes(now, cam)
	for i in range(flashes.size() - 1, -1, -1):
		var f: Dictionary = flashes[i]
		var v := M.flash(now - float(f.t0), float(f.r))
		if v.y < 0.0:
			f.node.queue_free()
			flashes.remove_at(i)
			continue
		f.node.scale = Vector3(v.x, 1, v.x)
		f.mat.albedo_color.a = v.y


func _warns(now: float) -> void:
	var n := 0
	for w in warns:
		if n + 2 > warn_mm.instance_count:
			break
		var u := M.warn_u(now, float(w.t0), float(w.ms))
		var a := M.warn_alpha(u)
		var at := Co.gxyz(w.x, w.y, w.z + float(M.WARN.lift))
		warn_mm.set_instance_transform(n, Transform3D(M.fill_basis(float(w.r) * M.fill_frac(u)), at))
		warn_mm.set_instance_color(n, M.fill_color(a))
		warn_mm.set_instance_transform(n + 1, Transform3D(M.ring_basis(M.warn_radius(u, float(w.r)), float(M.WARN.spin) * (now - float(w.t0)) / 1000.0), at))
		warn_mm.set_instance_color(n + 1, M.ring_color(a))
		n += 2
	warn_mm.visible_instance_count = n
	warn_mmi.visible = n > 0


func _strikes(now: float, cam: Camera3D) -> void:
	for i in range(strikes.size() - 1, -1, -1):
		if M.strike_alpha(now - float(strikes[i].t0)) < 0.0:
			strikes.remove_at(i)
	var n := 0
	var height := float(M.STRIKE.height)
	var has_cam := cam != null and cam.is_inside_tree()
	var cam_inv := cam.global_transform.affine_inverse() if has_cam else Transform3D.IDENTITY
	# 단 (바깥 → 안) 을 바깥 묶음으로: 인스턴스 차례 = 그리는 차례 → 흰 심이 맨 위
	for layer in M.STRIKE.layers:
		for s in strikes:
			var foot := Co.gxyz(s.x, s.y, s.z)
			var k := M.strike_cap(height, cam_inv * foot, cam_inv.basis * Vector3.UP, cam.fov) if has_cam else 1.0
			if k <= 0.0:
				continue
			var a := M.strike_alpha(now - float(s.t0))
			# 띠는 카메라를 보는 세로 판 위에서 꺾임 (카메라가 바로 위면 카메라의 오른쪽)
			var to_cam := (cam.global_position - foot) if has_cam else Vector3.BACK
			var right := Vector3.UP.cross(to_cam)
			right = right.normalized() if right.length() > 1e-4 else (cam.global_transform.basis.x if has_cam else Vector3.RIGHT)
			var pts: PackedVector2Array = s.pts
			for j in pts.size() - 1:
				if n >= bolt_mm.instance_count:
					break
				var p0 := foot + (Vector3.UP * pts[j].y + right * pts[j].x) * k
				var p1 := foot + (Vector3.UP * pts[j + 1].y + right * pts[j + 1].x) * k
				var dir := (p1 - p0).normalized()
				if j > 0: # 마디 이음만 겹침 — 바닥 끝·꼭대기 끝은 그대로 (띠 높이 = 화면 상한이 잰 높이)
					p0 -= dir * float(M.STRIKE.overlap) * k
				if j < pts.size() - 2:
					p1 += dir * float(M.STRIKE.overlap) * k
				var view := (cam.global_position - (p0 + p1) / 2.0) if has_cam else Vector3.BACK
				var side := dir.cross(view)
				side = side.normalized() if side.length() > 1e-4 else right
				bolt_mm.set_instance_transform(n, Transform3D(Basis(side * float(layer[0]) * k, p1 - p0, side.cross(dir)), p0))
				bolt_mm.set_instance_color(n, M.layer_color(str(layer[1]), a * float(layer[2]) * M.top_alpha((pts[j].y + pts[j + 1].y) / 2.0 / height)))
				n += 1
	bolt_mm.visible_instance_count = n
	bolt_mmi.visible = n > 0
