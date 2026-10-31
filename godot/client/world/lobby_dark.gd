# 대기실 (방 안·판 전, 연습 아님) 어두운 무대 (client/lobby-dark.js LobbyDark 그대로, 2026-10-30 재혁): 고른 맵 테마의 어두운 '엔딩 아트' 장면.
# 방 섬·사람·블록은 그대로, 둘레만: 하늘 구·떠 있는 섬·먼 배경 숨김 → 테마 배경색·안개, 해·하늘빛을 테마 빛으로 낮춤,
# 섬 둘레에 타이틀 무대 (G 의 TitleStage, ring: 소품 사방·섬 자리 비움·섬 아래 거울 호수) + 블룸 (그래픽 낮춤이면 끔),
# 맵을 바꾸면 그 테마로 다시 + 테마 빛 번쩍 (LOBBY_DARK.flashMs). 판이 시작되면 World 가 dispose → G3.apply_theme 으로 밝은 판
extends Node3D

const C := preload("res://core/config.gd")
const Co := preload("res://core/coords.gd")
const STAGE := "res://title/title_stage.gd" # G 의 타이틀 무대 (있으면). new(theme, opts) → Node3D, update(t, lit, px)

var theme := ""
var T: Dictionary = {}
var low := false
var size := Vector2i.ZERO
var stage = null # G TitleStage (없으면 어두운 배경·안개·빛·블룸·번쩍만)
var flash_at := -1e12
var flash_rect: ColorRect
var flash_layer: CanvasLayer
var frames := 0 # 그린 프레임 수 (확인용)
var _glow_was := {}


# world: World Node3D (G3Env 를 가짐), G3: shaders/g3.gd, flash: 다른 테마에서 맵을 바꿔 들어옴
func setup(world: Node3D, G3, theme_id: String, w: int, d: int, low_gfx: bool, flash: bool) -> void:
	theme = theme_id
	T = C.TITLE_THEMES[theme_id]
	low = low_gfx
	size = Vector2i(w, d)
	var L: Dictionary = C.LOBBY_DARK
	var R: float = maxf(w, d) * L.clear + 3
	if ResourceLoader.exists(STAGE):
		var S = load(STAGE)
		stage = S.new(theme_id, {"low": low, "logoW": 0, "logoH": 0, "camDist": R, "ring": true, "clear": R, "floorZ": -float(L.drop)})
		if stage is Node3D:
			add_child(stage)
			stage.position = Co.gxyz(w / 2.0, d / 2.0, 0) # 무대 가운데 = 섬 가운데
			if stage.get("back_light") != null:
				stage.back_light.position = Vector3(0, R * 0.5, 6) # 무대 안 = 게임 좌표 (무대 뿌리가 돌림)
	# 맵 바꿈 번쩍: 화면 전체 판 (테마 빛 색, 더하기)
	flash_layer = CanvasLayer.new()
	flash_layer.layer = 0
	flash_rect = ColorRect.new()
	flash_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	flash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flash_rect.color = Co.color(T.glow).lerp(Color.WHITE, 0.5)
	flash_rect.color.a = 0.0
	var cm := CanvasItemMaterial.new()
	cm.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	flash_rect.material = cm
	flash_layer.add_child(flash_rect)
	add_child(flash_layer)
	flash_at = Time.get_ticks_msec() * 1.0 if flash else -1e12
	apply(world, G3)


# 같은 테마·판 크기·그래픽 설정이면 그대로 씀
func fits(theme_id, w: int, d: int, low_gfx: bool) -> bool:
	return theme_id == theme and size == Vector2i(w, d) and low_gfx == low


# 게임 장면 둘레를 어둡게 (매 프레임: 맵 테마가 다시 칠해도 덮어씀)
func apply(world: Node3D, G3) -> void:
	if G3 == null:
		return
	var L: Dictionary = C.LOBBY_DARK
	var env: Node3D = world.get_node_or_null("G3Env")
	if env == null:
		return
	var we: WorldEnvironment = env.get_node("Env")
	we.environment.background_color = Co.color(T.bg)
	var side := maxf(size.x, size.y)
	G3.set_fog(T.fog[0], side + float(L.fog[0]), side + float(T.fog[2]) + float(L.fog[1]))
	(env.get_node("Sky") as Node3D).visible = false
	G3.set_hemi(T.amb[0], T.bg, float(T.amb[1]) * float(L.hemi))
	var wt: Dictionary = C.WORLD_THEMES.get(theme, {})
	G3.set_sun(env.get_node("Sun"), T.key[0], float(T.key[1]) * float(L.sun), wt.get("sunDir", C.SUN_DIR))
	# 블룸 (TITLE_BLOOM [세기, 반지름, 문턱]) — 그래픽 낮춤이면 끔
	var e: Environment = we.environment
	if _glow_was.is_empty():
		_glow_was = {"on": e.glow_enabled, "i": e.glow_intensity, "s": e.glow_strength, "t": e.glow_hdr_threshold, "b": e.glow_bloom}
	e.glow_enabled = not low
	if not low:
		var B: Array = C.TITLE_BLOOM
		e.glow_intensity = float(B[0])
		e.glow_strength = 1.0 + float(B[1])
		e.glow_hdr_threshold = float(B[2])
		e.glow_bloom = 0.0
		e.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE


# 매 프레임
func step(world: Node3D, G3) -> void:
	frames += 1
	apply(world, G3)
	if stage != null and stage.has_method("update"):
		stage.update(Time.get_ticks_msec() / 1000.0, 1.0, get_viewport().get_visible_rect().size.y * 0.5)
	var k: float = 1.0 - (Time.get_ticks_msec() - flash_at) / float(C.LOBBY_DARK.flashMs)
	flash_rect.color.a = float(C.LOBBY_DARK.flash) * k * k if k > 0 else 0.0


# 치움. restore: 밝은 판으로 (하늘 구·맵 테마 다시 칠하기 — G3.apply_theme 은 World 가). 블룸은 예전 값으로
func dispose(world: Node3D) -> void:
	var env: Node3D = world.get_node_or_null("G3Env")
	if env != null:
		(env.get_node("Sky") as Node3D).visible = true
		var e: Environment = (env.get_node("Env") as WorldEnvironment).environment
		if not _glow_was.is_empty():
			e.glow_enabled = _glow_was.on
			e.glow_intensity = _glow_was.i
			e.glow_strength = _glow_was.s
			e.glow_hdr_threshold = _glow_was.t
			e.glow_bloom = _glow_was.b
	queue_free()
