# KO 연출 (client/ko.js 자리, 2026-10-27 재혁): 스매시 폭발 줄기 · 마지막 킬 슬로모션·줌 · 압사 히트스톱 · 화면 끝 번쩍. 수치는 config KO_*
# 화면만 (서버 시간·판정과 상관없음). 소리는 View.sound_cue "smash"·"koCrush" {x,y,z,me,near} · "final" {x,y,z} (audio/ 가 받음)
extends Node3D

const C := preload("res://core/config.gd")
const Co := preload("res://core/coords.gd")
const FM := preload("res://fx/fx_math.gd")

var fx # effects.gd
var color_of := func(_id): return 0xffffff
var low_gfx := func(): return false
var field := func(): return Vector2(C.GRID_W, C.GRID_W)
var plumes: Array = [] # {node, mat, age, life}
var slow := {} # 마지막 킬 슬로모션 {start, until, x, y, z}
var stop_until := 0.0 # 압사 히트스톱
var edge_layer := CanvasLayer.new()
var edge_rect := ColorRect.new()
var edge_mat := ShaderMaterial.new()
var edge_at = null # 게임 좌표 Vector3
var edge_color := Color.WHITE
var edge_until := 0.0
var cone: Mesh

const EDGE_SHADER := """
shader_type canvas_item;
uniform vec2 at = vec2(0.5);
uniform vec4 tint : source_color = vec4(1.0);
uniform float alpha = 0.0;
// radial-gradient(ellipse 45% 45% at px% py%, 색cc 0%, 색55 35%, transparent 70%) (ko.js drawEdge)
void fragment() {
	float d = length((UV - at) / 0.45);
	float a = d < 0.35 ? mix(0.8, 0.333, d / 0.35) : mix(0.333, 0.0, clamp((d - 0.35) / 0.35, 0.0, 1.0));
	COLOR = vec4(tint.rgb, a * alpha);
}
"""


func _init() -> void:
	var cm := CylinderMesh.new() # 꼭짓점이 가장자리, 넓은 쪽이 바깥 (+Y): 아래 반지름 0, 마디 노드가 LEN/2 올림
	cm.top_radius = C.KO_SMASH_WIDTH
	cm.bottom_radius = 0.0
	cm.height = C.KO_SMASH_LEN
	cm.radial_segments = 12
	cm.rings = 1
	cm.cap_top = false
	cm.cap_bottom = false
	cone = cm
	var sh := Shader.new()
	sh.code = EDGE_SHADER
	edge_mat.shader = sh
	edge_rect.material = edge_mat
	edge_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	edge_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	edge_rect.visible = false
	edge_layer.layer = 1
	edge_layer.add_child(edge_rect)
	add_child(edge_layer)


static func now_ms() -> float:
	return Time.get_ticks_usec() / 1000.0


func parts(n: float) -> int:
	return FM.parts(n, bool(low_gfx.call()))


# 서버 death 이벤트. me = 내가 죽음, dist = 나와의 거리 (null = 모름)
func death(e: Dictionary, me: bool, dist) -> void:
	var p := Vector3(float(e.get("x", 0)), float(e.get("y", 0)), float(e.get("z", 0)))
	var color: int = color_of.call(e.get("who"))
	var near: bool = me or (dist != null and float(dist) < C.KO_NEAR_DIST)
	var info := {"who": e.get("who"), "by": e.get("by"), "x": p.x, "y": p.y, "z": p.z, "out": e.get("out"), "color": color, "me": me, "near": near}
	if e.get("cause") == "fall" and e.get("out") != null:
		smash(p, e.out, color, me, near)
		View.sound_cue.emit("smash", info)
	elif e.get("cause") == "crush":
		crush(p, me, near)
		View.sound_cue.emit("koCrush", info)


# 스매시 줄기: 떨어진 쪽 필드 가장자리에서 바깥·위로 그 사람 색 폭발 줄기 + 파편 + 흔들림 + 화면 끝 번쩍
func smash(p: Vector3, out: Dictionary, color: int, me: bool, near: bool) -> void:
	var f: Vector2 = field.call()
	var at := FM.smash_at(p, f.x, f.y)
	var dir := FM.smash_dir(out)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	var c := Co.color(color)
	c.a = 0.9
	mat.albedo_color = c
	var node := Node3D.new()
	var mi := MeshInstance3D.new()
	mi.mesh = cone
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position.y = C.KO_SMASH_LEN / 2.0
	node.add_child(mi)
	node.position = Co.gpos(at)
	add_child(node)
	var pl := {"node": node, "mat": mat, "age": 0.0, "life": C.KO_SMASH_MS / 1000.0, "dir": Co.gpos(dir).normalized()}
	_plume_pose(pl, Vector3(0.2, 0.2, 0.9))
	plumes.append(pl)
	fx.burst(at, {"x": dir.x, "y": dir.y}, color, parts(C.KO_SMASH_PARTICLES), 12.0, 0.16, 0.8)
	fx.burst(at, null, 0xffffff, parts(C.KO_SMASH_PARTICLES / 2.0), 6.0, 0.1, 0.5)
	fx.ring(at, color, 5.0, 0.4)
	if me:
		fx.shake(C.KO_SHAKE_ME, C.KO_SHAKE_MS)
	elif near:
		fx.shake(C.KO_SHAKE_NEAR, C.KO_SHAKE_MS)
	edge_at = at
	edge_color = Co.color(color)
	edge_until = now_ms() + C.KO_EDGE_MS


