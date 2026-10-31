# 필드 아이템·투사체 자리: MultiMesh 상자·공 (모델은 나중, render.js itemMeshes·projMeshes 자리)
extends Node3D

const C := preload("res://core/config.gd")
const Co := preload("res://core/coords.gd")
const WC := preload("res://world/world_config.gd")

var items := MultiMeshInstance3D.new()
var projs := MultiMeshInstance3D.new()
var spin := 0.0


func _ready() -> void:
	var box := BoxMesh.new()
	box.size = Vector3.ONE * WC.ITEM_SIZE
	var im := StandardMaterial3D.new()
	im.albedo_color = Co.color(C.GAME_LIGHT_ITEM)
	im.emission_enabled = true
	im.emission = Co.color(C.GAME_LIGHT_ITEM) * WC.ITEM_GLOW
	box.material = im
	items.multimesh = MultiMesh.new()
	items.multimesh.transform_format = MultiMesh.TRANSFORM_3D
	items.multimesh.mesh = box
	add_child(items)
	var sp := SphereMesh.new()
	sp.radius = C.PROJECTILE_RADIUS
	sp.height = C.PROJECTILE_RADIUS * 2
	var pmat := StandardMaterial3D.new()
	pmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pmat.albedo_color = Color8(0xff, 0xee, 0x40)
	sp.material = pmat
	projs.multimesh = MultiMesh.new()
	projs.multimesh.transform_format = MultiMesh.TRANSFORM_3D
	projs.multimesh.mesh = sp
	add_child(projs)


func update(st: Dictionary, dt: float, now_ms: float) -> void:
	spin += dt * WC.ITEM_BOB[3]
	var list: Array = st.get("items", [])
	var mm := items.multimesh
	if mm.instance_count < list.size():
		mm.instance_count = list.size() + 4
	for i in list.size():
		var it: Dictionary = list[i]
		var z: float = it.z + WC.ITEM_BOB[0] + sin(now_ms / WC.ITEM_BOB[2] + i) * WC.ITEM_BOB[1]
		mm.set_instance_transform(i, Transform3D(Basis(Vector3.UP, spin), Co.gxyz(it.x + 0.5, it.y + 0.5, z)))
	mm.visible_instance_count = list.size()
	var pl: Array = st.get("projectiles", [])
	var pm := projs.multimesh
	if pm.instance_count < pl.size():
		pm.instance_count = pl.size() + 4
	for i in pl.size():
		pm.set_instance_transform(i, Transform3D(Basis(), Co.gxyz(pl[i].x, pl[i].y, pl[i].z)))
	pm.visible_instance_count = pl.size()
