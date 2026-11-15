# 쌓인 칸 (지형·쌓기·설치·테트리미노 남은 칸): MultiMesh 하나 (그리기 1번), 칸 색은 instance color (render.js updateGrid)
# + 필드 바닥판·섬 절벽 (z 0 아래)
extends Node3D

const C := preload("res://core/config.gd")
const Co := preload("res://core/coords.gd")
const Cells := preload("res://world/cells.gd")
const WC := preload("res://world/world_config.gd")
const PiecesView := preload("res://world/pieces_view.gd")
const CellLod := preload("res://world/cell_lod.gd")

var mmi := MultiMeshInstance3D.new()
var floor_mesh := MeshInstance3D.new()
var cliff := MeshInstance3D.new()
var terrain_color = null # 테마 지형 색 (없으면 TERRAIN_COLOR)
var piece_colors: Dictionary = C.SHAPE_COLORS
var skip := {} # 그리지 않을 칸 (건축가 블록이 따로 그림)
var count := 0
var make_mat = null # Callable(Color) -> Material: G3 툰 재질 (없으면 StandardMaterial3D)
var piece_mmi := MultiMeshInstance3D.new() # 쌓인 테트리미노 칸 (모양 칸) 만: G3 PieceLook (set_piece_look), 없으면 mmi 에 같이
var piece_caster := MultiMeshInstance3D.new() # W32: 쌓인 모양 칸의 그림자를 던지는 상자 (모양 칸 한 개가 300~430 삼각형이라 쌓일수록 해 그림자 패스가 커짐). 보이는 칸은 그림자 끔
var proxy_on := false
var piece_far := MultiMeshInstance3D.new() # W39: 먼 쌓인 모양 칸은 낮은 모양 (world/cell_lod.gd). 같은 재질·같은 칸 색
var low_mesh: Mesh = null # 낮은 모양 (없거나 칸 모양이 이미 가벼우면 null = LOD 안 함)
var _pxf: Array[Transform3D] = [] # 쌓인 모양 칸 자리·색 (rebuild 가 적고 regroup 이 가까움/멂으로 나눠 MultiMesh 에 씀)
var _pcol: PackedColorArray = PackedColorArray()
var _lod_cam := Vector3(INF, INF, INF)
var _lod_fov := 0.0
var lod_far := 0 # 지난 나눔에서 먼 칸 수 (확인용)
var near_idx := PackedInt32Array() # 지난 나눔에서 가까운 칸 번호 (_pxf 안, 확인용 — 헤드리스는 MultiMesh 자리를 못 읽음)
var regroups := 0 # 가까움/멂을 다시 나눈 번 수 (확인용)
var terrain_mmi := MultiMeshInstance3D.new() # 테마 지형 칸 (값 1) 만: G3 지형 셰이더 (칸 크기 1, 이웃·그늘 비트는 custom data)
var terrain_custom = null # Callable(grid, w, d, h, skip) -> PackedColorArray (G3.terrain_custom), null 이면 지형도 칸 색 블록


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
	var tm := MultiMesh.new()
	tm.transform_format = MultiMesh.TRANSFORM_3D
	tm.use_custom_data = true
	terrain_mmi.multimesh = tm
	var pmm := MultiMesh.new()
	pmm.transform_format = MultiMesh.TRANSFORM_3D
	pmm.use_colors = true
	piece_mmi.multimesh = pmm
	piece_mmi.visible = false
	add_child(piece_mmi)
	var qm := MultiMesh.new()
	qm.transform_format = MultiMesh.TRANSFORM_3D
	qm.mesh = box
	piece_caster.multimesh = qm
	piece_caster.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	piece_caster.visible = false
	add_child(piece_caster)
	var fmm := MultiMesh.new()
	fmm.transform_format = MultiMesh.TRANSFORM_3D
	fmm.use_colors = true
	piece_far.multimesh = fmm
	piece_far.visible = false
	add_child(piece_far)
	terrain_mmi.visible = false
	add_child(terrain_mmi)
	for n in [floor_mesh, cliff]:
		n.mesh = BoxMesh.new()
		n.material_override = StandardMaterial3D.new() # 바닥 판 무늬는 G3 floor_material 이 오면
		add_child(n)


# 쌓인 테트리미노 칸 모습 (G3 piece_mesh·piece_material, 조각 색). mesh 가 null 이면 끔 (칸 색 상자)
func set_piece_look(mesh: Mesh, mat: Material, colors: Dictionary, lod_mesh: Mesh = null) -> void:
	piece_mmi.visible = mesh != null
	low_mesh = lod_mesh if mesh != null and lod_mesh != null and CellLod.worth(PiecesView.mesh_tris(mesh), PiecesView.mesh_tris(lod_mesh)) else null
	piece_far.visible = low_mesh != null
	piece_far.multimesh.instance_count = 0
	piece_far.multimesh.mesh = low_mesh if low_mesh != null else mesh
	piece_far.material_override = mat
	_lod_cam = Vector3(INF, INF, INF)
	piece_mmi.multimesh.instance_count = 0
	piece_mmi.multimesh.mesh = mesh
	piece_mmi.material_override = mat
	piece_colors = colors
	proxy_on = mesh != null and PiecesView.proxy_wanted(mesh)
	piece_caster.visible = proxy_on
	piece_caster.multimesh.instance_count = 0
	piece_mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if proxy_on else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	piece_far.cast_shadow = piece_mmi.cast_shadow


