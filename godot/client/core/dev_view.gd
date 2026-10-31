# 개발용 판 그림 (G0): world/world.tscn (G1) 이 생기기 전까지만. 상자로 격자·떨어지는 블록·사람, 내 뒤 3인칭 카메라.
# 게임 좌표 (x, y 바닥, z 위) → 고도 Vector3(x, z, y). 위치는 Store.view_pos (보간)
extends Node3D

const C := preload("res://core/config.gd")
const Co := preload("res://core/coords.gd")

var cam: Camera3D
var grid_mm: MultiMeshInstance3D
var piece_pool: Array = []
var bodies := {}
var lava: MeshInstance3D
var floor_mesh: MeshInstance3D
var headless := false


static func gpos(v: Vector3) -> Vector3:
	return Co.gpos(v)


func _ready() -> void:
	headless = DisplayServer.get_name() == "headless"
	if headless:
		return
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color("1d2440")
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color("8090c0")
	env.environment.ambient_light_energy = 0.7
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -35, 0)
	sun.shadow_enabled = true
	add_child(sun)
	cam = Camera3D.new()
	cam.fov = 70
	add_child(cam)
	grid_mm = MultiMeshInstance3D.new()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	var box := BoxMesh.new()
	box.size = Vector3.ONE * 0.97
	mm.mesh = box
	grid_mm.multimesh = mm
	var gm := StandardMaterial3D.new()
	gm.vertex_color_use_as_albedo = true
	grid_mm.material_override = gm
	add_child(grid_mm)
	floor_mesh = MeshInstance3D.new()
	floor_mesh.mesh = BoxMesh.new()
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color("5f7a4a")
	floor_mesh.material_override = fm
	add_child(floor_mesh)
	lava = MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(80, 80)
	lava.mesh = pm
	var lm := StandardMaterial3D.new()
	lm.albedo_color = Color(1, 0.35, 0.1)
	lm.emission_enabled = true
	lm.emission = Color(1, 0.3, 0.05)
	lava.material_override = lm
	add_child(lava)
	Store.grid_changed.connect(func(_v): _build_grid())


func _build_grid() -> void:
	var f: Dictionary = Store.state.get("field", {})
	if f.is_empty():
		return
	var w := int(f.w)
	var d := int(f.d)
	var cells := []
	for i in Store.grid.size():
		if Store.grid[i] != 0:
			cells.append(i)
	grid_mm.multimesh.instance_count = cells.size()
	for k in cells.size():
		var i: int = cells[k]
		var x := i % w
		var y := (i / w) % d
		var z := i / (w * d)
		grid_mm.multimesh.set_instance_transform(k, Transform3D(Basis(), gpos(Vector3(x + 0.5, y + 0.5, z + 0.5))))
		var v: int = Store.grid[i]
		grid_mm.multimesh.set_instance_color(k, Color("8d9a6a") if v == 1 else Color.from_hsv(fmod(v * 0.13, 1.0), 0.5, 0.95))


func _process(_d: float) -> void:
	if headless or Store.state.is_empty():
		return
	var st := Store.state
	var f: Dictionary = st.field
	floor_mesh.mesh.size = Vector3(f.w, 0.5, f.d)
	floor_mesh.position = Co.gxyz(f.w / 2.0, f.d / 2.0, -0.25)
	lava.visible = st.lava.active
	lava.position.y = st.lava.z
	# 떨어지는 블록
	var k := 0
	for pc in st.pieces:
		for c in pc.cells:
			if k >= piece_pool.size():
				var m := MeshInstance3D.new()
				var b := BoxMesh.new()
				b.size = Vector3.ONE * 0.97
				m.mesh = b
				add_child(m)
				piece_pool.append(m)
			piece_pool[k].visible = true
			piece_pool[k].position = gpos(Vector3(c[0] + 0.5, c[1] + 0.5, c[2] + 0.5))
			k += 1
	for i in range(k, piece_pool.size()):
		piece_pool[i].visible = false
	# 사람 (보간 위치)
	var seen := {}
	for p in st.players:
		var id := int(p.id)
		seen[id] = true
		if not bodies.has(id):
			bodies[id] = _make_body(int(p.color))
		var node: Node3D = bodies[id]
		node.visible = p.alive and not p.get("master", false)
		node.position = gpos(Store.view_pos(id))
		node.rotation = Vector3(0, Co.rot_y(p.yaw), 0)
		(node.get_node("Label") as Label3D).text = "%s %d%%" % [p.nick if str(p.nick) != "" else p.name, int(p.damage)]
	for id in bodies.keys():
		if not seen.has(id):
			bodies[id].queue_free()
			bodies.erase(id)
	# 카메라: 내 뒤 3인칭 (PlayerInput 시선), 방 밖·관전이면 필드 위
	var me := Store.me()
	if not me.is_empty() and me.alive:
		var at := gpos(Store.view_pos(Store.my_id)) + Vector3(0, 1.4, 0)
		var yaw := PlayerInput.yaw
		var pitch := PlayerInput.pitch
		var fwd := Co.dir(yaw, pitch)
		cam.position = at - fwd * 4.0 + Vector3(0, 0.6, 0)
		cam.look_at(at + fwd * 2.0)
	else:
		cam.position = Co.gxyz(f.w / 2.0, -f.d * 0.4, f.w * 1.1)
		cam.look_at(Co.gxyz(f.w / 2.0, f.d / 2.0, 0))


func _make_body(color_index: int) -> Node3D:
	var root := Node3D.new()
	var body := MeshInstance3D.new()
	var cm := CapsuleMesh.new()
	cm.radius = C.PLAYER_HALF
	cm.height = C.PLAYER_HEIGHT
	body.mesh = cm
	body.position.y = C.PLAYER_HEIGHT / 2
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Co.color(C.PLAYER_PALETTE[color_index % C.PLAYER_PALETTE.size()])
	body.material_override = mat
	root.add_child(body)
	var nose := MeshInstance3D.new()
	var nb := BoxMesh.new()
	nb.size = Vector3(0.3, 0.15, 0.15)
	nose.mesh = nb
	nose.position = Vector3(0.35, C.PLAYER_HEIGHT * 0.75, 0)
	nose.material_override = mat
	root.add_child(nose)
	var lab := Label3D.new()
	lab.name = "Label"
	lab.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lab.position.y = C.PLAYER_HEIGHT + 0.45
	lab.font_size = 40
	lab.outline_size = 10
	lab.pixel_size = 0.006
	root.add_child(lab)
	add_child(root)
	return root
