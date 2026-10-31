# 상승하는 위험 (용암 자리) 단순 모습: 지평선까지 큰 표면 판 하나 (테마 색·투명도) + 블록·바닥이 표면을 뚫는 곳 거품 띠 (MultiMesh)
# 계산은 hazard_field.gd (client/hazard-field.js 그대로). 파도·잠김 물들임·번쩍 등 꾸밈은 G3 셰이더 뒤
extends Node3D

const C := preload("res://core/config.gd")
const Co := preload("res://core/coords.gd")
const HF := preload("res://world/hazard_field.gd")
const WC := preload("res://world/world_config.gd")

var surface := MeshInstance3D.new()
var foam := MultiMeshInstance3D.new()
var surf_mat := StandardMaterial3D.new()
var foam_mat := StandardMaterial3D.new()
var _key := "" # 거품 자리를 다시 계산할 때 (격자 판·표면 높이 단계)
var step := -1 # 차오름 단계 (riseStep) — 바뀌면 rose 신호 자리
var vignette := 0.0 # 화면 가장자리 경고 세기 (G4 HUD 가 읽어 감, vignetteStrength)


func _ready() -> void:
	var pm := PlaneMesh.new()
	pm.size = Vector2.ONE * WC.SEA_SIZE
	surface.mesh = pm
	surf_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	surf_mat.roughness = WC.HAZARD_SURF[0]
	surf_mat.metallic_specular = WC.HAZARD_SURF[1]
	surface.material_override = surf_mat
	surface.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(surface)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var q := PlaneMesh.new()
	q.size = Vector2(WC.FOAM_SIZE[0], WC.FOAM_SIZE[1])
	mm.mesh = q
	foam.multimesh = mm
	foam_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	foam_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	foam.material_override = foam_mat
	foam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(foam)
	visible = false


func set_theme(theme: Dictionary) -> void:
	var hz: Dictionary = theme.get("hazard", {})
	var mid := Co.color(hz.get("mid", 0xff5a1a))
	var alpha = hz.get("alpha", [0.92, 0.6])
	mid.a = float(alpha[0])
	surf_mat.albedo_color = mid
	var lava := str(hz.get("style", "lava")) == "lava"
	surf_mat.emission_enabled = lava or hz.has("light")
	surf_mat.emission = Co.color(hz.get("shallow", 0xff8030))
	surf_mat.emission_energy_multiplier = WC.HAZARD_GLOW[0] if lava else WC.HAZARD_GLOW[1]
	var fc := Co.color(hz.get("contact", hz.get("foam", 0xffffff)))
	fc.a = WC.FOAM_ALPHA
	foam_mat.albedo_color = fc


func update(st: Dictionary, grid: PackedByteArray, grid_version: int, me: Dictionary) -> void:
	var lava: Dictionary = st.get("lava", {})
	var on: bool = lava.get("active", false)
	visible = on
	vignette = 0.0
	if not on:
		_key = ""
		return
	var zs: float = lava.z
	var f: Dictionary = st.field
	surface.position = Co.gxyz(f.w / 2.0, f.d / 2.0, zs)
	step = HF.rise_step(zs)
	if not me.is_empty() and me.alive:
		vignette = HF.vignette_strength(me.z - zs)
	var key := "%d|%d" % [grid_version, roundi(zs * 20)]
	if key == _key:
		return
	_key = key
	var hf := HF.field(grid, int(f.w), int(f.d), int(f.get("h", C.GRID_H)), zs, 1)
	var mm := foam.multimesh
	mm.instance_count = hf.contacts.size()
	for i in hf.contacts.size():
		var c: Dictionary = hf.contacts[i]
		# 띠는 변을 따라 (변이 x 방향이면 그대로, y 방향이면 90도)
		var b := Basis(Vector3.UP, PI / 2.0) if c.nx != 0 else Basis()
		mm.set_instance_transform(i, Transform3D(b, Co.gxyz(c.x, c.y, zs + WC.SHADOW_LIFT)))
