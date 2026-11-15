# 가벼운 모션 팝 카운터 (W48): 새 모델 몸의 뼈 회전이 한 표본 (1/60초) 에 임계 (몸통·팔다리 35°, 머리 60°) 를 넘고 갑자기 늘면 '튐' 한 번 —
# core/motion_qa.gd 의 가벼운 모드 (--motion-qa) 와 같은 기준이지만 노드 없이, 판 중 기본으로 켜 둘 수 있게 아주 싸게:
#   · 몸 하나만 0.5초씩 번갈아 지켜봄 (연속 표본이어야 각속도가 뜻이 있어서) → 프레임당 뼈 12개 한 몸 = 몇 µs. 몸마다 '관측 초' 를 같이 세어 비교할 수 있게 (캐릭터별 팝 수 / 관측 초)
#   · 표본은 60Hz 시간 간격 (프레임이 더 짧으면 건너뜀, 더 길면 각을 1/60초 몫으로 줄여 셈)
#   · 맞아 날아가는·쓰러진 몸 (래그돌) 은 판정 대상 아님 (motion_qa 와 같은 제외)
# 결과는 core/report.gd 가 보고서에 넣음 (캐릭터별 팝 수·관측 초·상위 5개). 순수 계산이 아닌 부분은 새 모델 몸 (chars/external.gd) 의 ext.sk·ext.last_st 읽기만 — 몸은 안 건드림.
extends RefCounted

const Motion_ := preload("res://chars/ext_motion.gd")
const Rag_ := preload("res://chars/ragdoll.gd")
const M := preload("res://core/motion_qa_math.gd")

const BONES := ["Hips", "Spine", "Spine2", "Head", "LeftUpLeg", "RightUpLeg", "LeftLeg", "RightLeg", "LeftArm", "RightArm", "LeftForeArm", "RightForeArm"]
const WINDOW_MS := 500.0 # 한 몸을 이만큼 지켜본 뒤 다음 몸으로
const SAMPLE_US := 16000 # 표본 간격 (60Hz 에서 프레임 지터를 받아 줌)
const SAMPLE_S := 1.0 / 60.0
const RAG_MARGIN := 4 # 래그돌이 풀린 뒤 이만큼 표본은 계속 제외
const TOP_KEEP := 5
const MAX_GAP_S := 0.08 # 표본 사이가 이보다 길면 (멈춤·창 끌기) 그 표본은 버림

static var enabled := true # 테스트가 끔

var total := 0
var by := {} # 캐릭터 → 팝 수
var obs := {} # 캐릭터 → 관측 초
var top: Array = [] # {sev, char, bone, t} 심한 순서 TOP_KEEP 개
var win_body = null
var win_since_us := 0
var last_us := 0
var cursor := -1
var have := false
var prev: Array = []
var w_prev := PackedFloat32Array()
var excl_left := 0
var last_pos := Vector3.INF
var _cache := {} # Skeleton3D id → {ids, thr, names}
var last_cost_us := 0 # 마지막 step 이 쓴 시간 (측정용)


func reset() -> void:
	total = 0
	by = {}
	obs = {}
	top = []
	win_body = null
	last_us = 0
	cursor = -1
	have = false
	excl_left = 0


# 프레임마다 (core/report.gd tick). t_s = 판 시작부터 초
func step(now_us: int, t_s: float) -> void:
	if not enabled or Motion_.bodies.is_empty():
		return
	if win_body == null or not _usable(win_body) or now_us - win_since_us >= int(WINDOW_MS * 1000.0):
		_next_body(now_us)
		if win_body == null:
			return
	var gap := now_us - last_us
	if last_us > 0 and gap < SAMPLE_US:
		return
	var t0 := Time.get_ticks_usec()
	var first := last_us == 0
	last_us = now_us
	_sample(win_body, gap / 1000000.0 if not first else 0.0, t_s)
	last_cost_us = Time.get_ticks_usec() - t0


func _usable(b) -> bool:
	if not is_instance_valid(b) or b.get("ext") == null or not b.is_inside_tree() or not b.is_visible_in_tree():
		return false
	var ext = b.ext
	return ext.last_st != null and ext.st_frame >= Engine.get_process_frames() - 2


