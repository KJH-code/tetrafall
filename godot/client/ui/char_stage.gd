# 대기실 큰 3D 캐릭터 (JS client/char-stage.js): 내 캐릭터를 내 색으로 크게, 고르면 정면에서 전용 도발 한 번 (EMOTE_MS) → 천천히 돎 (CHAR_STAGE_SPIN).
# 자기 SubViewport (own_world) 에 G2 몸 하나 + 앞 빛 하나 (G3 툰 — 앰비언트 검정, portrait.gd 주석). 방향·도발 시간은 ui_calc.stage_yaw·taunt_at.
# 대기실 판이 안 보이면 몸을 놓음 (JS release). 헤드리스면 안 만듦 (lobby 는 정지 초상·색 상자)
extends SubViewportContainer

const C := preload("res://core/config.gd")
const U := preload("res://ui/ui_calc.gd")
const Portrait := preload("res://ui/portrait.gd")
const CHARS_PATH := "res://chars/chars.gd"
const FOV := 26.0

var vp: SubViewport
var turn: Node3D # 도는 받침 (게임 z 축 = 고도 y 축)
var cam: Camera3D
var body = null
var key := "" # "char|색"
var picked_at := -1.0e9 # 고른 시각 ms (도발·정면 기준)
var Chars = null


func _ready() -> void:
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if ResourceLoader.exists(CHARS_PATH):
		Chars = load(CHARS_PATH)
	vp = SubViewport.new()
	vp.own_world_3d = true
	vp.transparent_bg = true
	vp.msaa_3d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	add_child(vp)
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color.BLACK
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	we.environment = env
	vp.add_child(we)
	var light := DirectionalLight3D.new()
	vp.add_child(light)
	light.look_at_from_position(Vector3(3, 4, 2), Vector3.ZERO, Vector3.UP) # JS 앞 빛 (3, -2, 4)
	turn = Node3D.new()
	vp.add_child(turn)
	cam = Camera3D.new()
	cam.fov = FOV
	cam.near = 0.05
	cam.far = 60.0
	cam.current = true
	vp.add_child(cam)
	visibility_changed.connect(func():
		if not is_visible_in_tree():
			release())


func active() -> bool:
	return body != null


# 캐릭터·색이 바뀌면 몸을 새로. 처음 들어올 땐 도발 없이 바로 돌기 시작, 그 뒤 바꾸면 도발 한 번
func show_char(char_id: String, color: Color) -> void:
	if Chars == null or char_id == "" or DisplayServer.get_name() == "headless":
		return
	var k := "%s|%s" % [char_id, color.to_html(false)]
	if k == key:
		return
	var first := key == ""
	if body != null:
		body.queue_free()
	body = Chars.make_body(char_id, color)
	turn.add_child(body)
	turn.rotation = Vector3.ZERO
	_pose(0.0, 0.0)
	# 몸 크기에 맞춰 카메라 (portrait 온몸과 같은 방식, 정면 +x 에서)
	var box: AABB = Portrait._bounds(body)
	var top: float = box.end.y if box.size != Vector3.ZERO else C.PLAYER_HEIGHT
	var bot: float = box.position.y if box.size != Vector3.ZERO else 0.0
	var half := (top - bot) / 2.0 * 1.18
	var dist := half / tan(deg_to_rad(FOV / 2.0))
	var at_z := (top + bot) / 2.0
	cam.look_at_from_position(Vector3(dist, at_z + half * 0.12, 0), Vector3(0, at_z, 0), Vector3.UP)
	var now := float(Time.get_ticks_msec())
	picked_at = now - C.EMOTE_MS if first else now
	key = k


func _pose(age: float, now: float) -> void:
	var tz := U.taunt_at(age)
	body.pose({"id": -1, "alive": true, "x": 0.0, "y": 0.0, "z": 0.0, "yaw": 0.0, "emote": C.EMOTE_CHAR if tz.on else -1}, now)


func _process(_d: float) -> void:
	if body == null or not is_visible_in_tree():
		return
	var now := float(Time.get_ticks_msec())
	var age := now - picked_at
	turn.rotation.y = U.stage_yaw(age / 1000.0) # 게임 z 축 돌기 = 고도 y 축 (x→(x, z, -y) 이라 각이 같음)
	_pose(age, now)


# 판이 시작하면 (대기실 판이 숨으면): 몸을 놓음, 다시 대기실이면 show_char 가 새로 만듦
func release() -> void:
	if body != null:
		body.queue_free()
	body = null
	key = ""
