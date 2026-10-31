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


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "--shot" and i + 1 < args.size():
			shot = args[i + 1]
		if args[i] == "--theme" and i + 1 < args.size():
			theme = args[i + 1]
	G3.apply_theme(self, theme)
	G3.set_field(self, 8, 8)
	for t in THINGS:
		var mi := MeshInstance3D.new()
		match t[0]:
			"box":
				var b := BoxMesh.new()
				b.size = Coords.gpos(t[2])
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
		add_child(mi)
	var cam := Camera3D.new()
	cam.fov = 60
	cam.near = 0.05 # render.js 카메라
	cam.far = 200.0
	add_child(cam)
	cam.look_at_from_position(Coords.gxyz(9, -5, 4), Coords.gxyz(4, 8, 2.5), Vector3.UP)
	if shot != "":
		for i in 6:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(shot)
		get_tree().quit()