func _next_body(now_us: int) -> void:
	var list: Array = Motion_.bodies
	win_body = null
	have = false
	for k in list.size():
		var i := (cursor + 1 + k) % list.size()
		if _usable(list[i]):
			cursor = i
			win_body = list[i]
			win_since_us = now_us
			last_us = 0
			excl_left = 0
			last_pos = Vector3.INF
			return


func _info(sk: Skeleton3D) -> Dictionary:
	var key := sk.get_instance_id()
	if _cache.has(key):
		return _cache[key]
	var ids := PackedInt32Array()
	var thr := PackedFloat32Array()
	var names := []
	for n in BONES:
		var i := sk.find_bone("mixamorig_" + n)
		if i >= 0:
			ids.append(i)
			thr.append(M.pop_thr(M.bone_class("mixamorig_" + n)))
			names.append(n)
	var info := {"ids": ids, "thr": thr, "names": names}
	_cache[key] = info
	if _cache.size() > 32:
		_cache.clear()
	return info


# 이 몸이 지금 래그돌·맞는 중이라 판정 대상이 아닌가
func _excluded(b, ext) -> bool:
	var st: Dictionary = ext.last_st
	if bool(st.get("stunned", false)) or float(st.get("tumble", 0.0)) > 0.0 or float(st.get("flip", -1.0)) >= 0.0 or float(st.get("dizzy", 0.0)) > 0.0 or float(st.get("whirl", -1.0)) >= 0.0:
		excl_left = RAG_MARGIN
	var rg = Rag_._inst
	if rg != null and is_instance_valid(rg) and rg.rags.has(b):
		var r: Dictionary = rg.rags[b]
		if r.awake and float(r.motor) < 0.97:
			excl_left = RAG_MARGIN
	if excl_left > 0:
		excl_left -= 1
		return true
	return false


func _sample(b, gap_s: float, t_s: float) -> void:
	var ext = b.ext
	var gp: Vector3 = b.global_position
	if last_pos != Vector3.INF and gp.distance_to(last_pos) > 0.8:
		have = false # 순간이동 (부활·재배치)
	last_pos = gp
	if _excluded(b, ext) or gap_s > MAX_GAP_S:
		have = false
		return
	sample_skel(ext.sk, gap_s, t_s, str(b.get("char_id")))


# 뼈대 하나의 표본 한 번 (테스트·측정이 합성 뼈대로 직접 부름). gap_s = 앞 표본과의 시간
func sample_skel(sk: Skeleton3D, gap_s: float, t_s: float, ch: String) -> void:
	var info := _info(sk)
	var ids: PackedInt32Array = info.ids
	var thr: PackedFloat32Array = info.thr
	var n := ids.size()
	if prev.size() != n:
		prev.resize(n)
		w_prev.resize(n)
		have = false
	var scale := minf(1.0, SAMPLE_S / gap_s) if gap_s > 0.0 else 1.0
	if have:
		obs[ch] = float(obs.get(ch, 0.0)) + gap_s
	for i in n:
		var q := sk.get_bone_pose_rotation(ids[i])
		if have:
			var w := rad_to_deg(prev[i].angle_to(q)) * scale
			var th := thr[i]
			if w > th and absf(w - w_prev[i]) >= M.POP_JERK_K * th:
				_pop(ch, str(info.names[i]), w, t_s)
			w_prev[i] = w
		else:
			w_prev[i] = 0.0
		prev[i] = q
	have = true


func _pop(ch: String, bone: String, w: float, t_s: float) -> void:
	total += 1
	by[ch] = int(by.get(ch, 0)) + 1
	top.append({"sev": w, "char": ch, "bone": bone, "t": t_s})
	if top.size() > TOP_KEEP * 4:
		top.sort_custom(func(a, c): return a.sev > c.sev)
		top = top.slice(0, TOP_KEEP)


# 보고서 칸 (관측한 몸이 하나도 없으면 안 넣음 → 새 모델 몸이 없는 판은 모션 줄이 안 나옴)
func into(d: Dictionary) -> void:
	var secs := 0.0
	for k in obs:
		secs += float(obs[k])
	if secs <= 0.0 and total == 0:
		return
	var rows := top.duplicate()
	rows.sort_custom(func(a, c): return a.sev > c.sev)
	d["pops"] = total
	d["pop_by"] = by
	d["pop_obs"] = obs
	d["pop_lines"] = rows.slice(0, TOP_KEEP).map(func(r): return "%s %s %.0f°/표본 @ %.1fs" % [r.char, r.bone, r.sev, r.t])
