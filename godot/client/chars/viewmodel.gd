# 1인칭 팔·무기 (client/viewmodel.js 옮김): 내 3인칭 몸 (chars/body.gd) 과 같은 몸을 하나 더 만들어 팔꿈치 아래·든 무기만 그리고,
# 관절은 매 프레임 내 몸에서 베낌 → 평타·스킬 동작이 그대로. 어깨 각만 바꿔 손이 화면 아래 구석에 오게 함.
# 필드 위에 겹쳐 그려야 해서 (벽에 안 박힘) 자기 SubViewport (투명 배경·자기 3D 세계·자기 카메라 VM_FOV) 에 그리고 화면 전체 TextureRect 로 덮음.
# 쓰는 법 (World/G1): var vm = Viewmodel.new(); add_child(vm) → 매 프레임 vm.update(내 몸 노드 또는 null, 1인칭이면 true, dt). 끝.
extends Node

const C := preload("res://core/config.gd")
const Body := preload("res://chars/body.gd")
const G3 := preload("res://shaders/g3.gd")
const K := preload("res://chars/chars_config.gd")
const WC := preload("res://world/world_config.gd")

const HALF_PI := PI / 2

var view: SubViewport
var cam: Camera3D
var anchor: Node3D # 카메라 앞 어깨 높이 기준점 (몸 좌표 → 카메라 좌표)
var rect: TextureRect
var layer: CanvasLayer
var base_basis: Basis
var src = null # 지금 베끼는 내 몸 (body.gd)
var twin = null # 1인칭용 몸 (body.gd, 합치지 않음)
var pairs: Array = [] # [원본 노드 번호, ...] 허리 아래 (허리 제외)
var char_id := ""
var hold := false # 두 손으로 무기를 잡는 캐릭터 (VM_HOLD: 바드·대포수)
var spin := false # 몸 전체 돌기를 그대로 (VM_SPIN)
var on := false
var star: Node3D = null # 닌자: 왼손에 부채꼴로 쥔 표창 3개 (단검 대신)
var pips: Array = [] # 대포수: 대포 등에 남은 포탄 수만큼 쇠공 [[쇠공, 원본 포탄 노드]]
var veins: Array = [] # 광전사: 분노가 차면 아래팔 핏줄 (팔마다 묶음)
var shield_k := 0.0 # 탱크 방패를 쥔 정도 (W11): 0 = 빈손 (방패 넣음), VM_SHIELD_REACH 까지 = 손을 내림, 1 = 쥐고 든 자세
static var _star_mesh: ArrayMesh = null
static var clip_arm: float = K.VM_CLIP_ARM # W40: 3인칭 클립 팔 곡선을 1인칭 팔에 섞는 비율 (확인 도구가 0 으로 끄고 전후 비교)
static var shield_hand: bool = K.VM_SHIELD_HAND # 탱크 방패를 왼손에 쥠 (W11). 확인 도구 (tools/vm_shots.gd old) 가 예전 모습을 찍을 때 끔


func _ready() -> void:
	layer = CanvasLayer.new()
	layer.layer = 0 # 3D 판 위, UI (G4) 아래
	add_child(layer)
	view = SubViewport.new()
	view.transparent_bg = true
	view.own_world_3d = true
	set_msaa() # JS 는 팔도 판과 같은 캔버스 (antialias) — 판 화면과 같은 값, 그래픽 낮춤을 바꾸면 곧바로
	View.changed.connect(_on_view)
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(view)
	cam = Camera3D.new()
	cam.fov = C.VM_FOV
	cam.near = 0.01
	cam.far = 20.0
	view.add_child(cam)
	# 빛: 위·왼쪽 앞에서 비추는 해 + 고른 주변광 (카메라에 붙어 시선이 바뀌어도 팔 밝기는 같음)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_CLEAR_COLOR
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color.BLACK # 하늘빛·해 세기는 G3 툰 셰이더 전역 값 (필드와 같음) — 고도 주변광을 더하면 팔이 하얗게 날아감
	env.environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	view.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.light_color = Color.WHITE # 툰 셰이더는 방향만 씀 (색·세기는 g3_sun)
	sun.light_energy = 1.0
	sun.look_at_from_position(Vector3(-1, 2, 1), Vector3.ZERO)
	cam.add_child(sun)
	# 몸 좌표 (앞 +x, 왼쪽 +y, 위 +z) → 카메라 좌표 (앞 -z, 오른쪽 +x, 위 +y)
	base_basis = Basis(Vector3(0, 0, -1), Vector3(-1, 0, 0), Vector3(0, 1, 0))
	anchor = Node3D.new()
	anchor.rotation_order = EULER_ORDER_XYZ
	cam.add_child(anchor)
	rect = TextureRect.new()
	rect.texture = view.get_texture()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE # 텍스처 (창 픽셀) 가 UI 좌표보다 커도 화면 크기 그대로 (W9)
	layer.add_child(rect)
	_set_on(false)


