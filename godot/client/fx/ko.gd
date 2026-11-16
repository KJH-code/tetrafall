# KO 연출 (client/ko.js 자리, 2026-10-27 재혁): 스매시 폭발 줄기 · 마지막 킬 슬로모션·줌 · 압사 히트스톱 · 화면 끝 번쩍. 수치는 config KO_*
# 화면만 (서버 시간·판정과 상관없음). 소리는 View.sound_cue "smash"·"koCrush" {x,y,z,me,near} · "final" {x,y,z} (audio/ 가 받음)
extends Node3D

const C := preload("res://core/config.gd")
const Co := preload("res://core/coords.gd")
const FM := preload("res://fx/fx_math.gd")
const FXC := preload("res://fx/fx_config.gd")

var fx # effects.gd
var color_of := func(_id): return 0xffffff
var low_gfx := func(): return false
var field := func(): return Vector2(C.GRID_W, C.GRID_W)
var plumes: Array = [] # {node, mats (단마다 재질 — FXC.PLUME 차례), age, life, dir}
var slow := {} # 마지막 킬 슬로모션 {start, until, x, y, z}
var stop_until := 0.0 # 압사 히트스톱
var edge_layer := CanvasLayer.new()
var edge_rect := ColorRect.new()
var edge_mat := ShaderMaterial.new()
var edge_at = null # 게임 좌표 Vector3
var edge_color := Color.WHITE
var edge_until := 0.0
var cone: Mesh
var cam: Camera3D = null # 지금 카메라 (fx.gd 가 넣음): 카메라가 줄기 안에 있으면 줄기를 옅게

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
	cone = cone_mesh(FXC.PLUME_SEG, FXC.PLUME_TIP_FADE)
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


