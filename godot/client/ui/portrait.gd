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


# 있으면 텍스처, 없으면 null (그리기를 줄에 세움)
static func tex(char_id, color: Color, size: int, full := false) -> Texture2D:
	if inst == null or char_id == null or str(char_id) == "":
		return null
	return inst._lookup(str(char_id), color, size, full)


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


# 메뉴에 오래 있으면 카드 8장을 미리 (JS warmPortraits)
func warm(color: Color) -> void:
	for c in C.CHARACTERS:
		_lookup(str(c), color, 128, true)


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
	# 몸 색이 어두워도 윤곽이 보이게: 앞·위·뒤 고정 빛 (JS makeScene — 게임 좌표 (x, y, z) → 고도 (x, z, -y))
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color.WHITE
	env.ambient_light_energy = 1.05
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	we.environment = env
	vp.add_child(we)
	for l in [[Vector3(3, 4, 2), Color.WHITE, 1.5], [Vector3(-3, 1, -2), Color("99bbff"), 0.9]]:
		var d := DirectionalLight3D.new()
		d.light_color = l[1]
		d.light_energy = l[2]
		vp.add_child(d)
		d.look_at_from_position(l[0], Vector3.ZERO, Vector3.UP)
	var body = Chars.make_body(char_id, job[2])
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
func _bounds(n: Node) -> AABB:
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
