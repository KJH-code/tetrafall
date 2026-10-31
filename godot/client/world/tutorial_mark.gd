# 튜토리얼 목표 칸 빛 (G6, render.js updateTutorialMark 자리, config TUTORIAL_MARK): 바닥 고리 + 퍼져 나가는 고리 + 빛 기둥 + 가운데 심.
# 단계에 목표가 있고 아직 못 했을 때만, 그 칸 맨 위 (벽 위 목표면 벽 꼭대기) 에. main.gd 가 붙임
extends Node3D

const C := preload("res://core/config.gd")
const Co := preload("res://core/coords.gd")
const Effects := preload("res://fx/effects.gd")

var ring := MeshInstance3D.new()
var wave := MeshInstance3D.new()
var beam := MeshInstance3D.new()
var core := MeshInstance3D.new()


static func _mat(color, a: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	var c := Co.color(color)
	c.a = a
	m.albedo_color = c
	return m


func _init() -> void:
	var M: Dictionary = C.TUTORIAL_MARK
	var rm := Effects.ring_mesh(M.ring[0], M.ring[1], 40)
	for r in [[ring, 0.03], [wave, 0.04]]:
		r[0].mesh = rm
		r[0].material_override = _mat(M.color, M.ringOpacity)
		r[0].position.y = r[1]
		r[0].rotation.x = -PI / 2 # 고리는 고도 XY 면 → 바닥 (XZ) 으로 눕힘
		add_child(r[0])
	for b in [[beam, M.beamR, M.color, M.beamOpacity[0], 24], [core, M.coreR, M.core, M.coreOpacity[0], 12]]:
		var cm := CylinderMesh.new()
		cm.top_radius = b[1]
		cm.bottom_radius = b[1]
		cm.height = M.h
		cm.radial_segments = b[4]
		cm.cap_top = false
		cm.cap_bottom = false
		b[0].mesh = cm
		b[0].material_override = _mat(b[2], b[3])
		b[0].position.y = M.h / 2.0
		b[0].cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(b[0])
	visible = false


# 그 자리 칸 맨 위 높이 (격자, 없으면 0)
static func top_at(x: float, y: float, grid: PackedByteArray, f: Dictionary) -> int:
	var W := int(f.get("w", 0))
	var D := int(f.get("d", 0))
	var H := int(f.get("h", C.GRID_H))
	var gx := floori(x)
	var gy := floori(y)
	if gx < 0 or gy < 0 or gx >= W or gy >= D or grid.size() < W * D * H:
		return 0
	for z in range(H - 1, -1, -1):
		if grid[(z * D + gy) * W + gx] != 0:
			return z + 1
	return 0


func _process(_dt: float) -> void:
	var t = Store.state.get("tutorial")
	var target = t.get("target") if t is Dictionary and not t.get("done", false) and not t.get("ok", false) else null
	if not (target is Dictionary):
		visible = false
		return
	var M: Dictionary = C.TUTORIAL_MARK
	var top := top_at(float(target.x), float(target.y), Store.grid, Store.state.get("field", {}))
	position = Co.gxyz(target.x, target.y, top)
	var ph: float = fmod(Time.get_ticks_msec(), M.pulseMs) / M.pulseMs
	var k := 0.5 + 0.5 * sin(ph * TAU)
	ring.scale = Vector3.ONE * (1.0 + M.ringPulse * k)
	wave.scale = Vector3.ONE * (1.0 + ph * 1.6)
	(wave.material_override as StandardMaterial3D).albedo_color.a = M.ringOpacity * (1.0 - ph)
	(beam.material_override as StandardMaterial3D).albedo_color.a = M.beamOpacity[0] + (M.beamOpacity[1] - M.beamOpacity[0]) * k
	(core.material_override as StandardMaterial3D).albedo_color.a = M.coreOpacity[0] + (M.coreOpacity[1] - M.coreOpacity[0]) * k
	visible = true