# 테마 지형 셰이더 (G3 terrain_mesh·terrain_material·terrain_custom). mesh 가 null 이면 끔 (지형도 칸 색 블록)
func set_terrain_look(mesh: Mesh, mat: Material, custom) -> void:
	terrain_custom = custom if mesh != null else null
	terrain_mmi.visible = mesh != null
	if mesh != null:
		terrain_mmi.multimesh.instance_count = 0
		terrain_mmi.multimesh.mesh = mesh
		terrain_mmi.material_override = mat


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


# W39: 쌓인 모양 칸을 카메라 거리로 가까움 (칸 모양) / 멂 (낮은 모양) 으로 나눠 MultiMesh 두 개에 씀. 카메라가 regroup_move 만큼 움직였을 때만 다시 나눔 (force 면 늘)
func regroup(force := false) -> void:
	var pm := piece_mmi.multimesh
	var fm := piece_far.multimesh
	var n := _pxf.size()
	var cam: Dictionary = CellLod.camera_of(self) if low_mesh != null else {}
	if low_mesh == null or cam.is_empty() or n == 0:
		if force or lod_far != 0:
			pm.instance_count = n
			for k in n:
				pm.set_instance_transform(k, _pxf[k])
				pm.set_instance_color(k, _pcol[k])
			fm.instance_count = 0
			lod_far = 0
		return
	var cp: Vector3 = cam.pos
	var fov: float = float(cam.fov)
	if not force and cp.distance_to(_lod_cam) < float(WC.CELL_LOD.regroup_move) and is_equal_approx(fov, _lod_fov):
		return
	_lod_cam = cp
	_lod_fov = fov
	regroups += 1
	var near := PackedInt32Array()
	var far := PackedInt32Array()
	for k in n:
		if CellLod.far_state(cp.distance_to(_pxf[k].origin), fov, false):
			far.append(k)
		else:
			near.append(k)
	near_idx = near
	pm.instance_count = near.size()
	fm.instance_count = far.size()
	for j in near.size():
		pm.set_instance_transform(j, _pxf[near[j]])
		pm.set_instance_color(j, _pcol[near[j]])
	for j in far.size():
		fm.set_instance_transform(j, _pxf[far[j]])
		fm.set_instance_color(j, _pcol[far[j]])
	lod_far = far.size()


func rebuild(grid: PackedByteArray, w: int, d: int, h: int) -> void:
	var mm := mmi.multimesh
	var cells := PackedInt32Array()
	var terr := PackedInt32Array()
	var pcs := PackedInt32Array()
	var shader_terrain: bool = terrain_custom != null
	var piece_look: bool = piece_mmi.visible
	for i in grid.size():
		if grid[i] != 0 and not skip.has(i):
			if shader_terrain and grid[i] == Cells.TERRAIN:
				terr.append(i)
			elif piece_look and grid[i] > Cells.THROWN:
				pcs.append(i) # 모양 칸 (render.js blockMeshes.shape)
			else:
				cells.append(i)
	if shader_terrain:
		# 순서 z → y → x (격자 번호 순) = terrain_custom 순서
		var looks: PackedColorArray = terrain_custom.call(grid, w, d, h, skip)
		var tm := terrain_mmi.multimesh
		tm.instance_count = terr.size()
		for k in terr.size():
			var i: int = terr[k]
			tm.set_instance_transform(k, Transform3D(Basis(), Co.gxyz(i % w + 0.5, (i / w) % d + 0.5, i / (w * d) + 0.5)))
			if k < looks.size():
				tm.set_instance_custom_data(k, looks[k])
	var qm := piece_caster.multimesh
	qm.instance_count = pcs.size() if proxy_on else 0
	_pxf.clear()
	_pcol.resize(pcs.size())
	for k in pcs.size():
		var i: int = pcs[k]
		var x := i % w
		var y := (i / w) % d
		var z := i / (w * d)
		var pxf := Transform3D(Basis(), Co.gxyz(x + 0.5, y + 0.5, z + 0.5))
		_pxf.append(pxf)
		if proxy_on:
			qm.set_instance_transform(k, pxf)
		var c := Co.color(Cells.cell_color(grid[i], piece_colors))
		if (x + y + z) % 2:
			c = c * WC.CHECKER
			c.a = 1.0
		_pcol[k] = c
	_lod_cam = Vector3(INF, INF, INF)
	regroup(true)
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
