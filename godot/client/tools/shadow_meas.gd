# 해 그림자 비용 재기 (W32): 8명 몸 + 떨어지는 칸 + 쌓인 칸을 해 그림자 켠 장면에 놓고 그림자 패스 삼각형·그리기·물체와 화면 삼각형을 켬/끔 (--no-shadow-opt) 으로 비교.
# xvfb-run -a godot --path godot/client --rendering-driver opengl3 --resolution 1280x720 -s res://tools/shadow_meas.gd -- [--chars ninja,tank,hunter,hook,ninja,tank,hunter,hook] [--level high|medium|low] [--theme castle] [--cells 150] [--falling 24] [--far 40] [--close|--zoom] [--no-shadow-opt] [--shot a.png]
#   --far <m>: 몸 절반을 카메라에서 이만큼 뒤로 (먼 몸 그림자 끄기 확인)   --cells: 쌓인 칸 수   --falling: 떨어지는 칸 수
extends SceneTree

const WC := preload("res://world/world_config.gd")
const Co := preload("res://core/coords.gd")

var frames := 0
var cam: Camera3D
var bodies_node: Node3D
var chars: Array = []
var shot := ""
var far := 0.0
var bd = null # world/bodies.gd (몸 LOD·그림자 판정까지 같이 돌림)


func _arg(a: PackedStringArray, k: String, d: String) -> String:
	var i := a.find(k)
	return a[i + 1] if i >= 0 and i + 1 < a.size() else d


func _build() -> void:
	var a := OS.get_cmdline_user_args()
	var G3 = load("res://shaders/g3.gd")
	var Gfx = load("res://world/gfx.gd")
	Gfx.plan = {"level": _arg(a, "--level", "high")}
	var theme := _arg(a, "--theme", "castle")
	chars = _arg(a, "--chars", "ninja,tank,hunter,hook,ninja,tank,hunter,hook").split(",")
	shot = _arg(a, "--shot", "")
	far = float(_arg(a, "--far", "0"))
	WC.shadow_opt = not a.has("--no-shadow-opt")
	var fw := 19
	RenderingServer.set_default_clear_color(Color(0.45, 0.7, 0.95))
	var world := Node3D.new()
	world.name = "World"
	root.add_child(world)
	G3.set_field(world, fw, fw) # G3Env: 해·하늘·안개 + 그림자 거리 (판 크기)
	var sun: DirectionalLight3D = world.get_node("G3Env/Sun")
	sun.shadow_enabled = true
	sun.light_energy = 1.0
	sun.look_at_from_position(Vector3.ZERO, Vector3(-0.5, -1.0, -0.4), Vector3.UP)
	cam = Camera3D.new()
	world.add_child(cam)
	cam.fov = 70.0
	cam.far = 200.0
	cam.global_position = Vector3(fw / 2.0, 6.0, 4.0)
	cam.look_at(Vector3(fw / 2.0, 0.0, -fw / 2.0 + 2.0))
	if a.has("--zoom"): # 첫 몸 (gx 3, gy 4) 하나만 크게 (단검·손 모습 전후 비교)
		cam.fov = 28.0
		cam.global_position = Vector3(4.6, 1.5, -1.8)
		cam.look_at(Vector3(3.0, 0.95, -4.0))
	elif a.has("--close"): # 4명 가까이 (모습 전후 비교)
		cam.fov = 60.0
		cam.global_position = Vector3(fw / 2.0, 3.2, 3.5)
		cam.look_at(Vector3(fw / 2.0, 0.9, -4.0))
	var floor_m := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(fw, 0.5, fw)
	floor_m.mesh = bm
	floor_m.position = Co.gxyz(fw / 2.0, fw / 2.0, -0.25)
	world.add_child(floor_m)
	var Chars = load("res://chars/chars.gd")
	var Bodies = load("res://world/bodies.gd")
	bd = Bodies.new()
	bd.cam = cam
	bd.pos_fn = func(p, _pos): return Vector3(p.x, p.y, p.z) # 몸 자리는 Store 보간 대신 정한 자리 그대로
	world.add_child(bd)
	bodies_node = bd
	var st_players := []
	for i in chars.size():
		var col := Color.from_hsv(i / 8.0, 0.7, 0.9)
		var b = Chars.make_body(chars[i], col)
		var root_n := Node3D.new()
		var gx := 3.0 + (i % 4) * 4.0
		var gy := 4.0 + (i / 4) * 6.0
		if far > 0.0 and i >= chars.size() / 2:
			gy += far # 카메라 앞쪽 (판 안쪽 방향) 으로 이만큼 더 멀리
		root_n.position = Co.gxyz(gx, gy, 0.0)
		root_n.add_child(b)
		world.add_child(root_n)
		bd.nodes[i + 1] = {"root": root_n, "body": b, "label": Label3D.new(), "char": chars[i], "color": 0, "bar_back": Sprite3D.new(), "bar_fill": Sprite3D.new()}
		st_players.append({"id": i + 1, "char": chars[i], "alive": true, "yaw": 0.0, "x": gx, "y": gy, "z": 0.0, "slot": i})
	# 떨어지는 칸·쌓인 칸 (테마 칸 모양)
	var mesh: Mesh = G3.piece_mesh(theme, false)
	var mat: Material = G3.piece_material(theme, false, {"rim": 0.0})
	var PV = load("res://world/pieces_view.gd")
	var pv = PV.new()
	world.add_child(pv)
	pv.set_look(mesh, [mat, mat], G3.piece_colors(theme))
	var nf := int(_arg(a, "--falling", "24"))
	var cells := []
	for i in nf:
		cells.append([2 + (i * 3) % 15, 2 + (i * 5) % 15, 8 + (i / 4)])
	pv.update({"pieces": [{"shape": "T", "cells": cells, "sky": false}]}, 1, {}, 0.0)
	var GV = load("res://world/grid_view.gd")
	var gv = GV.new()
	world.add_child(gv)
	gv.set_piece_look(mesh, mat, G3.piece_colors(theme))
	var ncell := int(_arg(a, "--cells", "150"))
	var grid := PackedByteArray()
	grid.resize(fw * fw * 12)
	for i in ncell:
		grid[((i * 7919) % (fw * fw)) + fw * fw * (i % 3)] = 5
	gv.rebuild(grid, fw, fw, 12)
	print("SHADOW_MEAS opt=%s level=%s chars=%s far=%.0f cells=%d falling=%d" % [WC.shadow_opt, Gfx.plan.level, ",".join(chars), far, ncell, nf])
	for i in chars.size():
		st_players[i]["nick"] = ""
	_players = st_players


