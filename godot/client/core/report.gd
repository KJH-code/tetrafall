# 성능·모션 보고서 모으기 (W48, 노드 하나 — main.gd 가 붙임). 재혁이 클릭 한 번 (결과 화면 '성능 보고 복사' 버튼·F4) 으로 채팅에 붙일 한 덩어리 글을 만들고
# user://last_report.txt 에도 남김 (게임을 껐으면 배포 폴더 보고서-복사.bat / report.sh 가 이 파일을 읽음). 글 만들기는 core/report_calc.gd (순수 계산).
#
# 비용: 방 안에서 프레임마다 하는 일 = 프레임 간격 한 칸 + Performance 모니터 한 번 + 태그 가져오기 (있을 때만). 판 안 (playing) 에서만 기록, 방 밖은 거의 0.
#   · F3 (Hitch.full) 없이도 FPS·1% low·히치 원인 상위가 모임: 히치 태그 (Hitch.on) 는 늘 켜 두고, 히치 판정은 Hitch.Log.push (MIN_MS 아래 프레임은 정렬도 안 함).
#   · F3·--hitch 가 켜져 있으면 ui/perf.gd 의 로그 (스크립트·렌더 CPU 까지 든 것) 를 그대로 씀 (full_src).
#   · 글은 판이 끝날 때 한 번 만들어 둠 (결과 화면에서 누르면 바로). 판 도중에 누르면 지금까지로 (진행 중).
# 꺼짐: Report.enabled = false (테스트) — _process 가 바로 끝나고 Hitch.on 도 안 건드림
extends Node

const Opts := preload("res://core/opts.gd")
const C := preload("res://core/config.gd")
const Calc := preload("res://core/report_calc.gd")
const Hitch := preload("res://core/hitch.gd")
const Build := preload("res://core/build_info.gd")
const Gfx := preload("res://world/gfx.gd")
const GC := preload("res://world/gfx_calc.gd")
const PC := preload("res://ui/perf_calc.gd")
const Pops := preload("res://core/pop_count.gd")

signal copied(ok: bool, text: String) # ui/report_ui.gd 가 토스트·글 칸을 띄움

const FILE := "user://last_report.txt"
const RING_CAP := 60000 # 판 하나에서 남길 프레임 수 (60fps 로 약 17분, 넘으면 앞 절반 버림)

static var inst: Node = null
static var enabled := true # 테스트가 끔
static var clipboard_set: Callable = Callable() # 테스트가 바꿈 (기본 DisplayServer.clipboard_set)
static var clipboard_get: Callable = Callable()
static var file_path := FILE # 테스트가 바꿈
static var full_src: Node = null # ui/perf.gd (F3·--hitch 켜져 있을 때 이쪽 hlog 를 씀)

var last_text := "" # 마지막으로 끝난 판 보고서 (없으면 "")
var last_data := {}
var playing := false
var phase_now := ""
var frames := PackedFloat32Array()
var worst_ms := 0.0
var worst_t := 0.0
var start_us := 0
var prev_us := 0
var proc_sum := 0.0
var proc_max := 0.0
var proc_n := 0
var rcpu_sum := 0.0
var rgpu_sum := 0.0
var gpu_n := 0
var light_log := Hitch.Log.new()
var full_from := 0 # 판 시작 때 perf.gd 로그의 히치 수·시각 (그 판 몫만 보이게)
var full_t0 := 0.0
var just_started := false
var ctx := {} # 판 정보 (캐릭터·인원·맵·모드) — 시작 때 찍고 끝날 때 다시 찍음
var pops := Pops.new()


func _ready() -> void:
	name = "Report"
	inst = self
	if enabled:
		Hitch.on = true # 태그만 (프레임마다 하는 일은 Hitch.full)
	var pi = get_node_or_null("/root/PlayerInput")
	if pi != null:
		pi.ui_action.connect(func(id, pressed): if id == "report" and pressed: request_copy())


func _exit_tree() -> void:
	if playing:
		_end_round()
	if inst == self:
		inst = null


func _process(_d: float) -> void:
	if not enabled:
		return
	var now := Time.get_ticks_usec()
	var ph: String = Store.phase() if Store.in_room() else ""
	if ph != phase_now:
		_on_phase(phase_now, ph)
		phase_now = ph
	var dt_ms := (now - prev_us) / 1000.0 if prev_us > 0 else 0.0
	prev_us = now
	if just_started: # 판이 시작된 프레임의 간격은 앞 단계 (불러오기·카운트다운) 몫이라 판 기록에 안 셈
		just_started = false
		dt_ms = 0.0
	var tags: Array = []
	if Hitch.pending() and not Hitch.full:
		tags = Hitch.take() # F3 가 켜져 있으면 perf.gd 가 가져감
	if not playing or dt_ms <= 0.0:
		return
	tick(now, dt_ms, tags)