func set_msaa() -> void:
	view.msaa_3d = WC.vm_msaa(bool(View.settings.get("lowGfx", false)))


func _on_view(k: String) -> void:
	if k == "lowGfx":
		set_msaa()


func _set_on(v: bool) -> void:
	on = v
	if layer != null:
		layer.visible = v
	if view != null:
		view.render_target_update_mode = SubViewport.UPDATE_ALWAYS if v else SubViewport.UPDATE_DISABLED


# body = 내 3인칭 몸 (World 가 만든 chars.make_body, 없으면 null), first_person = 1인칭이고 살아 있음
func update(body, first_person: bool, dt: float) -> void:
	if body != src:
		_sync(body)
	_set_on(first_person and twin != null)
	if not on:
		return
	var size: Vector2i = load("res://core/ui_scale.gd").pixel_size(get_viewport()) # 창 픽셀 (UI 배율이 커도 선명하게, W9 — visible_rect 는 UI 좌표)
	if size != view.size:
		view.size = size
	_follow(dt)


# 내 몸이 바뀜 (캐릭터 바꿈·다시 들어옴): 같은 몸을 하나 더 만들어 팔·무기만 남김
func _sync(body) -> void:
	src = body
	if twin != null:
		twin.queue_free()
		twin = null
	for c in anchor.get_children():
		c.queue_free()
	pairs.clear()
	shield_k = 0.0
	if body == null or not (body is Body):
		return
	char_id = body.char_id
	twin = Body.new()
	twin.build(char_id, body.skin_color, false) # 합치지 않음 (조각마다 보이기)
	twin.set_hz_light(false) # 자기 SubViewport 장면 — 판의 위험 빛 안 받음 (JS viewmodel 은 따로 된 scene)
	view.add_child(twin)
	if twin.ext != null and body.ext != null: # W40: 3인칭 클립 팔 곡선
		twin.ext.src_ext = body.ext
		twin.ext.clip_arm_k = clip_arm
	twin.visible = false # 몸 자체는 안 그림 — 허리만 떼어 anchor 에 붙임
	var w: int = twin.nodes.find(twin.waist)
	# 허리 아래 (허리 제외) 노드 번호
	var under := {w: true}
	for i: int in twin.nodes.size():
		var p: int = twin.parents[i]
		if p >= 0 and under.has(p):
			under[i] = true
			if i < body.nodes.size(): # 구운 몸: 판 몸 (묶음) 은 묶음에 들어간 잎이 없음 — 잎은 안 움직여서 베낄 것도 없음
				pairs.append(i)
	var waist: Node3D = twin.waist
	waist.get_parent().remove_child(waist)
	anchor.add_child(waist)
	waist.position = Vector3(0, 0, -(float(twin.d.torso) - float(twin.d.armR) * 1.6)) # 어깨 높이가 기준점
	anchor.scale = Vector3.ONE * C.FIGURE_SCALE * C.VM_SCALE * float(C.VM_SIZE.get(char_id, 1.0)) # 굵은 몸은 작게
	# 그릴 것: 팔꿈치 아래 + 몸통에 붙은 캐릭터 무기 (탱크 앞 방패·대포수 대포·바드 악기). 나머지 조각은 안 그림 (layers 0)
	var show := {}
	var roots: Array = [twin.elbows[0], twin.elbows[1]]
	for r in [twin.refs.get("shields", {}).get("front") if twin.refs.get("shields") is Dictionary else null, twin.refs.get("cannon"), twin.refs.get("lute", {}).get("lute") if twin.refs.get("lute") is Dictionary else null, twin.refs.get("guitar")]:
		var n = twin._n(r)
		if n != null:
			roots.append(n)
	for r in roots:
		show[twin.nodes.find(r)] = true
	for i in twin.nodes.size():
		var shown := false
		var k: int = i
		while k >= 0:
			if show.has(k):
				shown = true
				break
			k = twin.parents[k]
		var n: Node3D = twin.nodes[i]
		if n is MeshInstance3D:
			(n as MeshInstance3D).layers = 1 if shown else 0
	hold = char_id in C.VM_HOLD
	spin = char_id in C.VM_SPIN
	_props()
	_local_light(anchor) # 허리 아래는 anchor 로 옮겨 붙음


