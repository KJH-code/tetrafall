# W44 모션 QA: 판 중 새 모델 몸 (외부 .glb 4명) 의 뼈·메시를 60Hz 로 표본해 튐 (팝)·떨림·발 미끄러짐·뚫림·늘어남·관절 한계·전환 이음새를 센다.
#   재연:  godot --headless --path godot/client -- --replay <녹화> --replay-secs 60 --replay-warm 0 --fixed-fps 120 --motion-qa <출력 폴더>
#          → <폴더>/motion_qa.json (요약 + 상위 목록) · motion_qa.csv (사건 한 줄씩). 렌더 없이 뼈 포즈·월드 변환만 읽음 — 가상 시계라 기계가 느려도 같은 시뮬 시간.
#   판 중 (재혁 PC): --motion-qa (폴더 없이) = 가벼운 모드 (팝 카운터만) → 한 판 끝에 user://motion_qa.txt 에 '팝 상위 5개' (hitch 로거와 같은 형식)
# 계산은 core/motion_qa_math.gd (순수 — tests/test_motion_qa.gd 가 합성 뼈 열로 시험). 꺼져 있으면 이 노드가 트리에 없어 비용 0.
extends Node

const M := preload("res://core/motion_qa_math.gd")
const Motion_ := preload("res://chars/ext_motion.gd")
const Clips := preload("res://chars/ext_clips.gd")
const Rag_ := preload("res://chars/ragdoll.gd")
const K := preload("res://chars/chars_config.gd")

const FILE := "user://motion_qa.txt"
const STRETCH_EVERY := 6 # 몸 모양 (메시) 검사는 표본 N 번에 한 번
const RAG_MARGIN := 4 # 래그돌이 풀린 뒤 이만큼 표본은 계속 제외
const TOP_KEEP := 40

var args := {}
var out_dir := ""
var light := false
var rec_name := ""
var tracks := {} # 몸 instance id → Track
var next_t := -1.0
var epoch := 0.0 # 재연 첫 글자의 가상 시각 (초) — 사건 시각은 이 기준
var k := 0 # 표본 번호
var agg := {} # 캐릭터 → 집계
var tops := {"pop": [], "slide": [], "pen": [], "stretch": [], "limit": [], "seam": [], "jitter": [], "weapon": [], "flicker": []}
var csv: Array = []
var done := false
var _skin_cache := {} # 캐릭터 → 메시·캡슐·경첩 데이터 (한 번만 만듦)
var _last_phase := ""
var _round_pops: Array = []
var _file: FileAccess = null
var trace: FileAccess = null
var btrace: FileAccess = null
var btrace_bone := ""
var _last_now := -1.0
var trace_pid := -999


func _ready() -> void:
	process_priority = 1000000 # 몸이 다 맞춰진 뒤
	var v = args.get("motion-qa", true)
	out_dir = str(v) if v is String and str(v) != "" else ""
	light = out_dir == ""
	rec_name = str(args.get("replay", "live")).get_file()
	if args.has("qa-bone-trace"):
		btrace_bone = str(args["qa-bone-trace"])
		trace_pid = int(args.get("qa-trace", trace_pid))
		DirAccess.make_dir_recursive_absolute(out_dir)
		btrace = FileAccess.open(out_dir.path_join("btrace.csv"), FileAccess.WRITE)
		btrace.store_line("t,label,move,u,clip,cw,fade_t,clip_t,qx,qy,qz,qw,excl")
	if args.has("qa-trace"): # 확인용: 한 몸 (id) 의 표본별 발 줄 → <폴더>/trace.csv
		trace_pid = int(args["qa-trace"])
		DirAccess.make_dir_recursive_absolute(out_dir)
		trace = FileAccess.open(out_dir.path_join("trace.csv"), FileAccess.WRITE)
		trace.store_line("t,label,clip,cw,side,lift,a_y,t_y,foot_x,foot_z,body_x,body_z")
	if args.has("replay"):
		Motion_.clock = func(): return Net.virt / 1000.0 # 가상 시계 (core/replay.gd 도 같은 값을 꽂음)


func _now() -> float:
	return Motion_.now_s()


func _process(_d: float) -> void:
	if done:
		return
	var now := _now()
	if light:
		_phase_watch()
	if next_t < 0.0:
		next_t = ceilf(now * M.HZ - 1e-6) / M.HZ # 표본 칸은 시계 절대값에 맞춤 (몸이 만들어지는 프레임이 달라도 같은 순간을 잼)
	if now + 1e-6 < next_t:
		return
	if now - _last_now > 0.08 and _last_now >= 0.0: # 재연이 건너뛰는 동안 (시간이 크게 점프) 은 표본 안 함
		for id in tracks.keys():
			tracks[id].reset()
		_last_now = now
		next_t = ceilf((now + 1e-6) * M.HZ) / M.HZ
		return
	_last_now = now
	next_t = ceilf((now + 1e-6) * M.HZ) / M.HZ
	var seen := {}
	for b in Motion_.bodies:
		if not is_instance_valid(b) or b.get("ext") == null or not b.is_inside_tree():
			continue
		var ext = b.ext
		if ext.last_st == null or ext.st_frame < Engine.get_process_frames() - 2:
			continue
		var id: int = b.get_instance_id()
		seen[id] = true
		var t: Track = tracks.get(id)
		if t == null:
			t = Track.new()
			t.q = self
			if not t.setup(b, light):
				continue
			tracks[id] = t
		t.step(now - epoch, k)
	for id in tracks.keys():
		if not seen.has(id):
			tracks[id].reset()
	k += 1


func _phase_watch() -> void:
	var st = get_node_or_null("/root/Store")
	var ph: String = str(st.phase()) if st != null else ""
	if ph != _last_phase:
		if _last_phase == "playing":
			_write_round()
		_last_phase = ph


func _exit_tree() -> void:
	if light and _last_phase == "playing":
		_write_round()


