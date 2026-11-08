# 떨어지는 블록 칸 + 착지 그림자 칸: MultiMesh 둘 (render.js 의 pieceMeshes·shadowMeshes + instpool 자리)
# 블록 모습: G3 PieceLook (piece_mesh·piece_material, set_look) 이 있으면 그것, 없으면 상자 + 툰/단순 재질. 색은 테마 조각 색
extends Node3D

const C := preload("res://core/config.gd")
const Co := preload("res://core/coords.gd")
const Cells := preload("res://world/cells.gd")
const WC := preload("res://world/world_config.gd")

var cells_mmi := MultiMeshInstance3D.new()
var sky_mmi := MultiMeshInstance3D.new() # 하늘 계단 블록 (render.js skyPieceMat: 밝게·살짝 비침·하늘색 빛) — 늘 반투명 재질
var shadow_mmi := MultiMeshInstance3D.new()
var caster_mmi := MultiMeshInstance3D.new() # W32: 보이는 칸과 같은 자리에서 그림자만 던지는 상자 (칸 모양이 복잡한 테마에서 해 그림자 패스 삼각형을 줄임)
var proxy_on := false # 보이는 칸 그림자를 끄고 caster_mmi 가 대신 던지는 중
var piece_mat := StandardMaterial3D.new()
var piece_colors: Dictionary = C.SHAPE_COLORS
var mats = null # G3 툰 재질 [불투명, 반투명] (없으면 piece_mat 의 transparency 를 바꿈)


func _ready() -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	var box := BoxMesh.new()
	box.size = Vector3.ONE * WC.CELL_SIZE
	mm.mesh = box
	cells_mmi.multimesh = mm
	piece_mat.vertex_color_use_as_albedo = true
	piece_mat.roughness = WC.BLOCK_ROUGH[1]
	cells_mmi.material_override = piece_mat
	add_child(cells_mmi)
	var cm := MultiMesh.new()
	cm.transform_format = MultiMesh.TRANSFORM_3D
	cm.mesh = box
	caster_mmi.multimesh = cm
	caster_mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	add_child(caster_mmi)
	var km := MultiMesh.new()
	km.transform_format = MultiMesh.TRANSFORM_3D
	km.use_colors = true
	km.mesh = box
	sky_mmi.multimesh = km
	sky_mmi.material_override = piece_mat
	sky_mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(sky_mmi)
	var sm := MultiMesh.new()
	sm.transform_format = MultiMesh.TRANSFORM_3D
	sm.use_colors = true
	var quad := PlaneMesh.new()
	quad.size = Vector2.ONE
	sm.mesh = quad
	shadow_mmi.multimesh = sm
	var smat := StandardMaterial3D.new()
	smat.vertex_color_use_as_albedo = true
	smat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	smat.no_depth_test = false
	shadow_mmi.material_override = smat
	shadow_mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(shadow_mmi)


# G3 칸 모양·재질 [불투명, 반투명 (알파 = 인스턴스 색 a)]·조각 색
func set_look(mesh: Mesh, materials: Array, colors: Dictionary) -> void:
	cells_mmi.multimesh.mesh = mesh
	sky_mmi.multimesh.mesh = mesh
	set_proxy(proxy_wanted(mesh))
	mats = materials
	piece_colors = colors


# W32: 칸 모양이 이 삼각형 수보다 많으면 그림자는 상자로 (상자 12 삼각형), 아니면 보이는 칸이 그대로 던짐
static func mesh_tris(mesh: Mesh) -> int:
	if mesh == null:
		return 0
	if not mesh is ArrayMesh: # 상자 등 (PrimitiveMesh)
		return mesh.get_faces().size() / 3
	if mesh.get_surface_count() == 0:
		return 0
	var n: int = mesh.surface_get_array_index_len(0)
	return (n if n > 0 else mesh.surface_get_array_len(0)) / 3


static func proxy_wanted(mesh: Mesh) -> bool:
	return WC.shadow_opt and bool(WC.SHADOW.piece_proxy) and mesh_tris(mesh) > int(WC.SHADOW.piece_proxy_min_tris)


func set_proxy(on: bool) -> void:
	proxy_on = on
	cells_mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if on else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	if not on:
		caster_mmi.multimesh.visible_instance_count = 0
	_key_st = null # 상자 자리를 다음 갱신에서 다시 씀


# 착지 예고 그림자 진하기 (render.js shadowFor: 5단계)
static func shadow_alpha(eta) -> float:
	var near := 0.0
	if eta != null and is_finite(float(eta)):
		near = 1.0 - clampf(float(eta) / C.SHADOW_DARKEN_MS, 0.0, 1.0)
	return C.SHADOW_OPACITY_FAR + (C.SHADOW_OPACITY_NEAR - C.SHADOW_OPACITY_FAR) * roundi(near * 4) / 4.0


func piece_color(pc: Dictionary) -> Color:
	if str(pc.get("shape", "")) == "ghost":
		var g = pc.get("ghostColor", pc.get("ghostSlot", 0))
		return Co.color(C.PLAYER_PALETTE[int(g if g != null else 0) % C.PLAYER_PALETTE.size()])
	if pc.get("thrown", false):
		var tc := Co.color(C.THROWN_COLOR)
		if int(Time.get_ticks_msec() / C.THROWN_BLINK_MS) % 2: # render.js thrownMat 깜빡임 (emissive 0x806000)
			tc += Color(0.5, 0.375, 0.0, 0.0)
		return tc
	if pc.get("controller") != null:
		return Co.color(WC.CONTROLLED_COLOR)
	return Co.color(piece_colors.get(str(pc.get("shape", "")), C.TERRAIN_COLOR))