# 1인칭 팔은 필드 테마와 상관없이 JS viewmodel 의 노을 빛 (G3.toon_local_light — 인자 없으면 그 빛), 위험 빛도 안 받음 (소품 포함).
# 복제 몸 재질은 몸마다 따로라 필드 몸은 그대로.
func _local_light(root: Node) -> void:
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var m = (mi as MeshInstance3D).material_override
		if m is ShaderMaterial:
			G3.toon_local_light(m)
			G3.toon_hazard_light(m, false)



# 캐릭터별 1인칭 소품 (viewmodel.js sync 끝)
func _props() -> void:
	star = null
	pips.clear()
	veins.clear()
	if char_id == "ninja":
		# 왼손엔 단검 대신 부채꼴로 쥔 표창 3개 (던지면 잠깐 비었다가 다시 쥠)
		var cd: Dictionary = twin.cd # 예전 조립이면 bodies.bin 한 줄, 구운 몸이면 manifest (같은 번호)
		for i in twin.nodes.size():
			if cd.nodes[i].get("dagger", false) and twin.nodes[i] is MeshInstance3D:
				(twin.nodes[i] as MeshInstance3D).layers = 0
		star = Node3D.new()
		var mat := G3.toon_material(0xc8d0dc)
		for i in 3:
			var m := MeshInstance3D.new()
			m.mesh = _star()
			m.material_override = mat
			m.rotation_order = EULER_ORDER_XYZ
			m.position = Vector3(0.01 * i, 0, -0.02 * i)
			m.rotation = Vector3(PI / 2, 0.5 * (i - 1), 0)
			star.add_child(m)
		star.position = Vector3(0.02, 0, -float(twin.d.hand) * 1.4)
		twin.hands[1].add_child(star)
	var cannon = twin._n(twin.refs.get("cannon"))
	if cannon != null and twin.refs.get("balls") is Array:
		# 대포 등에 남은 포탄 수만큼 쇠공 (허리 뒤 포탄은 1인칭에서 안 보여서)
		var balls: Array = twin.refs.balls
		for i in balls.size():
			var b = twin._n(balls[i])
			if not (b is MeshInstance3D):
				continue
			var m := MeshInstance3D.new()
			m.mesh = (b as MeshInstance3D).mesh
			m.material_override = (b as MeshInstance3D).material_override
			m.scale = Vector3.ONE * C.VM_PIP_SCALE
			m.position = Vector3(0.05 + i * 0.13, 0, 0.14)
			cannon.add_child(m)
			pips.append([m, src._n(src.refs.balls[i])])
	if twin.refs.get("rage") is Dictionary:
		# 분노가 차면 아래팔에도 핏줄 (머리 핏줄과 같이 벌떡벌떡): 갈라지는 한 가닥 (줄기 + 양쪽 가지), 팔꿈치 쪽
		var mat: Material = null
		var vs = twin.refs.rage.get("veins")
		if vs is Array and vs.size() > 0 and twin._n(vs[0]) is MeshInstance3D:
			mat = (twin._n(vs[0]) as MeshInstance3D).material_override
		if mat == null:
			mat = G3.toon_material(0x9a1020)
		for el in twin.elbows:
			var g := Node3D.new()
			for v in [[0.0, 0.06, 0.08, 0.0], [0.012, 0.11, 0.04, 0.6], [-0.012, 0.12, 0.04, -0.6]]:
				var m := MeshInstance3D.new()
				var bm := BoxMesh.new()
				bm.size = Vector3(0.008, 0.008, v[2])
				m.mesh = bm
				m.material_override = mat
				m.position = Vector3(float(twin.d.foreR), v[0], -v[1])
				m.rotation.x = v[3]
				g.add_child(m)
			el.add_child(g)
			veins.append(g)


