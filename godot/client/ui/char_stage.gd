# 대기실 큰 3D 캐릭터 (JS client/char-stage.js): 내 캐릭터를 내 색으로 크게, 고르면 정면에서 전용 도발 한 번 (EMOTE_MS) → 천천히 돎 (CHAR_STAGE_SPIN).
# 자기 SubViewport (own_world) 에 G2 몸 하나 + 앞 빛 하나 (G3 툰 — 앰비언트 검정, portrait.gd 주석). 방향·도발 시간은 ui_calc.stage_yaw·taunt_at.
# 대기실 판이 안 보이면 몸을 놓음 (JS release). 헤드리스면 안 만듦 (lobby 는 정지 초상·색 상자)
# SubViewport 는 화면 픽셀 크기 (UI 좌표 × UI 배율, core/ui_scale.gd) 로 그려 TextureRect 로 이 칸에 맞춤 — SubViewportContainer stretch 는 UI 좌표 크기로 그려 배율이 크면 흐림 (W9)
extends Control

const C := preload("res://core/config.gd")
const U := preload("res://ui/ui_calc.gd")
const Portrait := preload("res://ui/portrait.gd")
const WC := preload("res://world/world_config.gd")
const Lod := preload("res://world/pose_lod.gd")
const Gate := preload("res://core/entry_gate.gd")
const Opts := preload("res://core/opts.gd")
const CHARS_PATH := "res://chars/chars.gd"
const FOV := 26.0

var vp: SubViewport
var img: TextureRect # vp 를 이 칸 크기로 그림
var turn: Node3D # 도는 받침 (게임 z 축 = 고도 y 축)
var cam: Camera3D
var body = null
var key := "" # "char|색"
var picked_at := -1.0e9 # 고른 시각 ms (도발·정면 기준)
var Chars = null
var _rate := {} # 다시 그리기 빈도 (world/pose_lod.gd frame_due)
var prime_i := -1 # W45: 자세 굳히기가 어디까지 (-1 = 안 하는 중)
var _first := false # 처음 들어온 캐릭터면 도발 없이 (show_char → _finish_show)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if ResourceLoader.exists(CHARS_PATH):
		Chars = load(CHARS_PATH)
	vp = SubViewport.new()
	vp.own_world_3d = true
	vp.transparent_bg = true
	vp.msaa_3d = Viewport.MSAA_4X if not bool(View.settings.get("lowGfx", false)) else WC.MSAA_LOW # 작은 판이라 보통 화질도 4× 그대로, 낮음이면 끔 (W6)
	vp.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	add_child(vp)
	img = TextureRect.new()
	img.texture = vp.get_texture()
	img.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	img.stretch_mode = TextureRect.STRETCH_SCALE
	img.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(img)
	resized.connect(_fit)
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


# 칸 크기 × 화면 배율 (UI 좌표 → 화면 픽셀): 대기실 판 크기·UI 배율이 바뀔 때
func _fit() -> void:
	var want := pixel_size(size, get_viewport().get_final_transform().get_scale().x if is_inside_tree() else 1.0)
	if want != vp.size:
		vp.size = want


static func pixel_size(ui: Vector2, px: float) -> Vector2i:
	return Vector2i(maxi(1, roundi(ui.x * px)), maxi(1, roundi(ui.y * px)))


func active() -> bool:
	return body != null


# 캐릭터·색이 바뀌면 몸을 새로. 처음 들어올 땐 도발 없이 바로 돌기 시작, 그 뒤 바꾸면 도발 한 번
# W42: show_char 가 일을 하나 (캐릭터·색이 바뀜) — 입장 쪼개기가 큰 일 차례를 먼저 물음
func pending(char_id: String, color: Color) -> bool:
	if Chars == null or char_id == "" or DisplayServer.get_name() == "headless":
		return false
	return "%s|%s" % [char_id, color.to_html(false)] != key


func show_char(char_id: String, color: Color) -> void:
	if Chars == null or char_id == "" or DisplayServer.get_name() == "headless":
		return
	var k := "%s|%s" % [char_id, color.to_html(false)]
	if k == key:
		return
	var first := key == ""
	if body != null:
		body.queue_free()
	body = Portrait.still_body(Chars, char_id, color) # 판 위험 빛 안 받음
	turn.add_child(body)
	turn.rotation = Vector3.ZERO
	key = k
	_first = first
	if Gate.on() and not Gate.no_split("portrait"): # W45: 자세 굳히기 50번 (5~10ms) 는 프레임마다 10번씩 — 다 굳기 전엔 그리지 않음 (T·A 포즈가 안 보이게)
		prime_i = 0
		vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
		return
	# 만든 그 프레임이 외부 모델의 처음 자세 (T·A 포즈) 가 아니게 쉬는 자세부터 (portrait.prime_idle)
	Portrait.prime_idle(body)
	_finish_show()


