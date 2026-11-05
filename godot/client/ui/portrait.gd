# 캐릭터 초상 (JS client/portrait.js): G2 몸 (chars.make_body, 재질은 G3 toon) 을 화면 밖 SubViewport 에 한 번 그려 ImageTexture 로 캐시.
# 아래 판 (96 얼굴)·캐릭터 카드 (128 온몸)·대기실 큰 캐릭터 (256 온몸)·결과 승자 (192 얼굴)·결과 표 (64 얼굴) 가 씀.
# 같은 (캐릭터, 색, 크기, 온몸) 은 한 번만. 한 프레임에 하나씩 그림 (대기실 들어가는 순간 8장이 한꺼번에 멈추지 않게) — tex() 가 아직이면 null,
# 다 그리면 drawn(key). 헤드리스면 안 그림 (null 그대로 → 색 상자). ui.gd 가 하나 만들어 Portrait.inst 에 둠
extends Node

const C := preload("res://core/config.gd")
const CHARS_PATH := "res://chars/chars.gd"

const LEFT_SIDE := ["cannon"] # 오른어깨 포신이 얼굴을 가려 반대쪽에서 봄 (JS 그대로)
const FOV := 26.0

signal drawn(key: String)

static var inst = null

var cache := {} # key → ImageTexture (못 그리면 null 로 기억)
var queue := [] # [key, char, color, size, full]
var busy := false
var Chars = null


func _ready() -> void:
	inst = self
	if ResourceLoader.exists(CHARS_PATH):
		Chars = load(CHARS_PATH)


static func key_of(char_id: String, color: Color, size: int, full: bool) -> String:
	return "%s|%s|%d|%d" % [char_id, color.to_html(false), size, 1 if full else 0]


# 있으면 텍스처, 없으면 null (그리기를 줄에 세움). size = UI 좌표 크기 — 실제로는 UI 배율만큼 크게 그림 (render_px, W9)
static func tex(char_id, color: Color, size: int, full := false) -> Texture2D:
	if inst == null or char_id == null or str(char_id) == "":
		return null
	return inst._lookup(str(char_id), color, render_px(size, float(View.ui_scale)), full)


# 그릴 픽셀 크기: UI 크기 × UI 배율 (0.25 단위로 올림 — 창 크기를 끌 때마다 새로 그리지 않게, 1 아래면 그대로, 최대 RENDER_MAX)
# 초상을 보이는 칸은 전부 EXPAND_IGNORE_SIZE·expand_icon 이라 텍스처 크기가 배치를 안 바꿈
const RENDER_MAX := 768


static func render_px(size: int, ui_scale: float) -> int:
	var k := maxf(1.0, ceilf(ui_scale * 4.0 - 0.001) / 4.0)
	return mini(maxi(size, RENDER_MAX), roundi(size * k))


func _lookup(char_id: String, color: Color, size: int, full: bool) -> Texture2D:
	var k := key_of(char_id, color, size, full)
	if cache.has(k):
		return cache[k]
	if Chars == null or DisplayServer.get_name() == "headless":
		return null
	for j in queue:
		if j[0] == k:
			return null
	queue.append([k, char_id, color, size, full])
	return null


# 초상·대기실 큰 캐릭터 (char_stage) 몸: 자기 SubViewport 장면이라 판의 위험 빛 (전역 값 g3_hz_lp) 을 안 받게 끔 (JS portrait·char-stage 는 따로 된 scene)
static func still_body(chars, char_id: String, color: Color) -> Node3D:
	var body = chars.make_body(char_id, color)
	if body.has_method("set_hz_light"):
		body.set_hz_light(false)
	stage_light(body)
	return body


# 무대 빛 (JS 초상·큰 캐릭터와 같은 흰 빛, G3K.STAGE_*): 몸 재질 (구운 몸·외부 모델·소품 모두 몸마다 따로) 을 전역 테마 빛 대신 이 빛으로
static func stage_light(body: Node) -> void:
	var G3 = load("res://shaders/g3.gd")
	var K = load("res://shaders/g3_config.gd")
	for mi in body.find_children("*", "MeshInstance3D", true, false):
		var m = (mi as MeshInstance3D).material_override
		if m is ShaderMaterial and _has_local_light((m as ShaderMaterial).shader):
			G3.toon_local_light(m, true, K.STAGE_HEMI[0], K.STAGE_HEMI[1], K.STAGE_HEMI[2], K.STAGE_SUN[0], K.STAGE_SUN[1])


# G3 툰 계열 셰이더 (toon_common 을 쓰는 것 — 툰·투명 툰·스텐실 툰 등) 인지: local_light 유니폼이 있음
static func _has_local_light(sh: Shader) -> bool:
	if sh == null:
		return false
	for u in sh.get_shader_uniform_list():
		if str(u.get("name", "")) == "local_light":
			return true
	return false