# 손에 쥔 표창 (네 날 별, 두께 0.01 — three ExtrudeGeometry 와 같은 모양). 고도는 시계 방향이 앞면
static func _star() -> ArrayMesh:
	if _star_mesh != null:
		return _star_mesh
	var pts: Array[Vector2] = []
	for i in 8:
		var r := 0.025 if i % 2 == 1 else 0.085
		var ang := i / 8.0 * TAU
		pts.append(Vector2(cos(ang), sin(ang)) * r)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var z1 := 0.01
	for i in 8:
		var a := pts[i]
		var b := pts[(i + 1) % 8]
		for tri in [[Vector3.ZERO + Vector3(0, 0, z1), Vector3(b.x, b.y, z1), Vector3(a.x, a.y, z1)], [Vector3.ZERO, Vector3(a.x, a.y, 0), Vector3(b.x, b.y, 0)],
				[Vector3(a.x, a.y, z1), Vector3(b.x, b.y, z1), Vector3(b.x, b.y, 0)], [Vector3(a.x, a.y, z1), Vector3(b.x, b.y, 0), Vector3(a.x, a.y, 0)]]:
			for p in tri:
				st.add_vertex(p)
	st.generate_normals()
	_star_mesh = st.commit()
	return _star_mesh


# 매 프레임: 관절 베끼기 + 어깨 각 바꾸기 + 걷기·숨쉬기 흔들림 (viewmodel.js update)
func _follow(_dt: float) -> void:
	for i in pairs:
		var s: Node3D = src.nodes[i]
		var t: Node3D = twin.nodes[i]
		t.transform = s.transform
		t.visible = s.visible
	var cannon = twin._n(twin.refs.get("cannon"))
	if cannon != null and twin.nodes.find(cannon) in pairs: # 베낀 노드만 (안 베끼면 매 프레임 쌓임)
		# 어깨 대포는 카메라 바로 옆이라 그대로면 화면 오른쪽을 다 덮음 → 작게, 앞으로 내밀어 두 손이 닿게
		cannon.scale *= C.VM_CANNON[0]
		cannon.position += Vector3(C.VM_CANNON[1], C.VM_CANNON[2], C.VM_CANNON[3])
	var shields = twin.refs.get("shields")
	if shields is Dictionary:
		var sh = twin._n(shields.get("front"))
		if sh != null and twin.nodes.find(sh) in pairs and not shield_hand: # 예전 (JS): 허리에 붙은 채. 쥐면 아래 _hold_shield
			sh.scale *= C.VM_SHIELD[0]
			sh.position += Vector3(0, C.VM_SHIELD[1], C.VM_SHIELD[2])
			sh.rotation.z += C.VM_SHIELD[3]
	var now := Time.get_ticks_msec() * 1.0
	for pp in pips:
		(pp[0] as Node3D).visible = pp[1] != null and (pp[1] as Node3D).visible
	if veins.size() > 0:
		var r: float = src.rage_k
		var beat := 1.0 + 0.3 * maxf(0.0, sin(float(src.t) * 9.0)) * r
		for g in veins:
			(g as Node3D).visible = r > 0.35
			(g as Node3D).scale = Vector3(beat, beat, 1.0)
	if star != null:
		# 던진 직후 잠깐 빈손, 그 뒤 다시 쥠 (작게 튀어나옴)
		var su: float = (now - float(src.star_at)) / C.VM_STAR_HIDE_MS
		star.visible = su >= 1.0
		star.scale = Vector3.ONE * (minf(1.0, 0.4 + (su - 1.0) * 3.0) if su >= 1.0 else 0.01)
	var k: float = C.VM_BODY_FOLLOW
	var w: Vector3 = src.waist.rotation
	var hip_twist: float = src.P.waistRoll * C.FIGURE_HIP_TWIST * src.twist_k
	twin.waist.rotation = Vector3(w.x * k, (w.y - float(src.d.hunch)) * k, (w.z + hip_twist) * k + (src.hips.rotation.z - hip_twist if spin else 0.0))
	for i in 2:
		if hold:
			continue
		var side := 1.0 if i else -1.0
		var sr: Vector3 = src.shoulders[i].rotation
		var fwd := -sr.y
		var out := side * sr.x
		# 내린 팔(0)~앞으로 든 팔(π/2) 을 VM_ARM_LOW~π/2 로 눌러 담음 → 가만히 있어도 손이 화면 아래에 보이고, 앞으로 뻗으면 그대로 앞
		var up := clampf(fwd / HALF_PI, 0.0, 1.0)
		var f2: float = C.VM_ARM_LOW + up * (HALF_PI - C.VM_ARM_LOW) if fwd < HALF_PI else fwd
		var ts: Node3D = twin.shoulders[i]
		ts.rotation = Vector3(side * out * C.VM_ARM_OUT, -f2, sr.z)
		ts.position.y = src.shoulders[i].position.y * C.VM_NARROW # 두 팔을 화면 가운데 쪽으로
		twin.elbows[i].rotation.y = src.elbows[i].rotation.y - C.VM_ELBOW_ADD * (1.0 - up) # 내린 팔일수록 팔꿈치를 더 굽혀 주먹이 올라오게
	# 갈고리: 장전된 권총은 앞으로 겨눔 (탕 동작은 그대로)
	if twin.refs.has("gun") and src.loaded and -src.shoulders[0].rotation.y < 0.6:
		twin.shoulders[0].rotation.y = -C.VM_GUN_AIM[0]
		twin.elbows[0].rotation.y = -C.VM_GUN_AIM[1]
	if shield_hand:
		_hold_shield(_dt)
	var sw := [0.0, 0.0, 0.0, 0.0, 0.0, 0.0] # [yaw, pitch, kick, dx, lift, roll]
	if hold and twin.refs.has("formParts"):
		sw = _bard_hold(src.cur_act, src.t)
	elif hold and cannon != null:
		sw = _cannon_hold(src.cur_act, cannon)
	elif not hold:
		sw = act_swing(src.cur_act)
	_swing(sw[0], sw[1], sw[5])
	# 걷기 흔들림 (걸음 위상 따라 위아래·좌우), 가만히 있으면 숨쉬기
	var amp := minf(1.0, src.hs / C.MOVE_SPEED)
	var t: float = src.t
	var pos: Array = C.VM_POS.get(char_id, C.VM_POS["default"])
	anchor.position = Vector3(
		# 카메라 좌표: 오른쪽 +x, 위 +y, 뒤 +z
		pos[0] + sw[3] + sin(src.walk) * C.VM_BOB * 0.6 * amp,
		pos[1] + sw[4] - absf(cos(src.walk)) * C.VM_BOB * amp + sin(t * 2.0) * C.VM_BREATH,
		pos[2] + sw[2] * C.VM_CANNON_KICK_BACK)
	# W18 팔 반동 (fx/effects.gd vm_offset — 때린 순간 주먹이 몸 쪽으로, 맞은 순간 옆·아래로. 카메라 좌표)
	var fxn = src.get("fx_node")
	if fxn != null and is_instance_valid(fxn) and fxn.has_method("vm_offset"):
		anchor.position += fxn.vm_offset()


