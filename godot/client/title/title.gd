# 타이틀 화면 흐름 + 메뉴 3D 배경 (client/title.js · menu-theme.js 자리): 처음 켤 때 테마 엔딩 장면 + 블록 로고 → 빛 터진 뒤 'Enter / 클릭하여 시작'
# → 아무 키·클릭 (다 안 쌓였으면 빨리 감기) → 카메라가 로고 위로 날아가 메뉴 카메라로 → 그 장면이 그대로 메뉴 배경 (천천히 떠돎) → 메뉴 판.
# 테마는 켤 때마다 무작위 (이번 실행 동안 메뉴 테마 = View.menu_theme, 앰비언트·메뉴 판 빛 색도). 누른 키는 메뉴 입력으로 새지 않음.
# 방 주소 (--room)·자동 조종 (--auto) 이면 타이틀 없이 메뉴 배경만. 움직임 줄이기면 완성 로고 + 하얀 페이드. 방에 들어가면 장면을 끄고 판 (world) 을 보임.
# 확인용: --title <테마 id> 로 테마 고정. 소리 신호 View.sound_cue "titleLand" {n} · "titleBurst" · "titleExit"
extends Node

signal active_changed(on: bool) # 3D 배경이 켜짐/꺼짐 — main.gd 가 판 (world) 을 숨김/보임

const C := preload("res://core/config.gd")
const Co := preload("res://core/coords.gd")
const TC := preload("res://title/title_calc.gd")
const Scene := preload("res://title/title_scene.gd")
const LP := preload("res://world/lobby_preview.gd")
const S := preload("res://ui/ui_style.gd")
const HAZE := preload("res://title/haze.gdshader")
const U := preload("res://ui/ui_calc.gd")
# 타이틀 위 겹 (JS index.html #title): 위아래 검은 띠 7vh (누르면 .9s ease-in 으로 화면 밖), 가장자리 어둡게
# radial-gradient(ellipse at 50% 45%, transparent 0 50%, rgba(0,0,0,.6) 100%), 안내 글 text-shadow 0 0 14px 테마 빛 + 'Enter' 테마 빛 색
const BAR_VH := 0.07
const BAR_MS := 900.0
const SHADE_AT := Vector2(0.5, 0.45)
const SHADE_STOP := 0.5
const SHADE_A := 0.6
const HINT_GLOW := [[14, 0.28], [7, 0.45]] # 흐린 빛 흉내 [외곽선 굵기, 진하기] (글자 뒤 겹)

var scene = null
var theme := ""
var title_mode := false # 지금 타이틀 (Enter 전·날아가는 중)
var pressed := false
var start_ms := 0.0
var layer := CanvasLayer.new()
var hint := HBoxContainer.new() # 'Enter' (테마 빛 색) + ' / 클릭하여 시작'
var hint_parts: Array = [] # 글자 Label 들 (빛 겹 포함 — 크기 바꿀 때)
var bars: Array = [] # 위·아래 검은 띠
var shade: TextureRect
var press_ms := -1.0 # 누른 뒤 ms (띠가 빠짐)
var white := ColorRect.new()
var haze_layer := CanvasLayer.new() # 넓은 빛 안개 (W8, haze.gdshader) — 3D 바로 위·타이틀 겹 아래
var haze := ColorRect.new()
var headless := false
var prev_cam: Camera3D = null
var skip := false # main.gd 가 정함: 방 주소 (--room, 웹 ?room=)·자동 조종이면 타이틀 없이 메뉴 배경
var fixed_theme := "" # main.gd: --title <테마> (웹 ?title=)
var auto_press := -1.0 # 확인용 (--title-press 초): 그 초에 누른 셈


func _init() -> void:
	name = "Title" # 자동 조종 (--shot-at title) 이 찾음


