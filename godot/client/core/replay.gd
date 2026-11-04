# 성능 재연 (W12 2026-11-02): 같은 판을 서버 없이 다시 돌려 스크립트 시간을 같은 조건으로 잼 (A/B — 기계를 다른 워커와 나눠 써 판마다 흔들리던 것).
#   녹화: --rec <파일> (자동 조종 판과 같이: 받은 글자를 "시각\t글자" 줄로, core/net.gd)
#   재연: --replay <파일> [--replay-fps 120] [--replay-warm 3] [--replay-secs 10] [--replay-render] [--prof] [--shot <png>]
#     가상 시계 (Net.virt) 가 프레임마다 1000/fps ms 씩 흐름 → 프레임마다 받는 스냅샷 수가 실제 120fps 와 같음 (llvmpipe 4fps 에서 재면 한 프레임에 스냅샷 7개라 JSON·신호가 7배로 잡히던 것).
#     처음 'playing' 스냅샷 + warm 초부터 secs 초 동안 잼. 기본은 그리기 끔 (RenderingServer.render_loop_enabled — 스크립트만, 빠름), --replay-render 면 그리며 그리기·물체·삼각형도.
#     --set 키=값,키=값 (View.settings 를 바꿔 알림만 — 설정 파일엔 안 남김, 예: outline=false,shadows=false) : 외곽선·그림자 비용을 같은 판에서 A/B
#     끝에 한 줄: 프레임 · 스냅샷 · 스크립트 (_process 합, 탐침) ms/프레임 · 물리 ms/틱 · 120fps 환산 (스크립트 + 물리 × 틱/프레임) — --prof 면 구간 (core/prof.gd)
extends Node

const Prof := preload("res://core/prof.gd")
const Probe := preload("res://ui/perf.gd").Probe
const UiCensus := preload("res://core/ui_census.gd")

var args := {}
var fps := 120.0
var t_start := 0.0 # 재기 시작 (가상 ms)
var t_end := 0.0
var frames := 0
var snaps := 0
var script_us := 0
var phys_us := 0
var phys_ticks := 0
var first: Probe
var tail: Probe
var measuring := false
var done := false
var frame_us: Array = [] # 프레임마다 스크립트 µs (중앙값·최악)
var spikes: Array = [] # --prof: 가장 느린 프레임 [µs, 가상 초, 그 프레임 구간 큰 순서 글자]
var _prev_sums := {}
# --frame-log <파일> (W17): 재는 동안 프레임마다 한 줄 (벽시계 프레임 ms·스크립트 ms·위험 켬·그리기·물체) — 위험이 처음 나오는 프레임만 튀는지 (셰이더 첫 컴파일) 보기
var flog: FileAccess = null
var _wall0 := 0
var _last_s_us := 0


static func load_file(path: String) -> Array:
	var out := []
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return out
	while not f.eof_reached():
		var line := f.get_line()
		var tab := line.find("\t")
		if tab > 0:
			out.append([float(line.substr(0, tab)), line.substr(tab + 1)])
	return out


# 녹화 시각 다시 매기기: 녹화한 기계가 느리면 (llvmpipe 4fps) 스냅샷 여럿이 한 프레임에 같은 시각으로 찍힘 → 재연 때도 한 프레임에 몰려
# 실제 120fps 와 달라짐. 스냅샷은 서버 시각 (state.time) 간격 그대로 (첫 스냅샷 받은 시각 기준), 다른 메시지는 바로 앞 줄 시각 (순서 그대로)
static func retime(lines: Array) -> Array:
	var out := []
	var base = null # [받은 시각, 서버 시각]
	var last := 0.0
	for l in lines:
		var at := float(l[0])
		var txt := str(l[1])
		var st = server_time(txt)
		if st != null:
			if base == null:
				base = [at, st]
			at = base[0] + (st - base[1])
		elif base != null:
			at = last
		at = maxf(at, last)
		last = at
		out.append([at, txt])
	return out


# 스냅샷 글자의 서버 시각 (ms) — JSON 을 다 풀지 않고 "time": 숫자만. 스냅샷 아니면 null
static func server_time(txt: String):
	if not txt.begins_with("{\"type\":\"state\""):
		return null
	var i := txt.find("\"time\":")
	if i < 0:
		return null
	var j := i + 7
	var k := j
	while k < txt.length() and "0123456789.-e+".contains(txt[k]):
		k += 1
	return float(txt.substr(j, k - j)) if k > j else null