# 줄기 원뿔 (c8-u3: 예전 CylinderMesh 와 같은 치수 — 꼭짓점이 아래 (반지름 0), 넓은 끝이 위 (반지름 KO_SMASH_WIDTH), 높이 KO_SMASH_LEN, 가운데가 원점. 마디 노드가 LEN/2 올림).
# 꼭짓점 색 알파: 넓은 끝 0 → 길이의 fade 지점부터 1 — 원뿔이 넓은 끝에서 뚝 잘려 확성기 입처럼 보이지 않고 끝이 흩어짐 (꼭짓점 색을 쓰는 재질만 — 보통 섞기 단)
static func cone_mesh(seg: int, fade: float) -> ArrayMesh:
	var verts := PackedVector3Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	var rows := [[0.0, 1.0], [1.0 - fade, 1.0], [1.0, 0.0]] # [길이 비 (0 꼭짓점 ~ 1 넓은 끝), 알파]
	for r in rows:
		for i in seg:
			var a := TAU * i / seg
			verts.append(Vector3(cos(a) * C.KO_SMASH_WIDTH * r[0], (r[0] - 0.5) * C.KO_SMASH_LEN, sin(a) * C.KO_SMASH_WIDTH * r[0]))
			cols.append(Color(1, 1, 1, r[1]))
	for j in rows.size() - 1:
		for i in seg:
			var a0 := j * seg + i
			var a1 := j * seg + (i + 1) % seg
			idx.append_array([a0, a1, a0 + seg, a1, a1 + seg, a0 + seg])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_COLOR] = cols
	arr[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m


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
	# c8-u3: 원뿔 하나 (더하기 섞기 — 밝은 하늘 앞에서 흰·하늘색 큰 삼각) → 한 노드 아래 겹친 원뿔 2~3단 (FXC.PLUME: 바깥 = 그 사람 색 옅게 · 가운데 = 진하게 · 심 = 흰 쪽).
	# 단들은 보통 섞기 (색이 남음 — FXC.PLUME_CORE_ADD 를 켜면 심만 더하기). 줄기 항목 (plumes) 은 그대로 하나 — 모양 (FM.plume)·수명은 노드 하나가 맡고 단은 그 아래 배율만
	var node := Node3D.new()
	var mats := []
	var bands: Array = FXC.PLUME
	for i in bands.size():
		var b: Array = bands[i]
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		var add: bool = FXC.PLUME_CORE_ADD and i == bands.size() - 1
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if add else BaseMaterial3D.BLEND_MODE_MIX
		mat.vertex_color_use_as_albedo = not add # 보통 섞기 단 = 효과 풀 고리 재질 (effects.ring_mat) 과 같은 모양, 더하기 심 = 예전 줄기 재질 모양 → 판 중에 새 셰이더를 안 만듦 (world/warm_scan.gd STD_KEYS)
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
		FM.near_fade(mat) # 카메라 바로 앞이면 흐려짐 (화면을 덮지 않게)
		mat.albedo_color = Co.color(color).lerp(Color.WHITE, float(b[3]))
		var mi := MeshInstance3D.new()
		mi.mesh = cone
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.scale = Vector3(float(b[0]), float(b[1]), float(b[0]))
		mi.position.y = C.KO_SMASH_LEN / 2.0 * float(b[1])
		mi.sorting_offset = i * FXC.PLUME_SORT_STEP
		node.add_child(mi)
		mats.append(mat)
	node.position = Co.gpos(at)
	add_child(node)
	var pl := {"node": node, "mats": mats, "age": 0.0, "life": C.KO_SMASH_MS / 1000.0, "dir": Co.gpos(dir).normalized()}
	_plume_pose(pl, Vector3(0.2, 0.2, 0.9))
	plumes.append(pl)
	fx.burst(at, {"x": dir.x, "y": dir.y}, color, parts(C.KO_SMASH_PARTICLES), 12.0, 0.16, 0.8)
	fx.burst(at, null, 0xffffff, parts(C.KO_SMASH_PARTICLES / 2.0), 6.0, 0.1, 0.5)
	fx.ring(at, color, 5.0, 0.4)
	# W18: 줄기 밑동 번쩍 + 바깥으로 그 사람 색 불꽃 줄 (fx_config KO_FX)
	var K: Dictionary = FXC.KO_FX
	fx.glow(at, color, K.smash_flash[0], K.smash_flash[1], 1.0, fx.STAR, {"grow": 1.4, "hot": 1.0})
	var sp: Array = K.smash_sparks
	fx.sparks(at, dir, color, FXC.count(sp[0], fx.lv), sp[1], sp[2], sp[3], 0.45)
	if me:
		fx.shake(C.KO_SHAKE_ME, C.KO_SHAKE_MS)
	elif near:
		fx.shake(C.KO_SHAKE_NEAR, C.KO_SHAKE_MS)
	edge_at = at
	edge_color = Co.color(color)
	edge_until = now_ms() + C.KO_EDGE_MS


# 줄기 노드: 로컬 +Y 를 dir 쪽으로 (setFromUnitVectors), 크기 (옆, 길이, 옆) × 화면 상한 배율. 단마다 알파 = s.z × 단 알파 배율 × 카메라가 그 단 안이면 옅게
func _plume_pose(pl: Dictionary, s: Vector3) -> void:
	var d: Vector3 = pl.dir
	var axis := Vector3.UP.cross(d)
	var q := Quaternion() if axis.length() < 1e-6 else Quaternion(axis.normalized(), Vector3.UP.angle_to(d))
	if axis.length() < 1e-6 and d.y < 0:
		q = Quaternion(Vector3.RIGHT, PI)
	var k := plume_cap(pl, s)
	pl.node.basis = Basis(q).scaled_local(Vector3(s.x * k, s.y * k, s.x * k))
	var seen: bool = cam != null and cam.is_inside_tree() and pl.node.is_inside_tree()
	var rel: Vector3 = Co.game(cam.global_position - (pl.node as Node3D).global_position) if seen else Vector3.ZERO
	var bands: Array = FXC.PLUME
	for i in pl.mats.size():
		var b: Array = bands[i]
		var a := s.z * float(b[2])
		if seen:
			a *= FM.plume_inside_fade(rel, Co.game(d).normalized(), s.x * k * float(b[0]), s.y * k * float(b[1]))
		(pl.mats[i] as StandardMaterial3D).albedo_color.a = a


# 줄기 화면 상한 배율 (c8-u3 · c8-fix F1, FM.plume_cap): 지금 카메라에 줄기 (가장 큰 = 바깥 단) 를 원근 투영한 크기 (비친 길이·끝 지름 중 큰 쪽) 가 화면 높이 × FXC.SCREEN_CAP 을 넘으면 줄임. 카메라가 없으면 (테스트) 1.
# 줄기 꼭짓점 (노드 자리)·축 (pl.dir — 노드 부모 기준) 을 카메라 공간으로 옮겨 넘김
func plume_cap(pl: Dictionary, s: Vector3) -> float:
	if cam == null or not cam.is_inside_tree() or not pl.node.is_inside_tree():
		return 1.0
	var n: Node3D = pl.node
	var inv := cam.global_transform.affine_inverse()
	var par := n.get_parent() as Node3D
	var dir: Vector3 = pl.dir if par == null else par.global_basis * (pl.dir as Vector3)
	return FM.plume_cap(C.KO_SMASH_LEN * s.y, 2.0 * C.KO_SMASH_WIDTH * s.x, inv * n.global_position, (inv.basis * dir).normalized(), cam.fov, FXC.SCREEN_CAP, FXC.PLUME_CAP_SEG, FXC.PLUME_CAP_STEPS, FXC.PLUME_CAP_NEAR)


func crush(p: Vector3, me: bool, near: bool) -> void:
	var base := p + Vector3(0, 0, 0.1)
	fx.burst(base, null, 0x9a8a7a, parts(C.KO_CRUSH_DUST), 7.0, 0.22, 1.0) # 먼지 크게
	fx.burst(base + Vector3(0, 0, 0.6), null, 0x5d6b7a, parts(C.KO_CRUSH_CHIPS), 9.0, 0.16, 0.8) # 블록 조각
	fx.ring(base, 0xd8c8b0, 3.5, 0.35, true)
	# W18: 먼지 구름 + 블록 조각 (튀고 멈춤) + 바닥 빛 고리 (fx_config KO_FX)
	var K: Dictionary = FXC.KO_FX
	var cs: Array = K.crush_smoke
	fx.smoke(base, 0xa89a88, FXC.count(cs[0], fx.lv), cs[1], cs[2], 0.5, 1.6, 0.7)
	var cc: Array = K.crush_chunks
	fx.chunks(base + Vector3(0, 0, 0.4), null, 0x5d6b7a, FXC.count(cc[0], fx.lv), cc[1], cc[2])
	fx.quake(base, 1.4)
	if me or near:
		if not fx.reduced: # 움직임 줄이기면 히트스톱 없음 (W18)
			stop_until = now_ms() + C.KO_CRUSH_STOP_MS # 짧은 히트스톱
		fx.shake(C.KO_SHAKE_ME if me else C.KO_SHAKE_NEAR, C.KO_SHAKE_MS)


# 서버 finalKill 이벤트: 판을 끝낸 킬 → 잠깐 느리게 + 그 자리로 줌
func final(e: Dictionary) -> void:
	var now := now_ms()
	slow = {"start": now, "until": now + C.KO_FINAL_MS, "x": float(e.get("x", 0)), "y": float(e.get("y", 0)), "z": float(e.get("z", 0))}
	# W18: 마지막 킬 자리에 하얀 번쩍 + 그 사람 색 빛 고리 (슬로모션 화면 시계로 흘러 천천히 퍼짐 — fx_config KO_FX.final)
	var F: Array = FXC.KO_FX.final
	var at := Vector3(slow.x, slow.y, slow.z + 0.8)
	fx.glow(at, 0xffffff, F[0], F[1], 1.0, fx.STAR, {"grow": 1.5, "hot": 1.0, "front": 0.5})
	fx.glow(at, color_of.call(e.get("who")), 0.5, F[1] * 1.4, 0.9, fx.SHOCK, {"grow": F[0] * 2.0 / 0.5, "pw": 1.2})
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
		_plume_pose(pl, FM.plume(t)) # 화면 상한·카메라가 줄기 안이면 옅게 는 _plume_pose 가 단마다
