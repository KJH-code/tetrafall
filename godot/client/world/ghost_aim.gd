# 유령 투하 조준 (render.js pickColumn·setGhostAim + main.js updateGhostAim·클릭): 죽은 사람이 관전 중에 시선이 닿는 기둥 꼭대기에 1칸 블록을 떨어뜨림.
# 조준 = 마우스가 잡혀 있으면 화면 가운데, 아니면 마우스 자리. 기둥 꼭대기 칸 테두리 + 내 색 반투명 큐브 (쿨 중이면 회색). 쿨 원·안내 글은 G4 HUD
# (snapshot me.ghostCd: null 못 함 · 0 가능 · ms 쿨). pick 은 순수 계산 (정답 자료 tests/fixtures/ghost.json)
# c11: 관전 따라가기에서는 화면 가운데 시선이 대상 뒤 바닥에 닿아 반투명 큐브가 대상 머리·이름표 위에 겹침 → 화면 사각형이 겹치면 면을 지우고 테두리만 (SpecCam.ghost_fill)
extends Node3D

const C := preload("res://core/config.gd")
const Co := preload("res://core/coords.gd")
const WC := preload("res://world/world_config.gd")
const SpecCam := preload("res://world/spec_cam.gd")

var aim = null # {x, y, z} 조준한 기둥 (z = 꼭대기), 없으면 null
var follow = null # c11: 관전 따라가기 대상의 화면 (보간) 자리 — 게임 좌표 Vector3, world/cam_rig.gd place 가 넣음 (전체 보기·살아 있음이면 null)
var cube := MeshInstance3D.new()
var cube_mat := StandardMaterial3D.new()
var edges := MeshInstance3D.new()
var edge_mat := StandardMaterial3D.new()
var mouse_seen := false # 마우스가 한 번이라도 움직였나 (JS ghost.mouse — 없으면 화면 가운데)


func _input(e: InputEvent) -> void:
	if e is InputEventMouseMotion:
		mouse_seen = true


# 시선 (게임 좌표 o 에서 단위 방향 d) 이 처음 닿는 칸 기둥: 바닥 (z ≤ 0) 이나 단단한 칸. 필드 밖은 지나감, 바닥 아래로 내려가면 없음
# solid: Callable(x, y, z) -> bool, top: Callable(gx, gy) -> int (기둥 꼭대기 높이)
static func pick(o: Vector3, d: Vector3, w: int, dd: int, solid: Callable, top: Callable):
	var t := 0.3
	while t < C.GHOST_AIM_RANGE:
		var x: float = o.x + d.x * t
		var y: float = o.y + d.y * t
		var z: float = o.z + d.z * t
		if z < -0.5:
			break
		var gx := floori(x)
		var gy := floori(y)
		if gx >= 0 and gy >= 0 and gx < w and gy < dd and (z <= 0 or solid.call(x, y, z)):
			return {"x": gx, "y": gy, "z": top.call(gx, gy)}
		t += 0.05
	return null


func _ready() -> void:
	var b := BoxMesh.new()
	b.size = Vector3.ONE
	cube.mesh = b
	for m in [cube_mat, edge_mat]:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.no_depth_test = m == edge_mat
	cube.material_override = cube_mat
	cube.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(cube)
	# 칸 테두리 (바닥 얇은 판 + 큐브 모서리)
	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	for box in [[Vector3(0, 0.03, 0), Vector3(1.02, 0.04, 1.02)], [Vector3(0, 0.5, 0), Vector3.ONE]]:
		var c: Vector3 = box[0]
		var h: Vector3 = box[1] / 2.0
		for a in 3:
			for s1 in [-1.0, 1.0]:
				for s2 in [-1.0, 1.0]:
					var u := Vector3.ZERO
					u[(a + 1) % 3] = s1 * h[(a + 1) % 3]
					u[(a + 2) % 3] = s2 * h[(a + 2) % 3]
					var v := u
					u[a] = -h[a]
					v[a] = h[a]
					im.surface_add_vertex(c + u)
					im.surface_add_vertex(c + v)
	im.surface_end()
	edges.mesh = im
	edges.material_override = edge_mat
	add_child(edges)
	visible = false


# on: 유령 투하 조준 중 (관전·하늘 시점 아님·ghostCd 있음). cam: 지금 카메라. color: 내 색 (0xRRGGBB). solid/top: 격자
func update(on: bool, cam: Camera3D, color: int, ready: bool, w: int, d: int, solid: Callable, top: Callable, now_ms: float) -> void:
	aim = null
	if on:
		var vp := get_viewport()
		var at: Vector2 = vp.get_visible_rect().size / 2.0 if PlayerInput.locked or not mouse_seen else vp.get_mouse_position()
		var o := Co.game(cam.project_ray_origin(at))
		var dir := Co.game(cam.project_ray_normal(at)).normalized()
		aim = pick(o, dir, w, d, solid, top)
	visible = aim != null
	if aim == null:
		return
	position = Co.gxyz(aim.x + 0.5, aim.y + 0.5, aim.z)
	cube.position = Vector3(0, 0.5, 0)
	var col := Co.color(color if ready else C.GHOST_AIM_COOLDOWN_COLOR)
	col.a = C.GHOST_AIM_OPACITY * (0.8 + 0.2 * sin(now_ms / 150.0) if ready else 0.6) * face_fill(cam)
	cube_mat.albedo_color = col
	cube.visible = col.a > 0.0 # 면이 다 지워졌으면 안 그림 (테두리는 그대로 — 어디에 떨어지는지는 남김)
	edge_mat.albedo_color = Co.color(color).lerp(Color.WHITE, 0.5) if ready else Co.color(C.GHOST_AIM_COOLDOWN_COLOR)


# c11: 면 알파 배율. 따라가는 대상이 있으면 조준 칸 (z..z+1) 과 대상 (몸 상자 가로 ±C.PLAYER_HALF, 세로 0 ~ 이름표 높이 + ghost_label_up) 을 화면 사각형으로 바꿔 겹침을 봄
func face_fill(cam: Camera3D) -> float:
	if aim == null or follow == null:
		return 1.0
	var s: Vector3 = follow
	var top: float = C.PLAYER_HEIGHT + C.LABEL_ABOVE_HEAD + WC.LABEL_LIFT + float(SpecCam.SPEC.ghost_label_up)
	var box := on_screen(cam, Vector3(aim.x, aim.y, aim.z), Vector3(aim.x + 1, aim.y + 1, aim.z + 1))
	var target := on_screen(cam, Vector3(s.x - C.PLAYER_HALF, s.y - C.PLAYER_HALF, s.z), Vector3(s.x + C.PLAYER_HALF, s.y + C.PLAYER_HALF, s.z + top))
	if box.is_empty() or target.is_empty():
		return 1.0
	return SpecCam.ghost_fill(SpecCam.screen_rect(box), SpecCam.screen_rect(target), true)


# 상자 [lo, hi] (게임 좌표) 의 8 꼭짓점이 화면에 찍히는 자리. 카메라 뒤 점은 뺌
static func on_screen(cam: Camera3D, lo: Vector3, hi: Vector3) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in 8:
		var p := Co.gxyz(hi.x if i & 1 else lo.x, hi.y if i & 2 else lo.y, hi.z if i & 4 else lo.z)
		if not cam.is_position_behind(p):
			out.append(cam.unproject_position(p))
	return out