# 재기 시작 시각: 처음 판 (phase playing) 스냅샷 + warm 초
static func start_at(lines: Array, warm_s: float) -> float:
	for l in lines:
		if str(l[1]).contains("\"phase\":\"playing\""):
			return float(l[0]) + warm_s * 1000.0
	return float(lines[0][0]) + warm_s * 1000.0 if not lines.is_empty() else 0.0


func _ready() -> void:
	process_priority = -999999 # 가상 시계를 맨 먼저 흘림 (Net·Store 보다 앞)
	if args.has("rec"):
		Net.rec = FileAccess.open(str(args.rec), FileAccess.WRITE)
		print("[재연] 기록 → %s" % args.rec)
		return
	var lines := retime(load_file(str(args.replay)))
	if lines.is_empty():
		print("[재연] 파일 없음·글자 없음 %s" % args.replay)
		get_tree().quit(2)
		return
	fps = float(args.get("replay-fps", 120))
	t_start = start_at(lines, float(args.get("replay-warm", 3)))
	t_end = t_start + float(args.get("replay-secs", 10)) * 1000.0
	Net.replay = lines
	Net.replay_i = 0
	Net.virt = float(lines[0][0])
	Prof.on = args.has("prof")
	if not args.has("replay-render"):
		RenderingServer.render_loop_enabled = false
	first = Probe.new(false)
	tail = Probe.new(true)
	tail.peer = first
	tail.sink = func(s_us: int, p_us: int):
		if measuring:
			script_us += s_us
			frame_us.append(s_us)
			_last_s_us = s_us
			phys_us += p_us
			if Prof.on:
				_spike(s_us)
	get_tree().root.add_child.call_deferred(first)
	get_tree().root.add_child.call_deferred(tail)
	if args.has("set"):
		_apply_sets.call_deferred(parse_sets(str(args.set)))
	if args.has("frame-log"):
		flog = FileAccess.open(str(args["frame-log"]), FileAccess.WRITE)
		flog.store_line("frame\tvirt_s\twall_ms\tscript_ms\tlava\tdraws\tobjects")
	print("[재연] %s · 글자 %d개 · %.0ffps · 재기 %.1f~%.1f초" % [args.replay, lines.size(), fps, (t_start - lines[0][0]) / 1000.0, (t_end - lines[0][0]) / 1000.0])


