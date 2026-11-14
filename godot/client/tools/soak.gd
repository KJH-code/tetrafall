# 스트레스·장시간 시험 (W50): main.gd 가 --soak <시나리오> 로 붙이는 노드. 소프트웨어 렌더 xvfb 에서 도는 자동 조종 시험의 '객체·메모리·로그' 추세를 찍음.
# 사용 (서버 필요 — tools/soak.mjs 가 서버·고도·표를 다 함): godot --path godot/client -- --server ws://127.0.0.1:3000 --soak <시나리오> [--soak-n N] [--bots N] [--soak-sample 초]
# 시나리오: rounds (한 방에서 N판 연속) · enter (방 만들기→나가기 N회, 5번에 한 번은 판 시작 중·입장 직후 나가기) · chars (대기실 8명 방에서 캐릭터 N번 바꾸기) ·
#   resize (창 크기·UI 크기·화질 N번 바꾸기, 대기실 + 판 중) · modes (연습·튜토리얼·생존·마스터·킬·팀전·체력전·하늘 계단을 L바퀴) · reconnect (판 중·대기실·카운트다운에 연결을 N번 끊음) · idle
# 출력: "[soak] <시나리오> <표시 이름> ..." 한 줄씩 (rss·객체·노드·고아·자원·정적 메모리·영상 메모리·최악 프레임·경고/에러 수·정적 상태 크기) — tools/soak.mjs 가 표로 만듦. 끝은 "[soak] <시나리오> DONE rc=…"
extends Node

const PSched := preload("res://world/prewarm_sched.gd")
const Motion_ := preload("res://chars/ext_motion.gd")
const TexPre := preload("res://chars/tex_prefetch.gd")
const EntryGate := preload("res://core/entry_gate.gd")
const CHARS := ["tank", "ninja", "builder", "hook", "hunter", "cannon", "berserker", "bard"]
const SIZES := [Vector2i(1280, 720), Vector2i(960, 540), Vector2i(1920, 1080), Vector2i(800, 600), Vector2i(1600, 900), Vector2i(1024, 768)]
const SCALES := ["auto", 0.8, 1.0, 1.25, 1.5, 2.0]
const GFXS := ["auto", "high", "medium", "low"]

var args := {}
var scen := "rounds"
var n := 10
var bots := 3
var t0 := 0.0
var frame_max := 0.0 # 마지막 표본 이후 최악 프레임 (ms, 벽시계)
var proc_max := 0.0 # 같은 때 TIME_PROCESS 최악 (ms)
var frames := 0
var errs := 0
var warns := 0
var err_seen := {}
var logger = null
var _last_us := 0
var rounds_done := 0
var _sample_next := 0.0
var failed := ""


class ErrLog extends Logger:
	var owner = null
	var lock := Mutex.new()

	func _log_error(function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool, error_type: int, _backtraces: Array) -> void:
		lock.lock()
		if owner != null:
			if error_type == ERROR_TYPE_WARNING:
				owner.warns += 1
			else:
				owner.errs += 1
			var k := "%s:%d %s" % [file.get_file(), line, (rationale if rationale != "" else code).left(60)]
			owner.err_seen[k] = int(owner.err_seen.get(k, 0)) + 1
		lock.unlock()


func _ready() -> void:
	scen = str(args.get("soak", "rounds"))
	n = int(args.get("soak-n", 10))
	bots = int(args.get("bots", 3))
	t0 = Time.get_ticks_msec() * 0.001
	logger = ErrLog.new()
	logger.owner = self
	OS.add_logger(logger)
	_p("시작 n=%d bots=%d 화면 %s %s" % [n, bots, DisplayServer.get_name(), RenderingServer.get_video_adapter_name()])
	_run.call_deferred()


func _exit_tree() -> void:
	if logger != null:
		logger.owner = null
		OS.remove_logger(logger)
		logger = null


func _p(t: String) -> void:
	print("[soak] %s %s" % [scen, t])


