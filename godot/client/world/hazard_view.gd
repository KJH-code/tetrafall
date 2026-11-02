# 상승하는 위험 (용암 자리, client/hazard.js). G3 hazard 재질 (B3) 이 있으면: 필드 판 near + 지평선 바다 far (파도·닿는 곳 테·먼 섬 잠김 테·물들임은 셰이더),
# 여기선 표 (닿는 곳 거리 field·먼 섬 rings·발 밑 들썩 bulge·차오름 번쩍 pulse)·빛·떠다니는 입자·닿는 곳 거품 입자·차오름 흔들림·잠겨 죽으면 튀김.
# G3 가 없으면 예전 단순 모습: 지평선까지 큰 표면 판 하나 (테마 색·투명도) + 닿는 곳 거품 띠 (MultiMesh). 계산은 hazard_field.gd (client/hazard-field.js 그대로)
extends Node3D

const C := preload("res://core/config.gd")
const Co := preload("res://core/coords.gd")
const HF := preload("res://world/hazard_field.gd")
const WC := preload("res://world/world_config.gd")
const VIG := preload("res://world/hazard_vignette.gdshader")

var surface := MeshInstance3D.new()
var foam := MultiMeshInstance3D.new()
var surf_mat := StandardMaterial3D.new()
var foam_mat := StandardMaterial3D.new()
var _key := "" # 거품 자리를 다시 계산할 때 (격자 판·표면 높이 단계)
var step := -1 # 차오름 단계 (riseStep) — 바뀌면 rose 신호 자리. 음수도 진짜 단계 (LAVA_START_Z -1 → -2, -1, 0 …)
var has_step := false # step 이 있음 (hazard.js this.step !== null — 예전 step >= 0 확인은 0 아래 단계의 번쩍·거품 둘을 놓침)
var vignette := 0.0 # 화면 가장자리 경고 목표 세기 (vignetteStrength) — vig_k 가 부드럽게 따라가 vig 에 그림
var vig_k := 0.0 # 그리는 세기 (hazard.js vigK: += (목표 - vigK) × (1 - e^(-6 dt)))
var vig_layer := CanvasLayer.new() # 위험 가장자리 경고 (hazard.js overlay — 3D 다음, 판 빛 비네트·HUD 아래)
var vig := ColorRect.new()
# G3 재질 (set_g3) — 없으면 null
var G3 = null
var near_mi: MeshInstance3D = null
var far_mi: MeshInstance3D = null
var mats := []
var look := {} # G3.hazard_look (입자·빛 색)
var low := false
var scenery = null # far_objects() (먼 섬 잠김 테)
var effects = null # G5 파편·고리·흔들림
var light_color := Color.BLACK # 위험 빛 색 (look.light[0]) — 빛은 툰 셰이더 전역 값 g3_hz_l* (hz_light.gdshaderinc, set_light)
var pulse := 0.0
var t := 0.0
var _was := false
var _field_key := ""
var _field = null
var _amb_acc := 0.0
var _contact_acc := 0.0
var _alive := {}
var _off_sent := false
var _cleared := false # clear() 를 했고 그 뒤 update 가 없었음
var bodies = null # 잠기는 몸 (nodes[id].root·shown[id])
var sinks := {} # id -> {t0, x, y, z, zs}


func _init() -> void: # 가장자리 경고 (트리 밖에서도 — 테스트)
	vig_layer.layer = -2 # 3D 바로 위, 판 빛 비네트 (game_light -1) 아래 — JS 는 캔버스 안 (CSS 비네트 아래)
	vig.set_anchors_preset(Control.PRESET_FULL_RECT)
	vig.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vig.material = ShaderMaterial.new()
	vig.material.shader = VIG
	vig.visible = false
	vig_layer.add_child(vig)
	add_child(vig_layer)


# _ready 전에 지워지면 (트리에 안 넣은 채 — 테스트) 아직 안 붙인 표면·거품 노드도 같이
func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		for n in [surface, foam]:
			if is_instance_valid(n) and n.get_parent() == null:
				n.free()


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