func _ready() -> void:
	headless = DisplayServer.get_name() == "headless"
	theme = fixed_theme if C.TITLE_THEMES.has(fixed_theme) else TC.pick_theme(randf())
	View.menu_theme = theme
	View.ui_theme = theme
	layer.layer = 9 # 메뉴 판 (G4 ui = 10) 아래
	add_child(layer)
	haze_layer.layer = -1
	add_child(haze_layer)
	var hm := ShaderMaterial.new()
	hm.shader = HAZE
	haze.material = hm
	haze.mouse_filter = Control.MOUSE_FILTER_IGNORE
	haze.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	haze.visible = false
	haze_layer.add_child(haze)
	white.color = Color(1, 1, 1, 0)
	white.mouse_filter = Control.MOUSE_FILTER_IGNORE
	white.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(white)
	var edge := Co.color(C.TITLE_THEMES[theme].edge)
	shade = S.radial_shade(SHADE_AT, SHADE_STOP, Color(0, 0, 0, 0), Color(0, 0, 0, SHADE_A))
	layer.add_child(shade)
	layer.move_child(shade, 0)
	shade.visible = false # 타이틀 동안만 (_place_bars)
	for k in 2:
		var b := ColorRect.new()
		b.color = Color.BLACK
		b.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.visible = false
		layer.add_child(b)
		bars.append(b)
	hint.add_theme_constant_override("separation", 0)
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var hf := FontVariation.new() # JS #title .hint letter-spacing 6px
	hf.base_font = load("res://assets/fonts/ui_font.tres")
	hf.spacing_glyph = 6
	for part in [["Enter", edge], [" / 클릭하여 시작", Color.WHITE]]:
		var box := Control.new() # 글자 + 뒤 빛 겹 (같은 자리)
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		for gl in HINT_GLOW + [null]:
			var l := Label.new()
			l.text = part[0]
			l.add_theme_font_override("font", hf)
			if gl == null:
				l.add_theme_color_override("font_color", part[1])
				l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8)) # 0 0 2px rgba(0,0,0,.8)
				l.add_theme_constant_override("outline_size", 2)
			else:
				l.add_theme_color_override("font_color", Color(0, 0, 0, 0))
				l.add_theme_color_override("font_outline_color", S.alpha(edge, gl[1]))
				l.add_theme_constant_override("outline_size", gl[0])
			box.add_child(l)
			hint_parts.append(l)
		hint.add_child(box)
	hint.visible = false
	layer.add_child(hint)
	layer.move_child(white, -1) # 하얀 막은 맨 위 (JS #title .white)
	View.changed.connect(func(k): # 화질 (W6): 메뉴에서 낮음 ↔ 다른 화질이면 배경 장면을 그 화질로 다시 (거울·블룸·장식)
		if k == "lowGfx" and scene != null and not title_mode:
			_drop()
			_make(true))
	if not headless and not skip:
		title_mode = true
		View.title_on = true
		_make(false)
	start_ms = Time.get_ticks_msec()


func _reduced() -> bool:
	return bool(View.settings.get("reducedMotion", false))


func _make(menu: bool) -> void:
	scene = Scene.new()
	add_child(scene)
	scene.setup(theme, {"menu": menu, "low": bool(View.settings.get("lowGfx", false)), "instant": _reduced()})
	scene.landed.connect(func(n): View.sound_cue.emit("titleLand", {"n": n}))
	scene.burst.connect(func(): View.sound_cue.emit("titleBurst", {}))
	scene.exit_started.connect(func(): View.sound_cue.emit("titleExit", {}))
	prev_cam = get_viewport().get_camera_3d()
	scene.cam.make_current()
	_haze_on()
	active_changed.emit(true)


# 빛 안개: 장면이 떠 있고 그래픽 낮춤이 아닐 때만 (세기·밉 단계는 테마별 C.TITLE_HAZE)
func _haze_on() -> void:
	var on := scene != null and not bool(View.settings.get("lowGfx", false))
	haze.visible = on
	if on:
		var hz: Array = TC.haze(theme)
		haze.material.set_shader_parameter("strength", hz[0])
		haze.material.set_shader_parameter("lod", hz[1])
		haze.material.set_shader_parameter("thr", hz[2])


func _drop() -> void:
	if scene == null:
		return
	scene.queue_free()
	scene = null
	haze.visible = false
	if prev_cam != null and is_instance_valid(prev_cam):
		prev_cam.make_current()
	active_changed.emit(false)


