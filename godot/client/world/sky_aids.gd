# 하늘 시점 도우미 (client/sky-aids.js 그대로): 내 블록 착지 칸 반투명 + 지금 칸에서 내려가는 빛 기둥 (못 놓으면 빨강)
# + 생존자 머리 위 아래로 향한 삼각뿔 + 바닥까지 빛 기둥 (그 사람 색). MultiMesh 넷 + 착지 칸 테두리 선
extends Node3D

const C := preload("res://core/config.gd")
const Co := preload("res://core/coords.gd")
const SkyV := preload("res://world/sky_view.gd")

const CAP := 16

var ghost: MultiMeshInstance3D
var pillar: MultiMeshInstance3D
var cone: MultiMeshInstance3D
var beam: MultiMeshInstance3D
var edges := MeshInstance3D.new()
var edge_mat := StandardMaterial3D.new()


func _pool(mesh: Mesh, opacity: float, order: int) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = CAP
	mm.visible_instance_count = 0
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.vertex_color_use_as_albedo = true
	m.albedo_color = Color(1, 1, 1, opacity)
	m.render_priority = order
	var n := MultiMeshInstance3D.new()
	n.multimesh = mm
	n.material_override = m
	n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(n)
	return n


func _ready() -> void:
	var v: Dictionary = C.SKY_VIEW
	var box := BoxMesh.new()
	box.size = Vector3.ONE * 0.98
	ghost = _pool(box, v.ghost, 3)
	var unit := BoxMesh.new()
	pillar = _pool(unit, v.pillar[1], 3)
	var cn := CylinderMesh.new() # 아래로 향한 삼각뿔 (위 반지름 0.5, 아래 0, 네 모)
	cn.top_radius = 0.5
	cn.bottom_radius = 0.0
	cn.height = 1.0
	cn.radial_segments = 4
	cn.rings = 1
	cone = _pool(cn, 0.95, 6)
	beam = _pool(unit, v.beacon[4], 3)
	edge_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	edge_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	edges.material_override = edge_mat
	edges.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	edges.mesh = ImmediateMesh.new()
	add_child(edges)


# on: 하늘 시점. piece: 내가 조종하는 블록 (없으면 {}). people: [{x, y, z, color: Color}] 생존자 화면 위치
func update(on: bool, piece: Dictionary, people: Array, now_ms: float) -> void:
	var v: Dictionary = C.SKY_VIEW
	var g := 0
	var p := 0
	var im := edges.mesh as ImmediateMesh
	im.clear_surfaces()
	if on and not piece.is_empty():
		var lp := SkyV.landing_preview(piece)
		var c := Co.color(v.ok if lp.ok else v.bad)
		im.surface_begin(Mesh.PRIMITIVE_LINES)
		for cell in lp.cells:
			if g >= CAP:
				break
			var at := Co.gxyz(cell[0] + 0.5, cell[1] + 0.5, cell[2] + 0.5)
			ghost.multimesh.set_instance_transform(g, Transform3D(Basis(), at))
			ghost.multimesh.set_instance_color(g, c)
			g += 1
			for a in 3: # 상자 모서리 12개
				for s1 in [-0.49, 0.49]:
					for s2 in [-0.49, 0.49]:
						var u := Vector3.ZERO
						var w := Vector3.ZERO
						u[(a + 1) % 3] = s1
						u[(a + 2) % 3] = s2
						w = u
						u[a] = -0.49
						w[a] = 0.49
						im.surface_add_vertex(at + u)
						im.surface_add_vertex(at + w)
		im.surface_end()
		edge_mat.albedo_color = Color(c, 0.9)
		var pw: float = v.pillar[0]
		for pl in lp.pillars:
			if p >= CAP:
				break
			var h: float = pl[3] - pl[2]
			pillar.multimesh.set_instance_transform(p, Transform3D(Basis().scaled(Vector3(pw, h, pw)), Co.gxyz(pl[0] + 0.5, pl[1] + 0.5, (pl[2] + pl[3]) / 2.0)))
			pillar.multimesh.set_instance_color(p, c)
			p += 1
	var b := 0
	if on:
		var size: float = v.beacon[0]
		var lift: float = v.beacon[1]
		var bob: float = v.beacon[2]
		var bw: float = v.beacon[3]
		var t := now_ms / 1000.0
		for s in people:
			if b >= CAP:
				break
			var top: float = s.z + C.PLAYER_HEIGHT + lift + sin(t * 3 + b) * bob
			cone.multimesh.set_instance_transform(b, Transform3D(Basis().scaled(Vector3(size, size * 1.2, size)), Co.gxyz(s.x, s.y, top + size * 0.6)))
			cone.multimesh.set_instance_color(b, s.color)
			beam.multimesh.set_instance_transform(b, Transform3D(Basis().scaled(Vector3(bw, top, bw)), Co.gxyz(s.x, s.y, top / 2.0)))
			beam.multimesh.set_instance_color(b, s.color)
			b += 1
	ghost.multimesh.visible_instance_count = g
	pillar.multimesh.visible_instance_count = p
	cone.multimesh.visible_instance_count = b
	beam.multimesh.visible_instance_count = b
	ghost.visible = g > 0
	pillar.visible = p > 0
	cone.visible = b > 0
	beam.visible = b > 0
	edges.visible = g > 0
