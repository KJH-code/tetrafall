# 쌓인 칸 (지형·쌓기·설치·테트리미노 남은 칸): MultiMesh 하나 (그리기 1번), 칸 색은 instance color (render.js updateGrid)
# + 필드 바닥판·섬 절벽 (z 0 아래)
extends Node3D

const C := preload("res://core/config.gd")
const Co := preload("res://core/coords.gd")
const Cells := preload("res://world/cells.gd")
const WC := preload("res://world/world_config.gd")

var mmi := MultiMeshInstance3D.new()
var floor_mesh := MeshInstance3D.new()
var cliff := MeshInstance3D.new()
var terrain_color = null # 테마 지형 색 (없으면 TERRAIN_COLOR)
var piece_colors: Dictionary = C.SHAPE_COLORS
var skip := {} # 그리지 않을 칸 (건축가 블록이 따로 그림)
var count := 0
var make_mat = null # Callable(Color) -> Material: G3 툰 재질 (없으면 StandardMaterial3D)


func _ready() -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	var box := BoxMesh.new()
	box.size = Vector3.ONE * WC.CELL_SIZE
	mm.mesh = box
	mmi.multimesh = mm
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = WC.BLOCK_ROUGH[0]
	mmi.material_override = m
	add_child(mmi)
	for n in [floor_mesh, cliff]:
		n.mesh = BoxMesh.new()
		n.material_override = StandardMaterial3D.new() # 바닥 판 무늬는 G3 floor_material 이 오면
		add_child(n)


# G3 툰 재질로 바꿈 (인스턴스 색 COLOR 를 곱하는 재질)
func set_material(m: Material) -> void:
	mmi.material_override = m


func set_theme(theme: Dictionary) -> void:
	terrain_color = theme.get("terrain", {}).get("top", null)
	piece_colors = Cells.piece_colors(theme)
	var fl: Dictionary = theme.get("floor", {})
	_paint(floor_mesh, Co.color(fl.get("a", C.TERRAIN_COLOR)))
	_paint(cliff, Co.color(theme.get("terrain", {}).get("side", fl.get("rim", WC.CLIFF_COLOR))))


func _paint(n: MeshInstance3D, c: Color) -> void:
	if make_mat != null:
		n.material_override = make_mat.call(c)
	else:
		(n.material_override as StandardMaterial3D).albedo_color = c


func set_field(w: int, d: int) -> void:
	(floor_mesh.mesh as BoxMesh).size = Vector3(w, WC.FLOOR_THICK, d)
	floor_mesh.position = Co.gxyz(w / 2.0, d / 2.0, -WC.FLOOR_THICK / 2.0)
	(cliff.mesh as BoxMesh).size = Vector3(w - 0.2, WC.CLIFF_THICK, d - 0.2)
	cliff.position = Co.gxyz(w / 2.0, d / 2.0, -WC.FLOOR_THICK - WC.CLIFF_THICK / 2.0)


func rebuild(grid: PackedByteArray, w: int, d: int, h: int) -> void:
	var mm := mmi.multimesh
	var cells := PackedInt32Array()
	for i in grid.size():
		if grid[i] != 0 and not skip.has(i):
			cells.append(i)
	count = cells.size()
	mm.instance_count = count
	for k in count:
		var i: int = cells[k]
		var x := i % w
		var y := (i / w) % d
		var z := i / (w * d)
		mm.set_instance_transform(k, Transform3D(Basis(), Co.gxyz(x + 0.5, y + 0.5, z + 0.5)))
		var v: int = grid[i]
		var c := Co.color(terrain_color if v == Cells.TERRAIN and terrain_color != null else Cells.cell_color(v, piece_colors))
		if (x + y + z) % 2:
			c = c * WC.CHECKER
			c.a = 1.0
		mm.set_instance_color(k, c)
