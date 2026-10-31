# 1인칭 팔·무기 (client/viewmodel.js 옮김): 내 3인칭 몸 (chars/body.gd) 과 같은 몸을 하나 더 만들어 팔꿈치 아래·든 무기만 그리고,
# 관절은 매 프레임 내 몸에서 베낌 → 평타·스킬 동작이 그대로. 어깨 각만 바꿔 손이 화면 아래 구석에 오게 함.
# 필드 위에 겹쳐 그려야 해서 (벽에 안 박힘) 자기 SubViewport (투명 배경·자기 3D 세계·자기 카메라 VM_FOV) 에 그리고 화면 전체 TextureRect 로 덮음.
# 쓰는 법 (World/G1): var vm = Viewmodel.new(); add_child(vm) → 매 프레임 vm.update(내 몸 노드 또는 null, 1인칭이면 true, dt). 끝.
extends Node

const C := preload("res://core/config.gd")
const Body := preload("res://chars/body.gd")

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


func _ready() -> void:
	layer = CanvasLayer.new()
	layer.layer = 0 # 3D 판 위, UI (G4) 아래
	add_child(layer)
	view = SubViewport.new()
	view.transparent_bg = true
	view.own_world_3d = true
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
	env.environment.ambient_light_color = Color(1.0, 0.89, 0.82)
	env.environment.ambient_light_energy = 0.6
	view.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.light_color = Color(1, 0.95, 0.88)
	sun.light_energy = 1.25
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
	layer.add_child(rect)
	_set_on(false)


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
	var size := get_viewport().get_visible_rect().size
	if Vector2i(size) != view.size:
		view.size = Vector2i(size)
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
	if body == null or not (body is Body):
		return
	char_id = body.char_id
	twin = Body.new()
	twin.build(char_id, body.skin_color, false) # 합치지 않음 (조각마다 보이기)
	view.add_child(twin)
	twin.visible = false # 몸 자체는 안 그림 — 허리만 떼어 anchor 에 붙임
	var w: int = twin.nodes.find(twin.waist)
	# 허리 아래 (허리 제외) 노드 번호
	var under := {w: true}
	for i in twin.nodes.size():
		var p: int = twin.parents[i]
		if p >= 0 and under.has(p):
			under[i] = true
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
		var k := i
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
		if sh != null and twin.nodes.find(sh) in pairs:
			sh.scale *= C.VM_SHIELD[0]
			sh.position += Vector3(0, C.VM_SHIELD[1], C.VM_SHIELD[2])
			sh.rotation.z += C.VM_SHIELD[3]
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
	var sw := [0.0, 0.0, 0.0, 0.0, 0.0, 0.0] # [yaw, pitch, kick, dx, lift, roll]
	if hold and twin.refs.has("formParts"):
		sw = _bard_hold(src.cur_act, src.t)
	elif hold and cannon != null:
		sw = _cannon_hold(src.cur_act, cannon)
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


# 대포수: 어깨에 멘 대포를 두 손으로 (오른손 뒤 손잡이·왼손 앞 받침). 탄 없음 후려치기 = 대포째 휘두름
func _cannon_hold(act, cannon: Node3D) -> Array:
	var P: Dictionary = C.VM_GRIP.cannon
	_reach(0, _waist_point(cannon, P.rear))
	_reach(1, _waist_point(cannon, P.front))
	var yaw := 0.0
	if act != null and act.move == "후려치기" and act.phase != "broken":
		var u: float = act.u
		yaw = -0.6 * _e(u) if act.phase == "wind" else (-0.6 + 1.6 * _e(u) if act.phase == "strike" else 1.0 * (1.0 - _e(u)))
	return [yaw, 0.0, 0.0, 0.0, 0.0, 0.0]