# 메뉴에 오래 있으면 카드 8장을 미리 (JS warmPortraits)
func warm(color: Color) -> void:
	for c in C.CHARACTERS:
		_lookup(str(c), color, render_px(128, float(View.ui_scale)), true)


func _process(_d: float) -> void:
	if busy or queue.is_empty():
		return
	busy = true
	var job: Array = queue.pop_front()
	await _draw_one(job)
	busy = false


func _draw_one(job: Array) -> void:
	var k: String = job[0]
	var char_id: String = job[1]
	var size: int = job[3]
	var full: bool = job[4]
	var vp := SubViewport.new()
	vp.size = Vector2i(size, size)
	vp.own_world_3d = true
	vp.transparent_bg = true
	vp.msaa_3d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(vp)
	# 빛: G3 툰 셰이더는 ALBEDO = 1 로 두고 색·하늘빛·해 세기를 전역 값 (g3_hemi_*·g3_sun — 판 테마가 정함) 에서 가져옴.
	# 그래서 고도 앰비언트는 검정이어야 하고 (G3Env 와 같게 — 아니면 하얀 실루엣), 빛은 방향만 주는 하나 (빛마다 해·하늘빛이 한 번 더 더해짐).
	# 방향 = JS makeScene 의 앞 빛 (게임 (3, -2, 4) → 고도 (x, z, -y)). JS 의 파란 뒷빛은 툰 셰이더가 빛 색을 안 써서 뺌
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color.BLACK
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	we.environment = env
	vp.add_child(we)
	var key := DirectionalLight3D.new()
	vp.add_child(key)
	key.look_at_from_position(Vector3(3, 4, 2), Vector3.ZERO, Vector3.UP)
	var body = still_body(Chars, char_id, job[2])
	vp.add_child(body)
	# 가만히 선 자세 (숨쉬기 위상을 조금 줘서 팔이 굳어 보이지 않게 — JS t 0.8)
	if body.has_method("pose"):
		for i in 50:
			body.pose({"id": -1, "alive": true, "x": 0.0, "y": 0.0, "z": 0.0, "yaw": 0.0}, i * 16.0)
	# 몸의 실제 크기에 맞춰 화면을 채움 (고도 y = 게임 z). 온몸 = 몸 전체, 얼굴 = 목 관절 위 (머리) 기준
	var box := _bounds(body)
	var z_top := box.end.y if box.size != Vector3.ZERO else C.PLAYER_HEIGHT
	var z_bot := box.position.y if box.size != Vector3.ZERO else 0.0
	var h := maxf(0.3, z_top - z_bot)
	var top := z_top + h * 0.04
	var bot := z_bot - h * 0.03
	var neck = body.get("neck")
	if not full and neck is Node3D:
		var neck_z: float = (neck as Node3D).global_position.y
		var hb := _bounds(neck)
		var head_h := maxf(0.12, (hb.end.y if hb.size != Vector3.ZERO else neck_z + 0.3) - neck_z)
		top = neck_z + head_h * 1.3
		bot = neck_z - head_h * 1.0
	elif not full:
		bot = z_top - h * 0.4
	var half := (top - bot) / 2.0 * 1.08
	var dist := half / tan(deg_to_rad(FOV / 2.0))
	var ang := deg_to_rad(38.0 if full else 46.0) # 앞 (+x) 에서 돌린 각
	var side := 1.0 if LEFT_SIDE.has(char_id) else -1.0
	var at_z := (top + bot) / 2.0
	var cam := Camera3D.new()
	cam.fov = FOV
	cam.near = 0.05
	cam.far = 60.0
	vp.add_child(cam)
	var gx := cos(ang) * dist
	var gy := side * sin(ang) * dist
	var gz := at_z + (0.0 if full else (top - bot) * 0.1)
	cam.look_at_from_position(Vector3(gx, gz, -gy), Vector3(0, at_z, 0), Vector3.UP)
	cam.current = true
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	cache[k] = ImageTexture.create_from_image(img) if img != null and not img.is_empty() else null
	vp.queue_free()
	drawn.emit(k)


# 아래 MeshInstance3D 들의 전역 상자 (고도 좌표)
static func _bounds(n: Node) -> AABB:
	var out := AABB()
	var first := true
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if not m.is_visible_in_tree():
			continue
		var b: AABB = m.global_transform * m.get_aabb()
		if first:
			out = b
			first = false
		else:
			out = out.merge(b)
	if n is MeshInstance3D:
		var b0: AABB = (n as MeshInstance3D).global_transform * (n as MeshInstance3D).get_aabb()
		out = b0 if first else out.merge(b0)
	return out