# 탱크 앞 방패를 왼손에 쥠 (W11, JS 는 허리에 붙은 채): 원본 앞 방패가 보이면 (방패 동작) 손을 내려 방패를 쥐고 들어 올림 →
# 쥔 자세 + 동작별 밀치기 (당김 → 밀침 → 복귀) → 끝나면 내려 넣고 손이 원래 자리로. 방패가 보이는 동안 왼손 (손목) 은 늘 손잡이 점 (IK _reach)
func _hold_shield(dt: float) -> void:
	var shields = twin.refs.get("shields")
	if not (shields is Dictionary):
		return
	var sh = twin._n(shields.get("front"))
	if sh == null or not (twin.nodes.find(sh) in pairs):
		return
	var want: bool = sh.visible # 원본 앞 방패 보이기 (위에서 베낌)
	shield_k = minf(1.0, shield_k + dt / K.VM_SHIELD_IN_S) if want else maxf(0.0, shield_k - dt / K.VM_SHIELD_OUT_S)
	sh.visible = false
	if shield_k <= 0.0:
		return
	var ra: float = K.VM_SHIELD_REACH
	var low := shield_xf(K.VM_SHIELD_LOW)
	if shield_k < ra: # 빈손으로 방패 쪽 (화면 밖 아래) 으로 내려감 / 넣은 뒤 원래 자리로
		var free := _waist_point(twin.hands[1], [0.0, 0.0, 0.0])
		_reach(1, free.lerp(shield_grip(low), _e(shield_k / ra)))
		return
	var held: Array = K.VM_SHIELD_GUARD.duplicate()
	var off := shield_push(src.cur_act)
	for i in 5:
		held[i] += off[i]
	var s := _e((shield_k - ra) / (1.0 - ra))
	var p: Array = []
	for i in 5:
		p.append(lerpf(float(K.VM_SHIELD_LOW[i]), float(held[i]), s))
	var xf := shield_xf(p)
	# 팔이 닿는 데까지만: 손잡이가 어깨에서 팔 길이보다 멀면 방패째 어깨 쪽으로
	var shp: Vector3 = twin.shoulders[1].position
	var g := shield_grip(xf) - shp
	var far := float(twin.d.upper) + float(twin.d.lower) - K.VM_SHIELD_ARM_SLACK
	if g.length() > far:
		xf.origin -= g.normalized() * (g.length() - far)
	sh.transform = xf
	sh.visible = true
	_reach(1, shield_grip(xf))