var _players: Array = []


func _process(_d: float) -> bool:
	frames += 1
	if frames == 1:
		_build() # (트리가 돌기 시작한 다음에 — look_at·_ready 가 트리 안을 요구함)
		return false
	if frames <= 3 or frames == 6:
		bd.update({"players": _players, "teamMode": false}, 1, false, false, frames * 16.0)
	if frames == 9:
		var vp := root
		var V := Viewport.RENDER_INFO_TYPE_VISIBLE
		var S := Viewport.RENDER_INFO_TYPE_SHADOW
		var info := func(t: int, w: int) -> int: return vp.get_render_info(t, w)
		print("SHADOW_MEAS 그리기 %d + 그림자 %d · 물체 %d + %d · 삼각형 %d + %d (화면 + 그림자) · 영상 메모리 %.1fMB" % [
			info.call(V, Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME), info.call(S, Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME),
			info.call(V, Viewport.RENDER_INFO_OBJECTS_IN_FRAME), info.call(S, Viewport.RENDER_INFO_OBJECTS_IN_FRAME),
			info.call(V, Viewport.RENDER_INFO_PRIMITIVES_IN_FRAME), info.call(S, Viewport.RENDER_INFO_PRIMITIVES_IN_FRAME),
			Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0])
		var off := 0
		for id in bd.nodes:
			off += 1 if bd.nodes[id].body.has_method("shadow_off") and bd.nodes[id].body.shadow_off() else 0
		print("SHADOW_MEAS 그림자 끈 몸 %d/%d · 그림자 거리 %.1f" % [off, bd.nodes.size(), (world_sun().directional_shadow_max_distance)])
		if shot != "":
			var img := root.get_texture().get_image()
			img.save_png(shot)
		quit()
	return false


func world_sun() -> DirectionalLight3D:
	return root.get_node("World/G3Env/Sun")