func _process(dt: float) -> void:
	# 판 빛 색 테마: 메뉴 = 메뉴 테마, 대기실 = 고른 맵 테마 (JS markTheme)
	var st := Store.state
	if Store.in_room():
		var lt = LP.lobby_theme(st, View.menu_theme)
		View.ui_theme = lt if lt != null else View.menu_theme
	else:
		View.ui_theme = theme
	var want := not Store.in_room() and not headless
	if title_mode and Store.in_room():
		_finish() # 타이틀 중에 방에 들어감 (재접속 등)
	if not want:
		_drop()
		return
	if scene == null:
		_make(true)
	scene.step(minf(dt, 0.1))
	if title_mode and auto_press >= 0.0 and Time.get_ticks_msec() - start_ms >= auto_press * 1000.0:
		auto_press = -1.0
		_go()
	if title_mode:
		var vp := layer.get_viewport().get_visible_rect().size
		hint.visible = scene.ready_hint() and not pressed
		if hint.visible:
			# JS #title .hint: 글자 clamp(18px, 2.2vw, 30px), 아래 14%, title-blink 2.2s 1 ↔ .4 (예전 22px 고정·아래 120·2.5초 .2 ↔ 1)
			_hint_size(int(clampf(vp.x * 0.022, 18.0, 30.0)))
			hint.position = Vector2((vp.x - hint.size.x) / 2.0, vp.y * 0.86 - hint.size.y)
			hint.modulate.a = 0.7 + 0.3 * cos(TAU * Time.get_ticks_msec() / 2200.0)
		if pressed:
			press_ms += dt * 1000.0
		var ex = scene.exit_state()
		_place_bars(vp, ex != null and ex.show)
		if ex != null:
			white.color.a = ex.white
			if ex.show:
				View.title_on = false # 메뉴 판이 들어옴 (카메라가 자리 잡는 동안)
			if ex.done:
				_finish()


func _finish() -> void:
	title_mode = false
	View.title_on = false
	hint.visible = false
	white.color.a = 0.0
	shade.visible = false
	for b in bars:
		b.visible = false


# 안내 글 크기 (빛 겹 포함)
func _hint_size(fs: int) -> void:
	for l in hint_parts:
		l.add_theme_font_size_override("font_size", fs)
	for box in hint.get_children():
		var m: Vector2 = box.get_child(box.get_child_count() - 1).get_combined_minimum_size()
		box.custom_minimum_size = m
		for l in box.get_children():
			l.size = m
	hint.reset_size()


# 위아래 띠 (누르면 ease-in 으로 빠짐, 움직임 줄이기면 바로) · 가장자리 어둡게. out = 메뉴 판이 들어옴 (JS #title.out: 띠·어둡게 없음)
func _place_bars(vp: Vector2, out: bool) -> void:
	shade.visible = not out
	var h := ceilf(vp.y * BAR_VH)
	var e := 0.0
	if pressed:
		e = 1.0 if _reduced() else U.cubic_bezier(clampf(press_ms / BAR_MS, 0.0, 1.0), 0.42, 0.0, 1.0, 1.0)
	for i in bars.size():
		var b: ColorRect = bars[i]
		b.visible = not out and e < 1.0
		b.size = Vector2(vp.x, h)
		b.position = Vector2(0, -h * e if i == 0 else vp.y - h + h * e)


func _go() -> void:
	if pressed or Time.get_ticks_msec() - start_ms < C.TITLE_INPUT_DELAY_MS:
		return # 켜자마자 눌린 키는 무시
	pressed = true
	press_ms = 0.0
	hint.visible = false
	scene.press()


# 타이틀 동안 키·클릭은 여기서 먹음 (메뉴로 새지 않게). 컨트롤·F 키는 그대로
func _input(e: InputEvent) -> void:
	if not title_mode or scene == null:
		return
	if e is InputEventKey:
		if e.ctrl_pressed or e.alt_pressed or e.meta_pressed or (e.keycode >= KEY_F1 and e.keycode <= KEY_F12):
			return
		get_viewport().set_input_as_handled()
		if e.pressed and not e.echo:
			_go()
	elif e is InputEventMouseButton or e is InputEventScreenTouch:
		get_viewport().set_input_as_handled()
		if e.pressed:
			_go()
