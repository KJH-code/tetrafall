# 성능 표시 (F3, client/perf.js PerfPanel 자리): 오른쪽 위 핑 아래 작은 글자 판 + '복사' (한 줄 클립보드, Ctrl+C 도). 켠 상태는 View.settings.perf (JS tf-perf).
# 메뉴·대기실·판 어디서나 (타이틀도). JS 칸 (FPS·1% low·구간·그리기·삼각형·인원·화면·GPU·핑) 다음에 고도만의 칸 (W6 2026-11-02, 재혁 PC 랙 진단):
#   화면 상태 (맨 앞) · 스크립트 (GDScript _process 합 — 탐침 노드 두 개 사이, 아래) · 물리 (_physics_process 합) · 렌더 CPU·GPU (고도가 잰 판 화면) ·
#   물체 · SubViewport (지금 그리는 것 크기·MSAA) · 영상 메모리 · 화질 (world/gfx.gd) · 렌더러 · 제조사 · 하이브리드 안내.
# 'JS' 자리 = 스크립트 + 렌더 CPU. 고도 4.7 Performance.TIME_PROCESS 는 그리기 (RenderingServer.draw) 까지 들어가 스크립트 시간이 아님 → 안 씀.
# 구간 (래그돌·몸 애니·블록·위험) 은 그 묶음이 PerfCalc.begin/end 로 감싸면 나옴. main.gd 가 붙임.
# 메뉴·타이틀 (방 밖) 에선 왼쪽 아래 구석에 작은 글씨로 GPU·렌더러·창 크기·화질을 늘 보이고, 내장 그래픽 + 다른 GPU 면 안내 한 줄 (F3 와 상관없이)
extends CanvasLayer
const Opts := preload("res://core/opts.gd")

const C := preload("res://core/config.gd")
const PC := preload("res://ui/perf_calc.gd")
const S := preload("res://ui/ui_style.gd")
const Gfx := preload("res://world/gfx.gd")
const Hitch := preload("res://core/hitch.gd")
const Prof := preload("res://core/prof.gd")
const GC := preload("res://world/gfx_calc.gd")
const CORNER_SIZE := 11 # 구석 글자 px
const CORNER_ALPHA := 0.6
const HINT_COLOR := Color("ffc861")


# 탐침: process 순서 맨 앞·맨 뒤 노드 (process_priority) — 둘 사이 시간 = 이 프레임 모든 노드 _process (GDScript) 합. 물리도 같게
class Probe:
	extends Node
	var last := false
	var t0 := 0
	var p0 := 0
	var peer: Probe = null # 맨 뒤 탐침이 맨 앞 탐침 시각을 읽음
	var phys_us := 0 # 이번 프레임 물리 틱들 합 (맨 뒤 탐침)
	var sink: Callable # 맨 뒤: (script_us, phys_us) 를 받음

	func _init(is_last: bool) -> void:
		last = is_last
		process_priority = 1000000 if last else -1000000
		process_physics_priority = 1000000 if last else -1000000
		process_mode = Node.PROCESS_MODE_ALWAYS

	func _process(_d: float) -> void:
		var t := Time.get_ticks_usec()
		if not last:
			t0 = t
			return
		sink.call(t - peer.t0, phys_us)
		phys_us = 0

	func _physics_process(_d: float) -> void:
		var t := Time.get_ticks_usec()
		if not last:
			p0 = t
			return
		phys_us += t - peer.p0