# --census (W15): 보이는 3D 물체를 무리별로 (가장 가까운 스크립트 붙은 조상 + 노드 이름 앞부분) 세어 많은 순서 — 대기실·판 물체 수 줄이기 근거.
#   [무리, 물체 수, 외곽선 다음 패스 있는 수, 삼각형 (메시 표면 색인/3 × MultiMesh 보이는 수)] + 뷰포트 (SubViewport 갱신 모드·크기)
static func census(root: Node) -> void:
	var rows := {}
	var stack: Array[Node] = [root]
	var vps := []
	var c2d := {}
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is Viewport:
			var vp := n as Viewport
			var ri := func(ty: int, what: int) -> int: return vp.get_render_info(ty, what)
			var V := Viewport.RENDER_INFO_TYPE_VISIBLE
			var SH := Viewport.RENDER_INFO_TYPE_SHADOW
			var CV := Viewport.RENDER_INFO_TYPE_CANVAS
			var D := Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME
			var O := Viewport.RENDER_INFO_OBJECTS_IN_FRAME
			var P := Viewport.RENDER_INFO_PRIMITIVES_IN_FRAME
			var info := "3D 그리기 %d + 그림자 %d + 2D %d · 물체 %d + %d + 2D %d · 삼각형 %d + %d + 2D %d" % [ri.call(V, D), ri.call(SH, D), ri.call(CV, D), ri.call(V, O), ri.call(SH, O), ri.call(CV, O), ri.call(V, P), ri.call(SH, P), ri.call(CV, P)]
			if n is SubViewport:
				var sv := n as SubViewport
				vps.append("%s %s %s (%s)" % [sv.name, sv.size, ["off", "once", "visible", "parent", "always"][sv.render_target_update_mode], info])
			else:
				vps.append("창 %s (%s)" % [vp.get_visible_rect().size, info])
		if n is Node3D and not (n as Node3D).is_visible_in_tree():
			continue
		if n is CanvasItem and not (n as CanvasItem).is_visible_in_tree():
			continue
		for c in n.get_children():
			stack.append(c)
		if n is CanvasItem:
			var a2: Node = n.get_parent()
			while a2 != null and a2.get_script() == null:
				a2 = a2.get_parent()
			var k2 := "2D %s/%s" % [a2.get_script().resource_path.get_file() if a2 != null else "-", n.get_class()]
			c2d[k2] = int(c2d.get(k2, 0)) + 1
		if not (n is GeometryInstance3D):
			continue
		var gi := n as GeometryInstance3D
		var a: Node = n
		while a != null and a.get_script() == null:
			a = a.get_parent()
		var key := "%s/%s" % [a.get_script().resource_path.get_file() if a != null else "-", String(n.name).rstrip("0123456789@_").left(18)]
		var r: Array = rows.get(key, [0, 0, 0])
		r[0] += 1
		var tris := 0
		var mesh: Mesh = null
		var k := 1
		if n is MeshInstance3D:
			mesh = (n as MeshInstance3D).mesh
		elif n is MultiMeshInstance3D and (n as MultiMeshInstance3D).multimesh != null:
			var mm := (n as MultiMeshInstance3D).multimesh
			mesh = mm.mesh
			k = mm.visible_instance_count if mm.visible_instance_count >= 0 else mm.instance_count
		if mesh != null:
			for si in mesh.get_surface_count():
				var arr := mesh.surface_get_arrays(si) if mesh is ArrayMesh or mesh is PrimitiveMesh else []
				if arr.size() > Mesh.ARRAY_INDEX and arr[Mesh.ARRAY_INDEX] != null and (arr[Mesh.ARRAY_INDEX] as PackedInt32Array).size() > 0:
					tris += (arr[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
				elif arr.size() > 0 and arr[Mesh.ARRAY_VERTEX] != null:
					tris += (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
				var sm: Material = gi.material_override if gi.material_override else mesh.surface_get_material(si)
				if sm != null and sm.next_pass != null:
					r[1] += 1
		r[2] += tris * k
		rows[key] = r
	var list := []
	for key in rows:
		list.append([key] + rows[key])
	list.sort_custom(func(x, y): return x[1] > y[1])
	var tot := [0, 0, 0]
	for row in list:
		for i in 3:
			tot[i] += row[i + 1]
	print("[재연] 물체 무리 (보이는 GeometryInstance3D %d · 외곽선 패스 %d · 삼각형 %d):" % tot)
	for row in list.slice(0, 40):
		print("  %-40s %4d · 외곽선 %4d · 삼각형 %7d" % row)
	var l2 := c2d.keys()
	l2.sort_custom(func(x, y): return c2d[x] > c2d[y])
	var t2 := 0
	for k2 in l2:
		t2 += c2d[k2]
	print("[재연] 보이는 2D 노드 %d: %s" % [t2, ", ".join(l2.slice(0, 30).map(func(k2): return "%s %d" % [k2, c2d[k2]]))])
	print("[재연] viewport:\n  %s" % "\n  ".join(vps))


# "outline=false,gfx=medium,fov=80" → {outline: false, gfx: "medium", fov: 80.0}
static func parse_sets(txt: String) -> Dictionary:
	var out := {}
	for kv in txt.split(",", false):
		var i := kv.find("=")
		if i <= 0:
			continue
		var v := kv.substr(i + 1)
		out[kv.substr(0, i)] = true if v == "true" else (false if v == "false" else (float(v) if v.is_valid_float() else v))
	return out


func _apply_sets(sets: Dictionary) -> void:
	for k in sets:
		View.settings[k] = sets[k]
		View.changed.emit(k)
	print("[재연] 설정 %s" % str(sets))


func _physics_process(_d: float) -> void:
	if measuring:
		phys_ticks += 1


func _process(_d: float) -> void:
	if Net.replay.is_empty() or done:
		return
	var v: float = Net.virt
	# 재기 전까지는 크게 건너뜀 (대기실·판 시작) — 단 재기 2초 전부터는 제 빠르기 (몸·효과가 자리 잡게)
	if v < t_start - 2000.0:
		Net.virt = minf(t_start - 2000.0, v + 250.0)
		return
	Net.virt = v + 1000.0 / fps
	if not measuring and Net.virt >= t_start:
		measuring = true
		_bake0 = _bakes()
		if args.has("bake-why"):
			preload("res://ui/baked_panel.gd").why_on = true
		if args.has("replay-open"): # W16: 재기 전에 창을 띄움 (settings — 설정 창)
			var ui = get_tree().root.find_children("*", "CanvasLayer", true, false).filter(func(n): return n.get("settings") is Control)
			if not ui.is_empty():
				ui[0].get(str(args["replay-open"])).visible = true
		Prof.reset()
	if measuring:
		frames += 1
		_frame_line()
	if measuring and Net.virt >= t_end:
		done = true
		measuring = false
		_report()


# 지난 프레임 한 줄 (이 노드가 맨 먼저 돌아 지난 _process 부터 지금까지 = 지난 프레임 전체: 스크립트·그리기·셰이더 컴파일)
func _frame_line() -> void:
	var now := Time.get_ticks_usec()
	if flog != null and _wall0 > 0:
		var lava: bool = Store.state.get("lava", {}).get("active", false) if Store.state is Dictionary else false
		flog.store_line("%d\t%.3f\t%.2f\t%.2f\t%d\t%d\t%d" % [frames - 1, (Net.virt - t_start) / 1000.0, (now - _wall0) / 1000.0, _last_s_us / 1000.0, int(lava), Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)])
	_wall0 = now


# 느린 프레임 (튐) 이 무엇 때문인지: 이번 프레임 구간 합 - 지난 프레임 구간 합
func _spike(us: int) -> void:
	var cur := {}
	for k in Prof.sums:
		cur[k] = Prof.sums[k][0]
	if spikes.size() < 6 or us > spikes[-1][0]:
		var rows := []
		for k in cur:
			var dlt: int = cur[k] - int(_prev_sums.get(k, 0))
			if dlt > 200:
				rows.append([k, dlt])
		rows.sort_custom(func(a, b): return a[1] > b[1])
		spikes.append([us, (Net.virt - t_start) / 1000.0, ", ".join(rows.slice(0, 5).map(func(r): return "%s %.1f" % [r[0], r[1] / 1000.0]))])
		spikes.sort_custom(func(a, b): return a[0] > b[0])
		spikes = spikes.slice(0, 6)
	_prev_sums = cur


# (W16) 구운 판 (ui/baked_panel.gd) 이 다시 구운 수 — 재는 동안 (가상 시간) 초당
var _bake0 := {}


func _bakes() -> Dictionary:
	var out := {}
	for b in get_tree().root.find_children("Baked_*", "", true, false):
		out[str(b.name)] = int(b.get("renders"))
	return out


func _report() -> void:
	if flog != null:
		flog.close()
	var n := maxi(1, frames)
	var b1 := _bakes()
	if not b1.is_empty():
		var secs := maxf(0.001, (t_end - t_start) / 1000.0)
		print("[재연] 구운 판 다시 그림 (초당, 가상 시간): %s" % ", ".join(b1.keys().map(func(k): return "%s %.1f" % [k, (b1[k] - int(_bake0.get(k, 0))) / secs])))
		if args.has("bake-why"):
			for b in get_tree().root.find_children("Baked_*", "", true, false):
				var w: Dictionary = b.get("why")
				var ks := w.keys()
				ks.sort_custom(func(x, y): return w[x] > w[y])
				print("[재연] %s 다시 그린 이유: %s" % [b.name, ", ".join(ks.slice(0, 8).map(func(x): return "%s %d" % [x, w[x]]))])
	var s_ms := script_us / 1000.0 / n
	var tick_ms := phys_us / 1000.0 / maxf(1, phys_ticks)
	var ticks_per_frame := 60.0 / fps # 실제 기계에서 물리 60Hz
	var sorted := frame_us.duplicate()
	sorted.sort()
	var med: float = sorted[sorted.size() / 2] / 1000.0 if not sorted.is_empty() else 0.0
	var p99: float = sorted[mini(sorted.size() - 1, int(sorted.size() * 0.99))] / 1000.0 if not sorted.is_empty() else 0.0
	print("[재연] 결과: 프레임 %d · 스크립트 %.2fms/프레임 (50%% %.2f · 99%% %.2f) · 물리 %.2fms/틱 (%d틱) · %.0ffps 환산 %.2fms" % [frames, s_ms, med, p99, tick_ms, phys_ticks, fps, s_ms + tick_ms * ticks_per_frame])
	if Prof.on:
		print("[재연] 구간 (프레임당): %s" % Prof.report(n))
		for sp in spikes:
			print("[재연] 느린 프레임 %.1fms (재기 %.2f초): %s" % [sp[0] / 1000.0, sp[1], sp[2]])
	if args.has("replay-render"):
		print("[재연] 그리기 %d · 물체 %d · 삼각형 %d · 영상 메모리 %.1fMB" % [Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME), Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME), Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0])
	if args.has("census"):
		census(get_tree().root)
		await UiCensus.run(get_tree(), "재연 %.1f초" % ((Net.virt - t_start) / 1000.0))
	if args.has("ui-check"): # W16: 구운 판 위 입력 (core/ui_check.gd)
		await preload("res://core/ui_check.gd").run(get_tree())
	if args.has("shot") and DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		img.save_png(str(args.shot))
		print("[재연] 화면 저장 %s" % args.shot)
	get_tree().quit(0)
