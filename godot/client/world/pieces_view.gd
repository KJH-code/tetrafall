# 떨어지는 블록 칸 + 착지 그림자 칸: MultiMesh 둘 (render.js 의 pieceMeshes·shadowMeshes + instpool 자리)
# 블록 모습은 단순 재질 (테마 PieceLook 셰이더는 G3 shaders/ 가 나오면 바꿈), 색은 테마 조각 색
extends Node3D

const C := preload("res://core/config.gd")
const Co := preload("res://core/coords.gd")
const Cells := preload("res://world/cells.gd")
const WC := preload("res://world/world_config.gd")

var cells_mmi := MultiMeshInstance3D.new()
var shadow_mmi := MultiMeshInstance3D.new()
var piece_mat := StandardMaterial3D.new()
var piece_colors: Dictionary = C.SHAPE_COLORS


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
		return Co.color(C.THROWN_COLOR)
	if pc.get("controller") != null:
		return Co.color(WC.CONTROLLED_COLOR)
	return Co.color(piece_colors.get(str(pc.get("shape", "")), C.TERRAIN_COLOR))


# sky_blend: 하늘 시점 섞임 (0..1). me: 내 플레이어 (위험 그림자)
func update(st: Dictionary, my_id, me: Dictionary, sky_blend: float) -> void:
	var pieces: Array = st.get("pieces", [])
	var n := 0
	for pc in pieces:
		n += pc.cells.size()
	var mm := cells_mmi.multimesh
	var sm := shadow_mmi.multimesh
	if mm.instance_count < n:
		mm.instance_count = n + 8
		sm.instance_count = n + 8
	var alpha := WC.PIECE_SKY_ALPHA if sky_blend > 0.5 else 1.0
	piece_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA if alpha < 1.0 else BaseMaterial3D.TRANSPARENCY_DISABLED
	var warned: bool = not me.is_empty() and me.alive and me.get("danger") != null
	var k := 0
	var s := 0
	for pc in pieces:
		var col := piece_color(pc)
		col.a = alpha
		var mine: bool = str(pc.get("phase", "")) == "control" and pc.get("controller") != null and my_id != null and int(pc.controller) == int(my_id)
		var show_shadow: bool = pc.get("shadowVisible", false) or mine
		for i in pc.cells.size():
			var c: Array = pc.cells[i]
			mm.set_instance_transform(k, Transform3D(Basis(), Co.gxyz(c[0] + 0.5, c[1] + 0.5, c[2] + 0.5)))
			mm.set_instance_color(k, col)
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
	sm.visible_instance_count = s