var win := PC.PerfWindow.new()
var last := 0.0
var draw_at := 0.0
var box := PanelContainer.new()
var text: Label
var copy_btn: Button
var gpu := ""
var draws := 0
var tris := 0
var objs := 0
var samples: Array = [] # [t, 스크립트 ms, 물리 ms, 렌더 CPU ms, 렌더 GPU ms]
var means := [0.0, 0.0, 0.0, 0.0]
var script_ms := 0.0 # 지난 프레임 (탐침)
var phys_ms := 0.0
var svps: Array = [] # [[w, h, msaa 배수]] 지금 그리는 SubViewport
var first: Probe
var tail: Probe
var corner := VBoxContainer.new()
var corner_hint: Label
var corner_info: Label
var corner_at := 0.0
var hlog := Hitch.Log.new() # W30 히치 로거 (core/hitch.gd): F3 를 켜거나 --hitch 면 기록
var hfile: FileAccess = null
var hstart := 0.0


func _ready() -> void:
	name = "Perf"
	layer = 50
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.02, 0.03, 0.08, 0.72)
	sb.set_content_margin_all(6)
	box.add_theme_stylebox_override("panel", sb)
	box.mouse_filter = Control.MOUSE_FILTER_PASS
	box.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	box.position = Vector2(-420, 72)
	box.custom_minimum_size = Vector2(408, 0)
	var v := VBoxContainer.new()
	box.add_child(v)
	text = S.body_label("", 11, S.TEXT) # 본문 글꼴 (숫자·기호가 또렷 — Black Han Sans 는 '>' 가 ')' 처럼 보임)
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(text)
	copy_btn = S.button("복사 (Ctrl+C)", _copy, "ghost", 11)
	copy_btn.size_flags_horizontal = Control.SIZE_SHRINK_END
	v.add_child(copy_btn)
	add_child(box)
	# 구석 (방 밖): 왼쪽 아래
	corner.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	corner.grow_vertical = Control.GROW_DIRECTION_BEGIN
	corner.position = Vector2(10, -8)
	corner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	corner.add_theme_constant_override("separation", 1)
	corner_hint = S.body_label("", CORNER_SIZE + 1, HINT_COLOR)
	corner_info = S.body_label("", CORNER_SIZE, S.DIM)
	corner_info.modulate.a = CORNER_ALPHA
	for l in [corner_hint, corner_info]:
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		corner.add_child(l)
	add_child(corner)
	gpu = Gfx.adapter if Gfx.adapter != "" else RenderingServer.get_video_adapter_name()
	first = Probe.new(false)
	tail = Probe.new(true)
	tail.peer = first
	tail.sink = func(s_us: int, p_us: int):
		script_ms = s_us / 1000.0
		phys_ms = p_us / 1000.0
	PlayerInput.ui_action.connect(func(id, pressed):
		if id == "perf" and pressed:
			View.set_setting("perf", not bool(View.settings.get("perf", false))))
	View.changed.connect(func(k): if k == "perf": _apply())
	_apply()
	_corner(0.0)


func _apply() -> void:
	PC.on = bool(View.settings.get("perf", false)) or Opts.args().has("--perf") # --perf: 확인용 (설정에 안 남김)
	box.visible = PC.on
	var hon: bool = PC.on or Opts.args().has("--hitch") # 히치 로거는 F3 패널을 켜면 같이 (패널 없이 기록만: --hitch)
	if hon != Hitch.on:
		Hitch.on = hon
		Hitch.reset()
		Prof.set_hitch(hon)
		hlog = Hitch.Log.new()
		hstart = Time.get_ticks_usec() / 1000.0
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), hon or Gfx.adapting)
	win = PC.PerfWindow.new()
	samples = []
	last = 0.0
	# 탐침은 켰을 때만 트리에 (꺼져 있으면 비용 0). 맨 앞·맨 뒤는 process_priority 로 — 트리 어디에 있든
	for p in [first, tail]:
		if hon and p.get_parent() == null:
			get_tree().root.add_child.call_deferred(p)
		elif not hon and p.get_parent() != null:
			p.get_parent().remove_child(p)