# 방패 변환 (허리 좌표): p = [앞, 왼쪽, 위, 돌림, 들림]. 바깥면 (돌기, 방패 -x) 이 앞에서 돌림만큼 왼쪽·들림만큼 위를 봄, 크기 VM_SHIELD[0]
static func shield_xf(p: Array) -> Transform3D:
	var b := Basis(Vector3(0, 0, 1), float(p[3])) * Basis(Vector3(0, 1, 0), -float(p[4])) * Basis(Vector3(0, 0, 1), PI)
	return Transform3D(b * Basis.from_scale(Vector3.ONE * C.VM_SHIELD[0]), Vector3(p[0], p[1], p[2]))


# 손잡이 점 (허리 좌표)
static func shield_grip(xf: Transform3D) -> Vector3:
	return xf * Vector3(K.VM_SHIELD_GRIP[0], K.VM_SHIELD_GRIP[1], K.VM_SHIELD_GRIP[2])


# 동작별 밀치기 [앞, 왼쪽, 위, 돌림, 들림]: 준비 0 → W (당김), 타격 W → S (밀침), 회복 S → 0 (복귀)
static func shield_push(act) -> Array:
	var out := [0.0, 0.0, 0.0, 0.0, 0.0]
	if act == null or act.phase == "broken" or not K.VM_SHIELD_PUSH.has(act.move):
		return out
	var m: Dictionary = K.VM_SHIELD_PUSH[act.move]
	var u := _e(clampf(float(act.u), 0.0, 1.0))
	for i in 5:
		var w: float = m.W[i]
		var st: float = m.S[i]
		out[i] = w * u if act.phase == "wind" else (w + (st - w) * u if act.phase == "strike" else st * (1.0 - u))
	return out


