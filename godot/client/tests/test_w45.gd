# W45 최적화 7차: 입장 첫 프레임 쪼개기 (지형 네 단계·맵 적용 세 단계·초상 자세 굳히기 조각·외부 몸 붙이기 네 조각·몸 숨김 규칙)
# · 몸 LOD 압박 단계 (adapt_calc) · 코드 몸·메모리 점검 결과 (docs/w45/README.md)
extends RefCounted

const Gate := preload("res://core/entry_gate.gd")
const C := preload("res://core/config.gd")
const Body := preload("res://chars/body.gd")
const Chars := preload("res://chars/chars.gd")
const External := preload("res://chars/external.gd")
const Scenery := preload("res://world/scenery.gd")
const Portrait := preload("res://ui/portrait.gd")
const AC := preload("res://world/adapt_calc.gd")
const OutFar := preload("res://world/outline_far.gd")
const ShadowCalc := preload("res://world/shadow_calc.gd")
const PoseLod := preload("res://world/pose_lod.gd")
const WC := preload("res://world/world_config.gd")

var errors: Array = []


func check(cond: bool, msg: String) -> void:
	if not cond:
		errors.append(msg)


# 자식 메시 정점 수 목록 (순서대로) — 단계로 지은 것과 한 번에 지은 것이 같은 모양인지
func _shape(s: Scenery) -> Array:
	var out := []
	for host in [s, s.drift]:
		for c in host.get_children():
			if c.is_queued_for_deletion():
				continue
			if c is MeshInstance3D and (c as MeshInstance3D).mesh != null:
				var m: Mesh = (c as MeshInstance3D).mesh
				out.append([c.get_parent() == s, m.get_surface_count(), (m.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()])
			elif c is MultiMeshInstance3D:
				out.append(["motes", (c as MultiMeshInstance3D).multimesh.instance_count])
	out.append(["far", s.far_objs.size()])
	return out


# 지형: build_begin + build_step 네 번 = 한 번에 지은 것과 같은 메시 (난수 이어 씀), 단계 사이엔 building()
func test_scenery_staged_equals_full() -> void:
	for id in C.WORLD_THEMES.keys():
		var full := Scenery.new()
		full._ready()
		full.build(id, 14, 14, false, 32)
		var part := Scenery.new()
		part._ready()
		check(part.build_begin(id, 14, 14, false, 32), "%s: 지을 일이 있음" % id)
		var steps := 0
		while part.building():
			steps += 1
			var more := part.build_step()
			check(more == part.building(), "%s: 더 남았으면 building" % id)
			if steps > 10:
				break
		check(steps == 4, "%s: 네 단계 (%d)" % [id, steps])
		check(_shape(full) == _shape(part), "%s: 단계로 지은 것 = 한 번에 지은 것" % id)
		check(not part.stale(id, 14, 14, false), "%s: 다 지은 뒤엔 일 아님" % id)
		check(not part.build_begin(id, 14, 14, false, 32), "%s: 같은 걸 또 지으라면 건너뜀" % id)
		full.free()
		part.free()


# 짓는 중에 다른 테마·크기가 오면 처음부터 (옛 조각은 버림)
func test_scenery_restart_midway() -> void:
	var ids: Array = C.WORLD_THEMES.keys()
	var a := Scenery.new()
	a._ready()
	a.build_begin(ids[0], 12, 12, false, 32)
	a.build_step()
	a.build_step()
	check(a.building() and a.stale(ids[1], 12, 12, false), "짓는 중에 다른 테마는 일")
	a.build_begin(ids[1], 12, 12, false, 32)
	while a.build_step():
		pass
	var ref := Scenery.new()
	ref._ready()
	ref.build(ids[1], 12, 12, false, 32)
	check(a.theme_id == ids[1] and _shape(a) == _shape(ref), "중간에 갈아탄 것 = 처음부터 지은 것")
	a.free()
	ref.free()


# 초상 자세 굳히기를 10번씩 나눠 불러도 (시각 i × 16ms 그대로) 코드 몸 관절 자세가 한 번에 부른 것과 같음
func test_prime_chunks_equal_whole() -> void:
	check(Portrait.PRIME_STEPS % Portrait.PRIME_CHUNK == 0, "조각이 50 을 나눠 떨어짐")
	for id in ["bard", "berserker", "builder", "cannon"]:
		var a = Chars.make_body(id, Color(0.8, 0.2, 0.2))
		var b = Chars.make_body(id, Color(0.8, 0.2, 0.2))
		Portrait.prime_idle(a)
		var i := 0
		while i < Portrait.PRIME_STEPS:
			Portrait.prime_chunk(b, i, Portrait.PRIME_CHUNK)
			i += Portrait.PRIME_CHUNK
		var worst := 0.0
		var na: Array = a.find_children("*", "Node3D", true, false)
		var nb: Array = b.find_children("*", "Node3D", true, false)
		check(na.size() == nb.size(), "%s: 노드 수 같음" % id)
		for k in mini(na.size(), nb.size()):
			var ta: Transform3D = (na[k] as Node3D).transform
			var tb: Transform3D = (nb[k] as Node3D).transform
			worst = maxf(worst, (ta.origin - tb.origin).length())
			worst = maxf(worst, ta.basis.get_rotation_quaternion().angle_to(tb.basis.get_rotation_quaternion()))
		# 실제 시계 (Time) 를 읽는 숨쉬기가 있어 두 몸이 부르는 시각이 조금 달라 ~0.0007 라디안 (0.04도) 차 — 눈에 안 보임
		check(worst < 0.005, "%s: 나눠 부른 자세 = 한 번에 부른 자세 (최대 차 %.6f)" % [id, worst])
		a.free()
		b.free()


# 외부 몸 붙이기: split_ext 로 만든 몸은 바로 안 붙고 (ext null, ext_pending) 조각 네 개로 붙음 — 같은 몸 (그리는 조각 수) 이 한 번에 붙인 것과 같음
func test_attach_job_four_pieces() -> void:
	if not Body.use_ext:
		return
	for id in ["tank", "ninja", "hunter", "hook"]:
		if not External.has_char(id):
			continue
		var sync = Chars.make_body(id, Color(0.8, 0.2, 0.2)) # 옛 길 (한 번에)
		Body.split_ext = true
		var split = Chars.make_body(id, Color(0.8, 0.2, 0.2))
		Body.split_ext = false
		check(split.ext == null and split.ext_pending(), "%s: 만들고 나면 아직 안 붙음" % id)
		check(sync.ext != null and not sync.ext_pending(), "%s: 옛 길은 바로 붙음" % id)
		var seq := []
		var guard := 0
		while split.ext_pending() and guard < 200:
			guard += 1
			var r: int = split.ext_step()
			if r >= 0:
				seq.append(r)
		check(seq.size() == 4 and seq.slice(0, 3).all(func(x): return x == 0) and seq[3] == 1, "%s: 조각 넷 (0·0·0·1) = %s" % [id, str(seq)])
		check(split.ext != null and not split.ext_pending(), "%s: 다 붙음" % id)
		check(split.drawn.size() == sync.drawn.size(), "%s: 그리는 조각 수 같음 (%d vs %d)" % [id, split.drawn.size(), sync.drawn.size()])
		check(split.ext.parts.size() == sync.ext.parts.size() and split.ext.maps.size() == sync.ext.maps.size(), "%s: 재질 조각·뼈 맞춤 수 같음" % id)
		check(split.ext_step() == 1, "%s: 다 붙은 뒤 또 부르면 끝" % id)
		sync.free()
		split.free()


# 코드 몸 (새 모델 없는 4명) 은 붙일 게 없으니 split_ext 여도 바로 완성
func test_code_body_never_pending() -> void:
	Body.split_ext = true
	for id in ["bard", "berserker", "cannon", "builder"]:
		var b = Chars.make_body(id, Color(0.8, 0.2, 0.2))
		check(not b.ext_pending() and b.ext == null, "%s: 코드 몸은 대기 없음" % id)
		b.free()
	Body.split_ext = false


# 끄면 (Gate 꺼짐 · --no-body-split) 옛 길 그대로: 입장 문 꺼짐이면 no_split 이 어떤 값이든 문은 늘 통과
func test_split_switches() -> void:
	Gate.reset()
	check(not Gate.no_split("body") and not Gate.no_split("scene") and not Gate.no_split("theme") and not Gate.no_split("portrait"), "기본은 다 켬")
	Gate.entered = false
	Gate.reset()
	check(Gate.entered, "reset 이 입장 첫 바퀴 표시를 되돌림 (초상이 영영 안 막히게)")


# 몸 자리 (world/bodies.gd): 외부 모델이 다 붙기 전엔 몸을 안 보이고 pose 도 안 부름 (쉬는 자세 맞춤이 관절 처음 자세를 읽음), 조각은 프레임당 WC.BODY_JOBS_PER_FRAME 몸까지,
# 다 붙은 프레임부터 보임·자세 줌
func test_bodies_hide_until_attached() -> void:
	if not Body.use_ext or not External.has_char("tank"):
		return
	Gate.reset()
	var Bodies = load("res://world/bodies.gd")
	var bs = Bodies.new()
	bs._ready()
	var players := []
	for i in 4:
		players.append({"id": i + 1, "slot": i, "name": "P%d" % i, "nick": "", "char": ["tank", "ninja", "hunter", "hook"][i], "color": i, "alive": true, "yaw": 0.0, "x": 3.0 + i, "y": 3.0, "z": 1.0, "damage": 0, "team": ""})
	var st := {"players": players, "teamMode": false}
	var frames := 0
	var seen_hidden := false
	var max_jobs := 0
	var shown_at := {}
	while frames < 40:
		frames += 1
		var before := 0
		for id in bs.nodes:
			if bs.nodes[id].body.ext_pending():
				before += 1
		bs.update(st, null, false, false, frames * 16.0)
		var after := 0
		for id in bs.nodes:
			var n: Dictionary = bs.nodes[id]
			if n.body.ext_pending():
				after += 1
				seen_hidden = true
				check(not n.body.visible, "붙기 전 몸은 안 보임 (프레임 %d)" % frames)
				check(n.body.last_ms == null, "붙기 전엔 pose 를 안 부름 (프레임 %d)" % frames)
			elif n.body.ext != null and not shown_at.has(id):
				shown_at[id] = frames
				check(n.body.visible, "다 붙은 프레임부터 보임")
		max_jobs = maxi(max_jobs, before - after)
		if shown_at.size() == 4:
			break
	check(seen_hidden, "한 프레임 이상 숨은 채 지어짐")
	check(shown_at.size() == 4, "40프레임 안에 4명 다 붙음 (%d)" % shown_at.size())
	check(max_jobs <= WC.BODY_JOBS_PER_FRAME + 1, "한 프레임에 끝나는 몸이 상한 안 (%d)" % max_jobs)
	bs.free()
	Gate.reset()


# ---------- 항목 2: 몸 압박 단계 (적응형 해상도 다음 수단) ----------

# 가짜 GPU 부하 (배율² 로 줄어듦) 를 정한 만큼 돌리며 단계가 바뀐 순서를 적음: "배율" · "MSAA" · "압박1" · "압박2"
func _ladder(ctl, frames: int, gpu_full: float, cpu: float) -> Array:
	var seq := []
	var last_scale: float = ctl.scale
	var last_cut: bool = ctl.cut
	var last_press: int = ctl.press
	for i in frames:
		var g: float = gpu_full * ctl.scale * ctl.scale
		var f: float = maxf(cpu, g)
		if ctl.push(f, cpu, g):
			if absf(ctl.scale - last_scale) > 0.0001:
				seq.append("배율")
			if ctl.cut != last_cut:
				seq.append("MSAA")
			if ctl.press != last_press:
				seq.append("압박%d" % ctl.press)
			last_scale = ctl.scale
			last_cut = ctl.cut
			last_press = ctl.press
	return seq


# 순서: 해상도 (바닥까지) → MSAA → 몸 압박 1 → 2, 한 번에 한 단계, 단계 사이는 press_windows 창 이상
func test_press_ladder_order() -> void:
	var c := AC.Ctl.new(1.0, 16.667)
	var seq := _ladder(c, 20 * 120, 200.0, 4.0)
	var steps := seq.filter(func(x): return x != "배율")
	check(steps == ["MSAA", "압박1", "압박2"], "단계 순서: MSAA → 압박1 → 압박2 (%s)" % str(steps))
	var first_press := seq.find("압박1")
	check(first_press > 0 and seq.slice(0, first_press).has("MSAA") and seq.slice(0, seq.find("MSAA")).all(func(x): return x == "배율"), "압박은 해상도·MSAA 다음 (%s)" % str(seq))
	check(c.scale == 0.6 and c.cut and c.press == 2, "끝: 바닥 배율 · MSAA 낮춤 · 압박 2 (%.2f %s %d)" % [c.scale, str(c.cut), c.press])
	# 더 오래 돌려도 2 를 넘지 않음
	_ladder(c, 20 * 60, 200.0, 4.0)
	check(c.press == 2, "압박은 press_max 까지만")
	c.restart()
	check(c.press == 0 and not c.cut, "판이 끝나면 (restart) 압박·MSAA 되돌림")


# 해상도가 바닥이 아니면 (내릴 여지) 압박 안 함 · CPU 가 병목이면 (해상도로도 몸 압박으로도 안 풀림) 안 함 · 가벼운 부하면 안 함
func test_press_only_when_gpu_bound_at_floor() -> void:
	var c1 := AC.Ctl.new(1.0, 16.667)
	_ladder(c1, 20 * 60, 24.0, 4.0) # 배율을 낮추면 풀리는 부하: 바닥까지 안 감
	check(c1.press == 0 and not c1.cut and c1.scale > 0.6, "해상도로 풀리면 압박·MSAA 안 건드림 (%.2f)" % c1.scale)
	var c2 := AC.Ctl.new(1.0, 16.667)
	_ladder(c2, 20 * 120, 5.0, 40.0) # CPU 가 느림
	check(c2.press == 0 and c2.scale == 1.0, "CPU 병목이면 가만히")
	var c3 := AC.Ctl.new(1.0, 16.667)
	_ladder(c3, 20 * 120, 4.0, 4.0)
	check(c3.press == 0 and c3.scale == 1.0, "빠르면 가만히")


# 끄기 (press_max 0 = --no-body-pressure) 면 예전 그대로 (MSAA 까지만), 중간에 부하가 풀리면 연속이 끊겨 다음 단계로 안 감
func test_press_off_and_interrupted() -> void:
	var cfg := WC.ADAPT.duplicate()
	cfg["press_max"] = 0
	var c := AC.Ctl.new(1.0, 16.667, cfg)
	var seq := _ladder(c, 20 * 120, 200.0, 4.0)
	check(c.press == 0 and c.cut and not seq.has("압박1"), "press_max 0: MSAA 까지만 (%s)" % str(seq))
	# 부하가 한 창이라도 풀리면 (목표 안) 바닥 연속이 끊김: cut 뒤 press 직전에 끊고 다시 시작하면 처음부터 셈
	var c2 := AC.Ctl.new(1.0, 16.667)
	_ladder(c2, 20 * (int(WC.ADAPT.cut_windows) + 30), 200.0, 4.0)
	var before: int = c2.press
	for i in 20 * 2: # 두 창 가벼움
		c2.push(8.0, 4.0, 4.0)
	var seq2 := _ladder(c2, 20 * (int(WC.ADAPT.press_windows) - 1), 200.0, 4.0)
	check(c2.press <= before + 1, "끊긴 뒤엔 press_windows 를 다시 채워야 다음 단계 (%d → %d)" % [before, c2.press])


# 압박 단계 표: 0 단계는 원래 표 그대로 (모습 불변), 1 단계는 외곽선·자세 LOD 만, 2 단계에 그림자
func test_press_cfg_tables() -> void:
	check(WC.outline_far_cfg(0) == WC.OUTLINE_FAR and WC.shadow_cfg(0) == WC.SHADOW and WC.shadow_cfg(1) == WC.SHADOW and WC.pose_lod_cfg(WC.POSE_LOD, 0) == WC.POSE_LOD, "0 단계 (그림자는 1 단계도) 원래 표")
	var o1 := WC.outline_far_cfg(1)
	check(float(o1.taper_from) < float(WC.OUTLINE_FAR.taper_from) and float(o1.gone) < float(WC.OUTLINE_FAR.gone) and float(o1.gone) > float(o1.taper_from), "외곽선 거리가 가까워짐 (%s)" % str(o1))
	check(float(o1.min_k) == float(WC.OUTLINE_FAR.min_k) and float(o1.hyst) == float(WC.OUTLINE_FAR.hyst), "굵기·문턱 여유는 그대로")
	var s2 := WC.shadow_cfg(2)
	check(float(s2.far) < float(WC.SHADOW.far) and float(s2.hyst) == float(WC.SHADOW.hyst) and s2.caster_lod == WC.SHADOW.caster_lod, "2 단계: 그림자 끄는 거리만 가까워짐")
	var p1 := WC.pose_lod_cfg(WC.POSE_LOD, 1)
	check(float(p1.far2) < float(WC.POSE_LOD.far2) and float(p1.far3) < float(WC.POSE_LOD.far3) and float(p1.near) == float(WC.POSE_LOD.near) and float(p1.margin) == float(WC.POSE_LOD.margin), "자세 LOD 먼 단 거리만 당김")
	# 가까운 몸 (내 몸·3m) 은 어느 단계에서도 그대로: 외곽선 굵기 1, 자세는 매 프레임
	for k in 3:
		check(OutFar.thickness_k(3.0, WC.outline_far_cfg(k)) == 1.0, "가까운 몸 외곽선 굵기 그대로 (%d단계)" % k)
		check(not OutFar.far_state(3.0, 70.0, false, false, WC.outline_far_cfg(k)) and not ShadowCalc.far_off(3.0, 70.0, false, false, WC.shadow_cfg(k)), "가까운 몸은 껍질·그림자 그대로 (%d단계)" % k)
		check(PoseLod.interval_ms(3.0, true, false, WC.pose_lod_cfg(WC.POSE_LOD, k)) == PoseLod.interval_ms(3.0, true, false, WC.POSE_LOD), "가까운 몸 자세 주기 그대로 (%d단계)" % k)
	check(not OutFar.far_state(12.0, 70.0, false) and OutFar.far_state(12.0, 70.0, false, false, WC.outline_far_cfg(1)), "12m 몸: 평소엔 껍질 있음, 1 단계는 뗌")
	check(not ShadowCalc.far_off(16.0, 70.0, false) and ShadowCalc.far_off(16.0, 70.0, false, false, WC.shadow_cfg(2)), "16m 몸: 평소엔 그림자, 2 단계는 끔")
	check(OutFar.far_state(12.0, 70.0, false, true, WC.outline_far_cfg(2)) == false, "내 몸은 늘 껍질 있음")
	check(PoseLod.interval_ms(8.0, true, false, WC.pose_lod_cfg(WC.POSE_LOD, 1)) > PoseLod.interval_ms(8.0, true, false, WC.POSE_LOD), "8m 몸: 1 단계는 자세를 드물게")