# ---- 가벼운 모드: 한 판 끝에 팝 상위 5개 ----
func _write_round() -> void:
	if _file == null:
		_file = FileAccess.open(FILE, FileAccess.WRITE)
		if _file != null:
			_file.store_line("# 모션 QA %s · 팝 = 뼈 회전이 한 표본 (1/60초) 에 임계 (몸통·팔다리 %.0f°, 손·발·머리 %.0f°) 를 넘음" % [Time.get_datetime_string_from_system(), M.POP_TORSO, M.POP_END])
	if _file == null:
		return
	var n := 0
	for c in agg:
		n += int(agg[c].get("pops", 0))
	var rows: Array = tops["pop"].duplicate()
	rows.sort_custom(func(a, b): return a.sev > b.sev)
	_file.store_line("# ---- 판 요약 (%s): 팝 %d회 ----" % [Time.get_datetime_string_from_system(), n])
	for i in mini(5, rows.size()):
		var r: Dictionary = rows[i]
		_file.store_line("#   %d. %s %s %s · %.0f°/프레임 · %s @ %.1fs" % [i + 1, r.char, r.bone, r.cls, r.sev, r.state, r.t])
	_file.flush()
	tops["pop"].clear()
	agg.clear()


func A(ch: String) -> Dictionary:
	if not agg.has(ch):
		agg[ch] = {"samples": 0, "excluded": 0, "pops": 0, "pops_soft": 0, "pop_by": {}, "pop_worst": 0.0, "pop_worst_bone": "",
			"jit_win": 0, "jit_bad": 0, "jit_worst": 0.0, "jit_worst_bone": "",
			"slide_n": {}, "slide_ratio": {}, "slide_bad": {}, "slide_worst": 0.0, "idle_drift": [], "idle_drift_bad": 0,
			"sunk": 0, "sunk_min": 0.0, "float": 0, "float_max": 0.0, "ground_frames": 0,
			"cloth_pen": 0, "cloth_pen_max": 0.0, "cloth_frames": 0, "stretch_samples": 0, "stretch_hi": 0, "stretch_cloth_hi": 0, "stretch_cloth_max": 1.0, "stretch_lo": 0, "stretch_max": 1.0, "stretch_min": 1.0,
			"weapon_pen": 0, "weapon_pen_max": 0.0, "weapon_samples": 0,
			"lim": {}, "lim_worst": {}, "seam": {}, "flicker": {}, "clip_flicker": 0, "bone_w": {}}
	return agg[ch]


func top(kind: String, row: Dictionary) -> void:
	var a: Array = tops[kind]
	a.append(row)
	if a.size() > TOP_KEEP * 4:
		a.sort_custom(func(x, y): return x.sev > y.sev)
		tops[kind] = a.slice(0, TOP_KEEP)


func csv_row(kind: String, r: Dictionary) -> void:
	if light or csv.size() > 60000:
		return
	csv.append("%s,%.3f,%d,%s,%s,%.3f,%s,%s,%s" % [kind, float(r.t), int(r.pid), r.char, str(r.get("bone", "")), float(r.sev), str(r.get("state", "")), str(r.get("clip", "")), str(r.get("extra", ""))])