# 프레임 하나 기록 (테스트가 직접 부름)
func tick(now_us: int, dt_ms: float, tags: Array = []) -> void:
	frames.append(dt_ms)
	if frames.size() > RING_CAP:
		frames = frames.slice(RING_CAP / 2)
	var t_s := (now_us - start_us) / 1000000.0
	if dt_ms > worst_ms:
		worst_ms = dt_ms
		worst_t = t_s
	var pm := Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	proc_sum += pm
	proc_max = maxf(proc_max, pm)
	proc_n += 1
	if (Gfx.adapting or Hitch.full) and is_inside_tree():
		var vp := get_viewport().get_viewport_rid()
		rcpu_sum += RenderingServer.viewport_get_measured_render_time_cpu(vp) + RenderingServer.get_frame_setup_time_cpu()
		rgpu_sum += RenderingServer.viewport_get_measured_render_time_gpu(vp)
		gpu_n += 1
	if not Hitch.full:
		light_log.push(t_s, dt_ms, {"tags": tags, "screen": "판 (playing)"})
	pops.step(now_us, t_s)


func _on_phase(old: String, new: String) -> void:
	if new == "playing" and old != "playing":
		_start_round()
	elif old == "playing" and new != "playing":
		_end_round()


func _start_round() -> void:
	playing = true
	just_started = true
	frames = PackedFloat32Array()
	worst_ms = 0.0
	worst_t = 0.0
	start_us = Time.get_ticks_usec()
	proc_sum = 0.0
	proc_max = 0.0
	proc_n = 0
	rcpu_sum = 0.0
	rgpu_sum = 0.0
	gpu_n = 0
	light_log = Hitch.Log.new()
	Gfx.reset_round_stats()
	pops.reset()
	if full_src != null and is_instance_valid(full_src):
		full_from = full_src.hlog.count
		full_t0 = (Time.get_ticks_usec() / 1000.0 - full_src.hstart) / 1000.0
	var c := round_ctx()
	if not c.is_empty():
		ctx = c


func _end_round() -> void:
	playing = false
	var c := round_ctx()
	if not c.is_empty():
		ctx = c
	last_data = collect(false)
	last_text = Calc.build(last_data, Calc.env_names())
	write_file(last_text)


# 지금 판 정보 (스냅샷에서). 방 밖이면 {}
func round_ctx() -> Dictionary:
	var st: Dictionary = Store.state
	if st.is_empty() or not Store.in_room():
		return {}
	var ps: Array = (st.get("players", []) as Array).filter(func(p): return not p.get("spectator", false) and not p.get("dummy", false))
	var bots := 0
	for p in ps:
		if p.get("isBot", false):
			bots += 1
	var mine := "?"
	for p in st.get("players", []): # 스냅샷에서 직접 (Store.me() 는 스냅샷을 받은 뒤에만 참)
		if int(p.get("id", -1)) == int(Store.my_id):
			mine = str(p.get("char", "?"))
	var mp = st.get("map")
	return {"char": mine, "players": ps.size(), "bots": bots, "map": str(mp.get("id", "?")) if mp is Dictionary else "?",
		"mode": str(st.get("mode", "?")), "practice": bool(Store.room.get("practice", false)), "tutorial": bool(Store.room.get("tutorial", false))}