# 히치 판정 (프레임 간격이 문턱을 넘으면 기록 + user://hitches.txt 한 줄). 태그·구간은 이 간격에 모인 것
func _hitch(now: float, ms: float, rcpu: float) -> void:
	var sec := {}
	var fr := Prof.take_frame()
	for k in fr:
		sec[k] = fr[k] / 1000.0
	var rec := hlog.push((now - hstart) / 1000.0, ms, {"tags": Hitch.take(), "sec": sec, "script": script_ms, "rcpu": rcpu, "screen": _screen()})
	if rec.is_empty():
		return
	if hfile == null:
		hfile = FileAccess.open(Hitch.FILE, FileAccess.WRITE)
		if hfile != null:
			hfile.store_line("# 히치 기록 %s · %s · %s · 창 %s · 기준 = max(평균×%.0f, %.0fms)" % [Time.get_datetime_string_from_system(), _renderer(), PC.short_gpu(gpu), str(get_viewport().get_visible_rect().size), Hitch.FACTOR, Hitch.MIN_MS])
	if hfile != null:
		hfile.store_line(Hitch.line(rec))
		hfile.flush()


func _exit_tree() -> void:
	for p in [first, tail]:
		if p != null and p.get_parent() == null:
			p.free()


func _process(_dt: float) -> void:
	var now := Time.get_ticks_usec() / 1000.0
	if now - corner_at >= C.PERF_DRAW_MS:
		_corner(now)
	if not Hitch.on:
		return
	var vp := get_viewport().get_viewport_rid()
	var rcpu := RenderingServer.viewport_get_measured_render_time_cpu(vp) + RenderingServer.get_frame_setup_time_cpu()
	var rgpu := RenderingServer.viewport_get_measured_render_time_gpu(vp)
	var sec: Dictionary = PC.sec.duplicate()
	sec["render"] = float(sec.get("render", 0.0)) + rcpu
	var work: float = script_ms + rcpu
	if last > 0.0:
		win.push(now, now - last, sec, work)
		samples.append([now, script_ms, phys_ms, rcpu, rgpu])
		_hitch(now, now - last, rcpu)
		while samples.size() > 0 and samples[0][0] < now - C.PERF_FPS_MS:
			samples.pop_front()
	last = now
	PC.sec = {}
	if not PC.on:
		return
	draws = int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	tris = int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
	objs = int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME))
	if now - draw_at >= C.PERF_DRAW_MS:
		draw_at = now
		means = PC.recent_mean(samples, now, C.PERF_FPS_MS, 4)
		svps = _svps()
		_draw_text(now)


# 지금 그리는 SubViewport (항상·한 번·보이면 그리기 중 보이는 것): 크기·MSAA
func _svps() -> Array:
	var out := []
	for n in get_tree().root.find_children("*", "SubViewport", true, false):
		var sv := n as SubViewport
		var m := sv.render_target_update_mode
		var on := m == SubViewport.UPDATE_ALWAYS or m == SubViewport.UPDATE_ONCE
		if m == SubViewport.UPDATE_WHEN_VISIBLE or m == SubViewport.UPDATE_WHEN_PARENT_VISIBLE:
			var par := sv.get_parent()
			on = not (par is CanvasItem) or (par as CanvasItem).is_visible_in_tree()
		if on:
			out.append([sv.size.x * sv.scaling_3d_scale, sv.size.y * sv.scaling_3d_scale, GC.msaa_x(sv.msaa_3d)])
	return out


func _screen() -> String:
	return PC.screen_name(View.title_on, Store.in_room(), Store.phase(), bool(Store.room.get("practice", false)), bool(Store.room.get("tutorial", false)))


func _renderer() -> String:
	return GC.renderer_text(RenderingServer.get_current_rendering_driver_name(), RenderingServer.get_current_rendering_method())


func _gfx_text() -> String:
	return GC.level_text(Gfx.choice, Gfx.plan, Gfx.scale_now) + (" · " + Gfx.adapt_info if Gfx.adapt_info != "" else "") if not Gfx.plan.is_empty() else ""