# sky_blend: 하늘 시점 섞임 (0..1). me: 내 플레이어 (위험 그림자)
func update(st: Dictionary, my_id, me: Dictionary, sky_blend: float) -> void:
	# 칸 자리·색은 스냅샷 값 그대로 → 같은 스냅샷·같은 시점·같은 색 표·하늘 블록 없음 (반짝임이 시간에 따라 바뀜) 이면 지난 프레임 그대로 (W15)
	var sky_on := sky_blend > 0.5
	if is_same(st, _key_st) and sky_on == _key_sky and is_same(piece_colors, _key_cols) and my_id == _key_me:
		if not _sky_base.is_empty(): # 하늘 블록 반짝임만 (색 = 하얗게 섞은 모양 색 + 시간에 따라 하늘빛)
			var g := Color(0.12, 0.22, 0.3, 0.0) * (0.55 + 0.45 * sin(Time.get_ticks_msec() / 500.0))
			var km0 := sky_mmi.multimesh
			for i in _sky_base.size():
				var c: Color = _sky_base[i] + g
				c.a = _sky_a
				km0.set_instance_color(i, c)
		return
	_sky_base.clear()
	_key_st = st
	_key_sky = sky_on
	_key_cols = piece_colors
	_key_me = my_id
	writes += 1
	var pieces: Array = st.get("pieces", [])
	var n := 0
	for pc in pieces:
		n += pc.cells.size()
	var mm := cells_mmi.multimesh
	var km := sky_mmi.multimesh
	var sm := shadow_mmi.multimesh
	var qm := caster_mmi.multimesh
	if mm.instance_count < n:
		qm.instance_count = n + 8
		mm.instance_count = n + 8
		km.instance_count = n + 8
		sm.instance_count = n + 8
	var alpha := WC.PIECE_SKY_ALPHA if sky_blend > 0.5 else 1.0
	if mats != null:
		cells_mmi.material_override = mats[1] if alpha < 1.0 else mats[0]
		sky_mmi.material_override = mats[1]
	else:
		piece_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA if alpha < 1.0 else BaseMaterial3D.TRANSPARENCY_DISABLED
	# 하늘 계단 블록: 모양 색을 하얗게 섞고 하늘색으로 은은히 빛남 (render.js skyGlow), 살짝 비침 (하늘 시점이면 더)
	var sky_a: float = WC.SKY_PIECE_ALPHA_SKYVIEW if alpha < 1.0 else C.SKY_PIECE_OPACITY
	var glow := 0.55 + 0.45 * sin(Time.get_ticks_msec() / 500.0)
	var sky_glow := Color(0.12, 0.22, 0.3, 0.0) * glow
	var q := 0
	var warned: bool = not me.is_empty() and me.alive and me.get("danger") != null
	var k := 0
	var s := 0
	for pc in pieces:
		var col := piece_color(pc)
		col.a = alpha
		var sky: bool = pc.get("sky", false) and str(pc.get("shape", "")) != "ghost" and not pc.get("thrown", false) and pc.get("controller") == null
		var base := col
		if sky:
			base = col.lerp(Color.WHITE, C.SKY_PIECE_WHITEN)
			col = base + sky_glow
			col.a = sky_a
			_sky_a = sky_a
		var mine: bool = str(pc.get("phase", "")) == "control" and pc.get("controller") != null and my_id != null and int(pc.controller) == int(my_id)
		var show_shadow: bool = pc.get("shadowVisible", false) or mine
		for i in pc.cells.size():
			var c: Array = pc.cells[i]
			var xf := Transform3D(Basis(), Co.gxyz(c[0] + 0.5, c[1] + 0.5, c[2] + 0.5))
			if sky:
				km.set_instance_transform(q, xf)
				km.set_instance_color(q, col)
				_sky_base.append(base)
				q += 1
			else:
				mm.set_instance_transform(k, xf)
				mm.set_instance_color(k, col)
				if proxy_on:
					qm.set_instance_transform(k, xf)
				k += 1
			if show_shadow and pc.has("shadow") and i < pc.shadow.size():
				var sh: Array = pc.shadow[i]
				sm.set_instance_transform(s, Transform3D(Basis(), Co.gxyz(sh[0] + 0.5, sh[1] + 0.5, float(pc.landZ) + WC.SHADOW_LIFT)))
				var sc: Color
				if mine:
					sc = Co.color(WC.PREVIEW_COLOR[0] if pc.get("fits", false) else WC.PREVIEW_COLOR[1])
					sc.a = WC.PREVIEW_COLOR[2]
				elif warned and sh[0] < me.x + C.PLAYER_HALF and sh[0] + 1 > me.x - C.PLAYER_HALF and sh[1] < me.y + C.PLAYER_HALF and sh[1] + 1 > me.y - C.PLAYER_HALF:
					sc = Co.color(WC.DANGER_SHADOW[0])
					sc.a = WC.DANGER_SHADOW[1]
				else:
					sc = Color(0, 0, 0, shadow_alpha(pc.get("eta")))
				sm.set_instance_color(s, sc)
				s += 1
	mm.visible_instance_count = k
	qm.visible_instance_count = k if proxy_on else 0
	km.visible_instance_count = q
	sm.visible_instance_count = s


var writes := 0 # 칸을 다 다시 쓴 번 수 (확인용)
var _key_st = null # 지난번 그린 스냅샷·시점·색 표·내 id
var _key_sky := false
var _key_cols = null
var _key_me = null
var _sky_base: Array[Color] = [] # 지난번 하늘 블록 칸마다 반짝임 전 색 (같은 스냅샷이면 반짝임만 다시)
var _sky_a := 1.0
