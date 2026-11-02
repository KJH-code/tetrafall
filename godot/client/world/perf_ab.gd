# 성능·모습 짝 비교 (W5 웹 성능, 2026-11-02): 판 그리기 설정 하나를 한 판 안에서 켜고 끄며 잼. world.gd 가 옵션이 있을 때만 붙임.
# 기계를 다른 일과 나눠 쓰고 판마다 장면 (카메라·블록·위험 높이) 이 달라 따로 잰 두 판의 평균은 ±15% 흔들림 → 같은 판에서 번갈아 재야 작은 차이가 보임.
#   --ab <종류>      판 중 --ab-period 초 (기본 2) 마다 A (그대로)·B (바꿈) 번갈아, 바꾼 뒤 2 프레임 버리고 프레임 시간 (벽시계) 평균을 나눠 셈.
#                   --ab-warm 초 (기본 8) 뒤부터 --ab-secs 초 (기본 40) → 콘솔 'AB <종류>: A …ms · B …ms · B/A …'
#   --abshot <종류>  판 중 --abshot-at 초들 (쉼표, 기본 6,14,22) 에 시간을 멈춘 채 (force_draw, 흐른 시간 0) A·B 를 같은 프레임으로 그려 화소 차를 셈.
#                   PC 판이면 --abshot-dir 에 <종류>-<번호>-A/B.png. --abshot-quit 이면 다 찍고 끝냄. 'none' 은 아무것도 안 바꿈 (방법 확인: 차 0)
# 종류: msaa0 (4× ↔ 끔) · msaa2 (4× ↔ 2×) · shadow (해 그림자 끔) · outline (외곽선 next_pass 뗌) · light (판 빛 끔) · ui · sky · hazard · scenery ·
#   bodies · grid · pieces (그 노드 숨김 — 숨긴 뒤에 보이는 것 (위험 바다·하늘) 값이 같이 들어감) · hide:<노드 이름>
# 웹은 주소 뒤 ?ab=msaa0&ab-secs=40 처럼 (tools/perf_ab.cjs 가 열고 줄을 받음)
extends Node

const C := preload("res://core/config.gd")

var args := {}
var world: Node3D
var state := 0 # 0 = A, 1 = B
var since := 0.0
var skip := 0
var last_us := 0
var sums := [0.0, 0.0]
var counts := [0, 0]
var start := -1.0
var done := false
var saved := {} # 뗀 외곽선 재질 → next_pass
var shot_t0 := -1.0
var shot_i := 0


# 명령줄 (-- 뒤) + 웹 주소 ?키=값 (값 없으면 true)
static func read_args() -> Dictionary:
	var out := {}
	var list := OS.get_cmdline_user_args()
	for i in list.size():
		if list[i].begins_with("--"):
			out[list[i].substr(2)] = list[i + 1] if i + 1 < list.size() and not list[i + 1].begins_with("--") else true
	if OS.has_feature("web"):
		var q = JSON.parse_string(str(JavaScriptBridge.eval("JSON.stringify(Object.fromEntries(new URLSearchParams(location.search)))", true)))
		if typeof(q) == TYPE_DICTIONARY:
			for k in q:
				out[k] = q[k] if str(q[k]) != "" else true
	return out


static func wanted(a: Dictionary) -> bool:
	return a.has("ab") or a.has("abshot")


func _process(_d: float) -> void:
	var now := Time.get_ticks_usec() / 1000.0
	if args.has("ab"):
		_tick(now)
	if args.has("abshot"):
		_shot_tick(now)


func _tick(now: float) -> void:
	if done or Store.phase() != "playing":
		last_us = 0
		return
	var us := Time.get_ticks_usec()
	if start < 0.0:
		start = now + float(args.get("ab-warm", 8)) * 1000.0
		since = now
	if now < start:
		last_us = us
		return
	if last_us > 0:
		if skip > 0:
			skip -= 1
		else:
			sums[state] += (us - last_us) / 1000.0
			counts[state] += 1
	last_us = us
	if now - since >= float(args.get("ab-period", 2)) * 1000.0:
		since = now
		state = 1 - state
		skip = 2
		apply(str(args.ab), state == 1)
	if now - start >= float(args.get("ab-secs", 40)) * 1000.0:
		done = true
		apply(str(args.ab), false)
		var a: float = sums[0] / maxf(1, counts[0])
		var b: float = sums[1] / maxf(1, counts[1])
		print("AB %s: A %.1fms (%d) · B %.1fms (%d) · B/A %.3f" % [args.ab, a, counts[0], b, counts[1], b / maxf(0.001, a)])


