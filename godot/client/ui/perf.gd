# 성능 표시 (F3, client/perf.js PerfPanel 자리): 오른쪽 위 핑 아래 작은 글자 판 + '복사' (한 줄 클립보드). 켠 상태는 View.settings.perf (JS tf-perf)
# 고도 판이라 'JS' 자리는 GDScript 처리 시간 (Performance TIME_PROCESS), 렌더는 고도가 잰 CPU·GPU 시간, 그리기·삼각형은 엔진 세기.
# 구간 (래그돌·몸 애니·블록·위험) 은 그 묶음이 PerfCalc.begin/end 로 감싸면 나옴. main.gd 가 붙임
extends CanvasLayer

const C := preload("res://core/config.gd")
const PC := preload("res://ui/perf_calc.gd")
const S := preload("res://ui/ui_style.gd")

var win := PC.PerfWindow.new()
var last := 0.0
var draw_at := 0.0
var box := PanelContainer.new()
var text: Label
var copy_btn: Button
var gpu := ""
var draws := 0
var tris := 0


func _ready() -> void:
	layer = 50
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.02, 0.03, 0.08, 0.72)
	sb.set_content_margin_all(6)
	box.add_theme_stylebox_override("panel", sb)
	box.mouse_filter = Control.MOUSE_FILTER_PASS
	box.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	box.position = Vector2(-360, 72)
	box.custom_minimum_size = Vector2(348, 0)
	var v := VBoxContainer.new()
	box.add_child(v)
	text = S.label("", 11, S.TEXT)
	v.add_child(text)
	copy_btn = S.button("복사", _copy, "ghost", 11)
	copy_btn.size_flags_horizontal = Control.SIZE_SHRINK_END
	v.add_child(copy_btn)
	add_child(box)
	gpu = RenderingServer.get_video_adapter_name()
	PlayerInput.ui_action.connect(func(id, pressed):
		if id == "perf" and pressed:
			View.set_setting("perf", not bool(View.settings.get("perf", false))))
	View.changed.connect(func(k): if k == "perf": _apply())
	_apply()


func _apply() -> void:
	PC.on = bool(View.settings.get("perf", false)) or OS.get_cmdline_user_args().has("--perf") # --perf: 확인용 (설정에 안 남김)
	box.visible = PC.on
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), PC.on)
	win = PC.PerfWindow.new()
	last = 0.0


func _process(_dt: float) -> void:
	if not PC.on:
		return
	var now := Time.get_ticks_usec() / 1000.0
	var vp := get_viewport().get_viewport_rid()
	var sec: Dictionary = PC.sec.duplicate()
	sec["render"] = float(sec.get("render", 0.0)) + RenderingServer.viewport_get_measured_render_time_cpu(vp) + RenderingServer.get_frame_setup_time_cpu()
	var work: float = Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0 + float(sec.render)
	if last > 0.0:
		win.push(now, now - last, sec, work)
	last = now
	PC.sec = {}
	draws = int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	tris = int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
	if now - draw_at >= C.PERF_DRAW_MS:
		draw_at = now
		_draw_text(now)


func extra() -> Dictionary:
	var ps: Array = Store.state.get("players", [])
	var sz := get_viewport().get_visible_rect().size
	return {"draws": draws, "tris": tris, "players": ps.size(), "rag": 0, "low": bool(View.settings.get("lowGfx", false)), "size": "%d×%d" % [sz.x, sz.y], "gpu": gpu, "ping": Net.ping_text().replace("핑 ", "")}


func _draw_text(now: float) -> void:
	var s := win.summary(now)
	var e := extra()
	var gpu_ms := RenderingServer.viewport_get_measured_render_time_gpu(get_viewport().get_viewport_rid())
	var secs := []
	for k in C.PERF_SECTIONS:
		secs.append("%s %s" % [C.PERF_SECTIONS[k], PC.f1(s.sections.get(k, 0.0))])
	text.text = "\n".join([
		"FPS %d  프레임 %sms · 1%% low %sms" % [roundi(s.fps), PC.f1(s.avg), PC.f1(s.low)],
		"스크립트+렌더 %sms (기타 %s) · GPU %sms · 핑 %s" % [PC.f1(s.work), PC.f1(s.other), PC.f1(gpu_ms), e.ping],
		" · ".join(secs.slice(0, 3)),
		" · ".join(secs.slice(3)),
		"그리기 %d · 삼각형 %dk" % [e.draws, roundi(e.tris / 1000.0)],
		"%d명 · 그래픽 낮춤 %s · %s" % [e.players, "켬" if e.low else "끔", e.size],
		"GPU %s" % (PC.short_gpu(e.gpu) if PC.short_gpu(e.gpu) != "" else "모름"),
	])


func line() -> String:
	return PC.perf_line(win.summary(Time.get_ticks_usec() / 1000.0), extra())


func _copy() -> void:
	DisplayServer.clipboard_set(line())
	copy_btn.text = "복사됨"
	get_tree().create_timer(1.2).timeout.connect(func(): copy_btn.text = "복사")