func extra() -> Dictionary:
	var ps: Array = Store.state.get("players", []) if Store.in_room() else []
	var sz := get_viewport().get_visible_rect().size
	var rw = get_tree().root.get_node_or_null("TfRagdolls")
	var rag := int(rw.stats.get("n", 0)) if rw != null and rw.get("stats") is Dictionary else 0
	return {"draws": draws, "tris": tris, "players": ps.size(), "rag": rag, "low": bool(View.settings.get("lowGfx", false)), "size": "%d×%d" % [sz.x, sz.y], "gpu": gpu, "ping": Net.ping_text().replace("핑 ", ""),
		"screen": _screen(), "script": means[0], "phys": means[1], "rcpu": means[2], "rgpu": means[3], "objs": objs, "svp": PC.svp_text(svps),
		"vram": Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0, "gfx": _gfx_text(), "renderer": _renderer(), "vendor": Gfx.vendor, "hint": Gfx.hint, "hitch": hlog.summary()}


func _draw_text(now: float) -> void:
	var s := win.summary(now)
	var e := extra()
	var secs := []
	for k in C.PERF_SECTIONS:
		secs.append("%s %s" % [C.PERF_SECTIONS[k], PC.f1(s.sections.get(k, 0.0))])
	var sg := PC.short_gpu(e.gpu)
	text.text = "\n".join([
		"%s · FPS %d  프레임 %sms · 1%% low %sms" % [e.screen, roundi(s.fps), PC.f1(s.avg), PC.f1(s.low)],
		"스크립트 %sms · 물리 %sms · 렌더 CPU %sms · GPU %sms · 핑 %s" % [PC.f1(e.script), PC.f1(e.phys), PC.f1(e.rcpu), PC.f1(e.rgpu), e.ping],
		" · ".join(secs.slice(0, 3)),
		" · ".join(secs.slice(3)),
		"그리기 %d · 물체 %d · 삼각형 %dk · 영상 메모리 %dMB" % [e.draws, e.objs, roundi(e.tris / 1000.0), roundi(e.vram)],
		"SubViewport %s" % e.svp,
		"%d명 (래그돌 %d) · %s · 화질 %s" % [e.players, e.rag, e.size, e.gfx],
		"GPU %s · %s" % [sg if sg != "" else "모름", e.renderer],
		hlog.summary(),
	] + ([e.hint] if e.hint != "" else []))


# 구석 (방 밖만): GPU·렌더러·창 크기·화질 + 하이브리드 안내
func _corner(now: float) -> void:
	corner_at = now
	var show := not Store.in_room() and DisplayServer.get_name() != "headless"
	corner.visible = show
	if not show:
		return
	var sz := get_viewport().get_visible_rect().size
	var sg := PC.short_gpu(gpu)
	corner_info.text = "GPU %s · %s · 창 %d×%d · 화질 %s · F3 성능" % [sg if sg != "" else "모름", _renderer(), sz.x, sz.y, _gfx_text()]
	corner_hint.text = Gfx.hint
	corner_hint.visible = Gfx.hint != ""


func line() -> String:
	var now := Time.get_ticks_usec() / 1000.0
	means = PC.recent_mean(samples, now, C.PERF_FPS_MS, 4)
	svps = _svps()
	return PC.perf_line(win.summary(now), extra())


func _input(e: InputEvent) -> void:
	if not PC.on or not (e is InputEventKey):
		return
	var k := e as InputEventKey
	var f := get_viewport().gui_get_focus_owner()
	if PC.is_copy_key(k.keycode, k.ctrl_pressed, k.pressed, k.echo, f is LineEdit or f is TextEdit):
		get_viewport().set_input_as_handled()
		_copy()


func _copy() -> void:
	DisplayServer.clipboard_set(line())
	copy_btn.text = "복사됨"
	get_tree().create_timer(1.2).timeout.connect(func(): copy_btn.text = "복사 (Ctrl+C)")