# ============ 몸 하나 ============
class Track:
	var q: Node
	var body: Node3D
	var ext
	var sk: Skeleton3D
	var ch := ""
	var pid := -1
	var light := false
	var ids: PackedInt32Array = PackedInt32Array()
	var names: Array = []
	var cls: Array = []
	var pops: Array = []
	var jits: Array = []
	var nb := 0
	var G: Array = [] # 뼈대 공간 전역 (표본마다)
	var rest_loc_q: Dictionary = {} # 뼈 번호 → 쉬는 로컬 회전
	var feet := {} # "L"/"R" → {a, t (뼈 번호), ra, rt (쉬는 높이, 몸 로컬)}
	var slide: Dictionary = {}
	var have := 0
	var last_pos := Vector3.INF
	var lab := ""
	var lab_t := 0.0
	var last_lab_chg := -9.0
	var clip_last := ""
	var clip_chg := -9.0
	var excl_left := 0
	var settled := 0 # 같은 'idle' 이 이어진 표본 수
	var pending: Array = []
	var prev_wmax := 0.0
	var data: Dictionary = {}
	var stride_k := 0
	var slide_dir := {"mf": 0.0, "ms": 0.0, "n": 0}

	func setup(b: Node3D, light_: bool) -> bool:
		body = b
		ext = b.ext
		sk = ext.sk
		light = light_
		ch = str(b.get("char_id"))
		nb = sk.get_bone_count()
		for i in nb:
			var c := M.bone_class(sk.get_bone_name(i))
			if c == "skip":
				continue
			ids.append(i)
			names.append(sk.get_bone_name(i).trim_prefix("mixamorig_"))
			cls.append(c)
			pops.append(M.PopDet.new(M.pop_thr(c), M.POP_SOFT_K))
			jits.append(M.JitDet.new())
		G.resize(nb)
		var rl: Array = ext.info.rest_local
		for i in nb:
			rest_loc_q[i] = (rl[i] as Transform3D).basis.get_rotation_quaternion()
		if not light:
			data = q.get_skin_data(ch, ext, self)
			_init_feet()
		return true

	func _gl() -> void:
		for i in nb:
			var p := sk.get_bone_parent(i)
			var t := sk.get_bone_pose(i)
			G[i] = (G[p] * t) if p >= 0 else t

	func _loc_of(tr: Transform3D, local_to: Transform3D) -> Vector3:
		return (local_to * tr).origin

	func _init_feet() -> void:
		var rg: Array = ext.info.rest_global
		var sw: Transform3D = sk.global_transform
		var bi: Transform3D = body.global_transform.affine_inverse()
		for side in ["L", "R"]:
			var nm := "mixamorig_%sFoot" % ("Left" if side == "L" else "Right")
			var nt := "mixamorig_%sToeBase" % ("Left" if side == "L" else "Right")
			var a := sk.find_bone(nm)
			var t := sk.find_bone(nt)
			if a < 0 or t < 0:
				continue
			feet[side] = {"a": a, "t": t, "ra": (bi * sw * (rg[a] as Transform3D).origin).y, "rt": (bi * sw * (rg[t] as Transform3D).origin).y}
			slide[side] = M.SlideDet.new()

	func reset() -> void:
		have = 0
		for p in pops:
			p.reset()
		for j in jits:
			j.reset()
		for s in slide.values():
			s.reset()
		lab = ""
		settled = 0
		pending.clear()
		last_pos = Vector3.INF
		excl_left = 0

	# 상태 이름: [큰 상태, 하위 (클립)]
	func _label(st: Dictionary) -> String:
		if bool(st.get("stunned", false)) or float(st.get("tumble", 0.0)) > 0.0 or float(st.get("flip", -1.0)) >= 0.0 or float(st.get("dizzy", 0.0)) > 0.0 or float(st.get("whirl", -1.0)) >= 0.0:
			return "stun"
		if float(st.get("recover", 0.0)) > 0.0:
			return "recover"
		if st.get("act") != null:
			return "act"
		if float(st.get("airDash", 0.0)) > 0.0 or bool(st.get("glide", false)):
			return "dash"
		if bool(st.get("air", false)):
			return "air"
		if int(st.get("emote", -1)) >= 0 or float(st.get("victory", -1.0)) >= 0.0:
			return "pose"
		var h = st.get("hit")
		if h is Dictionary and float(h.get("age", 9.0)) < 0.4:
			return "hit"
		if float(st.get("land", 0.0)) > 0.02:
			return "land"
		if bool(st.get("walking", false)):
			return "loco"
		return "idle"

	func step(t: float, kk: int) -> void:
		var st: Dictionary = ext.last_st
		if not body.is_visible_in_tree():
			reset()
			return
		var gp := body.global_position
		if last_pos != Vector3.INF and gp.distance_to(last_pos) > 0.8:
			reset() # 순간이동 (부활·재배치)
		var lastp := last_pos
		last_pos = gp
		var a: Dictionary = q.A(ch)
		var excl := false
		var rg = Rag_._inst
		if rg != null and is_instance_valid(rg) and rg.rags.has(body):
			var r: Dictionary = rg.rags[body]
			if r.awake and float(r.motor) < 0.97:
				excl_left = RAG_MARGIN
		if excl_left > 0:
			excl = true
			excl_left -= 1
		var L := _label(st)
		var cc: Dictionary = ext.info.cfg.get("clips", {})
		if L == "stun": # 맞아 날아가는·쓰러진 몸은 래그돌 (물리) 이 맡음 — 판정 대상 아님
			excl = true
			excl_left = RAG_MARGIN
		elif L == "act" and st.act is Dictionary and not (cc.get("moves", {}) as Dictionary).has(str((st.act as Dictionary).get("move", ""))):
			excl = true # 이 캐릭터 클립에 없는 동작 (캐릭터를 바꿔 만든 녹화의 옛 캐릭터 기술) — 코드 자세라 검사 대상 아님
		if excl:
			L = "rag"
		var clip: String = str(ext.cur_clip) if ext.cw > 0.01 else "(코드)"
		# --- 각속도 (팝) ---
		var wmax := 0.0
		var wbone := ""
		var has := have > 0
		if q.btrace != null and pid_of() == q.trace_pid: # 확인용 (--qa-bone-trace 뼈 이름): 한 뼈의 표본별 회전·클립 층 값
			var bi0 := sk.find_bone("mixamorig_" + q.btrace_bone)
			if bi0 >= 0:
				var mvn := ""
				var u := -1.0
				if st.get("act") is Dictionary:
					mvn = "%s/%s" % [str(st.act.get("move", "")), str(st.act.get("phase", ""))]
					u = float(st.act.get("u", -1.0))
				var qq := sk.get_bone_pose_rotation(bi0)
				var ci: Dictionary = ext.clip_info
				q.btrace.store_line("%.3f,%s,%s,%.3f,%s,%.3f,%.3f,%s,%.4f,%.4f,%.4f,%.4f,%s" % [t, L, mvn, u, str(ext.cur_clip), ext.cw, ext.fade_t, str(ci.get("t", "")), qq.x, qq.y, qq.z, qq.w, str(excl)])
		var qs: Array = []
		for i in ids.size():
			qs.append(sk.get_bone_pose_rotation(ids[i]))
		for i in ids.size():
			var r2: Dictionary = pops[i].feed(qs[i])
			var w: float = r2.w
			if cls[i] != "cloth" and w > wmax:
				wmax = w
				wbone = names[i]
			if not has or excl:
				continue
			var cl: String = cls[i]
			if r2.soft:
				a.pops_soft += 1
			if w > float(a.bone_w.get(names[i], 0.0)):
				a.bone_w[names[i]] = w
			if r2.pop:
				a.pops += 1
				var key: String = cl
				a.pop_by[key] = int(a.pop_by.get(key, 0)) + 1
				if w > float(a.pop_worst):
					a.pop_worst = w
					a.pop_worst_bone = names[i]
				var mv := ""
				if st.get("act") is Dictionary:
					mv = " %s/%s" % [str((st.act as Dictionary).get("move", "")), str((st.act as Dictionary).get("phase", ""))]
				var row := {"t": t, "pid": pid_of(), "char": ch, "bone": names[i], "cls": cl, "sev": w, "state": L + mv, "clip": clip, "jerk": r2.jerk,
					"extra": "fade %.2f cw %.2f since_lab %.2f since_clip %.2f" % [ext.fade_t, ext.cw, t - last_lab_chg, t - clip_chg]}
				q.top("pop", row)
				q.csv_row("pop", row)
		if light:
			have += 1
			a.samples += 1
			return
		a.samples += 1
		if excl:
			a.excluded += 1
		# --- 상태 전환·깜빡임·이음새 ---
		if clip != clip_last:
			var ground_clip: bool = L in ["idle", "loco", "land"] and lab in ["idle", "loco", "land"] # 콤보 연타는 정상 — 땅 위 서기·걷기·달리기 사이만 '깜빡임'
			if has and t - clip_chg < 0.3 and not excl and ground_clip:
				a.clip_flicker += 1
				var fr := {"t": t, "pid": pid_of(), "char": ch, "bone": clip_last + "→" + clip, "sev": 0.3 - (t - clip_chg), "state": L, "clip": clip}
				q.top("flicker", fr)
				q.csv_row("flicker", fr)
			clip_chg = t
			clip_last = clip
		if has and L != lab and lab != "":
			var pair := lab + "→" + L
			if t - last_lab_chg < M.FLICKER_S:
				a.flicker[pair] = int(a.flicker.get(pair, 0)) + 1
			last_lab_chg = t
			pending.append({"pair": pair, "left": M.SEAM_WIN, "peak": wmax, "jump": wmax, "bone": wbone, "clip": clip, "t": t})
		elif lab == "":
			last_lab_chg = t
		for pd in pending:
			if wmax > float(pd.peak):
				pd.peak = wmax
				pd.bone = wbone
			pd.left -= 1
		var keep := []
		for pd in pending:
			if pd.left <= 0:
				var s: Dictionary = a.seam.get(pd.pair, {"n": 0, "jump_sum": 0.0, "jump_max": 0.0, "peak_sum": 0.0, "peak_max": 0.0, "bone": "", "clip": "", "t": 0.0})
				s.n += 1
				s.jump_sum += float(pd.jump)
				s.jump_max = maxf(s.jump_max, float(pd.jump))
				s.peak_sum += float(pd.peak)
				if float(pd.peak) > float(s.peak_max):
					s.peak_max = float(pd.peak)
					s.bone = pd.bone
					s.clip = pd.clip
					s.t = pd.t
				a.seam[pd.pair] = s
				var sr := {"t": pd.t, "pid": pid_of(), "char": ch, "bone": pd.bone, "sev": float(pd.peak), "state": pd.pair, "clip": pd.clip, "extra": "jump %.1f" % float(pd.jump)}
				q.top("seam", sr)
				q.csv_row("seam", sr)
			else:
				keep.append(pd)
		pending = keep
		lab = L
		if not has:
			have += 1
			_gl()
			return
		have += 1
		# --- 뼈 전역 + 월드 ---
		_gl()
		if excl:
			settled = 0
			for j in jits:
				j.reset()
			for s2 in slide.values():
				s2.reset()
			return
		_jitter(a, t, L, qs)
		_feet(a, t, L, st, gp, lastp)
		_limits(a, t, L, clip)
		if kk % STRETCH_EVERY == 0:
			_mesh(a, t, L, clip)
			_cloth(a, t, L, clip)

	var _pid_cache := -1

	func pid_of() -> int:
		return int(body.get("pid")) if body.get("pid") != null else -1

	# ---- 떨림: 서 있는 동안만 (idle 이 30표본 이상 이어진 뒤) ----
	func _jitter(a: Dictionary, t: float, L: String, qs: Array) -> void:
		if L != "idle":
			settled = 0
			for j in jits:
				j.reset()
			return
		settled += 1
		if settled < 20:
			return
		for i in jits.size():
			var win: Dictionary = jits[i].feed(qs[i])
			if win.is_empty() or cls[i] == "cloth":
				continue
			a.jit_win += 1
			if float(win.rms) > float(a.jit_worst):
				a.jit_worst = win.rms
				a.jit_worst_bone = names[i]
			if M.jitter_bad(win):
				a.jit_bad += 1
				var row := {"t": t, "pid": pid_of(), "char": ch, "bone": names[i], "sev": float(win.rms), "state": L, "clip": str(ext.cur_clip), "extra": "flip %.2f" % float(win.flip)}
				q.top("jitter", row)
				q.csv_row("jitter", row)

	# ---- 발 미끄러짐·박힘·뜸 ----
	func _feet(a: Dictionary, t: float, L: String, st: Dictionary, gp: Vector3, lastp: Vector3) -> void:
		if feet.is_empty():
			return
		var sw: Transform3D = sk.global_transform
		var bi: Transform3D = body.global_transform.affine_inverse()
		var lifts := {}
		var ys := {}
		for side0 in feet:
			var f0: Dictionary = feet[side0]
			ys[side0] = minf((bi * (sw * (G[f0.a] as Transform3D).origin)).y, (bi * (sw * (G[f0.t] as Transform3D).origin)).y)
		var grounded: bool = L in ["idle", "loco", "land"] and not bool(st.get("air", false)) # 공격·스킬은 도약·돌진이 많아 발 높이 기준이 안 맞음 — 빼고 봄
		for side in feet:
			var f: Dictionary = feet[side]
			var pa: Vector3 = sw * (G[f.a] as Transform3D).origin
			var pt: Vector3 = sw * (G[f.t] as Transform3D).origin
			var lift: float = minf((bi * pa).y, (bi * pt).y) - minf(float(f.ra), float(f.rt)) # 발·발가락 중 낮은 쪽 = 땅 (외부 몸 _ground_dy 와 같은 기준)
			lifts[side] = lift
			if q.trace != null and pid_of() == q.trace_pid:
				q.trace.store_line("%.3f,%s,%s,%s,%s,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f" % [t, L, str(ext.cur_clip), ext.cw, side, lift, (bi * pa).y, (bi * pt).y, pa.x, pa.z, gp.x, gp.z])
			var other: float = float(ys["R" if side == "L" else "L"]) if feet.size() > 1 else 1e9
			var support: bool = float(ys[side]) <= other + 0.01 # 지지하는 (더 낮은) 발만 디딤으로 침
			var d: Dictionary = (slide[side] as M.SlideDet).feed(Vector2(pa.x, pa.z), lift, Vector2(gp.x, gp.z), grounded and support)
			if st != null:
				slide_dir.mf += float(st.get("mvF", 0.0))
				slide_dir.ms += float(st.get("mvS", 0.0))
				slide_dir.n += 1
			if not d.is_empty():
				_run_done(a, t, L, side, d)
		if grounded:
			a.ground_frames += 1
			var mn := minf(float(lifts.get("L", 0.0)), float(lifts.get("R", 0.0)))
			if mn < M.SUNK_LIFT:
				a.sunk += 1
				a.sunk_min = minf(a.sunk_min, mn)
			if L in ["idle", "land"] and mn > M.FLOAT_LIFT:
				a.float += 1
				a.float_max = maxf(a.float_max, mn)
				var row := {"t": t, "pid": pid_of(), "char": ch, "bone": "발 뜸", "sev": mn, "state": L, "clip": str(ext.cur_clip)}
				q.top("slide", row)
				q.csv_row("float", row)

	func _run_done(a: Dictionary, t: float, L: String, side: String, d: Dictionary) -> void:
		var n: int = max(1, int(slide_dir.n))
		var mf: float = float(slide_dir.mf) / n
		var ms: float = float(slide_dir.ms) / n
		slide_dir = {"mf": 0.0, "ms": 0.0, "n": 0}
		if float(d.body) < 0.05:
			var dr: float = float(d.slide)
			(a.idle_drift as Array).append(dr)
			if dr > M.SLIDE_IDLE_BAD:
				a.idle_drift_bad += 1
				var row0 := {"t": t, "pid": pid_of(), "char": ch, "bone": "발 " + side, "sev": dr, "state": "정지 끌림", "clip": str(ext.cur_clip), "extra": "len %d" % int(d.len)}
				q.top("slide", row0)
				q.csv_row("slide", row0)
			return
		if float(d.body) < M.SLIDE_MOVE_MIN or float(d.body) / (float(d.len) / M.HZ) < 0.8:
			return # 거의 안 가는 (벽에 막혀 제자리 달리기 등) 디딤은 '걸음' 에서 뺌 (0.8 m/s 이상으로 가야)
		var th := rad_to_deg(atan2(ms, mf))
		var kind := "fwd"
		if absf(th) > 130.0:
			kind = "back"
		elif absf(th) > 50.0:
			kind = "side"
		if ext.dir_rev and kind == "fwd":
			kind = "back"
		a.slide_n[kind] = int(a.slide_n.get(kind, 0)) + 1
		if not a.slide_ratio.has(kind):
			a.slide_ratio[kind] = []
		(a.slide_ratio[kind] as Array).append(float(d.ratio))
		if float(d.ratio) > M.SLIDE_BAD_RATIO:
			a.slide_bad[kind] = int(a.slide_bad.get(kind, 0)) + 1
		a.slide_worst = maxf(a.slide_worst, float(d.ratio))
		var row := {"t": t, "pid": pid_of(), "char": ch, "bone": "발 " + side, "sev": float(d.ratio), "state": "걸음 " + kind, "clip": str(ext.cur_clip), "extra": "slide %.2f body %.2f len %d" % [float(d.slide), float(d.body), int(d.len)]}
		q.top("slide", row)
		q.csv_row("slide", row)

	# ---- 관절 한계 ----
	# 팔꿈치·무릎 굽힘 = 위 뼈 방향 U 와 아래 뼈 방향 F (위 뼈 로컬 틀) 사이 각, 부호 = (U × F) 가 자연 굽힘 축 h (클립에서 구한) 쪽이면 +
	func _limits(a: Dictionary, t: float, L: String, clip: String) -> void:
		var hz: Dictionary = data.get("hinge", {})
		var vs: Array = []
		for bn in hz:
			var bi := sk.find_bone(bn)
			if bi < 0:
				continue
			var hd: Dictionary = hz[bn]
			var Fv: Vector3 = sk.get_bone_pose_rotation(bi) * (hd.f as Vector3)
			var ang := rad_to_deg(hd.u.angle_to(Fv))
			var sgn := 1.0 if (hd.u.cross(Fv).dot(hd.h) >= 0.0 or ang < 10.0 or ang > 150.0) else -1.0 # 거의 펴졌거나 완전히 접히면 방향이 불안정 — 반대 굽힘으로 안 침
			for v in M.limit_flags(sgn * ang, 0.0, 0.0):
				vs.append([bn.trim_prefix("mixamorig_"), v])
		var nk := sk.find_bone("mixamorig_Neck")
		var hd2 := sk.find_bone("mixamorig_Head")
		if nk >= 0 and hd2 >= 0:
			var ax: Vector3 = data.get("neck_axis", Vector3.UP)
			var tw := M.twist_deg(rest_loc_q[nk].inverse() * sk.get_bone_pose_rotation(nk), ax) + M.twist_deg(rest_loc_q[hd2].inverse() * sk.get_bone_pose_rotation(hd2), data.get("head_axis", Vector3.UP))
			for v in M.limit_flags(0.0, tw, 0.0):
				vs.append(["Neck+Head", v])
		var s0 := sk.find_bone("mixamorig_Spine")
		var s1 := sk.find_bone("mixamorig_Spine1")
		var s2 := sk.find_bone("mixamorig_Spine2")
		if s0 >= 0 and s1 >= 0 and s2 >= 0:
			var rq: Quaternion = rest_loc_q[s0] * rest_loc_q[s1] * rest_loc_q[s2]
			var cq: Quaternion = sk.get_bone_pose_rotation(s0) * sk.get_bone_pose_rotation(s1) * sk.get_bone_pose_rotation(s2)
			for v in M.limit_flags(0.0, 0.0, M.ang(rq, cq)):
				vs.append(["Spine", v])
		for e in vs:
			var kind: String = e[1].kind
			a.lim[kind] = int(a.lim.get(kind, 0)) + 1
			var key: String = "%s %s" % [e[0], kind]
			var val: float = absf(float(e[1].value))
			if val > float(a.lim_worst.get(key, 0.0)):
				a.lim_worst[key] = val
			var row := {"t": t, "pid": pid_of(), "char": ch, "bone": e[0], "sev": val, "state": L + " " + kind, "clip": clip}
			q.top("limit", row)
			q.csv_row("limit", row)

	# ---- 몸 모양: 변 늘어남·무기 뚫림 ----
	func _skinned() -> PackedVector3Array:
		var sd: Dictionary = data.skin
		var binds: Array = sd.bind_pose
		var bb: PackedInt32Array = sd.bind_bone
		var M_: Array = []
		M_.resize(binds.size())
		for i in binds.size():
			var b: int = bb[i]
			M_[i] = (G[b] as Transform3D) * (binds[i] as Transform3D) if b >= 0 else Transform3D.IDENTITY
		var vs: PackedVector3Array = sd.sub_v
		var ib: PackedInt32Array = sd.sub_b
		var iw: PackedFloat32Array = sd.sub_w
		var out := PackedVector3Array()
		out.resize(vs.size())
		for i in vs.size():
			var p := Vector3.ZERO
			for j in 4:
				var w := iw[i * 4 + j]
				if w > 0.0:
					p += w * ((M_[ib[i * 4 + j]] as Transform3D) * vs[i])
			out[i] = p
		return out

	func _caps_now() -> Array:
		var out := []
		for c in data.caps:
			out.append([(G[c.a] as Transform3D).origin, (G[c.b] as Transform3D).origin, c.r])
		return out

	func _mesh(a: Dictionary, t: float, L: String, clip: String) -> void:
		if not data.has("skin"):
			return
		var sd: Dictionary = data.skin
		var sv := _skinned()
		var sc: float = sk.global_transform.basis.get_scale().x
		var edges: PackedInt32Array = sd.edges # 부분 점 번호 쌍
		var rl: PackedFloat32Array = sd.edge_rest
		var ec: PackedByteArray = sd.edge_cloth
		var hi := 0.0
		var lo := 1e9
		var hi_e := -1
		var chi := 0.0
		for e in rl.size():
			var ra := rl[e]
			var r := sv[edges[e * 2]].distance_to(sv[edges[e * 2 + 1]]) / ra
			if ec[e] == 1:
				chi = maxf(chi, r)
				continue
			if r > hi:
				hi = r
				hi_e = e
			if r < lo:
				lo = r
		a.stretch_samples += 1
		a.stretch_max = maxf(a.stretch_max, hi)
		a.stretch_min = minf(a.stretch_min, lo)
		a.stretch_cloth_max = maxf(a.stretch_cloth_max, chi)
		if chi > M.STRETCH_MAX:
			a.stretch_cloth_hi += 1
		if hi > M.STRETCH_MAX:
			a.stretch_hi += 1
			var row := {"t": t, "pid": pid_of(), "char": ch, "bone": sd.edge_name[hi_e], "sev": hi, "state": L, "clip": clip}
			q.top("stretch", row)
			q.csv_row("stretch", row)
		if lo < M.STRETCH_MIN:
			a.stretch_lo += 1
		# 무기 점이 몸 캡슐 안으로
		var wp: PackedInt32Array = sd.weapon
		if wp.size() > 0:
			var caps := _caps_now()
			var wb: PackedFloat32Array = sd.weapon_base
			var worst := 0.0
			for i in wp.size():
				var dd := 0.0
				for c in caps:
					dd = maxf(dd, M.capsule_depth(sv[wp[i]], c[0], c[1], c[2]))
				worst = maxf(worst, (dd - wb[i]) * sc)
			a.weapon_samples += 1
			if worst > M.PEN_MIN:
				a.weapon_pen += 1
				a.weapon_pen_max = maxf(a.weapon_pen_max, worst)
				var row2 := {"t": t, "pid": pid_of(), "char": ch, "bone": "무기 점", "sev": worst, "state": L, "clip": clip}
				q.top("weapon", row2)
				q.csv_row("weapon", row2)

	# ---- 천 사슬 끝점이 몸 안으로 ----
	func _cloth(a: Dictionary, t: float, L: String, clip: String) -> void:
		if ext.cloths.is_empty() or not data.has("caps"):
			return
		var Wi: Transform3D = sk.global_transform.affine_inverse()
		var sc: float = sk.global_transform.basis.get_scale().x
		var caps := _caps_now()
		var bases: Array = data.cloth_base
		var ci := 0
		a.cloth_frames += 1
		var any := false
		for cl in ext.cloths:
			if cl.pts.is_empty():
				ci += 1
				continue
			var worst := 0.0
			for i in range(1, cl.pts.size()):
				var p: Vector3 = Wi * (cl.pts[i] as Vector3)
				var dd := 0.0
				for c in caps:
					dd = maxf(dd, M.capsule_depth(p, c[0], c[1], c[2]))
				var base: float = bases[ci][i] if ci < bases.size() and i < bases[ci].size() else 0.0
				worst = maxf(worst, (dd - base) * sc)
			if worst > M.PEN_MIN:
				any = true
				a.cloth_pen_max = maxf(a.cloth_pen_max, worst)
				var row := {"t": t, "pid": pid_of(), "char": ch, "bone": sk.get_bone_name(cl.bones[0]).trim_prefix("mixamorig_"), "sev": worst, "state": L, "clip": clip}
				q.top("pen", row)
				q.csv_row("pen", row)
			ci += 1
		if any:
			a.cloth_pen += 1