func _process(_d: float) -> void:
	var us := Time.get_ticks_usec()
	if _last_us > 0:
		frame_max = maxf(frame_max, (us - _last_us) / 1000.0)
	_last_us = us
	frames += 1
	proc_max = maxf(proc_max, Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
	var every := float(args.get("soak-sample", 0))
	var el := Time.get_ticks_msec() * 0.001 - t0
	if every > 0.0 and el >= _sample_next:
		_sample_next = el + every
		sample("t")


static func rss_mb() -> float:
	var f := FileAccess.open("/proc/self/status", FileAccess.READ)
	if f == null:
		return -1.0
	while not f.eof_reached():
		var l := f.get_line()
		if l.begins_with("VmRSS:"):
			return float(l.split(" ", false)[1]) / 1024.0
	return -1.0


# 정적 스케줄러·캐시 크기 (선형으로 늘면 누수 후보)
func statics() -> String:
	var g3 = load("res://shaders/g3.gd")
	return "sched %d/%d motb %d g3 %d/%d texreq %d gate %d" % [PSched.main.tasks.size(), PSched.main.finished.size(), Motion_.bodies.size(), g3._mats.size(), g3._outlined.size(), TexPre._req.size(), EntryGate.log.size()]


# W51: 트리에서 닿는 자원을 클래스별로 셈 (노드 속성 → 자원 → 하위 자원, 한 번씩). 총 자원 수 (OBJECT_RESOURCE_COUNT) 와 뺀 값이 '트리 밖에 살아 있는 자원'
# (정적 캐시·누수 후보). 끄기·켜기 = --soak-res (기본 꺼짐 — 걷는 데 수백 ms)
func res_census() -> Dictionary:
	var seen := {}
	var cls := {}
	var stack: Array = [get_tree().root]
	while not stack.is_empty():
		var o = stack.pop_back()
		if o == null or seen.has(o.get_instance_id()):
			continue
		seen[o.get_instance_id()] = true
		if o is Resource and (o as Resource).resource_path.contains("::"): # OBJECT_RESOURCE_COUNT 는 경로 있는 (캐시에 든) 자원만 셈 — 경로 없는 코드 자원은 안 셈
			var rp: String = (o as Resource).resource_path
			var k: String = o.get_class()
			if rp.begins_with("res://"):
				var parts := rp.trim_prefix("res://").split("/")
				k += "@" + "/".join(parts.slice(0, mini(2, parts.size() - 1))) if parts.size() > 1 else "@" + rp
			else:
				k += "@local"
			cls[k] = int(cls.get(k, 0)) + 1
		if o is Node:
			for c in (o as Node).get_children(true):
				stack.append(c)
		for pr in o.get_property_list():
			if int(pr["type"]) == TYPE_OBJECT and (int(pr["usage"]) & PROPERTY_USAGE_STORAGE or int(pr["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE):
				var v = o.get(pr["name"])
				if v is Object and not (v is Node and not (o is Node)) and not (v is Node and v.get_parent() != null and o is Node and v != o.get_parent()):
					stack.append(v)
			elif int(pr["type"]) == TYPE_ARRAY and (int(pr["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE):
				for v in o.get(pr["name"]):
					if v is Resource:
						stack.append(v)
	return cls


var _res_files: PackedStringArray = []
var _res_prev := {}


func _scan_files(dir: String) -> void:
	for f in DirAccess.get_files_at(dir):
		if not f.ends_with(".import") and not f.ends_with(".uid") and not f.ends_with(".md") and not f.ends_with(".cjs") and not f.ends_with(".mjs") and not f.ends_with(".sh"):
			_res_files.append(dir.path_join(f))
	for d in DirAccess.get_directories_at(dir):
		if d != ".godot" and d != "tests" and not d.begins_with("."):
			_scan_files(dir.path_join(d))


# 캐시에 든 자원 이름을 세서 지난 표본과 비교 (새로 캐시된 경로를 이름으로 찍음). 파일 → ResourceLoader.has_cached, 하위 자원 (res://x.glb::Mesh) 은 트리에서 닿는 것만
func res_line(tag: String) -> void:
	if _res_files.is_empty():
		_scan_files("res://")
	var cur := {}
	for f in _res_files:
		if ResourceLoader.has_cached(f):
			var r = ResourceLoader.get_cached_ref(f)
			cur[f] = r.get_class() if r != null else "?"
	var reach := res_census()
	var sub := 0
	for k in reach:
		sub += int(reach[k])
	var added := []
	for f in cur:
		if not _res_prev.has(f):
			added.append("%s(%s)" % [f.trim_prefix("res://"), cur[f]])
	var gone := 0
	for f in _res_prev:
		if not cur.has(f):
			gone += 1
	_res_prev = cur
	var bydir := {}
	for f in cur:
		var pr: PackedStringArray = f.trim_prefix("res://").split("/")
		var k2 := "/".join(pr.slice(0, mini(2, pr.size() - 1))) if pr.size() > 1 else "(root)"
		bydir[k2] = int(bydir.get(k2, 0)) + 1
	var ds := bydir.keys()
	ds.sort_custom(func(a, b): return bydir[a] > bydir[b])
	var dp := []
	for k3 in ds.slice(0, 10):
		dp.append("%s=%d" % [k3, bydir[k3]])
	_p("%s rescache files=%d sub(reach)=%d total=%d 새 %d 빠짐 %d | 경로별 %s" % [tag, cur.size(), sub, int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)), added.size(), gone, " ".join(dp)])
	if not added.is_empty() and added.size() <= 40:
		_p("%s resnew %s" % [tag, " ".join(added)])
	elif not added.is_empty():
		_p("%s resnew %s ... (%d개 더)" % [tag, " ".join(added.slice(0, 40)), added.size() - 40])


func sample(tag: String) -> void:
	if args.has("soak-res") and tag != "t":
		res_line(tag)
	var line := "%s t=%.0f rss=%.0f obj=%d node=%d orph=%d res=%d smem=%.1f vmem=%.1f fmax=%.0f pmax=%.0f err=%d warn=%d | %s | %s/%s win=%s" % [
		tag, Time.get_ticks_msec() * 0.001 - t0, rss_mb(), Performance.get_monitor(Performance.OBJECT_COUNT), Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
		Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT), Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT),
		Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0, Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0,
		frame_max, proc_max, errs, warns, statics(), "방" if Store.in_room() else "메뉴", Store.phase(), str(get_window().size)]
	_p(line)
	frame_max = 0.0
	proc_max = 0.0


func wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout


func until(fn: Callable, timeout := 30.0) -> bool:
	var s := Time.get_ticks_msec()
	while not fn.call():
		if Time.get_ticks_msec() - s > timeout * 1000.0:
			return false
		await get_tree().process_frame
	return true


func in_phase(ph: String) -> bool:
	return Store.in_room() and Store.phase() == ph


func fail(why: String) -> void:
	failed = why
	_p("실패 %s" % why)


func finish() -> void:
	sample("끝")
	for k in err_seen:
		_p("로그 %d번 %s" % [err_seen[k], k])
	var rc := 0 if failed == "" else 3
	_p("DONE rc=%d errs=%d warns=%d rounds=%d" % [rc, errs, warns, rounds_done])
	await get_tree().process_frame
	get_tree().quit(rc)


func open_room(nick := "soak") -> bool:
	if not await until(func(): return Net.is_open(), 20.0):
		fail("접속 안 됨")
		return false
	Store.create_room("", nick)
	if not await until(func(): return Store.in_room(), 15.0):
		fail("방 만들기 안 옴")
		return false
	return true


func leave_room() -> void:
	Store.leave()
	if not await until(func(): return not Store.in_room(), 10.0):
		fail("방 나가기 안 옴 (연결 %s · 단계 %s · 창 %s · 크기 %.2f)" % [Net.is_open(), Store.phase(), str(get_window().size), get_window().content_scale_factor])


func add_bots(k: int) -> void:
	for i in k:
		Store.send_room({"type": "addBot"})
	await until(func(): return Store.in_room() and Store.state.get("players", []).size() >= k + 1, 10.0)


func play_once(secs := 8.0) -> bool:
	if not await until(func(): return in_phase("lobby") and Store.state.get("canStart", false), 15.0):
		fail("시작 못 함 (canStart)")
		return false
	Store.send_room({"type": "start"})
	if not await until(func(): return in_phase("playing"), 25.0):
		fail("playing 안 됨")
		return false
	await wait(secs)
	return true


func _run() -> void:
	match scen:
		"rounds": await _rounds()
		"enter": await _enter()
		"chars": await _chars()
		"resize": await _resize()
		"modes": await _modes()
		"reconnect": await _reconnect()
		"idle": await _idle()
		_:
			fail("모르는 시나리오 " + scen)
	await finish()


# ---- 시나리오 ----
func _idle() -> void: # 메뉴에서 가만히 (스케줄러 미리 하기·미리 읽기만)
	for i in n:
		await wait(float(args.get("soak-step", 5)))
		sample("idle%d" % i)


func _rounds() -> void:
	if not await open_room():
		return
	await add_bots(bots)
	sample("방")
	var step := float(args.get("soak-over", 3))
	for r in n:
		if failed != "":
			break
		if not await until(func(): return in_phase("lobby") or in_phase("over"), 60.0):
			fail("판 사이 상태 이상 %s" % Store.phase())
			break
		Store.send_room({"type": "start"})
		if not await until(func(): return in_phase("playing"), 30.0):
			fail("playing 안 됨 (판 %d)" % r)
			break
		if not await until(func(): return in_phase("over"), 240.0):
			fail("판 %d 안 끝남" % r)
			break
		await wait(step) # 결과 화면
		rounds_done += 1
		sample("판%d" % (r + 1))
	await leave_room()


func _enter() -> void:
	for i in n:
		if failed != "":
			break
		if not await open_room():
			break
		match i % 5:
			1: # 입장 직후 바로 나가기 (입장 도중 나가기)
				await wait(0.15)
			2: # 판 시작 직후 (카운트다운) 나가기
				await add_bots(2)
				Store.send_room({"type": "start"})
				await until(func(): return Store.phase() in ["countdown", "playing"], 10.0)
				await wait(0.5)
			4: # 판 중 나가기
				await add_bots(2)
				if not await play_once(3.0):
					break
			_:
				await wait(2.0)
		await leave_room()
		await wait(1.2)
		if (i + 1) % 5 == 0:
			sample("입장%d" % (i + 1))


func _chars() -> void:
	if not await open_room():
		return
	await add_bots(7)
	await wait(2.0)
	sample("처음")
	for i in n:
		Store.send_room({"type": "setChar", "char": CHARS[i % CHARS.size()]})
		await wait(float(args.get("soak-step", 1.0)))
		if (i + 1) % 10 == 0:
			sample("변경%d" % (i + 1))
	await leave_room()


func _cycle(i: int) -> void:
	get_window().size = SIZES[i % SIZES.size()]
	View.set_setting("uiScale", SCALES[(i / 2) % SCALES.size()])
	if i % 3 == 0:
		View.set_setting("gfx", GFXS[(i / 3) % GFXS.size()])
	if i % 7 == 0:
		View.set_setting("adaptRes", i % 2 == 0)


func _resize() -> void:
	if not await open_room():
		return
	await add_bots(bots)
	await wait(2.0)
	sample("처음")
	for i in n: # 대기실
		_cycle(i)
		await wait(float(args.get("soak-step", 1.0)))
		if (i + 1) % 10 == 0:
			sample("대기실%d" % (i + 1))
	if not await play_once(2.0):
		return
	for i in n: # 판 중
		_cycle(i + 3)
		await wait(float(args.get("soak-step", 1.0)))
		if (i + 1) % 10 == 0:
			sample("판%d" % (i + 1))
		if not in_phase("playing"):
			_p("판 중 단계 끝남 %d번째 (단계 %s)" % [i, Store.phase()])
			break
	await until(func(): return in_phase("over"), 240.0)
	sample("판끝")
	await wait(3.0)
	get_window().size = SIZES[0]
	View.set_setting("gfx", "auto")
	View.set_setting("uiScale", "auto")
	View.set_setting("adaptRes", true)
	await leave_room()


func _modes() -> void:
	var seq := ["practice", "tutorial", "survival", "master", "kills", "team", "hp", "sky"]
	for loop in n:
		for mode in seq:
			if failed != "":
				return
			if not await until(func(): return Net.is_open(), 20.0):
				fail("접속 안 됨")
				return
			if mode in ["practice", "tutorial"]:
				Net.send({"type": mode, "nick": "soak", "char": CHARS[loop % CHARS.size()]})
				if not await until(func(): return Store.in_room(), 15.0):
					fail("%s 방 안 열림" % mode)
					return
				if mode == "practice":
					Store.send_room({"type": "dummyAdd"})
				else:
					Store.send_room({"type": "tutorialSkip"})
				await wait(4.0)
				if mode == "practice":
					Store.send_room({"type": "setChar", "char": CHARS[(loop + 3) % CHARS.size()]}) # 판 중 캐릭터 바꾸기
					await wait(2.0)
			else:
				if not await open_room():
					return
				await add_bots(bots)
				match mode:
					"master", "kills", "survival":
						Store.send_room({"type": "setMode", "mode": mode})
					"team":
						Store.send_room({"type": "teamMode", "on": true})
					"hp":
						Store.send_room({"type": "hpMode", "on": true})
					"sky":
						Store.send_room({"type": "skyStairs", "on": true})
				await wait(1.0)
				if not await play_once(float(args.get("soak-play", 8))):
					return
			await leave_room()
			await wait(1.0)
		sample("바퀴%d" % (loop + 1))


func _reconnect() -> void:
	if not await open_room():
		return
	await add_bots(bots)
	await wait(2.0)
	sample("처음")
	var dropped := 0
	for i in n:
		match i % 4:
			1: # 카운트다운 중
				Store.send_room({"type": "start"})
				await until(func(): return Store.phase() == "countdown", 8.0)
			2: # 판 중
				if Store.phase() == "countdown":
					await until(func(): return Store.phase() == "playing", 10.0)
				else:
					Store.send_room({"type": "start"})
					await until(func(): return Store.phase() == "playing", 20.0)
				await wait(3.0)
			3: # 판 끝 근처
				await until(func(): return Store.phase() in ["over", "lobby"], 240.0)
		Net.drop_for_test()
		dropped += 1
		var rej := await until(func(): return Net.is_open() and Store.in_room() and Store.state.has("players"), 20.0)
		if not rej:
			fail("재접속 안 됨 (%d번째)" % dropped)
			break
		await wait(3.0)
		sample("끊김%d" % dropped)
	await leave_room()