# 값 모으기 → build 에 넘길 칸들. partial = 판이 아직 진행 중
func collect(partial: bool) -> Dictionary:
	var d := {"version": Build.text(), "time": Time.get_datetime_string_from_system().replace("T", " ").substr(0, 16)}
	d["os"] = OS.get_name() + (" " + OS.get_version() if OS.get_version() != "" else "") + (" (웹)" if Opts.web() else "")
	var raw_gpu: String = Gfx.adapter if Gfx.adapter != "" else RenderingServer.get_video_adapter_name()
	d["gpu"] = PC.short_gpu(raw_gpu)
	d["gpu_kind"] = GC.gpu_kind(Gfx.adapter if Gfx.adapter != "" else raw_gpu, Gfx.vendor)
	d["renderer"] = GC.renderer_text(RenderingServer.get_current_rendering_driver_name(), RenderingServer.get_current_rendering_method())
	var win := get_window() if is_inside_tree() else null
	var sz := Vector2i(win.size) if win != null else Vector2i.ZERO
	d["win"] = "%d×%d" % [sz.x, sz.y]
	d["ui"] = "%d%%" % roundi(float(View.ui_scale) * 100.0)
	d["scale3d"] = Gfx.scale_now
	d["scale_min"] = Gfx.scale_min
	if not Gfx.plan.is_empty():
		d["quality"] = "%s%s MSAA %d×" % [_gfx_label(str(Gfx.plan.get("level", ""))), " (자동)" if str(Gfx.choice) not in ["high", "medium", "low"] else "", GC.msaa_x(int(Gfx.plan.get("msaa", 0)))]
	d["opts"] = Calc.opt_list(_engine_args() + Array(Opts.args()))
	d["has_round"] = not ctx.is_empty() and not frames.is_empty()
	for k in ctx:
		d[k] = ctx[k]
	d["partial"] = partial
	d["secs"] = (Time.get_ticks_usec() - start_us) / 1000000.0 if partial else _secs_sum()
	var fs := Calc.frame_stats(frames)
	d["frames"] = fs.n
	d["fps"] = fs.fps
	d["low_ms"] = fs.low_ms
	d["low_fps"] = fs.low_fps
	d["worst_ms"] = worst_ms
	d["worst_t"] = worst_t
	d["proc_avg"] = proc_sum / proc_n if proc_n > 0 else -1.0
	d["proc_max"] = proc_max
	d["rcpu"] = rcpu_sum / gpu_n if gpu_n > 0 else -1.0
	d["rgpu"] = rgpu_sum / gpu_n if gpu_n > 0 else -1.0
	d["script"] = -1.0
	if Hitch.full and full_src != null and is_instance_valid(full_src) and full_src.has_method("cpu_means"):
		var m: Array = full_src.cpu_means() # [스크립트, 물리, 렌더 CPU, 렌더 GPU] 최근 평균
		d["script"] = float(m[0])
		d["rcpu"] = float(m[2])
		d["rgpu"] = float(m[3])
	d["vram"] = Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0
	_hitch_into(d)
	d["res_changes"] = Gfx.res_changes
	pops.into(d)
	return d


func _gfx_label(level: String) -> String:
	return str(GC.WC.GFX_LABEL.get(level, level))


func _engine_args() -> Array:
	var out := []
	var a := OS.get_cmdline_args()
	var i := 0
	while i < a.size():
		if a[i] in ["--rendering-method", "--rendering-driver"] and i + 1 < a.size():
			out.append(a[i])
			out.append(a[i + 1])
			i += 1
		i += 1
	return out


func _secs_sum() -> float:
	var s := 0.0
	for v in frames:
		s += v
	return s / 1000.0


# 히치 칸: F3 가 켜져 있으면 perf.gd 로그의 이번 판 몫, 아니면 가벼운 로그
func _hitch_into(d: Dictionary) -> void:
	var log: Hitch.Log = light_log
	var from := 0
	var off := 0.0
	if Hitch.full and full_src != null and is_instance_valid(full_src):
		log = full_src.hlog
		from = full_from
		off = full_t0
	var n := log.count - from
	var worst := 0.0
	if n > 0:
		for r in log.records.slice(maxi(0, log.records.size() - n)):
			worst = maxf(worst, float(r.ms))
	d["hitch_n"] = maxi(0, n)
	d["hitch_worst"] = worst
	d["hitch_lines"] = log.top_report(from, Calc.HITCH_LINES, off) if n > 0 else []


# ---- 보고서 글 (지금) ----
func current_text() -> String:
	if playing:
		var d := collect(true)
		return Calc.build(d, Calc.env_names())
	if last_text != "":
		return last_text
	return Calc.build(collect(false), Calc.env_names())


# 버튼·F4: 글을 클립보드에 + 파일에. 돌려줌 {ok (클립보드에 들어갔다고 확인됨), text}
func copy_now() -> Dictionary:
	var text := current_text()
	write_file(text)
	var ok := false
	var set_fn: Callable = clipboard_set if clipboard_set.is_valid() else Callable(DisplayServer, "clipboard_set")
	var get_fn: Callable = clipboard_get if clipboard_get.is_valid() else Callable(DisplayServer, "clipboard_get")
	set_fn.call(text)
	if Opts.web():
		ok = false # 브라우저는 복사가 됐는지 읽어 볼 수 없음 → 글 칸도 같이 띄움 (ui/report_ui.gd)
	else:
		ok = str(get_fn.call()).replace("\r\n", "\n").strip_edges() == text.strip_edges()
	copied.emit(ok, text)
	return {"ok": ok, "text": text}


static func request_copy() -> Dictionary:
	if inst != null and is_instance_valid(inst):
		return inst.copy_now()
	return {"ok": false, "text": ""}


func write_file(text: String) -> void:
	var f := FileAccess.open(file_path, FileAccess.WRITE)
	if f != null:
		f.store_string(text + "\n")
