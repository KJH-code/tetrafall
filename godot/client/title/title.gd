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

var scene = null
var theme := ""
var title_mode := false # 지금 타이틀 (Enter 전·날아가는 중)
var pressed := false
var start_ms := 0.0
var layer := CanvasLayer.new()
var hint := Label.new()
var white := ColorRect.new()
var headless := false
var prev_cam: Camera3D = null
var skip := false # main.gd 가 정함: 방 주소 (--room, 웹 ?room=)·자동 조종이면 타이틀 없이 메뉴 배경
var fixed_theme := "" # main.gd: --title <테마> (웹 ?title=)
var auto_press := -1.0 # 확인용 (--title-press 초): 그 초에 누른 셈


func _ready() -> void:
	headless = DisplayServer.get_name() == "headless"
	theme = fixed_theme if C.TITLE_THEMES.has(fixed_theme) else TC.pick_theme(randf())
	View.menu_theme = theme
	View.ui_theme = theme
	layer.layer = 9 # 메뉴 판 (G4 ui = 10) 아래
	add_child(layer)
	white.color = Color(1, 1, 1, 0)
	white.mouse_filter = Control.MOUSE_FILTER_IGNORE
	white.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(white)
	hint.text = "Enter / 클릭하여 시작"
	hint.add_theme_font_size_override("font_size", 22)
	hint.add_theme_color_override("font_color", Color(1, 1, 1, 0.92))
	hint.add_theme_color_override("font_outline_color", Co.color(C.TITLE_THEMES[theme].edge))
	hint.add_theme_constant_override("outline_size", 6)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	hint.position.y -= 120
	hint.visible = false
	layer.add_child(hint)
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
	active_changed.emit(true)


func _drop() -> void:
	if scene == null:
		return
	scene.queue_free()
	scene = null
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
		hint.visible = scene.ready_hint() and not pressed
		if hint.visible:
			hint.modulate.a = 0.6 + 0.4 * sin(Time.get_ticks_msec() / 400.0)
		var ex = scene.exit_state()
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


func _go() -> void:
	if pressed or Time.get_ticks_msec() - start_ms < C.TITLE_INPUT_DELAY_MS:
		return # 켜자마자 눌린 키는 무시
	pressed = true
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