# W38 1인칭 평타·스킬 휘두름 보정 (가산, 구조 그대로): 3인칭 클립과 같은 서버 단계 (wind u → 당김, strike u → 휘두름·뻗음, rec u → 되돌림) 에 맞춰
# 화면 전체 (어깨 기준점) 를 윈드업 때 뒤·아래로 당기고 타격 때 앞으로 밀며 휩쓸고, 회복 때 여운 있게 돌아오게. 동작 → 스타일 config VM_ACT_STYLE, 스타일 값 VM_ACT_SWING (W·S = [yaw, pitch, kick, dx, lift, roll])
static func act_swing(act) -> Array:
	var out := [0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
	if act == null or act.phase == "broken" or not C.VM_ACT_STYLE.has(act.move):
		return out
	var m: Dictionary = C.VM_ACT_SWING[C.VM_ACT_STYLE[act.move]]
	var u := _e(clampf(float(act.u), 0.0, 1.0))
	for i in 6:
		var w: float = m.W[i]
		var st: float = m.S[i]
		out[i] = w * u if act.phase == "wind" else (w + (st - w) * u if act.phase == "strike" else st * (1.0 - u))
	return out


# 화면 기준 추가 회전 (어깨 높이 기준점을 축으로): yaw 좌우로 휩쓸기, pitch 위아래, roll 기울기 (three Euler 'YXZ')
func _swing(yaw: float, pitch: float, roll: float) -> void:
	var r := Basis.from_euler(Vector3(pitch, yaw, roll + float(C.VM_ROLL.get(char_id, 0.0))), EULER_ORDER_YXZ)
	anchor.basis = r * base_basis # (basis 를 넣으면 크기가 1 로 → 아래에서 다시)
	anchor.scale = Vector3.ONE * C.FIGURE_SCALE * C.VM_SCALE * float(C.VM_SIZE.get(char_id, 1.0))


# 두 마디 팔: 손(손목 관절)이 target(허리 좌표)에 닿게 어깨 앞·옆 각과 팔꿈치를 셈 (viewmodel.js reach)
func _reach(i: int, target: Vector3) -> void:
	var a: float = twin.d.upper
	var b: float = twin.d.lower
	var sh: Node3D = twin.shoulders[i]
	var t := target - sh.position
	var L := minf(a + b - 1e-3, maxf(absf(a - b) + 1e-3, t.length()))
	var beta := PI - acos(clampf((a * a + b * b - L * L) / (2.0 * a * b), -1.0, 1.0)) # 팔꿈치 굽힘
	var r := maxf(1e-4, Vector2(t.y, t.z).length())
	var alpha := atan2(t.y, -t.z)
	var h0x := b * sin(beta)
	var h0z := -a - b * cos(beta)
	var f := atan2(t.x, r) - atan2(h0x, -h0z)
	sh.rotation = Vector3(alpha, -f, 0)
	twin.elbows[i].rotation.y = -beta


# obj 의 점 p (obj 좌표) → 허리 좌표
func _waist_point(obj: Node3D, p: Array) -> Vector3:
	var v := Vector3(p[0], p[1], p[2])
	var o: Node3D = obj
	while o != null and o != twin.waist:
		v = o.transform * v
		o = o.get_parent() as Node3D
	return v


static func _e(u: float) -> float:
	return u * u * (3.0 - 2.0 * u)


# 바드: 악기를 늘 두 손에 (왼손 목·오른손 줄). 음유 평타 = 줄 긁기, 메탈 = 기타째 휘두르기·내려치기
func _bard_hold(act, t: float) -> Array:
	var metal: bool = src.form == "metal"
	var ins = twin._n(twin.refs.get("guitar")) if metal else (twin._n(twin.refs.lute.get("lute")) if twin.refs.get("lute") is Dictionary else null)
	if ins == null:
		return [0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
	var P: Dictionary = C.VM_GRIP["guitar" if metal else "lute"]
	var strum := sin(t * 3.0) * 0.01
	var yaw := 0.0
	var pitch := 0.0
	var dx := 0.0
	var roll := 0.0
	if act != null and act.phase != "broken":
		var u: float = act.u
		var ph: String = act.phase
		match act.move:
			"류트 음파", "bardSong":
				strum = 0.07 * _e(u) if ph == "wind" else (0.07 - 0.15 * _e(u) if ph == "strike" else -0.08 * (1.0 - _e(u)) + sin(u * 20.0) * 0.02 * (1.0 - u))
				pitch = -0.08 * sin(PI * u) if ph == "strike" else 0.0
			"기타 후려치기":
				yaw = -0.4 * _e(u) if ph == "wind" else (-0.4 + 1.1 * _e(u) if ph == "strike" else 0.7 * (1.0 - _e(u)))
				dx = 0.08 * _e(u) if ph == "wind" else (0.08 - C.VM_SWEEP * _e(u) if ph == "strike" else -(C.VM_SWEEP - 0.08) * (1.0 - _e(u)))
				pitch = 0.25 * sin(PI * u) if ph == "strike" else 0.0
			"기타 내려치기":
				pitch = 0.9 * _e(u) if ph == "wind" else (0.9 - 1.5 * _e(u) if ph == "strike" else -0.6 * (1.0 - _e(u)))
			"bardRiff", "bardHeal":
				var lift := 0.75 if act.move == "bardRiff" else 0.35
				pitch = lift * (1.0 - _e(u)) if ph == "rec" else lift
				if act.move == "bardRiff":
					strum = sin(t * 36.0) * 0.05
			"기타 꽂기":
				pitch = 0.6 * _e(u) if ph == "wind" else (0.6 * (1.0 - _e(u)) if ph == "strike" else 0.0)
				roll = C.VM_DIVE_ROLL * _e(u) if ph == "strike" else (C.VM_DIVE_ROLL * (1.0 - _e(u)) if ph == "rec" else 0.0)
	_reach(1, _waist_point(ins, P.neck))
	_reach(0, _waist_point(ins, [P.body[0], P.body[1] + strum, P.body[2]]))
	return [yaw, pitch, 0.0, dx, 0.0, roll]


# 대포수: 어깨에 멘 대포를 두 손으로 (오른손 뒤 손잡이·왼손 앞 받침). 쏘면 대포·두 손이 같이 뒤로 튐, 탄 없음 후려치기 = 대포째 휘두름
func _cannon_hold(act, cannon: Node3D) -> Array:
	var P: Dictionary = C.VM_GRIP.cannon
	_reach(0, _waist_point(cannon, P.rear))
	_reach(1, _waist_point(cannon, P.front))
	var kick := maxf(0.0, 1.0 - (Time.get_ticks_msec() - float(src.cannon_kick_at)) / maxf(1.0, C.CANNON_KICK_MS))
	var pitch: float = C.VM_CANNON_KICK_PITCH * kick * kick # 반동: 대포 끝이 들림 (anchor 는 sw[2] × VM_CANNON_KICK_BACK 만큼 화면 쪽으로)
	var yaw := 0.0
	if act != null and act.move == "후려치기" and act.phase != "broken":
		var u: float = act.u
		yaw = -0.6 * _e(u) if act.phase == "wind" else (-0.6 + 1.6 * _e(u) if act.phase == "strike" else 1.0 * (1.0 - _e(u)))
	return [yaw, pitch, kick, 0.0, 0.0, 0.0]