# 가장자리 경고 그리기: want 로 부드럽게 (reset 이면 바로 0 — hazard.js 꺼짐), 0.01 아래면 안 그림
func _draw_vig(want: float, dt: float, reset := false) -> void:
	vig_k = 0.0 if reset else vig_k + (want - vig_k) * (1.0 - exp(-6.0 * dt))
	vig.visible = vig_k >= 0.01
	if vig.visible:
		vig.material.set_shader_parameter("k", vig_k)
		vig.material.set_shader_parameter("time", t)
		var c := Co.color(look.get("vignette", 0xff4010))
		vig.material.set_shader_parameter("color", Vector3(c.r, c.g, c.b))


# 위험 빛 (hazard.js PointLight(색, 세기, LAVA_LIGHT_RANGE, 1.4)): 세기 = three 값, at = 고도 자리. 툰 셰이더들이 전역 값으로 직접 셈 (hz_light.gdshaderinc)
func set_light(intensity: float, at: Vector3) -> void:
	if G3 == null:
		return
	var c := light_color.srgb_to_linear()
	G3._set_global("g3_hz_lp", Vector4(at.x, at.y, at.z, intensity))
	G3._set_global("g3_hz_lc", Vector4(c.r, c.g, c.b, C.LAVA_LIGHT_RANGE))
	G3._set_global("g3_hz_ld", WC.HAZARD_LIGHT_DECAY)


# G3 위험 재질로 (맵 테마마다·그래픽 낮춤 바뀔 때). g3 null 이면 예전 단순 모습
func set_g3(g3, theme_id, low_gfx: bool) -> void:
	G3 = g3
	low = low_gfx
	for mi in [near_mi, far_mi]:
		if mi != null:
			mi.queue_free()
	near_mi = null
	far_mi = null
	mats = []
	_field_key = ""
	if G3 == null:
		surface.visible = true
		return
	look = G3.hazard_look(theme_id)
	surface.visible = false
	foam.visible = false
	for far in [false, true]:
		var mi := MeshInstance3D.new()
		mi.mesh = G3.hazard_mesh(far, low)
		mi.material_override = G3.hazard_material(theme_id, low, far)
		mi.extra_cull_margin = 16384.0
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		mats.append(mi.material_override)
		if far:
			far_mi = mi
		else:
			near_mi = mi
	light_color = Co.color(look.light[0])


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


func update(st: Dictionary, grid: PackedByteArray, grid_version: int, me: Dictionary, dt := 0.0) -> void:
	_cleared = false
	var lava: Dictionary = st.get("lava", {})
	var on: bool = lava.get("active", false)
	visible = on
	vignette = 0.0
	if G3 != null:
		_update_g3(st, grid, grid_version, me, on, dt)
		return
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


