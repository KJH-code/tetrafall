# G3 확인 장면: 툰·외곽선 (나중에 테마) 를 JS 판 (scratch three 페이지) 과 같은 물체·빛·카메라로 그려 스샷.
#   xvfb-run -a godot --path godot/client --rendering-driver opengl3 res://shaders/demo/g3_demo.tscn -- --shot /tmp/g3.png [--theme crystal]
# 물체 자리는 게임 좌표 (x, y, z 위) — core/coords 로 고도 좌표
extends Node3D

const C := preload("res://core/config.gd")
const G3 := preload("res://shaders/g3.gd")
const K := preload("res://shaders/g3_config.gd")
const Coords := preload("res://core/coords.gd")

# [모양, 게임 자리, 크기, 색]
const THINGS := [
	["box", Vector3(4, 4, -0.15), Vector3(8, 8, 0.3), 0xa49aa0],
	["box", Vector3(1.5, 1.5, 0.5), Vector3(1, 1, 1), 0xe0533a],
	["box", Vector3(3.5, 2.5, 0.5), Vector3(1, 1, 1), 0x3a7be0],
	["box", Vector3(3.5, 2.5, 1.5), Vector3(1, 1, 1), 0x58c06a],
	["sphere", Vector3(2.5, 5, 0.7), Vector3(0.7, 0, 0), 0xf2c53d],
	["cyl", Vector3(5.5, 4.5, 1), Vector3(0.5, 2, 0), 0xb06ad8],
	["box", Vector3(14, 22, 2), Vector3(3, 3, 4), 0x8a8f9a],
	["box", Vector3(-6, 40, 4), Vector3(5, 5, 8), 0x8a8f9a],
	["box", Vector3(30, 60, 6), Vector3(8, 8, 12), 0x8a8f9a],
]

var shot := ""
var theme = null
var batch := -1 # --body 0|1: 시험 몸 (tests/test_batch.gd) 을 조각대로 (0) / G3.batch_mesh 로 (1) — 화소가 같아야 함
var terrain := false # --terrain: 테마 지형 블록 (terrain_grids.json, js_demo ?terrain 과 같음)


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "--shot" and i + 1 < args.size():
			shot = args[i + 1]
		if args[i] == "--theme" and i + 1 < args.size():
			theme = args[i + 1]
		if args[i] == "--body" and i + 1 < args.size():
			batch = int(args[i + 1])
		if args[i] == "--terrain":
			terrain = true
	G3.apply_theme(self, theme)
	var things := THINGS
	var cx := 4.0
	if terrain:
		cx = 6.0
		things = [["box", Vector3(6, 6, -0.15), Vector3(12, 12, 0.3), 0xa49aa0]]
		_terrain()
	if batch >= 0:
		things = [THINGS[0]]
		var body: Node3D = load("res://tests/test_batch.gd").new()._body()
		body.position = Coords.gxyz(4, 4, 1.2)
		body.get_node("torso/arm").rotation = Vector3(1.1, -0.4, 0.8)
		body.get_node("torso/arm").scale = Vector3(1, 1.3, 0.9)
		add_child(body)
		if batch == 1:
			G3.batch_mesh(body)
	G3.set_field(self, cx * 2, cx * 2)
	for t in things:
		var mi := MeshInstance3D.new()
		match t[0]:
			"box":
				var b := BoxMesh.new()
				b.size = Coords.gpos(t[2]).abs()
				mi.mesh = b
			"sphere":
				var s := SphereMesh.new()
				s.radius = t[2].x
				s.height = t[2].x * 2
				s.radial_segments = 32
				s.rings = 16
				mi.mesh = s
			"cyl":
				var cy := CylinderMesh.new()
				cy.top_radius = t[2].x
				cy.bottom_radius = t[2].x
				cy.height = t[2].y
				cy.radial_segments = 24
				mi.mesh = cy
		mi.position = Coords.gpos(t[1])
		mi.material_override = G3.toon_material(t[3])
		if t == things[0] and G3.floor_material(theme) != null:
			mi.material_override = G3.floor_material(theme) # 바닥 판 (테마 무늬)
		add_child(mi)
	var cam := Camera3D.new()
	cam.fov = 60
	cam.near = 0.05 # render.js 카메라
	cam.far = 200.0
	add_child(cam)
	if terrain:
		cam.look_at_from_position(Coords.gxyz(16, -5, 11), Coords.gxyz(6, 6, 1), Vector3.UP)
	else:
		cam.look_at_from_position(Coords.gxyz(9, -5, 4), Coords.gxyz(4, 8, 2.5), Vector3.UP)
	if shot != "":
		for i in 6:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(shot)
		var vp := get_viewport().get_viewport_rid()
		print("그리기 보이는/그림자: ", RenderingServer.viewport_get_render_info(vp, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME), " / ", RenderingServer.viewport_get_render_info(vp, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_SHADOW, RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME))
		get_tree().quit()


# 지형 칸 MultiMesh (G1 grid_view 가 할 것과 같게: 칸 자리 + custom_data = G3.terrain_custom)
func _terrain() -> void:
	var j = JSON.parse_string(FileAccess.get_file_as_string("res://shaders/demo/terrain_grids.json"))
	var w := int(j.W)
	var d := int(j.D)
	var h := int(j.H)
	var grid := PackedByteArray()
	for v in j.grids[theme]:
		grid.append(int(v))
	var look := G3.terrain_custom(grid, w, d, h)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = G3.terrain_mesh(theme)
	mm.instance_count = look.size()
	var n := 0
	for z in h:
		for y in d:
			for x in w:
				if grid[(z * d + y) * w + x] == 1:
					mm.set_instance_transform(n, Transform3D(Basis(), Coords.gxyz(x + 0.5, y + 0.5, z + 0.5)))
					mm.set_instance_custom_data(n, look[n])
					n += 1
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.material_override = G3.terrain_material(theme)
	add_child(mi)
	var sp := G3.sprout_node(theme)
	if sp:
		add_child(sp)
		G3.sprout_update(sp, grid, w, d, h)