# 종류별로 B (b = true) 또는 A 로
func apply(kind: String, b: bool) -> void:
	match kind:
		"none":
			pass
		"msaa0":
			get_viewport().msaa_3d = Viewport.MSAA_DISABLED if b else Viewport.MSAA_4X
		"msaa2":
			get_viewport().msaa_3d = Viewport.MSAA_2X if b else Viewport.MSAA_4X
		"shadow":
			var sun := world.find_child("Sun", true, false)
			if sun != null:
				sun.shadow_enabled = not b
		"light":
			if world.light_fx.has_method("set_preset"):
				world.light_fx.set_preset("off" if b else C.GAME_LIGHT)
		"ui":
			var ui := get_tree().root.find_child("UI", true, false)
			if ui != null:
				ui.visible = not b
		"sky":
			var env := world.get_node_or_null("G3Env")
			if env != null:
				env.get_node("Sky").visible = not b
		"hazard", "scenery", "bodies", "pieces":
			(world.get(kind + ("_view" if kind in ["hazard", "pieces"] else "")) as Node3D).visible = not b
		"grid":
			world.grid_view.visible = not b
		"outline":
			if b:
				saved = {}
				_strip_outline(world)
			else:
				for m in saved:
					m.next_pass = saved[m]
		_:
			if kind.begins_with("hide:"):
				for n in world.find_children(kind.substr(5), "", true, false):
					n.visible = not b


func _strip_outline(n: Node) -> void:
	var mats := []
	if n is GeometryInstance3D:
		mats.append((n as GeometryInstance3D).material_override)
		if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
			for i in (n as MeshInstance3D).mesh.get_surface_count():
				mats.append((n as MeshInstance3D).mesh.surface_get_material(i))
				mats.append((n as MeshInstance3D).get_surface_override_material(i))
		if n is MultiMeshInstance3D and (n as MultiMeshInstance3D).multimesh != null and (n as MultiMeshInstance3D).multimesh.mesh != null:
			var mm := (n as MultiMeshInstance3D).multimesh.mesh
			for i in mm.get_surface_count():
				mats.append(mm.surface_get_material(i))
	for m in mats:
		if m is Material and m.next_pass != null and not saved.has(m):
			saved[m] = m.next_pass
			m.next_pass = null
	for c in n.get_children():
		_strip_outline(c)


# 시간 안 흐르게 한 프레임 그려 판 화면 그림을 받음 (같은 장면을 A·B 로 두 번 — 처음 한 번은 바뀐 버퍼·셰이더 준비)
func _grab() -> Image:
	RenderingServer.force_draw(false, 0.0)
	RenderingServer.force_draw(false, 0.0)
	return get_viewport().get_texture().get_image()


func _shot_tick(now: float) -> void:
	if Store.phase() != "playing":
		return
	if shot_t0 < 0.0:
		shot_t0 = now
	var ats := str(args.get("abshot-at", "6,14,22")).split(",")
	if shot_i >= ats.size() or now - shot_t0 < float(ats[shot_i]) * 1000.0:
		return
	var kind := str(args.abshot)
	var a := _grab()
	apply(kind, true)
	var b := _grab()
	apply(kind, false)
	var d := diff(a, b)
	print("ABSHOT %s #%d: 다른 화소 %.3f%% (>8/255: %.3f%%) · 평균 차 %.3f/255 · 최대 %d" % [kind, shot_i, d[0], d[1], d[2], d[3]])
	if not OS.has_feature("web"):
		var dir := str(args.get("abshot-dir", OS.get_user_data_dir()))
		a.save_png("%s/%s-%d-A.png" % [dir, kind, shot_i])
		b.save_png("%s/%s-%d-B.png" % [dir, kind, shot_i])
	shot_i += 1
	if shot_i >= ats.size() and args.has("abshot-quit"):
		get_tree().quit(0)


# 두 그림 화소 차: [다른 화소 %, 8/255 넘게 다른 화소 %, 평균 차 (/255, RGB), 최대 차]
static func diff(a: Image, b: Image) -> Array:
	a.convert(Image.FORMAT_RGB8)
	b.convert(Image.FORMAT_RGB8)
	var pa := a.get_data()
	var pb := b.get_data()
	var n := mini(pa.size(), pb.size()) / 3
	var any := 0
	var big := 0
	var sum := 0
	var mx := 0
	for i in n:
		var m := 0
		for c in 3:
			var v := absi(pa[i * 3 + c] - pb[i * 3 + c])
			sum += v
			m = maxi(m, v)
		if m > 0:
			any += 1
			if m > 8:
				big += 1
			mx = maxi(mx, m)
	return [100.0 * any / maxf(1, n), 100.0 * big / maxf(1, n), float(sum) / maxf(1, n * 3), mx]