# 자세를 다 굳힌 뒤: 몸 크기에 맞춰 카메라 (portrait 온몸과 같은 방식, 정면 +x 에서) · 처음엔 도발 없이, 그 뒤 바꾸면 도발부터
func _finish_show() -> void:
	var fr := Portrait.frame(body, true)
	var half: float = fr.half * 1.02 # 온몸 칸 (위아래 여유 포함) 보다 조금만 더 (예전 몸 키 × 1.18)
	var dist := half / tan(deg_to_rad(FOV / 2.0))
	var at_z: float = fr.at.y
	cam.look_at_from_position(Vector3(dist, at_z + half * 0.12, 0), Vector3(0, at_z, 0), Vector3.UP)
	var now := float(Time.get_ticks_msec())
	picked_at = now - C.EMOTE_MS if _first else now
	_pose(now - picked_at, now) # 처음엔 도발 없이 쉬는 자세, 그 뒤 바꾸면 도발부터


func _pose(age: float, now: float) -> void:
	body.pose({"id": -1, "alive": true, "x": 0.0, "y": 0.0, "z": 0.0, "yaw": 0.0, "emote": emote_for(body, age), "noIdle": body.get("ext") != null}, now)


# 고른 뒤 age_ms 에 틀 이모트 (-1 = 쉬는 자세). 외부 모델 (새 몸) 은 도발·평소 버릇 (noIdle) 없이 쉬는 자세 + 돎만: 도발 포즈가 팔을 수평으로 올려 (사냥꾼 겨누기 등) 큰 무대에서 T 포즈로 보임 (재혁 2026-11-06).
# 예전 코드 몸은 그대로 도발. 판 중 도발 이모트는 안 건드림
static func emote_for(b, age_ms: float) -> float:
	if b != null and b.get("ext") != null:
		return -1.0
	return C.EMOTE_CHAR if U.taunt_at(age_ms).on else -1.0


func _process(_d: float) -> void:
	if body == null or not is_visible_in_tree():
		return
	if prime_i >= 0: # W45: 자세 굳히기 조각 (한 프레임에 PRIME_CHUNK 번) — 차례가 아니면 다음 프레임에
		if not Gate.ok("ui.portrait.prime"):
			return
		var tp := Gate.t()
		var n := mini(Portrait.PRIME_CHUNK, Portrait.PRIME_STEPS - prime_i)
		Portrait.prime_chunk(body, prime_i, n)
		prime_i += n
		Gate.done("ui.portrait.prime", tp)
		if prime_i >= Portrait.PRIME_STEPS:
			prime_i = -1
			_finish_show()
		return
	_fit() # UI 배율이 바뀌어도 (칸 크기는 그대로라 resized 가 안 옴)
	var now := float(Time.get_ticks_msec())
	# 자세·다시 그리기는 WC.SUBVIEW_HZ 까지만 (W15: 천천히 도는 작은 칸 — 120fps 면 한 프레임 걸러 그려도 같아 보임)
	var draw := Lod.frame_due(_rate, Engine.get_process_frames(), now, _d * 1000.0, WC.SUBVIEW_HZ)
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE if draw else SubViewport.UPDATE_DISABLED
	if not draw:
		return
	var age := now - picked_at
	turn.rotation.y = U.stage_yaw(age / 1000.0) # 게임 z 축 돌기 = 고도 y 축 (x→(x, z, -y) 이라 각이 같음)
	_pose(age, now)


# 판이 시작하면 (대기실 판이 숨으면): 몸을 놓음, 다시 대기실이면 show_char 가 새로 만듦
func release() -> void:
	if body != null:
		body.queue_free()
	body = null
	key = ""
	prime_i = -1
	if not Opts.args().has("--no-stage-shrink"): # W45: 판 중엔 안 보이는 큰 캐릭터 렌더 대상 (UI 크기 × 배율 픽셀, 2× MSAA ≈ 7MB) 을 2×2 로 — 다시 보이면 _process 의 _fit 이 되돌림
		vp.size = Vector2i(2, 2)