# G3 재질 모습 (hazard.js update 그대로)
func _update_g3(st: Dictionary, grid: PackedByteArray, grid_version: int, me: Dictionary, on: bool, dt: float) -> void:
	t += dt
	pulse = maxf(0.0, pulse - dt * C.HAZARD_PULSE_DECAY)
	var zs: float = float(st.lava.z) if on else -99.0
	if not on:
		_off()
		_track_deaths(st, zs, false)
		_step_sinks()
		return
	_off_sent = false
	var f: Dictionary = st.field
	var w := int(f.w)
	var d := int(f.d)
	var h := int(f.get("h", C.GRID_H))
	var cx := w / 2.0
	var cy := d / 2.0
	# 닿는 곳 거리 표 (격자나 표면 칸이 바뀔 때만)
	var p := {"on": true, "time": t, "z": zs}
	var key := "%d|%d|%s|%d|%d|%d" % [grid_version, floori(zs), zs < 0, w, d, h]
	if key != _field_key and grid.size() == w * d * h:
		_field_key = key
		_field = HF.field(grid, w, d, h, zs)
		p.field = _field
	# 차오름: 처음 시작 / 단계마다
	var s := HF.rise_step(zs)
	if not _was:
		_rise(true, zs, me)
	elif has_step and s > step:
		_rise(false, zs, me)
	_was = true
	step = s
	has_step = true
	near_mi.position = Co.gxyz(cx, cy, zs)
	near_mi.scale = Vector3(w + 2 * G3.HZ_MARGIN, 1, d + 2 * G3.HZ_MARGIN)
	far_mi.position = Co.gxyz(cx, cy, zs)
	p.rings = [] if low or scenery == null else HF.far_rings(scenery.far_objects(), zs, int(C.HAZARD_FAR_RINGS), cx, cy)
	p.pulse = pulse
	# 발 밑 들썩: 살아 있는 사람 중 표면에 가장 가까운 (나 먼저)
	var bulge = null
	for pl in st.get("players", []):
		if not pl.alive or pl.get("master", false):
			continue
		var gap: float = float(pl.z) - zs
		var mine: bool = not me.is_empty() and int(pl.id) == int(me.id)
		if gap < C.HAZARD_BULGE_DIST and gap > -0.3 and (bulge == null or mine or gap < bulge.gap):
			bulge = {"x": float(pl.x), "y": float(pl.y), "gap": gap, "mine": mine}
		if bulge != null and bulge.mine:
			break
	p.bulge = Vector4(bulge.x, bulge.y, C.HAZARD_BULGE_AMP * (1.0 - maxf(0.0, bulge.gap) / C.HAZARD_BULGE_DIST), 0) if bulge != null else Vector4.ZERO
	G3.hazard_update(mats, get_parent(), p)
	# 빛: 일렁임 + 번쩍
	set_light(C.LAVA_LIGHT_INTENSITY * float(look.light[1]) * (0.85 + 0.15 * sin(t * 7) * sin(t * 2.3)) * (1 + pulse), Co.gxyz(cx, cy, zs + 1.2))
	# 떠다니는 입자: 표면 아무 데서나 + 닿는 곳 (증기·거품·불꽃)
	if effects != null:
		var k: float = C.WORLD_LOW_DETAIL if low else 1.0
		_amb_acc += dt * C.LAVA_EMBER_RATE * float(look.ambient) * k
		while _amb_acc >= 1:
			_amb_acc -= 1
			effects.burst(Vector3(-1 + randf() * (w + 2), -1 + randf() * (d + 2), zs + 0.05), null, int(look.particles[0 if randf() < 0.5 else 1]), 1, float(look.particleSpeed), 0.06, 0.8)
		var contacts: Array = _field.contacts if _field != null else []
		if contacts.size() and not low:
			_contact_acc += dt * C.HAZARD_CONTACT_RATE * (1 + pulse * 3)
			while _contact_acc >= 1:
				_contact_acc -= 1
				var c: Dictionary = contacts[randi() % contacts.size()]
				var a := (randf() - 0.5) * 0.9
				effects.burst(Vector3(c.x + c.ny * a + c.nx * 0.12, c.y + c.nx * a + c.ny * 0.12, zs + 0.04), null, int(look.contact), 1, float(look.particleSpeed) * 0.5, 0.07, 0.9)
	if not me.is_empty() and me.alive and not me.get("master", false):
		vignette = HF.vignette_strength(float(me.z) - zs, pulse)
	_draw_vig(vignette, dt)
	_track_deaths(st, zs, true)
	_step_sinks()


# 위험 꺼짐: 빛 (전역 g3_hz_lp 세기 0)·가장자리 경고 (바로 0)·물들임과 하늘 아래 색 (G3.hazard_update on false, 한 번만)
func _off() -> void:
	set_light(0.0, Vector3.ZERO)
	_draw_vig(0.0, 0.0, true)
	_was = false
	step = -1
	has_step = false
	pulse = 0.0
	if G3 != null and not _off_sent:
		G3.hazard_update(mats, get_parent(), {"on": false, "time": t, "z": -99.0}) # 물들임·하늘 아래 색 끔
		_off_sent = true


# 방 밖 (메뉴): World 가 판 갱신을 멈추기 전에 부름 — 판 중에 나가면 update 가 더 안 불려 경고 판 (CanvasLayer 라 Node3D 를 숨겨도 그려짐)·
# 전역 위험 빛·물들임이 메뉴에 남던 것 (W3). 잠기는 몸·지난 생존 기억도 버림. 메뉴에선 매 프레임 불려도 한 번만 함 (update 가 다시 열 때까지)
func clear() -> void:
	if _cleared:
		return
	_cleared = true
	_off()
	sinks.clear()
	_alive.clear()
	_field_key = ""
	_key = ""
	vignette = 0.0