# 줄기 노드: 로컬 +Y 를 dir 쪽으로 (setFromUnitVectors), 크기 (옆, 길이, 옆)
func _plume_pose(pl: Dictionary, s: Vector3) -> void:
	var d: Vector3 = pl.dir
	var axis := Vector3.UP.cross(d)
	var q := Quaternion() if axis.length() < 1e-6 else Quaternion(axis.normalized(), Vector3.UP.angle_to(d))
	if axis.length() < 1e-6 and d.y < 0:
		q = Quaternion(Vector3.RIGHT, PI)
	pl.node.basis = Basis(q).scaled_local(Vector3(s.x, s.y, s.x))
	pl.mat.albedo_color.a = s.z


func crush(p: Vector3, me: bool, near: bool) -> void:
	var base := p + Vector3(0, 0, 0.1)
	fx.burst(base, null, 0x9a8a7a, parts(C.KO_CRUSH_DUST), 7.0, 0.22, 1.0) # 먼지 크게
	fx.burst(base + Vector3(0, 0, 0.6), null, 0x5d6b7a, parts(C.KO_CRUSH_CHIPS), 9.0, 0.16, 0.8) # 블록 조각
	fx.ring(base, 0xd8c8b0, 3.5, 0.35, true)
	if me or near:
		stop_until = now_ms() + C.KO_CRUSH_STOP_MS # 짧은 히트스톱
		fx.shake(C.KO_SHAKE_ME if me else C.KO_SHAKE_NEAR, C.KO_SHAKE_MS)


# 서버 finalKill 이벤트: 판을 끝낸 킬 → 잠깐 느리게 + 그 자리로 줌
func final(e: Dictionary) -> void:
	var now := now_ms()
	slow = {"start": now, "until": now + C.KO_FINAL_MS, "x": float(e.get("x", 0)), "y": float(e.get("y", 0)), "z": float(e.get("z", 0))}
	View.sound_cue.emit("final", {"who": e.get("who"), "by": e.get("by"), "x": slow.x, "y": slow.y, "z": slow.z, "color": color_of.call(e.get("who"))})


# 마지막 킬 슬로모션이 남은 ms (결과 화면이 기다림, main.js koSlowLeft)
func slow_left() -> float:
	return maxf(0.0, slow["until"] - now_ms()) if not slow.is_empty() else 0.0


func time_scale(now := now_ms()) -> float:
	return FM.time_scale(now, stop_until, slow)


# 카메라를 정한 뒤: 마지막 킬 줌 (시야를 좁히고 그 자리를 봄) + 화면 끝 번쩍 (ko.js camHook)
func cam_hook(cam: Camera3D, now := now_ms()) -> void:
	draw_edge(cam, now)
	var k := FM.final_k(now, slow)
	if k <= 0.0:
		return
	var target := Co.gxyz(slow.x, slow.y, slow.z + 0.8)
	# 카메라 자리는 rig 안 로컬 (rig 은 원점) — 트리 밖 (테스트) 에서도 됨
	var look := cam.position - cam.basis.z
	look = look.lerp(target, k * C.KO_FINAL_LOOK)
	var dirv := (look - cam.position).normalized()
	cam.look_at_from_position(cam.position, look, Vector3.UP if absf(dirv.y) < 0.999 else Vector3.FORWARD)
	cam.fov *= 1.0 - k * (1.0 - C.KO_FINAL_ZOOM)


func draw_edge(cam: Camera3D, now: float) -> void:
	if now >= edge_until or edge_at == null:
		edge_rect.visible = false
		return
	var vp := cam.get_viewport().get_visible_rect().size if cam.is_inside_tree() else Vector2(1, 1)
	var wp := Co.gpos(edge_at)
	var behind := cam.is_position_behind(wp)
	var sp := cam.unproject_position(wp) if cam.is_inside_tree() else Vector2.ZERO
	var e := FM.edge_pos(sp.x / vp.x * 2.0 - 1.0, 1.0 - sp.y / vp.y * 2.0, behind)
	edge_rect.visible = true
	edge_mat.set_shader_parameter("at", e / 100.0)
	edge_mat.set_shader_parameter("tint", edge_color)
	edge_mat.set_shader_parameter("alpha", FM.edge_alpha((edge_until - now) / C.KO_EDGE_MS))


func update(dt: float) -> void:
	for pl in plumes.duplicate():
		pl.age += dt
		var t: float = pl.age / pl.life
		if t >= 1.0:
			pl.node.queue_free()
			plumes.erase(pl)
			continue
		_plume_pose(pl, FM.plume(t))