# ============ 캐릭터별 한 번 만드는 자료 ============
func get_skin_data(ch: String, ext, tr) -> Dictionary:
	if _skin_cache.has(ch):
		return _skin_cache[ch]
	var d := {}
	var sk: Skeleton3D = ext.sk
	var info: Dictionary = ext.info
	var rg: Array = info.rest_global
	# 경첩: 팔꿈치·무릎의 위 뼈 방향 u (위 뼈 로컬 틀), 아래 뼈 방향 f (아래 뼈 로컬 틀), 자연 굽힘 축 h = 클립에서 (U × F) 의 평균 (굽힘 25° 넘는 표본)
	var hinge := {}
	var HJ := [["mixamorig_LeftForeArm", "mixamorig_LeftHand"], ["mixamorig_RightForeArm", "mixamorig_RightHand"], ["mixamorig_LeftLeg", "mixamorig_LeftFoot"], ["mixamorig_RightLeg", "mixamorig_RightFoot"]]
	for pr in HJ:
		var bn: String = pr[0]
		var bi := sk.find_bone(bn)
		var ci := sk.find_bone(pr[1])
		if bi < 0 or ci < 0:
			continue
		var u: Vector3 = (info.rest_local[bi] as Transform3D).origin.normalized()
		var f: Vector3 = (info.rest_local[ci] as Transform3D).origin.normalized()
		var sum := Vector3.ZERO
		for nm in ext.clipset:
			var cs: Dictionary = ext.clipset[nm]
			if not (cs.rot as Dictionary).has(bn):
				continue
			for s in 16:
				var qq: Quaternion = (cs.anim as Animation).rotation_track_interpolate(int(cs.rot[bn]), float(cs.len) * float(s) / 16.0)
				var Fv := qq * f
				if rad_to_deg(u.angle_to(Fv)) > 25.0:
					sum += u.cross(Fv).normalized()
		if sum.length() > 1e-6:
			hinge[bn] = {"u": u, "f": f, "h": sum.normalized()}
	d["hinge"] = hinge
	var nk := sk.find_bone("mixamorig_Neck")
	var hd := sk.find_bone("mixamorig_Head")
	var te := sk.find_bone("mixamorig_HeadTop_End")
	d["neck_axis"] = ((info.rest_local[hd] as Transform3D).origin).normalized() if nk >= 0 and hd >= 0 else Vector3.UP
	d["head_axis"] = ((info.rest_local[te] as Transform3D).origin).normalized() if te >= 0 else Vector3.UP
	# 메시 (가장 큰 스킨 조각)
	var best: MeshInstance3D = null
	var bn_v := 0
	for pt in ext.parts:
		var mi: MeshInstance3D = pt.mi
		if mi.skin == null or mi.mesh == null:
			continue
		var n := (mi.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
		if n > bn_v:
			bn_v = n
			best = mi
	if best != null:
		var arr := best.mesh.surface_get_arrays(0)
		var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var bones: PackedInt32Array = arr[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
		var per := 8 if (best.mesh.surface_get_format(0) & Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS) else 4
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
		var skin: Skin = best.skin
		var bb := PackedInt32Array()
		var bp := []
		for i in skin.get_bind_count():
			var b := skin.get_bind_bone(i)
			if b < 0:
				b = sk.find_bone(skin.get_bind_name(i))
			bb.append(b)
			bp.append(skin.get_bind_pose(i))
		# 정점마다 지배 뼈 (몸 뼈 번호)
		var dom := PackedInt32Array()
		dom.resize(vs.size())
		for v in vs.size():
			var bw := -1.0
			var bo := -1
			for j in per:
				var w := weights[v * per + j]
				if w > bw:
					bw = w
					bo = bones[v * per + j]
			dom[v] = bb[bo] if bo >= 0 and bo < bb.size() else -1
		# 캡슐: 지배 뼈 집합 → 쉬는 자세에서 축까지 거리 중앙값 × 0.85
		var defs := [["Hips", "Spine1", ["Hips", "Spine", "Spine1"]], ["Spine1", "Neck", ["Spine2"]]]
		for side in ["Left", "Right"]:
			defs.append([side + "UpLeg", side + "Leg", [side + "UpLeg"]])
			defs.append([side + "Leg", side + "Foot", [side + "Leg"]])
		var caps := []
		for df in defs:
			var ia := sk.find_bone("mixamorig_" + df[0])
			var ib := sk.find_bone("mixamorig_" + df[1])
			if ia < 0 or ib < 0:
				continue
			var set := {}
			for n in df[2]:
				set[sk.find_bone("mixamorig_" + n)] = true
			var pa: Vector3 = (rg[ia] as Transform3D).origin
			var pb: Vector3 = (rg[ib] as Transform3D).origin
			var ds := []
			for v in vs.size():
				if set.has(dom[v]):
					ds.append(M.capsule_depth(vs[v], pa, pb, 1e6)) # 1e6 - 거리
			var dd := []
			for x in ds:
				dd.append(1e6 - float(x))
			if dd.size() > 20:
				caps.append({"a": ia, "b": ib, "r": 0.85 * M.pct(dd, 0.5)})
		d["caps"] = caps
		# 변 고르기: 지배 뼈가 다른 변 중 일부 + 무기 점 (손 뼈 지배 + 손목에서 먼 점)
		var edges_all := {}
		var cand := []
		var i2 := 0
		while i2 + 2 < idx.size():
			for e in [[idx[i2], idx[i2 + 1]], [idx[i2 + 1], idx[i2 + 2]]]:
				var lo: int = mini(e[0], e[1])
				var hi: int = maxi(e[0], e[1])
				var key: int = lo * 100000 + hi
				if not edges_all.has(key):
					edges_all[key] = true
					if dom[lo] != dom[hi] and dom[lo] >= 0 and dom[hi] >= 0:
						cand.append([lo, hi])
			i2 += 3
		var stride: int = maxi(1, cand.size() / 700)
		var sel := []
		for i in range(0, cand.size(), stride):
			sel.append(cand[i])
		var wpts := []
		for side in ["Left", "Right"]:
			var hb := sk.find_bone("mixamorig_%sHand" % side)
			if hb < 0:
				continue
			var hp: Vector3 = (rg[hb] as Transform3D).origin
			for v in vs.size():
				var nm := sk.get_bone_name(dom[v]) if dom[v] >= 0 else ""
				if nm.begins_with("mixamorig_%sHand" % side) and (rg[dom[v]] as Transform3D).origin.distance_to(hp) < 0.2 and vs[v].distance_to(hp) > 0.14:
					wpts.append(v)
		if wpts.size() > 250:
			var w2 := []
			var st2: int = wpts.size() / 250
			for i in range(0, wpts.size(), st2):
				w2.append(wpts[i])
			wpts = w2
		# 부분 점 번호 매김
		var remap := {}
		var sub_idx := PackedInt32Array()
		for e in sel:
			for v in e:
				if not remap.has(v):
					remap[v] = remap.size()
					sub_idx.append(v)
		var wmap := PackedInt32Array()
		for v in wpts:
			if not remap.has(v):
				remap[v] = remap.size()
				sub_idx.append(v)
			wmap.append(remap[v])
		var sub_v := PackedVector3Array()
		var sub_b := PackedInt32Array()
		var sub_w := PackedFloat32Array()
		for v in sub_idx:
			sub_v.append(vs[v])
			var tot := 0.0
			for j in 4:
				tot += weights[v * per + j]
			for j in 4:
				sub_b.append(bones[v * per + j])
				sub_w.append(weights[v * per + j] / maxf(tot, 1e-6))
		var edges := PackedInt32Array()
		var erest := PackedFloat32Array()
		var ename := []
		var ecloth := PackedByteArray()
		for e in sel:
			var rl := vs[e[0]].distance_to(vs[e[1]])
			var nm0 := "%s|%s" % [sk.get_bone_name(dom[e[0]]), sk.get_bone_name(dom[e[1]])]
			if rl < 0.02 or (nm0.contains("LeftUpLeg") and nm0.contains("RightUpLeg")): # 짧은 변·두 허벅지 사이 (사타구니 막) 는 늘어나는 게 정상
				continue
			edges.append(remap[e[0]])
			edges.append(remap[e[1]])
			erest.append(rl)
			ename.append("%s|%s" % [sk.get_bone_name(dom[e[0]]).trim_prefix("mixamorig_"), sk.get_bone_name(dom[e[1]]).trim_prefix("mixamorig_")])
			ecloth.append(1 if (M.bone_class(sk.get_bone_name(dom[e[0]])) == "cloth" or M.bone_class(sk.get_bone_name(dom[e[1]])) == "cloth") else 0)
		d["skin"] = {"bind_pose": bp, "bind_bone": bb, "sub_v": sub_v, "sub_b": sub_b, "sub_w": sub_w, "edges": edges, "edge_rest": erest, "edge_name": ename, "edge_cloth": ecloth, "weapon": wmap, "weapon_base": PackedFloat32Array()}
		# 무기 점 쉬는 값 (쉬는 자세에서 이미 닿은 만큼)
		var cl_caps := []
		for c in caps:
			cl_caps.append([(rg[c.a] as Transform3D).origin, (rg[c.b] as Transform3D).origin, c.r])
		var wb := PackedFloat32Array()
		for v in wpts:
			var dd := 0.0
			for c in cl_caps:
				dd = maxf(dd, M.capsule_depth(vs[v], c[0], c[1], c[2]))
			wb.append(dd)
		d.skin.weapon_base = wb
		# 천 쉬는 값
		var cb := []
		for cl in ext.cloths:
			var row := [0.0]
			for i in range(1, cl.pts.size()):
				var p: Vector3 = (cl.rest_g[i] as Transform3D).origin if i < cl.rest_g.size() else (cl.rest_g[cl.rest_g.size() - 1] as Transform3D).origin + cl.rest_dir[cl.rest_g.size() - 1] * cl.rest_len[cl.rest_g.size() - 1]
				var dd := 0.0
				for c in cl_caps:
					dd = maxf(dd, M.capsule_depth(p, c[0], c[1], c[2]))
				row.append(dd)
			cb.append(row)
		d["cloth_base"] = cb
	if args.has("qa-debug") and d.has("skin"):
		var sd2: Dictionary = d.skin
		var Gr: Array = []
		for i in sk.get_bone_count():
			Gr.append(rg[i])
		var dev := 0.0
		var binds: Array = sd2.bind_pose
		var bbn: PackedInt32Array = sd2.bind_bone
		for i in sd2.sub_v.size():
			var pp := Vector3.ZERO
			for j in 4:
				var w: float = sd2.sub_w[i * 4 + j]
				if w > 0.0:
					pp += w * ((Gr[bbn[sd2.sub_b[i * 4 + j]]] as Transform3D) * (binds[sd2.sub_b[i * 4 + j]] as Transform3D) * sd2.sub_v[i])
			dev = maxf(dev, pp.distance_to(sd2.sub_v[i]))
		print("[모션QA 디버그] %s 스킨 쉬는 자세 오차 %.4f · 캡슐 %s · 경첩 %s" % [ch, dev, d.caps.map(func(c): return "%s %.3f" % [sk.get_bone_name(c.a).trim_prefix("mixamorig_"), c.r]), hinge.keys().map(func(k): return "%s %s" % [k, hinge[k].h])])
	_skin_cache[ch] = d
	return d


# ============ 끝 ============
func finish() -> void:
	if done:
		return
	done = true
	if args.has("qa-debug"):
		var info := []
		for b in Motion_.bodies:
			info.append("%s ext=%s vis=%s st=%s fr=%s/%s" % [b.get("char_id"), b.get("ext") != null, b.is_visible_in_tree() if b.is_inside_tree() else "outtree", b.get("ext").last_st != null if b.get("ext") != null else "-", b.get("ext").st_frame if b.get("ext") != null else -1, Engine.get_process_frames()])
		var st = get_node_or_null("/root/Store")
		print("[모션QA 디버그] phase ", st.phase() if st else "-", " players ", (st.state.get("players", []) as Array).size() if st else 0, " virt ", Net.virt)
		print("[모션QA 디버그] 몸 ", Motion_.bodies.size(), " ", info)
	if trace != null:
		trace.close()
	if btrace != null:
		btrace.close()
	if light:
		return
	var out := {"meta": {"rec": rec_name, "samples": k, "hz": M.HZ, "secs": (_now() - epoch), "thr": {"pop_torso": M.POP_TORSO, "pop_end": M.POP_END, "pop_cloth": M.POP_CLOTH}}, "chars": {}, "top": {}}
	for ch in agg:
		var a: Dictionary = agg[ch]
		var c := {"samples": a.samples, "excluded": a.excluded, "pops": a.pops, "pops_soft": a.pops_soft, "pop_by": a.pop_by, "pop_worst": snappedf(a.pop_worst, 0.1), "pop_worst_bone": a.pop_worst_bone,
			"jitter": {"windows": a.jit_win, "bad": a.jit_bad, "worst_rms": snappedf(a.jit_worst, 0.001), "worst_bone": a.jit_worst_bone},
			"slide": {}, "idle_drift": {"n": (a.idle_drift as Array).size(), "mean": snappedf(M.mean(a.idle_drift), 0.001), "p95": snappedf(M.pct(a.idle_drift, 0.95), 0.001), "bad": a.idle_drift_bad},
			"foot": {"ground_frames": a.ground_frames, "sunk": a.sunk, "sunk_min": snappedf(a.sunk_min, 0.001), "float": a.float, "float_max": snappedf(a.float_max, 0.001)},
			"cloth_pen": {"frames": a.cloth_pen, "of": a.cloth_frames, "max": snappedf(a.cloth_pen_max, 0.001)},
			"stretch": {"samples": a.stretch_samples, "hi": a.stretch_hi, "lo": a.stretch_lo, "max": snappedf(a.stretch_max, 0.01), "min": snappedf(a.stretch_min, 0.01), "cloth_hi": a.stretch_cloth_hi, "cloth_max": snappedf(a.stretch_cloth_max, 0.01)},
			"weapon_pen": {"samples": a.weapon_samples, "frames": a.weapon_pen, "max": snappedf(a.weapon_pen_max, 0.001)},
			"limits": a.lim, "limit_worst": a.lim_worst, "clip_flicker": a.clip_flicker, "label_flicker": a.flicker, "seam": {}}
		for kd in a.slide_n:
			var rr: Array = a.slide_ratio[kd]
			c.slide[kd] = {"n": a.slide_n[kd], "mean": snappedf(M.mean(rr), 0.001), "p95": snappedf(M.pct(rr, 0.95), 0.001), "bad": int(a.slide_bad.get(kd, 0))}
		for pair in a.seam:
			var s: Dictionary = a.seam[pair]
			c.seam[pair] = {"n": s.n, "jump_mean": snappedf(s.jump_sum / s.n, 0.1), "jump_max": snappedf(s.jump_max, 0.1), "peak_mean": snappedf(s.peak_sum / s.n, 0.1), "peak_max": snappedf(s.peak_max, 0.1), "bone": s.bone, "clip": s.clip}
		out.chars[ch] = c
	for kd in tops:
		var arr: Array = tops[kd]
		arr.sort_custom(func(x, y): return x.sev > y.sev)
		var rows := []
		for r in arr.slice(0, 20):
			var rr2: Dictionary = r.duplicate()
			for kk in rr2:
				if rr2[kk] is float:
					rr2[kk] = snappedf(rr2[kk], 0.001)
			rows.append(rr2)
		out.top[kd] = rows
	DirAccess.make_dir_recursive_absolute(out_dir)
	var f := FileAccess.open(out_dir.path_join("motion_qa.json"), FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(out, "  "))
		f.close()
	var f2 := FileAccess.open(out_dir.path_join("motion_qa.csv"), FileAccess.WRITE)
	if f2 != null:
		f2.store_line("kind,t,pid,char,bone,sev,state,clip,extra")
		for l in csv:
			f2.store_line(l)
		f2.close()
	print("[모션QA] 표본 %d · 몸 %d · %s → %s" % [k, tracks.size(), ", ".join(agg.keys().map(func(c): return "%s 팝 %d" % [c, agg[c].pops])), out_dir])