# 차오름 한 번: 번쩍·가까우면 흔들림·닿는 곳 거품 (hazard.js rise)
func _rise(start: bool, z: float, me: Dictionary) -> void:
	pulse = 1.0
	if effects == null:
		return
	var gap: float = float(me.z) - z if not me.is_empty() and me.alive else INF
	var S: Array = C.HAZARD_RISE_SHAKE
	if gap < float(S[2]):
		effects.shake(float(S[0]) * (2.0 if start else 1.0), float(S[1]))
	var contacts: Array = _field.contacts if _field != null else []
	if contacts.is_empty():
		return
	for i in mini(contacts.size(), 4 if low else 14):
		var c: Dictionary = contacts[randi() % contacts.size()]
		effects.burst(Vector3(c.x, c.y, z + 0.05), null, int(look.contact), 3, float(look.particleSpeed), 0.08, 0.7)


# 위험에 죽은 사람 (지난 프레임 살아 있었고 지금 죽었고 표면 근처): 튀김 + 잠기는 몸 (hazard.js trackDeaths·splash)
func _track_deaths(st: Dictionary, zs: float, on: bool) -> void:
	for pl in st.get("players", []):
		var id := int(pl.id)
		var was = _alive.get(id)
		_alive[id] = pl.alive
		if not on or not was or pl.alive or pl.get("master", false) or float(pl.z) > zs + 0.6:
			continue
		pulse = maxf(pulse, 0.6)
		var sp = bodies.shown.get(id) if bodies != null else null
		sinks[id] = {"t0": t, "x": float(sp.x if sp != null else pl.x), "y": float(sp.y if sp != null else pl.y), "z": zs - 0.35, "zs": zs}
		if effects == null:
			continue
		var pos := Vector3(float(pl.x), float(pl.y), zs + 0.1)
		effects.burst(pos, null, int(look.splash[0]), 12 if low else 34, float(look.particleSpeed) * 1.8, 0.16, 1.0)
		effects.burst(pos, null, int(look.splash[1]), 8 if low else 22, float(look.particleSpeed) * 1.1, 0.13, 1.3)
		effects.ring(Vector3(pl.x, pl.y, zs + 0.06), int(look.foam), 3.2, 0.7, true)
		effects.ring(Vector3(pl.x, pl.y, zs + 0.06), int(look.splash[0]), 2.0, 0.45, true)


# 잠기는 몸: bodies 가 죽은 몸을 숨긴 뒤 HAZARD_SINK_MS 동안 다시 보이게 하고 아래로 (hazard.js stepSinks — 처음엔 표면에 걸려 허우적, 그다음 천천히 가라앉음)
func _step_sinks() -> void:
	for id in sinks.keys():
		var s: Dictionary = sinks[id]
		var n: Dictionary = bodies.nodes.get(id, {}) if bodies != null else {}
		var k: float = (t - s.t0) * 1000.0 / C.HAZARD_SINK_MS
		if n.is_empty() or k >= 1.0:
			sinks.erase(id)
			continue
		var u := maxf(0.0, (k - C.HAZARD_SINK_FLOAT) / (1.0 - C.HAZARD_SINK_FLOAT))
		var e := u * u * (3 - 2 * u)
		var root: Node3D = n.root
		root.visible = true
		root.position = Co.gxyz(s.x, s.y, s.z + sin(k * 22) * 0.05 * (1 - u) - e * C.HAZARD_SINK_DEPTH)
		# 게임 x·y 축 흔들림 (three rotation.x·y), 방향 (yaw) 은 그대로
		var yaw := root.rotation.y
		root.basis = Basis(Vector3.RIGHT, sin(k * 11) * 0.22 * (1 - k)) * Basis(Vector3.FORWARD, cos(k * 8) * 0.15 * (1 - k)) * Basis(Vector3.UP, yaw)
		if effects != null and randf() < 0.3:
			effects.burst(Vector3(s.x, s.y, s.zs + 0.05), null, int(look.contact), 1, 2, 0.08, 0.6)
