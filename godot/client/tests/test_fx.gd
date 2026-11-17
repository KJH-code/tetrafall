# G5 효과 계산이 JS (client/effects.js·ko.js) 와 같은지 (tools/fixtures-fx.mjs 가 뽑은 정답) + 효과 노드가 이벤트를 받아 파편·줄기·소리 신호를 내는지
extends RefCounted

const C := preload("res://core/config.gd")
const Co := preload("res://core/coords.gd")
const FM := preload("res://fx/fx_math.gd")
const Effects := preload("res://fx/effects.gd")
const KO := preload("res://fx/ko.gd")
const FX := preload("res://fx/fx.gd")
const G3 := preload("res://shaders/g3.gd")

var errors: Array = []


func check(cond: bool, msg: String) -> void:
	if not cond:
		errors.append(msg)


func near(a: float, b: float, eps := 1e-6) -> bool:
	return absf(a - b) <= eps * maxf(1.0, absf(b))


func js():
	return JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/fx.json"))


func root() -> Window:
	return (Engine.get_main_loop() as SceneTree).root


func test_shake_matches_js() -> void:
	var sh := {"amp": 0.0, "ms": 1.0, "until": 0.0}
	for r in js().shake:
		FM.shake_take(sh, 1000.0 + r.t, r.amp, r.ms)
		check(near(sh.amp, r.gotAmp) and near(sh.ms, r.gotMs) and near(sh["until"] - 1000.0, r.gotUntil), "흔들림 t=%s: %s vs JS %s %s %s" % [r.t, sh, r.gotAmp, r.gotMs, r.gotUntil])
	check(FM.shake_amp(sh, sh["until"]) == 0.0, "끝나면 흔들림 0")
	check(near(FM.shake_amp(sh, sh["until"] - sh.ms * 0.5), sh.amp * 0.25), "흔들림은 남은 비율 제곱")


func test_squash_punch_match_js() -> void:
	var d = js()
	for r in d.squash:
		check(near(maxf(0.0, FM.squash(r[0])), r[1]), "찌그러짐 %s: %s vs JS %s" % [r[0], FM.squash(r[0]), r[1]])
	for r in d.punch:
		check(near(maxf(0.0, FM.punch(r[0])), r[1]), "팔 뻗음 %s: %s vs JS %s" % [r[0], FM.punch(r[0]), r[1]])


func test_time_scale_matches_js() -> void:
	var stop := 10000.0 + C.KO_CRUSH_STOP_MS # 가까운 압사 (JS 는 10000 에 death)
	var rows: Array = js().timeScale
	for i in rows.size():
		var r: Array = rows[i]
		var got: float
		if i < 5:
			got = FM.time_scale(10000.0 + r[0], stop, {})
		else:
			got = FM.time_scale(20000.0 + r[0] - 10000.0, stop, {"start": 20000.0, "until": 20000.0 + C.KO_FINAL_MS})
		check(near(got, r[1]), "시간 배율 %d (%s): %s vs JS %s" % [i, r[0], got, r[1]])


func test_smash_plume_match_js() -> void:
	var d = js()
	for r in d.smash:
		var at := FM.smash_at(Vector3(r.p.x, r.p.y, r.p.z), 12.0, 12.0)
		var dir := FM.smash_dir(r.out)
		check(at.is_equal_approx(Vector3(r.at[0], r.at[1], r.at[2])), "줄기 자리 %s vs JS %s" % [at, r.at])
		check(dir.distance_to(Vector3(r.dir[0], r.dir[1], r.dir[2])) < 1e-5, "줄기 방향 %s vs JS %s" % [dir, r.dir])
	for r in d.plume:
		var s := FM.plume(r[0] / (C.KO_SMASH_MS / 1000.0))
		check(near(s.x, r[1], 1e-5) and near(s.y, r[2], 1e-5) and near(s.z, r[3], 1e-5), "줄기 모양 %s: %s vs JS %s" % [r[0], s, r])
	check(d.plume.size() > 40, "줄기 프레임 %d" % d.plume.size())


func test_final_zoom_matches_js() -> void:
	var ko := KO.new()
	var cam := Camera3D.new()
	root().add_child(cam)
	for r in js().cam:
		cam.fov = 70.0
		cam.look_at_from_position(Co.gxyz(r.eye[0], r.eye[1], r.eye[2]), Co.gxyz(r.look[0], r.look[1], r.look[2]), Vector3.UP)
		ko.slow = {"start": 0.0, "until": C.KO_FINAL_MS, "x": float(r.target[0]), "y": float(r.target[1]), "z": float(r.target[2])}
		ko.cam_hook(cam, float(r.t))
		var f := Co.game(-cam.basis.z)
		check(near(cam.fov, r.fov, 1e-5), "줌 t=%s 시야 %s vs JS %s" % [r.t, cam.fov, r.fov])
		check(f.distance_to(Vector3(r.fwd[0], r.fwd[1], r.fwd[2])) < 1e-4, "줌 t=%s 보는 쪽 %s vs JS %s" % [r.t, f, r.fwd])
	cam.free()
	ko.free()


func test_edge_matches_js() -> void:
	for r in js().edge:
		var e := FM.edge_pos(r.sx, r.sy, r.behind)
		check(near(e.x, r.px, 1e-4) and near(e.y, r.py, 1e-4), "화면 끝 %s: %s vs JS %s %s" % [[r.sx, r.sy, r.behind], e, r.px, r.py])
		check(near(FM.edge_alpha(0.5), r.alpha), "화면 끝 세기 %s vs JS %s" % [FM.edge_alpha(0.5), r.alpha])


func test_effects_pool() -> void:
	var fx := Effects.new()
	root().add_child(fx)
	fx.burst(Vector3(3, 3, 1), {"x": 1, "y": 0}, 0xff0000, 200) # 160 넘게 → 돌려 씀
	fx.ring(Vector3(3, 3, 1), 0xffffff, 2.0, 0.3, true)
	fx.update(0.01, null)
	check(fx.alive_particles() == Effects.MAX_PARTICLES, "파편 %d (최대 %d)" % [fx.alive_particles(), Effects.MAX_PARTICLES])
	check(fx.alive_rings() == 1 and fx.ring_mmi.visible, "고리가 보임")
	for i in 100:
		fx.update(0.02, null)
	check(fx.alive_particles() == 0, "2초 뒤 파편 %d" % fx.alive_particles())
	check(fx.alive_rings() == 0 and not fx.ring_mmi.visible, "고리 사라짐")
	fx.hit_squash(7)
	check(fx.squash_amount(7) >= 0.0 and fx.squash_amount(8) == 0.0, "찌그러짐 타이머")
	fx.free()


# 이벤트 → 효과: 맞음은 파편, 낙사 (out 있음) 는 스매시 줄기 + 소리 신호, 마지막 킬은 슬로모션 + 소리 신호, 내 맞음은 흔들림
func test_events_to_fx() -> void:
	var keep_state := Store.state
	var keep_by := Store._players_by_id
	var keep_me = Store.my_id
	var a := {"id": 1, "x": 2.0, "y": 2.0, "z": 0.0, "alive": true, "slot": 0, "color": 0}
	var b := {"id": 2, "x": 3.0, "y": 2.0, "z": 0.0, "alive": true, "slot": 1, "color": 1}
	Store.state = {"phase": "playing", "field": {"w": 10, "d": 10}, "players": [a, b]}
	Store._players_by_id = {1: a, 2: b}
	Store.my_id = 2
	var cues := []
	var on_cue := func(k, i): cues.append(k)
	View.sound_cue.connect(on_cue)
	var fx := FX.new()
	root().add_child(fx)
	fx.on_event({"type": "hit", "by": 1, "target": 2, "ok": true, "kind": "melee"})
	fx.effects.update(0.001, null)
	check(fx.effects.alive_particles() == int(C.FX_PARTICLES), "맞음 파편 %d" % fx.effects.alive_particles())
	check(FM.shake_amp(fx.effects.sh, Effects.now_ms()) > 0.0, "내가 맞으면 흔들림")
	fx.on_event({"type": "death", "who": 1, "cause": "fall", "x": -1.5, "y": 4.0, "z": -3.0, "out": {"x": -1, "y": 0}})
	check(fx.ko.plumes.size() == 1, "낙사 줄기 %d" % fx.ko.plumes.size())
	fx.on_event({"type": "death", "who": 1, "cause": "crush", "x": 2.0, "y": 2.0, "z": 0.0})
	check(fx.ko.time_scale() == C.KO_CRUSH_STOP_SCALE, "가까운 압사 히트스톱 %s" % fx.ko.time_scale())
	fx.on_event({"type": "finalKill", "who": 1, "by": 2, "x": 2.0, "y": 2.0, "z": 0.0})
	check(fx.ko.slow_left() > C.KO_FINAL_MS - 50, "마지막 킬 슬로모션 남음 %s" % fx.ko.slow_left())
	check(cues == ["smash", "koCrush", "final"], "소리 신호 %s" % [cues])
	fx.on_event({"type": "nothing"})
	check(fx.events == 4, "효과 낸 이벤트 %d" % fx.events)
	View.sound_cue.disconnect(on_cue)
	fx.free()
	Store.state = keep_state
	Store._players_by_id = keep_by
	Store.my_id = keep_me
	View.time_scale = 1.0


# 카메라 바로 앞 효과가 화면을 덮지 않게 (2026-10-31 B4 스샷 '큰 반투명 판'): 파편·고리·줄기 재질은 가까우면 흐려짐, 카메라가 줄기 안이면 옅게
func test_near_camera_fades() -> void:
	var fx := Effects.new()
	var ring_mat: StandardMaterial3D = fx.ring_mat
	var box_mat: StandardMaterial3D = fx.mm.mesh.material
	for m in [ring_mat, box_mat]:
		check(m.distance_fade_mode == BaseMaterial3D.DISTANCE_FADE_PIXEL_ALPHA and m.distance_fade_max_distance > m.distance_fade_min_distance, "가까우면 흐려짐 %s" % m)
	for m in [fx.glow_mat, fx.smoke_mat]: # W18 빛·연기 셰이더도 같은 거리
		check((m.get_shader_parameter("near_fade") as Vector2).is_equal_approx(Vector2(FM.FX_NEAR_FADE[0], FM.FX_NEAR_FADE[1])), "W18 셰이더 가까우면 흐려짐 %s" % m)
	fx.free()
	var ax := Vector3(-1, 0, 0)
	check(near(FM.plume_inside_fade(Vector3(-4, 0, 0), ax, 1.0, 1.0), 0.2), "줄기 축 위 = 옅게")
	check(near(FM.plume_inside_fade(Vector3(4, 0, 0), ax, 1.0, 1.0), 1.0), "줄기 뒤 = 그대로")
	check(near(FM.plume_inside_fade(Vector3(-4, 5, 0), ax, 1.0, 1.0), 1.0), "줄기 밖 = 그대로")
	check(near(FM.plume_inside_fade(Vector3(-20, 0, 0), ax, 1.0, 1.0), 1.0), "줄기 끝 너머 = 그대로")


# 효과 기록 (body_fx·marks 가 부르는 effects.ring·burst 인자)
class FxRec:
	var rings := []
	var bursts := []

	func ring(p: Vector3, color := 0xffffff, grow := 2.2, life := 0.28, horizontal := false) -> void:
		rings.append([p, color, grow, life, horizontal])

	func burst(p, dir, color, n, speed, size, life) -> void:
		bursts.append([p, dir, color, n, speed, size, life])


# marks.gd 의 납작 몸 만들기만 기록 (몸 복제는 트리 안이어야 함)
class MarksRec extends "res://world/marks.gd":
	var flats_for := []

	func crush_flat(who) -> void:
		flats_for.append(who)


func test_w3_js_diffs() -> void:
	# W3 2026-11-02 JS 대조: 몸 찌그러짐·밀치기 팔 값은 group fx 노드의 effects 에서 (Fx 바로 아래만 찾아 늘 0 이던 것)
	var Body := preload("res://chars/body.gd")
	var F = load("res://fx/fx.gd").new()
	var e = Body.fx_effects(F)
	check(e != null and e == F.effects, "몸이 찾는 효과 노드 = fx.gd 의 effects")
	check(Body.fx_effects(null) == null, "fx 없으면 null")
	F.free()
	# 납작 몸은 marks.gd 하나만 (body.gd 에서도 만들면 둘이 겹침)
	var holder := Node3D.new()
	var b = load("res://chars/chars.gd").make_body("tank", Color(0.5, 0.5, 0.9))
	b.pid = 3
	holder.add_child(b)
	var before := holder.find_children("*", "", true, false).size()
	b.on_event({"type": "death", "cause": "crush", "who": 3})
	check(holder.find_children("*", "", true, false).size() == before, "몸 (body.gd) 은 압사 납작 몸을 안 만듦")
	holder.free()
	var mk := MarksRec.new()
	mk.on_event({"type": "death", "cause": "crush", "who": 3})
	mk.on_event({"type": "death", "cause": "fall", "who": 4})
	check(mk.flats_for == [3], "marks.gd 가 death crush 로만 만듦 %s" % [mk.flats_for])
	mk.free()
	# 사냥꾼 표식 꽉 참 = 금빛 (main.js mark)
	var FX := load("res://fx/fx.gd")
	check(FX.mark_color(C.HUNTER_MARK_MAX) == int(C.HUNT_MARK_UI.full) and FX.mark_color(1) == 0xff3a2a, "표식 불꽃 색 (꽉 차면 HUNT_MARK_UI.full)")


func test_w3_skill_fx_like_js() -> void:
	# W3 JS 대조: 지상 F 준비 발밑 흰 고리 (render.js skillWindup) · 바드 diveEnd 파편·고리 (render.js diveEnd) · 대형 포탄 빛 (bigShellMat emissive)
	var Effects := preload("res://fx/effects.gd")
	var BF := preload("res://world/body_fx.gd")
	var bf = BF.new()
	var fx = Effects.new()
	bf.effects = fx
	bf.on_event({"type": "diveEnd", "what": "hit", "x": 1.0, "y": 2.0, "z": 1.0})
	check(fx.pi == 32 and fx.ri == 1, "diveEnd 맞힘: 파편 18+14, 고리 1 (얻음 %d·%d)" % [fx.pi, fx.ri])
	bf.on_event({"type": "diveEnd", "what": "land", "x": 1.0, "y": 2.0, "z": 0.0, "r": 2.0})
	check(fx.pi == 54 and fx.ri == 3, "diveEnd 땅: 흙 22, 고리 2")
	fx.free()
	# 지상 F 준비 (c7): 그 사람 발밑 (화면 위치) 예고 고리 하나, 준비 시간 동안 — body_fx 가 들고 몸을 따라감 (효과 풀 고리는 안 씀. 모양은 test_c7_windup_ring_thick)
	var rec := FxRec.new()
	bf.effects = rec
	bf.bodies = {"shown": {5: Vector3(1, 2, 3)}}
	bf.on_event({"type": "skillWindup", "who": 5, "ms": 400})
	check(rec.rings.is_empty() and bf.windups.size() == 1, "준비 고리 하나 (풀 고리 %s · 예고 고리 %d)" % [rec.rings, bf.windups.size()])
	check(bf.windups.size() == 1 and (bf.windups[0].at as Vector3).is_equal_approx(Vector3(1, 2, 3.05)) and is_equal_approx(float(bf.windups[0].ms) / 1000.0, 0.4), "준비 고리 (발밑 0.05 위, ms) %s" % [bf.windups])
	bf.windups.clear() # 노드는 bf 자식이라 bf.free() 때 같이
	bf.on_event({"type": "skillWindup", "who": 5})
	check(bf.windups.size() == 1 and is_equal_approx(float(bf.windups[0].ms), C.SKILL_WINDUP_MS), "ms 없으면 SKILL_WINDUP_MS")
	# 둔화 고리: 남은 둔화가 있으면 보임, 내 몸 1인칭이면 숨김 (JS 는 몸 그룹 자식)
	var d := {}
	var slow := {"alive": true, "slowLeft": 500}
	bf.third = func() -> bool: return false
	bf._status(d, slow, Vector3.ZERO, true, 0.0)
	check(not d.slow.node.visible, "둔화 고리: 내 1인칭이면 숨김")
	bf._status(d, slow, Vector3.ZERO, false, 0.0)
	check(d.slow.node.visible, "둔화 고리: 남은 보임")
	bf.third = func() -> bool: return true
	bf._status(d, slow, Vector3.ZERO, true, 0.0)
	check(d.slow.node.visible, "둔화 고리: 내 3인칭이면 보임")
	bf._status(d, {"alive": true, "slowLeft": 0}, Vector3.ZERO, false, 0.0)
	check(not d.slow.node.visible, "둔화 끝나면 숨김")
	bf.free()
	# 준비 중 끊기면 하얀 번쩍 바로 끔 (main.js windupUntil.delete), 평타 끊김은 그대로
	var b = load("res://chars/chars.gd").make_body("ninja", Color(0.5, 0.5, 0.9))
	b.pid = 4
	b.on_event({"type": "skillWindup", "who": 4, "ms": 400})
	check(b.windup_until > 0.0, "준비 시작")
	b.on_event({"type": "interrupt", "kind": "attack", "who": 4})
	check(b.windup_until > 0.0, "평타 끊김은 준비 번쩍 그대로")
	b.on_event({"type": "interrupt", "kind": "skill", "who": 4})
	check(b.windup_until == -1e9, "준비 중 끊기면 하얀 번쩍 끔")
	b.free()
	# 대형 포탄 몸통 스스로 빛남 (render.js bigShellMat emissive 0x501000)
	var sh = load("res://world/shots.gd").new()
	sh.make_mat = func(c: Color): return G3.toon_material(c)
	var m: ShaderMaterial = sh._big_shell_mat()
	check((m.get_shader_parameter("emissive") as Color).is_equal_approx(Color8(0x50, 0x10, 0x00)), "대형 포탄 빛 0x501000")
	sh.free()


# ---------- W18 이펙트 (fx/fx_config.gd) ----------
const FXC := preload("res://fx/fx_config.gd")


func test_w18_tiers_grow() -> void:
	var names := ["light", "medium", "heavy", "crit"]
	for i in range(1, names.size()):
		var a := FXC.tier(names[i - 1])
		var b := FXC.tier(names[i])
		for key in ["kick", "vm", "stop", "body"]:
			check(float(b[key]) >= float(a[key]), "%s 가 %s 이상 (%s)" % [names[i], names[i - 1], key])
		check(float(b.flash[0]) > float(a.flash[0]) and int(b.sparks[0]) > int(a.sparks[0]), "%s 번쩍·불꽃이 %s 보다 큼" % [names[i], names[i - 1]])
	# 약·중타는 화면 히트스톱 없음, 강·치명만. 중·강 흔들림은 JS 값 그대로 (effects.js: 맞음 1·1.6, 때림 1·2)
	check(FXC.tier("light").stop == 0.0 and FXC.tier("medium").stop == 0.0 and FXC.tier("heavy").stop > 0.0 and FXC.tier("crit").stop > FXC.tier("heavy").stop, "히트스톱은 강·치명만")
	check(FXC.tier("medium").shake_hurt == 1.0 and FXC.tier("medium").shake_hit == 1.0 and FXC.tier("heavy").shake_hurt == 1.6 and FXC.tier("heavy").shake_hit == 2.0, "중·강 흔들림 = JS")
	check(FXC.tier("모름") == FXC.tier("medium"), "모르는 단계 = 중")
	# 화면 단계 = 소리 단계 (같은 hit_tier)
	var SM := preload("res://audio/sound_math.gd")
	check(SM.hit_tier({"crit": true}) == "crit" and SM.hit_tier({"finish": true}) == "heavy" and SM.hit_tier({"star": true}) == "light" and SM.hit_tier({"kind": "push"}) == "medium", "단계 이름")
	for n in names:
		check(FXC.HIT_SPARK_COLOR.has(n) and FXC.HIT_FLASH_COLOR.has(n), "단계 색 %s" % n)


func test_w18_curves_and_levels() -> void:
	check(FXC.kick_k(0.0, 100.0) == 1.0 and is_equal_approx(FXC.kick_k(50.0, 100.0), 0.25) and FXC.kick_k(100.0, 100.0) == 0.0 and FXC.kick_k(-1.0, 100.0) == 0.0, "반동 곡선 (1-t)²")
	check(FXC.hit_scale(10.0, 20.0) == FXC.HITSTOP_SCALE and FXC.hit_scale(20.0, 20.0) == 1.0, "히트스톱 배율")
	check(FXC.level_of("high", false) == FXC.LEVELS.high and FXC.level_of("medium", false) == FXC.LEVELS.medium and FXC.level_of("high", true) == FXC.LEVELS.low and FXC.level_of("??", false) == FXC.LEVELS.medium, "화질 → 수준 (그래픽 낮춤 = 낮음)")
	check(FXC.count(10, FXC.LEVELS.high) == 10 and FXC.count(10, FXC.LEVELS.medium) == 7 and FXC.count(10, FXC.LEVELS.low) == 0 and FXC.count(1, FXC.LEVELS.medium) == 1, "덧칠 수 (낮음 0, 적어도 1)")
	check(FXC.reduced_k("shake", true) == FXC.REDUCED.shake and FXC.reduced_k("shake", false) == 1.0 and FXC.reduced_k("stop", true) == 0.0, "움직임 줄이기 배율")


# 효과 풀: 종류마다 MultiMesh 하나, 상한에서 돌려 씀, 낮음이면 덧칠 없음 (JS 파편·고리는 그대로)
func test_w18_pools_and_low() -> void:
	var fx := Effects.new()
	root().add_child(fx)
	fx.lv = FXC.LEVELS.high
	for i in 30:
		fx.impact(Vector3(3, 3, 1), {"x": 1, "y": 0}, "crit")
		fx.explode(Vector3(4, 4, 1), 1.3)
		fx.ring(Vector3(3, 3, 1), 0xffffff, 2.0, 0.3)
	fx.update(0.01, null)
	var s: Dictionary = fx.stats()
	check(s.glow == Effects.MAX_GLOW and s.smoke == Effects.MAX_SMOKE and s.chunks == Effects.MAX_CHUNKS and s.rings == Effects.MAX_RINGS, "상한에서 멈춤 %s" % [s])
	check(s.draws == 4, "빛·연기·조각·고리 MultiMesh 4개 = 그리기 4 (효과가 아무리 겹쳐도, 파편은 안 냄) %s" % [s])
	check(fx.get_children().size() == 5, "효과 노드 5개 그대로 (%d)" % fx.get_children().size())
	for i in 200:
		fx.update(0.02, null)
	s = fx.stats()
	check(s.glow == 0 and s.smoke == 0 and s.chunks == 0 and s.rings == 0 and s.draws == 0, "4초 뒤 다 사라짐 (그리기 0) %s" % [s])
	fx.lv = FXC.LEVELS.low
	fx.impact(Vector3(3, 3, 1), {"x": 1, "y": 0}, "crit")
	fx.explode(Vector3(4, 4, 1), 1.3)
	fx.quake(Vector3(4, 4, 0), 2.0)
	fx.burst(Vector3(3, 3, 1), null, 0xffffff, 5)
	fx.update(0.01, null)
	s = fx.stats()
	check(s.glow == 0 and s.smoke == 0 and s.chunks == 0 and s.parts == 5, "낮음 = 덧칠 없음, JS 파편은 그대로 %s" % [s])
	fx.free()


# 조각은 땅에 닿으면 한 번 튀고 멈춤
func test_w18_chunks_bounce() -> void:
	var fx := Effects.new()
	fx.lv = FXC.LEVELS.high
	fx.chunks(Vector3(2, 2, 1), null, 0x888888, 6, 6.0, 0.2, 3.0)
	for i in 120:
		fx._update_chunks(1.0 / 60.0)
	for k in 6:
		check(fx.c_pos[k].z >= -0.05 and fx.c_vel[k].z == 0.0 and fx.c_bounced[k] == 1, "조각 %d 땅 위에 멈춤 %s %s" % [k, fx.c_pos[k], fx.c_vel[k]])
	fx.free()


# 이벤트 → 히트스톱·반동·팔 반동: 나와 상관있는 강·치명만 화면 멈칫, 남끼리 맞음은 없음. 움직임 줄이기면 멈칫·반동 없음, 흔들림 약하게
func test_w18_hit_feel_events() -> void:
	var keep_state := Store.state
	var keep_by := Store._players_by_id
	var keep_me = Store.my_id
	var keep_rm = View.settings.get("reducedMotion", false)
	var a := {"id": 1, "x": 2.0, "y": 2.0, "z": 0.0, "alive": true, "slot": 0, "color": 0}
	var b := {"id": 2, "x": 3.0, "y": 2.0, "z": 0.0, "alive": true, "slot": 1, "color": 1}
	var c := {"id": 3, "x": 5.0, "y": 2.0, "z": 0.0, "alive": true, "slot": 2, "color": 2}
	Store.state = {"phase": "playing", "field": {"w": 10, "d": 10}, "players": [a, b, c]}
	Store._players_by_id = {1: a, 2: b, 3: c}
	Store.my_id = 2
	View.settings.reducedMotion = false
	var fx := FX.new()
	root().add_child(fx)
	fx.effects.lv = FXC.LEVELS.high
	fx.on_event({"type": "hit", "by": 1, "target": 3, "ok": true, "crit": true})
	check(fx.effects.stop_scale() == 1.0 and fx.effects.kick_now() == Vector4.ZERO, "남끼리 치명: 화면 멈칫·반동 없음")
	check(fx.effects.stats().glow == 0, "그리기 전 (update 전)")
	fx.effects.update(0.001, null)
	check(fx.effects.stats().glow > 0, "남끼리 맞음도 번쩍·불꽃 (빛 풀)")
	fx.on_event({"type": "hit", "by": 2, "target": 1, "ok": true, "kind": "push", "n": 1})
	check(fx.effects.stop_scale() == 1.0, "내 중타: 멈칫 없음")
	check(fx.effects.kick_now().x < 0.0 and fx.effects.vm_offset().z > 0.0, "내 중타: 카메라 숙임·팔이 몸 쪽으로 %s %s" % [fx.effects.kick_now(), fx.effects.vm_offset()])
	fx.on_event({"type": "hit", "by": 1, "target": 2, "ok": true, "crit": true})
	check(fx.effects.stop_scale() == FXC.HITSTOP_SCALE, "내가 치명으로 맞음: 화면 멈칫")
	check(fx.screen_scale() == FXC.HITSTOP_SCALE, "멈칫 = 화면 시계 배율 %s" % fx.screen_scale())
	check(fx.effects.kick_now().x > 0.0 and fx.effects.kick_now().w > 0.0, "맞음: 카메라 들림 + 시야 조임 %s" % fx.effects.kick_now())
	var amp: float = fx.effects.sh.amp
	check(is_equal_approx(amp, C.FX_SHAKE_HURT * FXC.tier("crit").shake_hurt), "치명 맞음 흔들림 %s" % amp)
	# 움직임 줄이기
	fx.effects.stop_until = 0.0
	fx.effects.kick = {"t0": -1e9, "ms": 1.0, "pitch": 0.0, "yaw": 0.0, "roll": 0.0, "fov": 0.0}
	fx.effects.sh = {"amp": 0.0, "ms": 1.0, "until": 0.0}
	View.settings.reducedMotion = true
	fx.read_settings()
	fx.on_event({"type": "hit", "by": 1, "target": 2, "ok": true, "crit": true})
	check(fx.effects.stop_scale() == 1.0 and fx.effects.kick_now() == Vector4.ZERO, "움직임 줄이기: 멈칫·반동 없음")
	check(is_equal_approx(fx.effects.sh.amp, C.FX_SHAKE_HURT * FXC.tier("crit").shake_hurt * FXC.REDUCED.shake), "움직임 줄이기: 흔들림 약하게 %s" % fx.effects.sh.amp)
	fx.on_event({"type": "death", "who": 2, "cause": "crush", "x": 3.0, "y": 2.0, "z": 0.0})
	check(fx.ko.time_scale() == 1.0, "움직임 줄이기: 압사 히트스톱도 없음")
	View.settings.reducedMotion = keep_rm
	fx.free()
	Store.state = keep_state
	Store._players_by_id = keep_by
	Store.my_id = keep_me
	View.time_scale = 1.0


# 맞은 몸 번쩍 (단계별 ms) · 표창 맞음 몸짓은 표창이 닿을 때 (STAR_FLY_MS 뒤, JS main.js 와 같음)
func test_w18_body_flash_and_star_delay() -> void:
	var b = load("res://chars/chars.gd").make_body("ninja", Color(0.5, 0.5, 0.9))
	b.pid = 4
	var p := {"id": 4, "alive": true}
	var now := Time.get_ticks_msec() * 1.0
	check((b.fx_colors(p, now)[2] as Color).is_equal_approx(Color(0, 0, 0)), "평소엔 번쩍 없음")
	b.hit_flash("light")
	check((b.fx_colors(p, Time.get_ticks_msec() * 1.0)[2] as Color).is_equal_approx(Color(0, 0, 0)), "약타는 번쩍 없음 (body 0)")
	b.hit_flash("crit")
	var oe: Color = b.fx_colors(p, Time.get_ticks_msec() * 1.0)[2]
	check(oe.r > 0.8 and oe.g > 0.8, "치명 맞음 = 몸 밝게 %s" % oe)
	check((b.fx_colors(p, Time.get_ticks_msec() + FXC.tier("crit").body + 1.0)[2] as Color).is_equal_approx(Color(0, 0, 0)), "번쩍 끝")
	var Body := preload("res://chars/body.gd")
	check(Body.star_wait({"type": "hit", "star": true}) and not Body.star_wait({"type": "hit", "star": true, "late": true}) and not Body.star_wait({"type": "hit"}), "표창 맞음만 기다림 (late 면 바로)")
	b.on_event({"type": "hit", "by": 9, "target": 4, "ok": true, "star": true, "late": true})
	check(b.hit != null, "표창이 닿으면 (late) 몸짓")
	b.free()


# W18 묶음 효과 수 (화질 높음): 폭발·땅 충격·타격 — 수가 fx_config 값대로, 보통은 × 0.7
func test_w18_combo_counts() -> void:
	var fx := Effects.new()
	fx.lv = FXC.LEVELS.high
	var B: Dictionary = FXC.BOOM
	fx.explode(Vector3(3, 3, 1), 1.0)
	check(fx.gi == 1 + int(B.fire[0]) + 1 + int(B.sparks[0]), "폭발 빛 = 번쩍 1 + 불덩이 + 바닥 고리 1 + 불꽃 줄 (%d)" % fx.gi)
	check(fx.si == int(B.smoke[0]) and fx.ci == int(B.chunks[0]), "폭발 연기 %d · 조각 %d" % [fx.si, fx.ci])
	fx.explode(Vector3(3, 3, 1), 1.0, null, null, false)
	check(fx.ci == int(B.chunks[0]), "건축가 폭파는 판자 조각이 따로라 돌 조각 없음")
	var g0: int = fx.gi
	fx.impact(Vector3(3, 3, 1), {"x": 1, "y": 0}, "crit")
	var T := FXC.tier("crit")
	check(fx.gi - g0 == 3 + int(T.sparks[0]), "치명 = 번쩍 2 + 빛 고리 1 + 불꽃 줄 (%d)" % (fx.gi - g0))
	g0 = fx.gi
	fx.impact(Vector3(3, 3, 1), null, "light")
	check(fx.gi - g0 == 2 + int(FXC.tier("light").sparks[0]), "약타 = 번쩍 2 + 불꽃 줄, 빛 고리 없음 (%d)" % (fx.gi - g0))
	var s0: int = fx.si
	fx.quake(Vector3(3, 3, 0), 2.0)
	check(fx.si - s0 == int(FXC.QUAKE.dust[0]), "땅 충격 흙먼지 %d" % (fx.si - s0))
	fx.lv = FXC.LEVELS.medium
	g0 = fx.gi
	fx.impact(Vector3(3, 3, 1), null, "crit")
	check(fx.gi - g0 == 3 + roundi(T.sparks[0] * 0.7), "보통 = 불꽃 줄 × 0.7 (%d)" % (fx.gi - g0))
	fx.free()


# W3 남은 것 (render.js): 광전사 분노 김 · 닌자 강화 손 불티 · 바드 꽂기 속도선 + W18 낙사 잔상은 낮음이면 없음
func test_w18_char_fx_like_js() -> void:
	var BF := preload("res://world/body_fx.gd")
	var bf = BF.new()
	var fx := Effects.new()
	fx.lv = FXC.LEVELS.high
	bf.effects = fx
	bf.bodies = {"shown": {5: Vector3(1, 2, 0)}, "nodes": {}}
	var calm := {"id": 5, "alive": true, "char": "berserker", "damage": 0}
	for i in 200:
		bf._char_fx(calm, Vector3(1, 2, 0), false, 0.05)
	check(fx.pi == 0 and fx.gi == 0, "분노 없으면 김 없음")
	var rage := {"id": 5, "alive": true, "char": "berserker", "damage": C.BERSERK_RAGE_PCT}
	for i in 200:
		bf._char_fx(rage, Vector3(1, 2, 0), false, 0.05)
	check(fx.pi > 50 and fx.gi > 20, "분노 꽉 차면 김 (JS 파편, %d) + 붉은 기운 (%d)" % [fx.pi, fx.gi])
	var p0: int = fx.pi
	var emp := {"id": 5, "alive": true, "char": "ninja", "empower": 3000}
	for i in 100:
		bf._char_fx(emp, Vector3(1, 2, 0), false, 0.02)
	check(fx.pi - p0 > 20, "닌자 강화 손 불티 (초당 25, %d)" % (fx.pi - p0))
	var g0: int = fx.gi
	bf.on_event({"type": "dive", "who": 5})
	check(bf.dives.has(5), "기타 꽂기 시작")
	bf._dives(null, 0.1, BF.now_ms())
	check(fx.gi - g0 == int(C.DIVE_LINE_RATE * 0.1), "속도선 DIVE_LINE_RATE 개/초 (%d)" % (fx.gi - g0))
	bf.on_event({"type": "diveEnd", "who": 5, "what": "land", "x": 1.0, "y": 2.0, "z": 0.0})
	check(not bf.dives.has(5), "꽂기 끝")
	fx.lv = FXC.LEVELS.low
	bf.fall_ghost(5, {"x": 1, "y": 0})
	check(bf.ghosts.is_empty(), "낮음이면 낙사 잔상 없음")
	fx.free()
	bf.free()


# ---------- c6 (2026-11-15) 효과 모양: 얇은 고리·빛 안 받는 조각·화면 덮기 상한·이름표를 효과 위로 ----------
# 충격파 고리 풀의 메시: 세 줄 (안쪽 알파 0 → 심 → 바깥 잉크 테), 삼각형 seg × 4, 밝은 띠 폭이 반지름의 10% 안. ring_mesh (튜토리얼 표시가 씀) 는 그대로
func test_c6_soft_ring_mesh() -> void:
	var L: Dictionary = FXC.RING_LOOK
	for seg in [8, 40]:
		var m := Effects.soft_ring_mesh(seg)
		var arr := m.surface_get_arrays(0)
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var vc: PackedColorArray = arr[Mesh.ARRAY_COLOR]
		check(v.size() == seg * 4 * 3 and vc.size() == v.size(), "고리 삼각형 %d (seg %d × 4)" % [v.size() / 3, seg])
		var r_min := INF
		var r_max := 0.0
		var bad := 0
		for i in v.size():
			var r := v[i].length()
			r_min = minf(r_min, r)
			r_max = maxf(r_max, r)
			if absf(v[i].z) > 1e-6:
				bad += 1
			if near(r, float(L.inner), 1e-4) and vc[i].a != 0.0:
				bad += 1 # 안쪽 가장자리는 투명 (안이 비쳐 보임)
			if near(r, float(L.core), 1e-4) and not near(vc[i].a, float(L.core_alpha)):
				bad += 1
			if near(r, float(L.outer), 1e-4) and absf(vc[i].a - float(L.ink[3])) > 1.0 / 255.0: # 정점 색은 8비트로 저장됨
				bad += 1 # 바깥 가장자리 = 잉크 테
		check(bad == 0, "고리 정점 알파: 안쪽 0 → 심 %s → 바깥 %s (어긋난 정점 %d)" % [L.core_alpha, L.ink[3], bad])
		check(near(r_min, float(L.inner), 1e-4) and near(r_max, 1.0, 1e-4), "고리 반지름 %s ~ %s (바깥 = 1: 크기 뜻이 예전 고리와 같음)" % [r_min, r_max])
	check(float(L.outer) - float(L.inner) <= 0.1 + 1e-9 and float(L.inner) < float(L.core) and float(L.core) < float(L.outer), "밝은 띠 폭 ≤ 반지름 10%% (%s)" % (float(L.outer) - float(L.inner)))
	check(float(L.ink[3]) < float(L.core_alpha), "잉크 테는 심보다 옅음")
	var fx := Effects.new()
	var pool: PackedVector3Array = fx.ring_mm.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	check(pool.size() == int(L.seg) * 12 and fx.ring_mm.mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR] != null, "고리 풀이 세 줄 고리를 씀 (정점 %d)" % pool.size())
	fx.ring(Vector3(1, 1, 1), 0xff0000)
	check(near(fx.r_color[0].a, FXC.RING_ALPHA), "고리 처음 알파 = FXC.RING_ALPHA")
	fx.free()
	var old := Effects.ring_mesh(0.8, 1.0, 40).surface_get_arrays(0)
	check((old[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() == 240 and old[Mesh.ARRAY_COLOR] == null, "ring_mesh 는 그대로 (튜토리얼 표시)")


# 조각 상자: 면마다 밝기 (모두 0.5 이상 — 검은 면 없음), 재질은 빛을 안 받고 카메라 바로 앞이면 흐려짐, 앞면 방향은 BoxMesh 와 같음 (뒷면 지우기에 안 사라짐)
func test_c6_chunk_tones() -> void:
	var T: Dictionary = FXC.CHUNK_TONES
	for k in T:
		check(float(T[k]) >= 0.5 and float(T[k]) <= 1.0, "조각 면 밝기 %s = %s (0.5 이상)" % [k, T[k]])
	check(float(T.top) > float(T.side_a) and float(T.side_a) > float(T.side_b) and float(T.side_b) > float(T.bottom), "윗면 > 옆 > 밑 (입체로 읽힘)")
	var arr := Effects.chunk_mesh().surface_get_arrays(0)
	var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var n: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
	var vc: PackedColorArray = arr[Mesh.ARRAY_COLOR]
	check(v.size() == 36 and vc.size() == 36, "조각 상자 삼각형 %d (BoxMesh 와 같은 12)" % (v.size() / 3))
	# BoxMesh 의 앞면 감는 방향 (삼각형 법선 · 면 법선의 부호)
	var box := BoxMesh.new().get_mesh_arrays()
	var bv: PackedVector3Array = box[Mesh.ARRAY_VERTEX]
	var bn: PackedVector3Array = box[Mesh.ARRAY_NORMAL]
	var bi: PackedInt32Array = box[Mesh.ARRAY_INDEX]
	var want := signf((bv[bi[1]] - bv[bi[0]]).cross(bv[bi[2]] - bv[bi[0]]).dot(bn[bi[0]]))
	var bad := 0
	var tones := {}
	for t in 12:
		var a := v[t * 3]
		var nn := n[t * 3].round() # 법선은 눌러 저장돼 조금 어긋남
		if signf((v[t * 3 + 1] - a).cross(v[t * 3 + 2] - a).dot(nn)) != want:
			bad += 1
		for k in 3:
			var p := v[t * 3 + k]
			if not near(maxf(maxf(absf(p.x), absf(p.y)), absf(p.z)), 0.5) or not near(p.dot(nn), 0.5):
				bad += 1 # 한 변 1 상자의 그 면 위
			var c := vc[t * 3 + k]
			if c.a != 1.0 or c.r != c.g or c.g != c.b:
				bad += 1
			tones[Vector3i(nn)] = c.r
	check(want != 0.0 and bad == 0, "조각 상자 면·감는 방향 (어긋남 %d)" % bad)
	var q := 1.0 / 255.0 # 정점 색은 8비트로 저장됨
	check(tones.size() == 6, "면 6개 %s" % str(tones))
	for e in [[Vector3i.UP, T.top], [Vector3i.DOWN, T.bottom], [Vector3i.RIGHT, T.side_a], [Vector3i.LEFT, T.side_a], [Vector3i.BACK, T.side_b], [Vector3i.FORWARD, T.side_b]]:
		check(absf(float(tones.get(e[0], -1.0)) - float(e[1])) <= q, "면 %s 밝기 %s (바라는 값 %s)" % [e[0], tones.get(e[0]), e[1]])
	var fx := Effects.new()
	var m: StandardMaterial3D = fx.chunk_mm.mesh.surface_get_material(0)
	check(m == fx.chunk_mat and m.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED and m.vertex_color_use_as_albedo, "조각 재질: 빛 안 받음 + 정점 색 (면 밝기) × 칸 색")
	check(m.distance_fade_mode == BaseMaterial3D.DISTANCE_FADE_PIXEL_DITHER and near(m.distance_fade_min_distance, FM.FX_NEAR_FADE[0]) and near(m.distance_fade_max_distance, FM.FX_NEAR_FADE[1]), "조각 재질: 카메라 바로 앞이면 화소를 점점이 버려 사라짐 (거리는 FX_NEAR_FADE 그대로)")
	# c6 리뷰 F1: 조각은 불투명 패스 (알파 흐림 + 깊이 쓰기 + 먼저 그리기면 안 보이는 조각이 깊이만 남겨 뒤 효과를 도려냄). 버린 화소는 깊이를 안 씀
	check(m.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED and m.depth_draw_mode == BaseMaterial3D.DEPTH_DRAW_OPAQUE_ONLY and m.render_priority == 0, "조각은 불투명 (투명 %d · 깊이 %d · 순서 %d)" % [m.transparency, m.depth_draw_mode, m.render_priority])
	check(m.albedo_color.a == 1.0 and not m.no_depth_test, "조각 색 알파는 안 씀 · 깊이 검사 그대로 (연기·빛이 조각 앞뒤를 가림)")
	# 고리·파편은 알파 흐림 그대로 (반투명 — 깊이 안 씀)
	check(fx.ring_mat.distance_fade_mode == BaseMaterial3D.DISTANCE_FADE_PIXEL_ALPHA and fx.ring_mat.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA and fx.ring_mat.depth_draw_mode == BaseMaterial3D.DEPTH_DRAW_DISABLED, "고리는 알파 흐림·깊이 안 씀 그대로")
	var probe := StandardMaterial3D.new()
	FM.near_fade(probe)
	check(probe.distance_fade_mode == BaseMaterial3D.DISTANCE_FADE_PIXEL_ALPHA, "near_fade 기본은 알파 흐림")
	fx.free()


# 화면 덮기 상한: 지름 ≤ 화면 높이 × frac (그 깊이에서), 작은 것은 그대로. 카메라를 보는 고리·빛에만 (바닥에 눕힌 것·카메라 없음은 그대로)
func test_c6_screen_cap() -> void:
	check(near(FM.cap_size(10.0, 2.5, 75.0, 0.45), 0.45 * 2.0 * 2.5 * tan(deg_to_rad(37.5))), "2.5칸·75도: %s" % FM.cap_size(10.0, 2.5, 75.0, 0.45))
	check(near(FM.cap_size(10.0, 2.5, 75.0, 0.45), 1.7265, 1e-3), "2.5칸·75도 = 1.73칸")
	check(near(FM.cap_size(10.0, 7.0, 60.0, 0.45), 0.45 * 14.0 * tan(deg_to_rad(30.0))) and near(FM.cap_size(10.0, 7.0, 60.0, 0.45), 3.637, 1e-3), "7칸·60도 = 3.64칸")
	check(FM.cap_size(1.0, 2.5, 75.0, 0.45) == 1.0 and FM.cap_size(0.3, 7.0, 60.0, 0.45) == 0.3, "작은 크기는 그대로")
	check(FM.cap_size(5.0, 0.0, 75.0, 0.45) == 0.0 and FM.cap_size(5.0, -3.0, 75.0, 0.45) == 0.0, "카메라 뒤 = 0")
	check(FM.cap_size(10.0, 5.0, 75.0, 0.45) > FM.cap_size(10.0, 2.5, 75.0, 0.45) and FM.cap_size(10.0, 2.5, 90.0, 0.45) > FM.cap_size(10.0, 2.5, 75.0, 0.45), "멀수록·시야가 넓을수록 상한이 큼")
	check(FXC.SCREEN_CAP > 0.0 and FXC.SCREEN_CAP <= 0.5, "상한 %s (화면 높이의 절반 이하)" % FXC.SCREEN_CAP)
	# 효과 풀: 카메라를 보는 고리·빛에만, 바닥에 눕힌 것·카메라 없음은 그대로 (헤드리스는 MultiMesh 칸 자리를 못 읽어 크기 정하는 함수로 확인)
	var fx := Effects.new()
	var at := Vector3.ZERO
	fx.update(0.016, null)
	check(not fx._cap_on and fx._capped(40.0, at) == 40.0, "카메라가 없으면 그대로")
	var cam := Camera3D.new() # 트리 밖 카메라도 없는 것과 같음
	fx.update(0.016, cam)
	check(not fx._cap_on and fx._capped(40.0, at) == 40.0, "트리 밖 카메라면 그대로")
	cam.free()
	# 카메라가 2.5칸 앞에서 봄 (러너에선 카메라가 트리에 못 들어가 update 가 넣는 값을 손으로)
	fx._cap_on = true
	fx._cam_pos = Vector3(0, 0, 2.5)
	fx._cam_fwd = Vector3(0, 0, -1)
	fx._cam_fov = 75.0
	var cap := FM.cap_size(INF, 2.5, 75.0, FXC.SCREEN_CAP)
	check(near(fx._capped(40.0, at), cap) and near(cap, 2.5 * 2.0 * tan(deg_to_rad(37.5)) * FXC.SCREEN_CAP), "카메라를 보는 큰 효과 지름 %s = 화면 높이 × %s" % [fx._capped(40.0, at), FXC.SCREEN_CAP])
	check(fx._capped(40.0, at, true) == 40.0, "바닥에 눕힌 것은 그대로")
	check(fx._capped(0.5, at) == 0.5, "작은 효과는 그대로")
	check(near(fx._capped(40.0, Vector3(3.0, -2.0, 0.0)), cap), "깊이 (보는 방향 거리) 로 잼 — 화면 가장자리여도 같은 상한")
	check(fx._capped(40.0, Vector3(0, 0, 5.0)) == 0.0, "카메라 뒤는 0")
	fx.free()


# 머리 위 이름·% 는 효과 빛 (가산) 보다 뒤에 그려 효과와 겹쳐도 위에 보임. 체력전 HP 막대도 같은 순서
func test_c6_label_above_fx() -> void:
	var Bodies := preload("res://world/bodies.gd")
	var WC := preload("res://world/world_config.gd")
	var fx := Effects.new()
	var lab: Label3D = Bodies.make_label()
	check(lab.render_priority == WC.LABEL_PRIORITY and lab.render_priority > fx.glow_mat.render_priority, "이름표 순서 %d > 효과 빛 %d" % [lab.render_priority, fx.glow_mat.render_priority])
	check(lab.outline_render_priority == WC.LABEL_PRIORITY - 1 and lab.outline_render_priority > fx.glow_mat.render_priority, "이름표 외곽선 %d 도 효과 빛 위, 글자 아래" % lab.outline_render_priority)
	for m in [fx.ring_mat, fx.mm.mesh.material, fx.smoke_mat, fx.chunk_mat]:
		check(lab.outline_render_priority > m.render_priority, "이름표가 파편·고리·연기·조각 위")
	# c6 리뷰 F3: 이 풀 밖의 반투명 효과 (판 빛 5 · 바닥 표시 8 …) 도 이름표 외곽선보다 앞 순서 — 만들 수 있는 재질은 직접
	var gl = preload("res://shaders/game_light.gd").new()
	var halo: Material = (gl.get_node("Halos") as MultiMeshInstance3D).material_override
	check(halo != null and lab.outline_render_priority > halo.render_priority, "이름표가 판 빛 (%d) 위" % (halo.render_priority if halo != null else -1))
	gl.free()
	var mark: StandardMaterial3D = preload("res://world/marks.gd").flat_mat(0xffffff, 0.5)
	check(lab.outline_render_priority > mark.render_priority, "이름표가 바닥 표시 (%d) 위" % mark.render_priority)
	# 나머지 (함수 안에서 만드는 재질: 빛 터짐·블록 출렁·갈고리 호·위험 고리 …) 는 소스의 순서 값을 훑음:
	# 이름표 외곽선 (WC.LABEL_PRIORITY - 1) 보다 작거나, 이름표 위에 뜨는 표시 (머리 위 상태 글자·음표·사냥 표식 12 · 조준 표시 13) 이거나
	var above := {"res://world/body_fx.gd": [12], "res://world/shots.gd": [13]}
	var re := RegEx.create_from_string("render_priority\\s*=\\s*(-?\\d+)")
	var seen := {}
	var top := -1000
	for dir in ["res://world", "res://fx", "res://shaders", "res://chars"]:
		for f in DirAccess.get_files_at(dir):
			if not f.ends_with(".gd"):
				continue
			var path: String = dir.path_join(f)
			for hit in re.search_all(FileAccess.get_file_as_string(path)):
				var v := int(hit.get_string(1))
				seen[v] = true
				if above.get(path, []).has(v):
					check(v > WC.LABEL_PRIORITY, "%s 순서 %d 는 이름표 (%d) 위 표시" % [f, v, WC.LABEL_PRIORITY])
					continue
				top = maxi(top, v)
				check(v < WC.LABEL_PRIORITY - 1, "%s 순서 %d < 이름표 외곽선 %d" % [f, v, WC.LABEL_PRIORITY - 1])
	for v in [5, 6, 8, 9, 12, 13]:
		check(seen.has(v), "소스에서 순서 %d 를 찾음 (훑기가 실제로 도는지)" % v)
	check(top == 9 and WC.LABEL_PRIORITY == 11, "효과 순서 최대 %d < 외곽선 %d < 이름표 %d < 위 표시 12" % [top, WC.LABEL_PRIORITY - 1, WC.LABEL_PRIORITY])
	check(lab.no_depth_test and lab.billboard == BaseMaterial3D.BILLBOARD_ENABLED and lab.fixed_size and near(lab.pixel_size, WC.LABEL_PIXEL, 1e-5) and lab.font_size == WC.LABEL_FONT[0] and lab.outline_size == WC.LABEL_FONT[1], "이름표 나머지 값은 예전 그대로")
	lab.free()
	fx.free()
	var b = Bodies.new()
	var n: Dictionary = b._make({"id": 1, "x": 0.0, "y": 0.0, "z": 0.0, "alive": true}, 0xff0000)
	check((n.label as Label3D).render_priority == WC.LABEL_PRIORITY, "몸 이름표가 make_label 을 씀")
	check((n.bar_fill as Sprite3D).render_priority == WC.LABEL_PRIORITY and (n.bar_back as Sprite3D).render_priority == WC.LABEL_PRIORITY - 1, "HP 막대: 뒤판 %d · 채움 %d" % [n.bar_back.render_priority, n.bar_fill.render_priority])
	b.free()


# ---- c7 신호 고리 (world/ring_look.gd · body_fx 예고·스킬 고리 · 하늘 시점 삼각뿔 순서) ----
const RL := preload("res://world/ring_look.gd")
const BFX := preload("res://world/body_fx.gd")


# 메시의 정점 색에 col 이 있는지 (정점 색은 8비트로 저장됨)
func _has_color(m: ArrayMesh, col: Color) -> bool:
	var q := 1.5 / 255.0
	for c in m.surface_get_arrays(0)[Mesh.ARRAY_COLOR]:
		if absf(c.r - col.r) <= q and absf(c.g - col.g) <= q and absf(c.b - col.b) <= q and absf(c.a - col.a) <= q:
			return true
	return false


# 메시 정점의 [가장 안 반지름, 가장 바깥 반지름] (눕힌 고리: 고도 xz)
func _radii(m: ArrayMesh) -> Array:
	var lo := INF
	var hi := 0.0
	for v in m.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
		var r := Vector2(v.x, v.z).length()
		lo = minf(lo, r)
		hi = maxf(hi, r)
		check(absf(v.y) < 1e-6, "고리는 바닥에 눕힘")
	return [lo, hi]


# F 준비 예고 고리: 굵은 띠 (반지름의 20% 이상) · 흰 심 + 그 사람 색 + 잉크 테 · 수명의 75% 까지 또렷 · 몸을 따라감 · 순서 9
func test_c7_windup_ring_thick() -> void:
	var G3C := preload("res://shaders/g3_config.gd")
	var WC := preload("res://world/world_config.gd")
	check(RL.band_frac("windup") >= 0.2 and near(RL.band_frac("windup"), 0.24, 1e-6), "띠 폭 ÷ 반지름 %s" % RL.band_frac("windup"))
	var color := int(C.PLAYER_PALETTE[1])
	var m: ArrayMesh = RL.mesh("windup", color)
	var rr := _radii(m)
	check(near(rr[0], 0.76, 1e-5) and near(rr[1], 1.0, 1e-5) and (rr[1] - rr[0]) / rr[1] >= 0.2, "메시 단면 %s (0.76 ~ 1.0)" % [rr])
	check(_has_color(m, Color(1, 1, 1, 1)), "흰 심")
	check(_has_color(m, Color(G3C.OUTLINE_COLOR.r, G3C.OUTLINE_COLOR.g, G3C.OUTLINE_COLOR.b, RL.INK_ALPHA)) and near(RL.INK_ALPHA, 0.6), "잉크 테 (외곽선 색, 알파 0.6)")
	check(_has_color(m, RL.tint_of(color)) and not _has_color(m, RL.tint_of(int(C.PLAYER_PALETTE[0]))), "그 사람 색 띠")
	check(_has_color(m, Color(1, 1, 1, 0)), "안쪽 끝은 투명 (부드러운 안 가장자리)")
	check(RL.tint_of(0xffffff).is_equal_approx(Color(1, 1, 1, 1)) and RL.tint_of(color).is_equal_approx(Co.color(color)), "정점 색 = 팔레트 값 그대로 (선형으로 안 바꿈 — c7-fix F2)")
	for pc in C.PLAYER_PALETTE: # 어두운 팔레트 (0x2c2c38 등) 도 제 색 그대로 고리 메시에 들어감 (선형으로 바꾸면 거의 검정이 돼 서로 안 갈림)
		check(_has_color(RL.mesh("aura", int(pc)), Co.color(int(pc))) and _has_color(RL.mesh("windup", int(pc)), Co.color(int(pc))), "팔레트 %06x 고리 색 그대로" % int(pc))
	# 띠 순서: 안 → 바깥으로 이어지고 (틈 없음) 흰 심 0.80~0.88 · 색 0.88~0.97 · 잉크 0.97~1.0
	var bands: Array = RL.LOOKS.windup.bands
	for i in bands.size() - 1:
		check(near(bands[i][1], bands[i + 1][0]), "띠 %d 와 %d 사이 틈 없음" % [i, i + 1])
	check(bands[1] == [0.80, 0.88, "core", "core"] and bands[2] == [0.88, 0.97, "tint", "tint"] and bands[3] == [0.97, 1.0, "ink", "ink"], "띠 표 %s" % [bands])
	# 곡선: 반지름 0.95 → 1.25 ease-out · 알파는 75% 까지 1, 끝에 0
	check(near(RL.windup_radius(0.0), 0.95) and near(RL.windup_radius(1.0), 1.25) and near(RL.windup_radius(2.0), 1.25), "반지름 0.95 → 1.25칸")
	check(RL.windup_radius(0.5) > (0.95 + 1.25) / 2.0 and near(RL.windup_radius(0.5), 0.95 + 0.3 * 0.75), "ease-out (절반에 이미 3/4)")
	var prev := 2.0
	for i in 21:
		var u := i / 20.0
		var a := RL.windup_alpha(u)
		check(a <= prev + 1e-9, "알파는 늘지 않음 (u=%s)" % u)
		prev = a
		if u <= 0.75:
			check(a >= 0.9, "u=%s 알파 %s (75%% 까지 또렷)" % [u, a])
	check(RL.windup_alpha(1.0) == 0.0 and near(RL.windup_alpha(0.875), 0.5), "끝에 0 (뒤 25%% 에 곧게)")
	# 이벤트 → 예고 고리 하나 (효과 풀 고리 아님), 몸을 따라감
	var keep_by = Store._players_by_id
	var keep_state = Store.state
	Store._players_by_id = {5: {"id": 5, "color": 1, "slot": 0}}
	Store.state = {"players": []}
	var t := [1000.0]
	BFX.clock = func() -> float: return t[0]
	var bf = BFX.new()
	bf._ready() # 러너에선 트리에 못 들어가 직접 (위험 고리 노드를 만듦)
	var rec := FxRec.new()
	bf.effects = rec
	bf.bodies = {"shown": {5: Vector3(1, 2, 3)}}
	bf.on_event({"type": "skillWindup", "who": 5, "ms": 400})
	check(bf.windups.size() == 1 and rec.rings.is_empty(), "skillWindup 하나 → 예고 고리 하나 (풀 고리 %d)" % rec.rings.size())
	var w: Dictionary = bf.windups[0]
	var node: MeshInstance3D = w.node
	check(node.mesh == m, "메시 = 그 사람 색 예고 고리 (기억해 둔 것)")
	check(near(w.ms, 400.0) and near(w.t0, 1000.0), "수명 = ms")
	check((w.mat as StandardMaterial3D).render_priority == 9 and node.material_override == w.mat and 9 < WC.LABEL_PRIORITY - 1, "순서 9 (이름표 외곽선 아래)")
	check(not (w.mat as StandardMaterial3D).no_depth_test, "깊이 검사 켬 (블록 뒤면 가려짐)")
	check(node.position.is_equal_approx(Co.gxyz(1, 2, 3.05)) and near(node.scale.x, 0.95), "처음 자리·반지름 %s %s" % [node.position, node.scale])
	t[0] = 1200.0 # 수명의 절반: 몸이 움직였으면 따라감
	bf.bodies.shown[5] = Vector3(4, 2, 3)
	bf.update({}, null, 0.016)
	check(node.visible and node.position.is_equal_approx(Co.gxyz(4, 2, 3.05)) and near(node.scale.x, RL.windup_radius(0.5)) and near(node.scale.z, node.scale.x) and near(w.mat.albedo_color.a, 1.0), "절반: 몸을 따라감·커짐·또렷 (%s, %s, %s)" % [node.position, node.scale, w.mat.albedo_color.a])
	bf.update({}, 5, 0.016) # 1인칭 내 고리는 숨김 (W35 그대로)
	check(not node.visible, "1인칭 내 예고 고리는 숨김")
	bf.third = func() -> bool: return true
	bf.update({}, 5, 0.016)
	check(node.visible, "3인칭이면 내 것도 보임")
	t[0] = 1350.0
	bf.update({}, null, 0.016)
	check(near(w.mat.albedo_color.a, 0.5), "뒤 25%% 에 사라짐 (알파 %s)" % w.mat.albedo_color.a)
	t[0] = 1400.0
	bf.update({}, null, 0.016)
	check(bf.windups.is_empty(), "수명이 끝나면 없앰")
	bf.on_event({"type": "skillWindup", "who": 5})
	check(bf.windups.size() == 1 and near(bf.windups[0].ms, C.SKILL_WINDUP_MS), "ms 없으면 SKILL_WINDUP_MS")
	bf.on_event({"type": "skillWindup", "who": 99})
	check(bf.windups.size() == 1, "화면에 없는 사람이면 안 만듦")
	bf.bodies.shown.erase(5)
	bf.update({}, null, 0.016)
	check(bf.windups.is_empty(), "몸이 사라지면 고리도 없앰")
	bf.free()
	BFX.clock = Callable()
	check(BFX.now_ms() > 0.0 and absf(BFX.now_ms() - Time.get_ticks_msec()) < 1000.0, "시계를 비우면 엔진 시계")
	Store._players_by_id = keep_by
	Store.state = keep_state


# 스킬·필살기 고리: 부를 때마다 메시를 새로 안 만듦 · 스킬 = 흰 심 + 쓴 사람 색, 필살기 = 흰 심 + ULT_AURA_COLOR 두 겹
func test_c7_aura_mesh_cached() -> void:
	var keep_by = Store._players_by_id
	var keep_state = Store.state
	Store._players_by_id = {5: {"id": 5, "color": 1, "slot": 0}, 6: {"id": 6, "color": 3, "slot": 1}}
	Store.state = {"players": []}
	var bf = BFX.new()
	bf.bodies = {"shown": {5: Vector3(1, 2, 3), 6: Vector3(3, 2, 3)}}
	bf.aura(5, false)
	bf.aura(5, false)
	bf.aura(6, false)
	check(bf.auras.size() == 3, "스킬 고리 하나씩")
	var m5: ArrayMesh = bf.auras[0].node.mesh
	check(m5 == bf.auras[1].node.mesh and m5 == RL.mesh("aura", int(C.PLAYER_PALETTE[1])), "두 번 불러도 같은 메시 (기억해 둔 것)")
	check(bf.auras[2].node.mesh != m5 and bf.auras[2].node.mesh == RL.mesh("aura", int(C.PLAYER_PALETTE[3])), "색이 다른 사람은 다른 메시")
	check(bf.auras[0].mat != bf.auras[1].mat, "재질은 고리마다 (알파가 따로 흐름)")
	check(_has_color(m5, Color(1, 1, 1, 1)) and _has_color(m5, RL.tint_of(int(C.PLAYER_PALETTE[1]))), "스킬 고리 = 흰 심 + 그 사람 색")
	var bands: Array = RL.LOOKS.aura.bands
	check(bands.size() == 2 and bands[0][2] == "core" and bands[1][3] == "tint" and near(bands[0][1], bands[1][0]), "2단: 안 = 흰 심, 바깥 = 색 %s" % [bands])
	var rr := _radii(m5)
	check(near(RL.band_frac("aura"), 0.14, 1e-6) and near(rr[0], 0.86, 1e-5) and near(rr[1], 1.0, 1e-5), "띠 폭 = 반지름의 14%% %s" % [rr])
	check(near(bf.auras[0].ms, C.SKILL_AURA_MS * 0.6) and near(bf.auras[0].grow, 1.8), "스킬 고리 시간·커짐은 그대로")
	# 필살기: 두 겹 (둘째는 ms × 0.25 늦게), ULT_AURA_COLOR 바깥 + 흰 심
	var n0: int = bf.auras.size()
	var now: float = BFX.now_ms()
	bf.aura(5, true)
	check(bf.auras.size() == n0 + 2, "필살기 고리 두 겹")
	var u0: Dictionary = bf.auras[n0]
	var u1: Dictionary = bf.auras[n0 + 1]
	var mu: ArrayMesh = u0.node.mesh
	check(mu == u1.node.mesh and mu == RL.mesh("aura", int(C.ULT_AURA_COLOR)) and mu != m5, "필살기 메시 (두 겹이 같은 것)")
	check(_has_color(mu, Color(1, 1, 1, 1)) and _has_color(mu, RL.tint_of(int(C.ULT_AURA_COLOR))), "필살기 고리 = 흰 심 + ULT_AURA_COLOR")
	check(near(u1.t0 - u0.t0, C.ULT_AURA_MS * 0.25) and absf(u0.t0 - now) < 50.0 and near(u0.ms, C.ULT_AURA_MS * 0.6) and near(u0.grow, 2.6), "두 겹·지연·커짐은 그대로")
	check(bf.sparks.has(5), "필살기 반짝이는 그대로")
	# 처음 크기는 예전 고리 (ring_mesh(0.5, 0.58)) 바깥 반지름
	check(near(RL.AURA.r, 0.58) and near(RL.AURA.alpha, 0.85), "처음 반지름 0.58칸·알파 0.85")
	bf.aura(99, false)
	check(bf.auras.size() == n0 + 2, "화면에 없는 사람이면 안 만듦")
	bf.free()
	Store._players_by_id = keep_by
	Store.state = keep_state


# 하늘 시점 생존자 삼각뿔은 이름표 위 · 조준 표시 (13) 아래 순서 (나머지 도우미는 그대로 3)
func test_c7_sky_marker_above_label() -> void:
	var WC := preload("res://world/world_config.gd")
	var sa = preload("res://world/sky_aids.gd").new()
	sa._ready()
	var order: int = (sa.cone.material_override as StandardMaterial3D).render_priority
	check(order > WC.LABEL_PRIORITY and order < 13, "삼각뿔 순서 %d (이름표 %d 위, 조준 13 아래)" % [order, WC.LABEL_PRIORITY])
	for n in [sa.ghost, sa.pillar, sa.beam]:
		check((n.material_override as StandardMaterial3D).render_priority == 3, "착지 칸·빛 기둥 순서는 그대로 3")
	sa.free()


# 새 고리 재질 모양은 판 들어올 때 미리 그려 두는 표 (warm_scan.gd STD_KEYS) 안 — 처음 쓸 때 셰이더를 안 만듦
func test_c7_ring_materials_warm() -> void:
	var WS := preload("res://world/warm_scan.gd")
	var MF := preload("res://core/mat_first.gd")
	var have := []
	for k in WS.STD_KEYS:
		have.append(MF.mat_key(WS.std_material(k)))
	var wm: StandardMaterial3D = RL.material(1.0, int(RL.WINDUP.priority))
	var am: StandardMaterial3D = RL.material(float(RL.AURA.alpha))
	check(have.has(MF.mat_key(wm)) and have.has(MF.mat_key(am)), "고리 재질 열쇠 %s 가 표준 표 안" % MF.mat_key(wm))
	var fx := Effects.new()
	check(MF.mat_key(wm) == MF.mat_key(fx.ring_mat), "효과 풀 고리와 같은 모양 (이미 쓰이는 셰이더)")
	fx.free()
	check(wm.vertex_color_use_as_albedo and not wm.vertex_color_is_srgb and wm.next_pass == null and wm.distance_fade_mode == BaseMaterial3D.DISTANCE_FADE_DISABLED, "열쇠에 안 잡히는 갈래 (정점 색 sRGB·거리 흐림·덧패스) 도 표준 재질과 같음")
	check(wm.render_priority == 9 and am.render_priority == 0 and near(am.albedo_color.a, 0.85) and near(wm.albedo_color.a, 1.0), "순서·처음 알파")
	# body_fx 가 만드는 고리가 이 재질을 씀
	var keep_by = Store._players_by_id
	Store._players_by_id = {}
	var bf = BFX.new()
	bf.bodies = {"shown": {5: Vector3(1, 2, 3)}}
	bf.windup(5, 150.0)
	bf.aura(5, false)
	check(MF.mat_key(bf.windups[0].mat) == MF.mat_key(wm) and MF.mat_key(bf.auras[0].mat) == MF.mat_key(am), "body_fx 고리 재질 = ring_look 재질")
	check(bf.windups[0].node.mesh == RL.mesh("windup", 0xffffff), "모르는 사람이면 흰색 띠")
	bf.free()
	Store._players_by_id = keep_by


# 테스트 쪽 줄기 투영 (FM.plume_span 과 따로 짠 것): 카메라 공간 (보는 쪽 −z) 꼭짓점 apex · 축 dir · 길이 len_m · 끝 원 지름 width_m →
# 화면에 비친 길이 (꼭짓점 ~ 끝 원 가운데) 와 비친 끝 지름 (끝 원 둘레 48점 중 가장 먼 두 점) 중 큰 쪽 ÷ 화면 높이. 카메라 뒤로 간 점이 있으면 INF
func _plume_seen(len_m: float, width_m: float, apex: Vector3, dir: Vector3, fov: float) -> float:
	var t := tan(deg_to_rad(fov) / 2.0)
	var side := dir.cross(Vector3.FORWARD)
	side = side.normalized() if side.length() > 1e-4 else Vector3.RIGHT
	var up := side.cross(dir).normalized()
	var pts := [apex, apex + dir * len_m]
	for i in 48:
		pts.append(apex + dir * len_m + (side * cos(TAU * i / 48.0) + up * sin(TAU * i / 48.0)) * width_m / 2.0)
	var scr := []
	for p in pts:
		if p.z >= 0.0:
			return INF
		scr.append(Vector2(p.x, p.y) / (-p.z * t) / 2.0) # 화면 높이 = 1
	var far: float = (scr[0] as Vector2).distance_to(scr[1])
	for i in range(2, scr.size()):
		for j in range(2, i):
			far = maxf(far, (scr[i] as Vector2).distance_to(scr[j]))
	return far


# c8-fix F1 앞의 식 (비교용): 줄기 전체가 밑동 깊이 depth 에서 화면과 나란히 서 있다고 보고 잼 (toward = 줄기 축이 카메라 쪽으로 오는 정도, 멀어지면 0 으로 침)
func _plume_cap_old(len_m: float, width_m: float, depth: float, fov: float, frac: float, toward: float) -> float:
	var h := frac * 2.0 * tan(deg_to_rad(fov) / 2.0)
	return clampf(h * depth / (maxf(len_m, width_m) + h * len_m * maxf(0.0, toward)), 0.0, 1.0)


# c8-u3 · c8-fix F1 낙사 줄기 화면 상한 (FM.plume_cap): 줄기 길이·끝 지름 중 큰 쪽을 카메라에 원근 투영한 크기가 화면 높이 × SCREEN_CAP 안 — 넘지 않으면 배율 1 (안 줄임), 넘으면 딱 상한까지만.
# 예전 식 (밑동 깊이에서 화면과 나란히 선 줄기로 어림) 은 멀어지는 줄기를 상한 안인데도 줄였고 (밑동 6 m: 배율 0.38), 넘던 줄기는 상한보다 훨씬 작게 줄였음 (3 m: 0.19, 맞는 값 0.55)
func test_c8_plume_capped() -> void:
	var big := FM.plume(0.25) # 다 뻗은 순간
	var L: float = C.KO_SMASH_LEN * big.y
	var W: float = 2.0 * C.KO_SMASH_WIDTH * big.x
	var cap: float = FXC.SCREEN_CAP
	var seg: int = FXC.PLUME_CAP_SEG
	var steps: int = FXC.PLUME_CAP_STEPS
	var nr: float = FXC.PLUME_CAP_NEAR
	var tol := 0.01 # 끝 원을 12점 (그리는 원뿔도 12각) 으로 재는 것과 48점으로 재는 것의 차 (화면 높이 비 — 카메라 쪽으로 오는 줄기에서 가장 큼)
	check(L > W and near(L, 10.8, 1e-4), "줄기 길이 %s 칸 · 끝 지름 %s 칸" % [L, W])
	check(seg >= 8 and steps >= 10 and nr > 0.0 and nr < 0.4, "상한 재기 값: 둘레 %d점 · 이분법 %d번 · 가까운 깊이 %s" % [seg, steps, nr])
	# 장면: 꼭짓점이 눈 아래 1.5 m · 앞 D m (화면 가운데 세로줄), 줄기는 수평 방위 yaw (0 = 카메라에서 멀어짐, 90 = 옆, 180 = 카메라 쪽) + 위로 KO_SMASH_UP. [D, yaw]
	var cases := [[6.0, 0.0], [9.0, 0.0], [3.0, 0.0], [6.0, 45.0], [1.5, 0.0], [6.0, 90.0], [3.0, 90.0], [6.0, 180.0], [3.0, 180.0], [12.0, 135.0]]
	for fov in [60.0, 75.0]:
		for sc in cases:
			var d: float = sc[0]
			var yaw := deg_to_rad(float(sc[1]))
			var dir := (Vector3(sin(yaw), 0.0, -cos(yaw)) + Vector3.UP * C.KO_SMASH_UP).normalized()
			var apex := Vector3(0.0, -1.5, -d)
			var k := FM.plume_cap(L, W, apex, dir, fov, cap, seg, steps, nr)
			var full := _plume_seen(L, W, apex, dir, fov)
			var seen := _plume_seen(L * k, W * k, apex, dir, fov)
			var was := _plume_cap_old(L, W, d, fov, cap, dir.z)
			var tag := "밑동 %s m · 방위 %s° · 시야 %s" % [d, sc[1], fov]
			check(k > 0.0 and k <= 1.0 and seen <= cap + tol, "%s: 배율 %s, 화면 높이의 %s ≤ %s" % [tag, k, seen, cap])
			if full <= cap - tol:
				check(k == 1.0, "%s: 상한 안 (%s) 이면 안 줄임 (배율 %s)" % [tag, full, k])
			elif full > cap + tol:
				check(k < 1.0 and seen >= cap - tol, "%s: 넘던 줄기 (%s) 는 딱 상한까지만 (%s)" % [tag, full, seen])
				check(_plume_seen(L * k * 1.03, W * k * 1.03, apex, dir, fov) > cap, "%s: 더 키우면 넘음 (가장 큰 배율)" % tag)
			if float(sc[1]) == 90.0:
				check(near(k, was, 0.01), "%s: 옆으로 뻗는 줄기는 예전 식과 같은 배율 (%s · 예전 %s)" % [tag, k, was])
			else:
				check(k > was * 1.05, "%s: 멀어지는·다가오는 줄기는 예전 식 (%s) 보다 덜 줄임 (%s)" % [tag, was, k])
			if float(sc[1]) > 90.0:
				check((apex + dir * L * k).z < -nr, "%s: 카메라 쪽으로 오는 줄기 끝이 카메라 앞 (깊이 %s)" % [tag, -(apex + dir * L * k).z])
		var away := Vector3(0.0, C.KO_SMASH_UP, -1.0).normalized()
		check(FM.plume_cap(L, W, Vector3(0, -1.5, -60.0), Vector3.RIGHT, fov, cap, seg, steps, nr) == 1.0, "멀면 배율 1 (시야 %s)" % fov)
		check(FM.plume_cap(L, W, Vector3(0, -1.5, 0.0), away, fov, cap, seg, steps, nr) == 0.0 and FM.plume_cap(L, W, Vector3(0, -1.5, 3.0), away, fov, cap, seg, steps, nr) == 0.0, "밑동이 카메라 뒤면 0")
	# 검증 때의 네 장면 (시야 75, 눈 아래 1.5 m): 6·9 m 멀어짐은 상한 안이라 그대로 (예전 식 0.38 · 0.58), 3 m 멀어짐 0.55 (예전 0.19), 45° 비스듬히 0.80 (예전 0.38)
	var ks := []
	for sc in [[6.0, 0.0], [9.0, 0.0], [3.0, 0.0], [6.0, 45.0]]:
		var yaw := deg_to_rad(float(sc[1]))
		ks.append(FM.plume_cap(L, W, Vector3(0, -1.5, -float(sc[0])), (Vector3(sin(yaw), 0.0, -cos(yaw)) + Vector3.UP * C.KO_SMASH_UP).normalized(), 75.0, cap, seg, steps, nr))
	check(ks[0] == 1.0 and ks[1] == 1.0 and near(ks[2], 0.546, 0.01) and near(ks[3], 0.796, 0.01), "6·9·3 m 멀어짐 · 45° 배율 %s" % [ks])
	check(FM.plume_cap(0.6, 0.2, Vector3(0, 0, -2.0), Vector3.RIGHT, 75.0, cap, seg, steps, nr) == 1.0, "작은 줄기는 그대로")
	var kw := FM.plume_cap(1.0, 8.0, Vector3(0, 0, -2.0), Vector3.FORWARD, 75.0, cap, seg, steps, nr)
	check(kw < 1.0 and _plume_seen(1.0 * kw, 8.0 * kw, Vector3(0, 0, -2.0), Vector3.FORWARD, 75.0) <= cap + tol, "폭이 더 크면 끝 원 지름으로 걸림 (배율 %s)" % kw)
	check(FM.plume_cap(0.0, 0.0, Vector3(0, 0, -2.0), Vector3.RIGHT, 75.0, cap, seg, steps, nr) == 1.0, "크기 0 은 그대로")
	check(FM.plume_span(L, W, Vector3(0, -1.5, -6.0), Vector3(0.0, C.KO_SMASH_UP, 1.0).normalized(), 75.0, seg, nr) == INF, "끝이 카메라 뒤로 가면 넘는 것으로 침")
	# 수명 내내: 깊이 2.5칸 (효과 견본 near) 옆으로 뻗는 줄기가 비친 크기 ≤ 상한
	for i in 20:
		var s := FM.plume(i / 20.0)
		var ls: float = C.KO_SMASH_LEN * s.y
		var ws: float = 2.0 * C.KO_SMASH_WIDTH * s.x
		var k := FM.plume_cap(ls, ws, Vector3(0, -1.0, -2.5), Vector3(1.0, C.KO_SMASH_UP, 0.0).normalized(), 75.0, cap, seg, steps, nr)
		check(_plume_seen(ls * k, ws * k, Vector3(0, -1.0, -2.5), Vector3(1.0, C.KO_SMASH_UP, 0.0).normalized(), 75.0) <= cap + tol, "t=%s 비친 크기" % (i / 20.0))
	# 줄기 노드: 카메라가 없으면 (테스트·트리 밖) 배율 1
	var ko := KO.new()
	var pl := {"node": Node3D.new(), "mats": [], "dir": Vector3.UP}
	check(ko.plume_cap(pl, big) == 1.0, "카메라 없으면 1")
	var cam := Camera3D.new()
	ko.cam = cam
	check(ko.plume_cap(pl, big) == 1.0, "트리 밖 카메라도 1")
	ko.cam = null
	cam.free()
	pl.node.free()
	ko.free()


# c8-u3 낙사 줄기 단: 2~3단, 안쪽일수록 폭·길이는 작고 알파·흰 섞기는 큼. 줄기 항목은 그대로 하나 (노드 하나 아래 단마다 원뿔), 단 재질 = 그 사람 색 (흰 섞기) · 미리 그려 둔 재질 모양
func test_c8_plume_bands() -> void:
	var P: Array = FXC.PLUME
	check(P.size() >= 2 and P.size() <= 3, "줄기 %d단" % P.size())
	check(float(P[0][0]) == 1.0 and float(P[0][1]) == 1.0 and float(P[0][3]) == 0.0, "바깥 단 = 줄기 모양 그대로 (JS 크기) · 그 사람 색")
	for i in P.size():
		check(P[i].size() == 4 and float(P[i][2]) > 0.0 and float(P[i][2]) <= 1.0 and float(P[i][3]) >= 0.0 and float(P[i][3]) <= 1.0, "단 %d 값 범위" % i)
		if i > 0:
			check(float(P[i][0]) < float(P[i - 1][0]) and float(P[i][1]) < float(P[i - 1][1]), "단 %d: 안쪽일수록 폭·길이 작음" % i)
			check(float(P[i][2]) > float(P[i - 1][2]) and float(P[i][3]) > float(P[i - 1][3]), "단 %d: 안쪽일수록 알파·흰 섞기 큼" % i)
	check(float(FXC.PLUME_TIP_FADE) > 0.0 and float(FXC.PLUME_TIP_FADE) < 1.0, "끝 흩어짐 비율")
	# 원뿔: 예전 CylinderMesh 와 같은 치수, 넓은 끝 알파 0 · 꼭짓점 쪽 1
	var cone: ArrayMesh = KO.cone_mesh(FXC.PLUME_SEG, FXC.PLUME_TIP_FADE)
	var arr := cone.surface_get_arrays(0)
	var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var cs: PackedColorArray = arr[Mesh.ARRAY_COLOR]
	var lo := INF
	var hi := -INF
	var rmax := 0.0
	var ok_alpha := true
	for i in vs.size():
		lo = minf(lo, vs[i].y)
		hi = maxf(hi, vs[i].y)
		rmax = maxf(rmax, Vector2(vs[i].x, vs[i].z).length())
		var t: float = vs[i].y / C.KO_SMASH_LEN + 0.5 # 0 꼭짓점 ~ 1 넓은 끝
		ok_alpha = ok_alpha and near(cs[i].a, clampf((1.0 - t) / FXC.PLUME_TIP_FADE, 0.0, 1.0), 1e-5)
		check(near(Vector2(vs[i].x, vs[i].z).length(), C.KO_SMASH_WIDTH * t, 1e-4), "원뿔 반지름 = 폭 × 길이 비")
	check(near(lo, -C.KO_SMASH_LEN / 2.0) and near(hi, C.KO_SMASH_LEN / 2.0) and near(rmax, C.KO_SMASH_WIDTH, 1e-5), "원뿔 치수 %s~%s, 반지름 %s" % [lo, hi, rmax])
	check(ok_alpha and vs.size() == 3 * int(FXC.PLUME_SEG), "꼭짓점 색 알파: 넓은 끝 0 → 흩어짐 지점부터 1")
	# 줄기를 냄 (효과 풀 + KO, 카메라 없음)
	var e := Effects.new()
	var ko := KO.new()
	ko.fx = e
	var col := 0x3060e0
	ko.smash(Vector3(-1.5, 4.0, -3.0), {"x": -1, "y": 0}, col, false, false)
	check(ko.plumes.size() == 1, "줄기 항목 %d (그대로 하나)" % ko.plumes.size())
	var pl: Dictionary = ko.plumes[0]
	var node: Node3D = pl.node
	check(pl.mats.size() == P.size() and node.get_child_count() == P.size(), "한 노드 아래 %d단 (재질 %d)" % [node.get_child_count(), pl.mats.size()])
	var WS := preload("res://world/warm_scan.gd")
	var MF := preload("res://core/mat_first.gd")
	var have := []
	for k in WS.STD_KEYS:
		have.append(MF.mat_key(WS.std_material(k)))
	var prev_off := -INF
	for i in P.size():
		var mi := node.get_child(i) as MeshInstance3D
		var mat := pl.mats[i] as StandardMaterial3D
		var add: bool = FXC.PLUME_CORE_ADD and i == P.size() - 1
		check(mi.mesh == ko.cone and mi.material_override == mat and mi.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "단 %d 원뿔·재질" % i)
		check(near(mi.scale.x, P[i][0]) and near(mi.scale.z, P[i][0]) and near(mi.scale.y, P[i][1]) and near(mi.position.y, C.KO_SMASH_LEN / 2.0 * float(P[i][1])), "단 %d 폭·길이 배율, 꼭짓점이 밑동에" % i)
		check(mat.blend_mode == (BaseMaterial3D.BLEND_MODE_ADD if add else BaseMaterial3D.BLEND_MODE_MIX) and mat.vertex_color_use_as_albedo == (not add), "단 %d 섞기 (바깥 단은 보통 섞기)" % i)
		check(mat.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED and mat.cull_mode == BaseMaterial3D.CULL_DISABLED and mat.depth_draw_mode == BaseMaterial3D.DEPTH_DRAW_DISABLED and mat.distance_fade_mode == BaseMaterial3D.DISTANCE_FADE_PIXEL_ALPHA, "단 %d 빛 안 받음·양면·깊이 안 씀·가까우면 흐려짐" % i)
		var want := Co.color(col).lerp(Color.WHITE, float(P[i][3]))
		check(near(mat.albedo_color.r, want.r, 1e-5) and near(mat.albedo_color.g, want.g, 1e-5) and near(mat.albedo_color.b, want.b, 1e-5), "단 %d 색 = 그 사람 색 + 흰 %s" % [i, P[i][3]])
		check(near(mat.albedo_color.a, 0.9 * float(P[i][2]), 1e-5), "단 %d 처음 알파 %s" % [i, mat.albedo_color.a])
		check(mi.sorting_offset > prev_off, "단 %d 는 바깥 단 위에 그려짐" % i)
		prev_off = mi.sorting_offset
		check(have.has(MF.mat_key(mat)), "단 %d 재질 열쇠 %s 가 미리 그려 두는 표 안" % [i, MF.mat_key(mat)])
		if not add:
			check(MF.mat_key(mat) == MF.mat_key(e.ring_mat) and mat.distance_fade_mode == e.ring_mat.distance_fade_mode, "단 %d = 효과 풀 고리 재질과 같은 모양 (이미 쓰이는 셰이더)" % i)
	# 시간이 흐르면: 노드 크기 = FM.plume(t) (카메라 없음 → 상한 1), 단마다 알파 = FM.plume(t).z × 알파 배율
	ko.update(0.3)
	var s := FM.plume(0.3 / (C.KO_SMASH_MS / 1000.0))
	var sc := node.basis.get_scale()
	check(near(sc.x, s.x, 1e-4) and near(sc.y, s.y, 1e-4) and near(sc.z, s.x, 1e-4), "노드 크기 %s = 줄기 모양 %s" % [sc, s])
	for i in P.size():
		check(near((pl.mats[i] as StandardMaterial3D).albedo_color.a, s.z * float(P[i][2]), 1e-5), "단 %d 알파 = 모양 알파 × 배율" % i)
	ko.update(1.0)
	check(ko.plumes.is_empty(), "수명 끝나면 사라짐")
	ko.free()
	e.free()


# c8-u3 연기 상한: 연기 한 덩이 크기도 고리·빛과 같은 화면 상한 (_capped) 을 지남 — 카메라 앞에서 부푼 연기가 화면을 덮지 않게
func test_c8_smoke_capped() -> void:
	var src := FileAccess.get_file_as_string("res://fx/effects.gd")
	var a := src.find("func _update_smoke")
	var b := src.find("func _update_chunks")
	check(a >= 0 and b > a and src.substr(a, b - a).contains("s = _capped(s, gp)"), "_update_smoke 가 크기에 _capped 를 검")
	var fx := Effects.new()
	fx.lv = FXC.LEVELS.high
	fx.smoke(Vector3(3, 3, 0.5), 0x4a4440, 6, 1.4, 1300.0)
	fx.update(0.3, null) # 카메라 없이도 돎 (상한 없음)
	check(fx.smoke_mm.visible_instance_count == 6 and fx.smoke_mmi.visible, "연기 6덩이 (%d)" % fx.smoke_mm.visible_instance_count)
	# 폭발 연기가 다 부풀었을 때 (크기 × 1.9) 카메라 2칸 앞이면 상한, 12칸 앞이면 그대로
	var full: float = float(FXC.BOOM.smoke[1]) * float(FXC.BOOM_K.bigBomb) * 1.9
	fx._cap_on = true
	fx._cam_pos = Vector3(0, 0, 2.0)
	fx._cam_fwd = Vector3(0, 0, -1)
	fx._cam_fov = 75.0
	var near_s: float = fx._capped(full, Vector3.ZERO)
	check(near_s < full and near(near_s, FXC.SCREEN_CAP * 2.0 * 2.0 * tan(deg_to_rad(37.5))), "2칸 앞 연기 %s칸 → %s칸 (화면 높이 × %s)" % [full, near_s, FXC.SCREEN_CAP])
	check(fx._capped(full, Vector3(0, 0, -10.0)) == full, "12칸 앞 연기는 그대로")
	fx.update(0.1, null)
	fx.free()


# ---------- c9-u3 돌발 이벤트 세계 연출 (fx/event_fx.gd · event_fx_math.gd · event_fx_config.gd) ----------
const EFX := preload("res://fx/event_fx.gd")
const EM := preload("res://fx/event_fx_math.gd")
const EK := preload("res://fx/event_fx_config.gd")


# 판 대신: 격자와 격자 버전만 (빙판이 칸 윗면을 찾을 때 씀)
class FakeWorld extends RefCounted:
	var built_version := 1
	var g := PackedByteArray()

	func grid() -> PackedByteArray:
		return g


func _ev_state(kind, left := 3000.0, dir = null, n := 19, items := []) -> Dictionary:
	var st := {"phase": "playing", "field": {"w": n, "d": n, "h": 4}, "items": items, "lava": {"active": false, "z": -1.0}}
	if kind != null:
		st["roundEvent"] = {"kind": kind, "left": left, "dir": dir}
	return st


func _ev_shown(e) -> Dictionary: # 보이는 겹 → 인스턴스 수
	var out := {}
	for id in e.layers:
		var n: MultiMeshInstance3D = e.layers[id]
		if n.visible:
			out[id] = n.multimesh.visible_instance_count
	return out


func _ev_world(n: int) -> FakeWorld:
	var w := FakeWorld.new()
	w.g.resize(n * n * 4)
	return w


# 표에 5종 모두 있고, 종류마다 그 겹만 보임. 모르는 종류 (다른 단위의 새 이벤트 포함)·판 중 아님·끝남·방향 없는 돌풍은 인스턴스 0
func test_c9_event_fx_kinds() -> void:
	for k in ["wind", "ice", "lowgrav", "rain", "supply", "common"]:
		check(EK.EVENT_FX.has(k), "표에 %s" % k)
	check(EK.RUNNING == ["wind", "ice", "lowgrav", "rain"], "스냅샷으로 도는 종류 넷 (보급은 게임 이벤트)")
	var e = EFX.new()
	e.keep = true
	e.world = _ev_world(19)
	var f := Vector3i(19, 19, 4)
	check(_ev_shown(e).is_empty(), "처음엔 아무것도 안 보임 (평소 그리기 0)")
	for k in ["bolt", "", "supply", "meteor"]:
		e.update(0.1, null, _ev_state(k), false)
		check(_ev_shown(e).is_empty(), "모르는 종류 '%s' 는 인스턴스 0 (%s)" % [k, _ev_shown(e)])
	e.update(0.1, null, _ev_state("wind", 3000.0, {"x": 1, "y": 0}), false)
	check(_ev_shown(e) == {"wind": EM.count("wind", f, false, EK.EVENT_FX)}, "돌풍 = 바람 줄만 (%s)" % _ev_shown(e))
	e.update(0.1, null, _ev_state("lowgrav"), false)
	check(_ev_shown(e) == {"lowgrav": EM.count("lowgrav", f, false, EK.EVENT_FX)}, "저중력 = 티끌만 (%s)" % _ev_shown(e))
	e.update(0.1, null, _ev_state("rain"), false)
	check(_ev_shown(e) == {"rain": EM.count("rain", f, false, EK.EVENT_FX)}, "폭우 = 세로 줄만 (%s)" % _ev_shown(e))
	e.update(0.1, null, _ev_state("ice"), false)
	e.update(1.0, null, _ev_state("ice", 2000.0), false)
	var ice := _ev_shown(e)
	check(ice.get("ice", 0) == 19 * 19 and ice.get("glint", 0) > 0 and ice.size() == 2, "빙판 = 칸마다 판 + 반짝 줄 (%s)" % ice)
	e.update(0.1, null, _ev_state("wind", 3000.0, null), false)
	check(_ev_shown(e).is_empty(), "방향 없는 돌풍은 안 그림")
	e.update(0.1, null, _ev_state("rain", 0.0), false)
	check(_ev_shown(e).is_empty(), "남은 시간 0 이면 안 그림")
	var lobby := _ev_state("rain")
	lobby["phase"] = "lobby"
	e.update(0.1, null, lobby, false)
	check(_ev_shown(e).is_empty(), "판 중이 아니면 안 그림")
	e.update(0.1, null, _ev_state("rain"), false)
	e.update(0.1, null, _ev_state(null), false)
	check(_ev_shown(e).is_empty() and e.kind == "", "이벤트가 끝나면 (스냅샷에서 빠지면) 숨김")
	e.update(0.1, null, {}, false)
	check(_ev_shown(e).is_empty(), "방 밖 (빈 상태) 에서도 돎")
	e.free()


# 돌풍 줄은 시간이 흐르면 dir 쪽으로 감 (네 방향), 긴 축 = dir
func test_c9_wind_follows_dir() -> void:
	var w: Dictionary = EK.EVENT_FX.wind
	var f := Vector3i(19, 19, 16)
	var dt := 0.05
	for d: Vector2 in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
		var a := EM.wind_rows(48, f, 1.0, d, w, 1.0)
		var b := EM.wind_rows(48, f, 1.0 + dt, d, w, 1.0)
		var moved := 0
		for i in a.size():
			var dv: Vector3 = b[i][0] - a[i][0]
			if dv.length() > 2.0: # 필드 밖으로 나가 반대편에서 다시 나옴
				continue
			var along := dv.x * d.x + dv.y * d.y
			var side := absf(dv.x * d.y - dv.y * d.x)
			if along > float(w.speed) * (1.0 - float(w.jitter)) * dt - 1e-4 and along < float(w.speed) * (1.0 + float(w.jitter)) * dt + 1e-4 and side < 1e-4 and absf(dv.z) < 1e-6:
				moved += 1
		check(moved >= 44, "방향 %s: %d/48 줄이 dir 쪽으로 %s칸/초" % [d, moved, w.speed])
		# 그리는 노드: 줄 메시의 긴 축 (X) 이 dir (고도 좌표) 과 나란함
		var e = EFX.new()
		e.keep = true
		e.update(1.0, null, _ev_state("wind", 3000.0, {"x": d.x, "y": d.y}), false)
		var axis := Co.gxyz(d.x, d.y, 0.0)
		var ok := true
		for row in e.put.wind:
			var x: Vector3 = row[0].basis.x
			if x.normalized().dot(axis) < 0.999 or x.length() < float(w.len[0]) - 1e-3 or x.length() > float(w.len[1]) + 1e-3:
				ok = false
		check(ok and e.put.wind.size() == 72 and e.layers.wind.multimesh.visible_instance_count == 72, "방향 %s: 줄의 긴 축 = dir, 길이 %s~%s" % [d, w.len[0], w.len[1]])
		e.free()
	check(EM.wind_dir({"x": 0, "y": -3}) == Vector2(0, -1) and EM.wind_dir(null) == Vector2.ZERO and EM.wind_dir({"x": 0, "y": 0}) == Vector2.ZERO, "방향 읽기")
	# 카메라 쪽으로 돌려 세움: 긴 축 그대로, 앞면 (+Z) 이 카메라 쪽, 축끼리 직각
	for cam: Vector3 in [Vector3(3, 5, 9), Vector3(-4, 0.2, 1), Vector3(0, 30, 0)]:
		var t := EM.streak_xform(Vector3(1, 2, 3), Vector3(1, 0, 0), 2.0, 0.05, cam)
		check(near(t.basis.x.x, 2.0) and near(t.basis.y.length(), 0.05) and t.basis.z.dot(cam - Vector3(1, 2, 3)) > 0.0 and absf(t.basis.x.dot(t.basis.y)) < 1e-5 and absf(t.basis.z.dot(t.basis.x)) < 1e-5, "줄 돌려 세우기 (카메라 %s)" % cam)
	check(is_finite(EM.streak_xform(Vector3.ZERO, Vector3(1, 0, 0), 2.0, 0.05, Vector3(5, 0, 0)).basis.y.x), "카메라가 긴 축 위여도 값이 깨지지 않음")


# 줄·티끌은 판 10·19 에서 필드 + 1칸 안, 개수는 표의 상한 안
func test_c9_streaks_in_field() -> void:
	var cfg: Dictionary = EK.EVENT_FX
	var w: Dictionary = cfg.wind
	var m := float(cfg.common.margin)
	check(EM.count("wind", Vector3i(10, 10, 16), false, cfg) == 40 and EM.count("wind", Vector3i(19, 19, 16), false, cfg) == 72, "돌풍 줄 수: 판 10 = 40, 판 19 = 72")
	var mid := EM.count("wind", Vector3i(14, 14, 16), false, cfg)
	check(mid > 40 and mid < 72 and EM.count("wind", Vector3i(40, 40, 16), false, cfg) == 72 and EM.count("wind", Vector3i(4, 4, 16), false, cfg) == 40, "사이는 선형 (판 14 = %d), 밖은 끝 값" % mid)
	check(EM.count("lowgrav", Vector3i(19, 19, 16), false, cfg) == 80 and EM.count("lowgrav", Vector3i(10, 10, 16), false, cfg) == 40 and EM.count("lowgrav", Vector3i(15, 15, 16), false, cfg) == 50, "티끌 수: 판 19 = 80, 넓이에 비례, 최소 40")
	check(EM.count("rain", Vector3i(10, 10, 16), false, cfg) == 40 and EM.count("rain", Vector3i(19, 19, 16), false, cfg) == 40, "세로 줄 40")
	check(EM.count("wind", Vector3i.ZERO, false, cfg) == 0 and EM.count("bolt", Vector3i(19, 19, 16), false, cfg) == 0 and EM.count("supply", Vector3i(19, 19, 16), false, cfg) == 0, "판 없음·모르는 종류는 0")
	for n: int in [10, 19]:
		var f := Vector3i(n, n, 16)
		for d: Vector2 in [Vector2(1, 0), Vector2(0, -1)]:
			var bad := 0
			var faded := 0
			for ti in 40:
				for r in EM.wind_rows(EM.count("wind", f, false, cfg), f, ti * 0.37, d, w, m):
					var c: Vector3 = r[0]
					var hx := absf(d.x) * float(r[1]) * 0.5
					var hy := absf(d.y) * float(r[1]) * 0.5
					if c.x - hx < -m - 1e-4 or c.x + hx > n + m + 1e-4 or c.y - hy < -m - 1e-4 or c.y + hy > n + m + 1e-4 or c.z < float(w.z[0]) or c.z > float(w.z[1]) or float(r[1]) < float(w.len[0]) or float(r[1]) > float(w.len[1]):
						bad += 1
					if float(r[2]) < 1.0:
						faded += 1
			check(bad == 0, "판 %d 방향 %s: 줄 전체가 필드 + %s칸 안, 높이 %s~%s (%d개 어김)" % [n, d, m, w.z[0], w.z[1], bad])
			check(faded > 0, "판 %d: 가장자리에서 흐려지는 줄이 있음 (툭 나타나지 않음)" % n)
		var g: Dictionary = cfg.lowgrav
		var rn: Dictionary = cfg.rain
		var out := 0
		for ti in 40:
			for e in EM.mote_rows(EM.count("lowgrav", f, false, cfg), f, ti * 0.9, g):
				var p: Vector3 = e[0]
				if p.x < 0.0 or p.x > n or p.y < 0.0 or p.y > n or p.z < float(g.z[0]) or p.z > float(g.z[1]) or not [0, 1].has(e[1]) or absf(float(e[3])) > float(g.sway[0]) + 1e-6:
					out += 1
			for e in EM.rain_rows(EM.count("rain", f, false, cfg), f, ti * 0.21, rn):
				var p: Vector3 = e[0]
				if p.x < 0.0 or p.x > n or p.y < 0.0 or p.y > n or p.z - float(rn.len) * 0.5 < float(rn.z[0]) - 1e-4 or p.z + float(rn.len) * 0.5 > float(rn.z[1]) + 1e-4:
					out += 1
		check(out == 0, "판 %d: 티끌·세로 줄이 필드 안 (%d개 어김)" % [n, out])
	# 티끌은 오르고 세로 줄은 내려옴
	var f19 := Vector3i(19, 19, 16)
	var up := 0
	var down := 0
	var m0 := EM.mote_rows(80, f19, 2.0, cfg.lowgrav)
	var m1 := EM.mote_rows(80, f19, 2.1, cfg.lowgrav)
	var r0 := EM.rain_rows(40, f19, 2.0, cfg.rain)
	var r1 := EM.rain_rows(40, f19, 2.02, cfg.rain)
	for i in 80:
		if m1[i][0].z > m0[i][0].z:
			up += 1
	for i in 40:
		if r1[i][0].z < r0[i][0].z:
			down += 1
	check(up >= 74 and down >= 36, "티끌은 위로 (%d/80), 세로 줄은 아래로 (%d/40)" % [up, down])
	# 높이는 그 자리 바닥 (기둥 꼭대기·위험 액체 표면) 위: 지형이 높은 맵·액체가 찬 판에서 묻히지 않음
	var f4 := Vector3i(4, 4, 4)
	var g4 := PackedByteArray()
	g4.resize(4 * 4 * 4)
	g4[(0 * 4 + 1) * 4 + 1] = 1
	g4[(1 * 4 + 1) * 4 + 1] = 1
	g4[(2 * 4 + 3) * 4 + 3] = 12 # 떠 있는 칸도 꼭대기
	var tops := EM.column_tops(g4, f4)
	check(tops.size() == 16 and tops[1 * 4 + 1] == 2 and tops[3 * 4 + 3] == 3 and tops[0] == 0, "기둥 꼭대기 표")
	check(EM.column_tops(PackedByteArray(), f4).is_empty(), "격자가 없으면 빈 표")
	check(EM.surface_at(tops, f4, 1.5, 1.2, false, 0.0) == 2.0 and EM.surface_at(tops, f4, 0.5, 0.5, false, 9.0) == 0.0 and EM.surface_at(tops, f4, 0.5, 0.5, true, 1.3) == 1.3 and EM.surface_at(tops, f4, 1.5, 1.5, true, 1.3) == 2.0, "바닥 높이 = 꼭대기, 액체가 더 높으면 그 표면")
	check(EM.surface_at(tops, f4, 4.7, 5.0, false, 0.0) == 3.0 and EM.surface_at(tops, f4, -0.9, -0.2, false, 0.0) == 0.0 and EM.surface_at(PackedInt32Array(), f4, 1.5, 1.5, false, 0.0) == 0.0, "필드 밖은 가장 가까운 가장자리 칸, 표가 없으면 0")
	check(near(EM.follow(0.0, 2.0, 0.05, 8.0), 0.8) and EM.follow(0.0, 2.0, 1.0, 8.0) == 2.0 and EM.follow(1.0, 1.0, 0.1, 8.0) == 1.0, "바닥 높이를 부드럽게 따라감")
	var e = EFX.new()
	e.keep = true
	var wd := FakeWorld.new()
	wd.g.resize(19 * 19 * 4)
	for i in 19 * 19: # 판 전체가 높이 2
		wd.g[i] = 1
		wd.g[19 * 19 + i] = 1
	e.world = wd
	var st := _ev_state("lowgrav", 3000.0)
	e.update(0.5, null, st, false)
	var lo := INF
	for row in e.put.lowgrav:
		lo = minf(lo, row[0].origin.y)
	check(lo >= 2.0, "티끌은 지형 꼭대기 위에서 오름 (가장 낮은 %s)" % lo)
	st.lava = {"active": true, "z": 3.5}
	e.update(0.1, null, st, false)
	lo = INF
	for row in e.put.lowgrav:
		lo = minf(lo, row[0].origin.y)
	check(lo >= 3.5, "액체가 차오르면 그 표면 위 (가장 낮은 %s)" % lo)
	e.update(0.1, null, _ev_state("wind", 3000.0, {"x": 1, "y": 0}), false)
	lo = INF
	for row in e.put.wind:
		lo = minf(lo, row[0].origin.y)
	check(lo >= 2.0 + float(w.z[0]) - 1e-4, "바람 줄도 지형 위 (가장 낮은 %s)" % lo)
	e.update(0.1, null, _ev_state("rain"), false)
	lo = INF
	for row in e.put.rain:
		lo = minf(lo, row[0].origin.y)
	check(lo >= 2.0 + float(cfg.rain.z[0]), "세로 줄도 지형 위 (가장 낮은 %s)" % lo)
	e.free()


# 들어올 때 0.4초·끝날 때 0.6초 동안 알파가 흐려짐. 길이는 게임 이벤트의 ms, 못 받았으면 처음 본 left
func test_c9_event_fade() -> void:
	var c: Dictionary = EK.EVENT_FX.common
	check(near(float(c.fade_in), 0.4) and near(float(c.fade_out), 0.6), "들어올 때 0.4초, 끝날 때 0.6초")
	check(EM.fade(5000.0, 5000.0, c) == 0.0 and near(EM.fade(4800.0, 5000.0, c), 0.5) and EM.fade(4600.0, 5000.0, c) == 1.0, "들어올 때 0 → 1")
	check(EM.fade(3000.0, 5000.0, c) == 1.0 and EM.fade(600.0, 5000.0, c) == 1.0 and near(EM.fade(300.0, 5000.0, c), 0.5) and EM.fade(0.0, 5000.0, c) == 0.0 and EM.fade(-5.0, 5000.0, c) == 0.0, "끝날 때 1 → 0")
	check(EM.fade(3000.0, 3000.0, c) == 0.0 and near(EM.fade(2900.0, 3000.0, c), 0.25), "도중에 들어옴 (길이 = 처음 본 left): 그때부터 들어옴")
	# 노드: 게임 이벤트가 먼저 오면 그 ms, 안 오면 처음 본 left. 스냅샷 사이엔 프레임 dt 로 줄임
	var e = EFX.new()
	e.keep = true
	e.on_round_event({"type": "roundEvent", "kind": "rain", "ms": 6000.0})
	e.update(0.0, null, _ev_state("rain", 5900.0), false)
	check(e.total == 6000.0 and e.left == 5900.0, "길이 = 게임 이벤트 ms (%s)" % e.total)
	var a0: float = e.put.rain[0][1].a + e.put.rain[1][1].a
	e.update(0.1, null, _ev_state("rain", 5900.0), false)
	check(near(e.left, 5800.0), "같은 스냅샷이면 dt 로 줄임 (%s)" % e.left)
	e.update(0.1, null, _ev_state("rain", 5600.0), false)
	check(e.left == 5600.0, "새 스냅샷이면 그 값")
	var a1: float = e.put.rain[0][1].a + e.put.rain[1][1].a
	check(a1 > a0, "들어오며 진해짐 (%s → %s)" % [a0, a1])
	e.update(0.1, null, _ev_state(null), false)
	e.update(0.1, null, _ev_state("lowgrav", 2500.0), false)
	check(e.total == 2500.0, "게임 이벤트를 못 받았으면 처음 본 left (%s)" % e.total)
	e.on_round_event({"type": "roundEvent", "kind": "lowgrav", "ms": 6000.0})
	check(e.total == 6000.0, "뒤늦게 온 게임 이벤트의 ms 로 고침")
	e.free()


# 빙판 판은 바닥 표시 아래: 띄움 < 그림자 칸 띄움, 그리는 순서 < 0 (그림자 칸 0·착지 테 1·발밑 고리 7 아래). 위험 액체에 잠긴 칸은 빠짐
func test_c9_ice_below_ground_marks() -> void:
	var WC := preload("res://world/world_config.gd")
	var ic: Dictionary = EK.EVENT_FX.ice
	var c: Dictionary = EK.EVENT_FX.common
	check(float(ic.lift) > 0.0 and float(ic.lift) + float(ic.glint.lift) < float(WC.SHADOW_LIFT), "판·반짝 줄 띄움 %s < 그림자 칸 %s" % [float(ic.lift) + float(ic.glint.lift), WC.SHADOW_LIFT])
	check(float(ic.lift) < float(WC.FOOT_RING.lift), "발밑 고리 띄움 %s 보다 아래" % WC.FOOT_RING.lift)
	check(int(c.order_floor) == -2 and int(ic.glint.order) < 0 and int(ic.glint.order) > int(c.order_floor), "판 순서 −2, 반짝 줄은 그 위·0 아래")
	check(int(c.order_air) == 3 and int(c.order_air) < int(WC.FOOT_RING.order), "줄·티끌·기둥 순서 3 (발밑 고리 %d 아래)" % WC.FOOT_RING.order)
	# 4×4×4 판: (1, 1) 기둥 높이 2, (2, 0) 높이 1, 나머지 바닥 (0)
	var f := Vector3i(4, 4, 4)
	var g := PackedByteArray()
	g.resize(4 * 4 * 4)
	g[(0 * 4 + 1) * 4 + 1] = 1
	g[(1 * 4 + 1) * 4 + 1] = 1
	g[(0 * 4 + 0) * 4 + 2] = 10
	var rows := EM.ice_cells(g, f, false, 0.0)
	var top := {}
	var sorted := true
	for i in rows.size():
		top[Vector2i(rows[i][0], rows[i][1])] = rows[i][2]
		if i > 0 and rows[i][3] < rows[i - 1][3]:
			sorted = false
	check(rows.size() == 16 and top[Vector2i(1, 1)] == 2.0 and top[Vector2i(2, 0)] == 1.0 and top[Vector2i(3, 3)] == 0.0, "칸마다 윗면 (기둥 꼭대기) 하나")
	check(sorted and near(rows[0][3], sqrt(0.5)) and near(rows.back()[3], sqrt(4.5)), "가운데에서 가까운 순서")
	var wet := EM.ice_cells(g, f, true, 0.4)
	check(wet.size() == 2, "액체 0.4: 바닥 칸 (높이 0) 은 잠겨 빠지고 단 둘만 (%d)" % wet.size())
	check(EM.ice_cells(g, f, true, 1.0).size() == 1 and EM.ice_cells(g, f, true, 2.0).is_empty(), "액체 1 → 높이 2 기둥만, 2 → 없음")
	check(EM.ice_cells(g, f, false, 5.0).size() == 16, "액체가 안 켜졌으면 높이 값은 안 봄")
	var bumped := EM.ice_cells(g, f, false, 0.0, func(cx: int, cy: int, t: int) -> float: return 0.1 if t == 2 else 0.0)
	var b_top := 0.0
	for r in bumped:
		if r[0] == 1 and r[1] == 1:
			b_top = r[2]
	check(near(b_top, 2.1), "윗면 들썩임을 따라감 (%s)" % b_top)
	check(EM.ice_cells(PackedByteArray(), f, false, 0.0).is_empty(), "격자가 아직 없으면 빈 목록")
	# 퍼짐: 0.5초에 가운데에서 바깥으로
	var far: float = rows.back()[3]
	check(EM.ice_shown(rows, EM.ice_radius(0.0, far, float(ic.spread))) == 0 and EM.ice_shown(rows, EM.ice_radius(0.25, far, float(ic.spread))) == 4 and EM.ice_shown(rows, EM.ice_radius(0.5, far, float(ic.spread))) == 16, "0초 0칸 → 0.25초 가운데 4칸 → 0.5초 전부")
	check(near(float(ic.spread), 0.5), "퍼지는 시간 0.5초")
	# 반짝 줄: 4칸 중 1칸꼴, 방향 두 가지
	var gl := 0
	var d0 := 0
	for y in 40:
		for x in 40:
			if EM.glint_at(x, y, int(ic.glint.every)):
				gl += 1
				if EM.glint_dir(x, y) == 0:
					d0 += 1
	check(gl > 300 and gl < 500 and d0 > gl * 0.35 and d0 < gl * 0.65, "반짝 줄 1600칸 중 %d칸 (4칸 중 1칸꼴), 방향 반반 (%d)" % [gl, d0])
	# 노드: 판 재질 순서·자리, 격자가 바뀌면 다시 깖
	var e = EFX.new()
	e.keep = true
	var w := FakeWorld.new()
	w.g = g
	e.world = w
	var st := {"phase": "playing", "field": {"w": 4, "d": 4, "h": 4}, "items": [], "lava": {"active": false, "z": -1.0}, "roundEvent": {"kind": "ice", "left": 5000.0, "dir": null}}
	e.update(0.0, null, st, false)
	check((e.layers.ice.material_override as StandardMaterial3D).render_priority == -2 and (e.layers.glint.material_override as StandardMaterial3D).render_priority == int(ic.glint.order), "판·반짝 줄 재질 순서")
	check(e.layers.ice.multimesh.visible_instance_count == 0, "시작 순간엔 아직 안 퍼짐")
	st.roundEvent.left = 4000.0
	e.update(1.0, null, st, false)
	var mm: MultiMesh = e.layers.ice.multimesh
	check(mm.visible_instance_count == 16, "다 퍼지면 16칸")
	var tall := false
	var sized := true
	for row in e.put.ice:
		var t: Transform3D = row[0]
		if near(t.origin.x, 1.5) and near(t.origin.z, -1.5) and near(t.origin.y, 2.0 + float(ic.lift)):
			tall = true
		if not near(t.basis.x.length(), 1.0 - float(ic.inset)) or not near(row[1].a, float(ic.alpha)):
			sized = false
	check(tall and sized and e.put.ice.size() == 16, "높이 2 기둥 위 판은 2 + 띄움, 크기 = 칸 − %s, 알파 %s" % [ic.inset, ic.alpha])
	check(near((e.layers.ice.material_override as StandardMaterial3D).albedo_color.a, 1.0), "다 들어오면 재질 알파 1")
	st.lava = {"active": true, "z": 0.5}
	e.update(0.1, null, st, false)
	check(mm.visible_instance_count == 2, "액체가 차오르면 잠긴 칸의 판이 빠짐 (%d)" % mm.visible_instance_count)
	st.lava = {"active": false, "z": -1.0}
	w.g[(2 * 4 + 1) * 4 + 1] = 1 # 블록이 쌓임 → 격자 버전이 오름
	w.built_version = 2
	e.update(0.1, null, st, false)
	var up := false
	for row in e.put.ice:
		if near(row[0].origin.y, 3.0 + float(ic.lift)):
			up = true
	check(mm.visible_instance_count == 16 and up, "격자가 바뀌면 다시 깖 (쌓인 칸 위로)")
	e.world = null
	e.update(0.1, null, st, false)
	check(_ev_shown(e).is_empty(), "판이 없으면 빙판은 안 그림")
	e.free()


# 보급: 이벤트 뒤 새로 나타난 아이템 자리만 빛 기둥, 먹히면 바로 지움, 수명이 다하면 사라짐
func test_c9_supply_new_cells() -> void:
	var s: Dictionary = EK.EVENT_FX.supply
	var old := [{"type": "bomb", "x": 1, "y": 1, "z": 0}]
	var prev := EM.item_cells(old)
	var now := old + [{"type": "speed", "x": 2, "y": 3, "z": 1}, {"type": "bomb", "x": 2, "y": 3, "z": 1}, {"type": "brick", "x": 4, "y": 0, "z": 0}]
	var fresh := EM.new_cells(prev, now)
	check(fresh.size() == 2 and fresh[0][0] == 2 and fresh[0][1] == 3 and fresh[0][2] == 1.0 and fresh[1][0] == 4 and fresh[1][1] == 0, "앞 스냅샷에 없던 자리만, 같은 자리는 한 번 (%s)" % [fresh])
	check(EM.new_cells(prev, old).is_empty() and EM.new_cells({}, null).is_empty() and EM.new_cells(prev, []).is_empty(), "새 자리가 없으면 빈 목록")
	check(near(EM.pillar_k(0.0, 4.0), 1.0) and near(EM.pillar_k(2.0, 4.0), 0.5) and EM.pillar_k(4.0, 4.0) == 0.0 and near(float(s.life), 4.0) and near(float(s.h), 6.0), "기둥 알파: 4초에 0, 높이 6칸")
	var r0: Array = EM.ring_at(0.0, s.ring)
	var r1: Array = EM.ring_at(float(s.ring.ms) / 1000.0, s.ring)
	check(near(r0[0], float(s.ring.r)) and near(r0[1], 1.0) and near(r1[0], float(s.ring.r) * float(s.ring.grow)) and r1[1] == 0.0, "고리 한 번: 커지며 사라짐")
	var e = EFX.new()
	e.keep = true
	e.update(0.1, null, _ev_state(null, 0.0, null, 19, old), false)
	e.update(0.1, null, _ev_state(null, 0.0, null, 19, now), false)
	check(_ev_shown(e).is_empty(), "보급 이벤트가 아니면 새 아이템에 기둥 없음")
	e.update(0.1, null, _ev_state(null, 0.0, null, 19, old), false)
	e.on_round_event({"type": "roundEvent", "kind": "supply", "ms": 0})
	e.update(0.0, null, _ev_state(null, 0.0, null, 19, now), false)
	check(_ev_shown(e) == {"pillar": 2, "ring": 2}, "새 자리 둘에 빛 기둥 + 고리 (%s)" % _ev_shown(e))
	var t: Transform3D = e.put.pillar[0][0]
	check(near(t.origin.x, 2.5) and near(t.origin.z, -3.5) and near(t.origin.y, 1.0 + float(s.h) * 0.5) and near(t.basis.x.length(), float(s.h)) and t.basis.x.normalized().dot(Vector3.UP) > 0.999, "기둥은 아이템 칸 가운데에서 위로 %s칸" % s.h)
	check(near(e.put.pillar[0][1].a, float(s.alpha)), "처음 알파 %s" % s.alpha)
	e.update(1.0, null, _ev_state(null, 0.0, null, 19, now), false)
	check(_ev_shown(e) == {"pillar": 2}, "고리는 한 번 (1초 뒤엔 기둥만): %s" % _ev_shown(e))
	check(near(e.put.pillar[0][1].a, float(s.alpha) * 0.75), "기둥이 흐려짐 (%s)" % e.put.pillar[0][1].a)
	e.update(0.1, null, _ev_state(null, 0.0, null, 19, old + [now[3]]), false)
	check(_ev_shown(e) == {"pillar": 1} and near(e.put.pillar[0][0].origin.x, 4.5), "먹힌 아이템의 기둥은 바로 지움")
	e.update(float(s.life), null, _ev_state(null, 0.0, null, 19, old + [now[3]]), false)
	check(_ev_shown(e).is_empty(), "수명 %s초가 지나면 사라짐" % s.life)
	# 이벤트 뒤 arm 초가 지나도록 새 아이템이 없으면 그 뒤 아이템은 보급품이 아님
	e.on_round_event({"type": "roundEvent", "kind": "supply", "ms": 0})
	e.update(float(s.arm) + 0.1, null, _ev_state(null, 0.0, null, 19, old + [now[3]]), false)
	e.update(0.1, null, _ev_state(null, 0.0, null, 19, now), false)
	check(_ev_shown(e).is_empty(), "기다리는 시간이 지난 뒤 나온 아이템엔 기둥 없음")
	e.free()


# 카메라에서 1.5 m 안의 줄·티끌·기둥은 알파 0 (눈앞을 가리지 않음)
func test_c9_near_cam_hidden() -> void:
	var c: Dictionary = EK.EVENT_FX.common
	check(near(float(c.near), 1.5), "가까운 거리 1.5")
	check(EM.near_k(0.0, c) == 0.0 and EM.near_k(1.49, c) == 0.0 and EM.near_k(1.5, c) == 0.0 and EM.near_k(1.5 + float(c.near_soft), c) == 1.0 and EM.near_k(30.0, c) == 1.0, "1.5 안은 0, 그 밖은 다시 진해짐")
	check(near(EM.seg_dist(Vector3(0, 1, 0), Vector3(-2, 0, 0), Vector3(2, 0, 0)), 1.0) and near(EM.seg_dist(Vector3(5, 0, 0), Vector3(-2, 0, 0), Vector3(2, 0, 0)), 3.0) and near(EM.seg_dist(Vector3(1, 1, 1), Vector3.ZERO, Vector3.ZERO), sqrt(3.0)), "선분까지 거리")
	check(near(EM.wide(0.05, 4.0, float(c.thin)), 0.05) and near(EM.wide(0.05, 30.0, float(c.thin)), 30.0 * float(c.thin)), "가까이선 표의 폭, 멀면 거리에 비례 (가늘어지지 않게)")
	var cam := Camera3D.new()
	for k in ["wind", "lowgrav", "rain"]:
		var e = EFX.new()
		e.keep = true
		var st := _ev_state(k, 3000.0, {"x": 1, "y": 0})
		e.on_round_event({"type": "roundEvent", "kind": k, "ms": 6000.0}) # 길이를 알려 줌 → 남은 3초는 다 들어온 뒤 (알파 1)
		e.update(1.0, null, st, false)
		var at: Vector3 = e.put[k][3][0].origin
		cam.transform = Transform3D(Basis(), at + Vector3(0.3, 0.2, 0.4))
		e.update(0.0, cam, st, false)
		var hidden := 0
		var shown := 0
		var wrong := 0
		for row in e.put[k]:
			var a: float = row[1].a
			var d := cam.transform.origin.distance_to(row[0].origin)
			if a == 0.0:
				hidden += 1
			else:
				shown += 1
				if d < float(c.near) - 1.4: # 줄은 선분 거리라 가운데는 길이 절반까지 더 멀 수 있음
					wrong += 1
		check(e.put[k][3][1].a == 0.0 and hidden >= 1 and shown > hidden and wrong == 0, "%s: 카메라 앞 인스턴스는 알파 0 (숨김 %d · 보임 %d)" % [k, hidden, shown])
		e.free()
	# 보급 빛 기둥도
	var e = EFX.new()
	e.keep = true
	var items := [{"type": "bomb", "x": 5, "y": 5, "z": 0}, {"type": "bomb", "x": 12, "y": 12, "z": 0}]
	e.update(0.1, null, _ev_state(null), false)
	e.on_round_event({"type": "roundEvent", "kind": "supply", "ms": 0})
	cam.transform = Transform3D(Basis(), Co.gxyz(5.5, 6.2, 1.4))
	e.update(0.0, cam, _ev_state(null, 0.0, null, 19, items), false)
	check(e.put.pillar.size() == 2 and e.put.pillar[0][1].a == 0.0 and e.put.pillar[1][1].a > 0.5, "눈앞의 빛 기둥은 알파 0, 먼 기둥은 그대로")
	e.free()
	cam.free()


# 그래픽 낮춤: 줄·티끌 수 × 0.4, 반짝 줄 끔. 빙판 판·빛 기둥은 그대로 (신호)
func test_c9_low_counts() -> void:
	var cfg: Dictionary = EK.EVENT_FX
	var f := Vector3i(19, 19, 4)
	check(near(float(cfg.common.low_k), 0.4), "낮춤 배율 0.4")
	check(EM.count("wind", f, true, cfg) == 29 and EM.count("lowgrav", f, true, cfg) == 32 and EM.count("rain", f, true, cfg) == 16, "낮춤 수: 돌풍 29 · 티끌 32 · 세로 줄 16")
	check(EM.count("wind", Vector3i(10, 10, 4), true, cfg) == 16 and EM.count("lowgrav", Vector3i(10, 10, 4), true, cfg) == 16, "판 10 낮춤: 돌풍 16 · 티끌 16")
	var e = EFX.new()
	e.keep = true
	e.world = _ev_world(19)
	for k in ["wind", "lowgrav", "rain"]:
		e.update(0.5, null, _ev_state(k, 3000.0, {"x": 0, "y": 1}), true)
		check(_ev_shown(e) == {k: EM.count(k, f, true, cfg)}, "낮춤 %s 인스턴스 %s" % [k, _ev_shown(e)])
	e.update(0.1, null, _ev_state("ice"), true)
	e.update(1.0, null, _ev_state("ice", 2000.0), true)
	check(_ev_shown(e) == {"ice": 361}, "낮춤 빙판: 판은 그대로, 반짝 줄 끔 (%s)" % _ev_shown(e))
	e.update(0.1, null, _ev_state("ice", 1900.0), false)
	check(_ev_shown(e).get("glint", 0) > 0, "화질을 올리면 반짝 줄이 다시 깔림")
	e.update(0.1, null, _ev_state(null), true)
	e.on_round_event({"type": "roundEvent", "kind": "supply", "ms": 0})
	e.update(0.0, null, _ev_state(null, 0.0, null, 19, [{"type": "bomb", "x": 3, "y": 3, "z": 0}]), true)
	check(_ev_shown(e) == {"pillar": 1, "ring": 1}, "낮춤 보급: 빛 기둥·고리 그대로")
	e.free()


# 재질 모양은 판 들어올 때 미리 그려 두는 표 (warm_scan.gd STD_KEYS) 안 — 이벤트가 처음 올 때 셰이더를 안 만듦
func test_c9_event_materials_std() -> void:
	var WS := preload("res://world/warm_scan.gd")
	var MF := preload("res://core/mat_first.gd")
	var have := []
	for k in WS.STD_KEYS:
		have.append(MF.mat_key(WS.std_material(k)))
	check(WS.STD_KEYS.has(EK.KEY) and EK.KEY == [0, 1, 0, 0, 0, 0, 1, 0, 0, 1, 0], "재질 열쇠가 표준 표의 줄 (정점 색 반투명)")
	var want := MF.mat_key(WS.std_material(EK.KEY))
	var e = EFX.new()
	e.keep = true
	check(e.layers.size() == 7, "겹 7개 (바람 줄·티끌·세로 줄·빙판 판·반짝 줄·빛 기둥·고리)")
	for id in e.layers:
		var n: MultiMeshInstance3D = e.layers[id]
		var m := n.material_override as StandardMaterial3D
		check(m != null and have.has(MF.mat_key(m)) and MF.mat_key(m) == want, "%s 재질 열쇠 %s 가 표준 표 안" % [id, MF.mat_key(m) if m != null else "없음"])
		check(m != null and m.next_pass == null and not m.vertex_color_is_srgb and m.distance_fade_mode == BaseMaterial3D.DISTANCE_FADE_DISABLED, "%s: 열쇠에 안 잡히는 갈래 (덧패스·정점 색 sRGB·거리 흐림) 없음" % id)
		check(n.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF and not n.visible and n.multimesh.use_colors, "%s: 그림자 없음·처음엔 숨김·인스턴스 색" % id)
	# 줄 메시: 2단 (흰 심 + 바깥 색), 삼각형 수가 작음
	var w: Dictionary = EK.EVENT_FX.wind
	var wm: ArrayMesh = e.layers.wind.multimesh.mesh
	var sky := Co.color(w.color)
	check(_has_color(wm, Color(1, 1, 1, float(w.core_alpha))) and _has_color(wm, Color(sky.r, sky.g, sky.b, float(w.alpha))), "바람 줄 = 흰 심 + 연하늘")
	var r: Dictionary = EK.EVENT_FX.rain
	var G3C := preload("res://shaders/g3_config.gd")
	check(_has_color(e.layers.rain.multimesh.mesh, Color(1, 1, 1, float(r.core_alpha))) and _has_color(e.layers.rain.multimesh.mesh, Color(G3C.OUTLINE_COLOR.r, G3C.OUTLINE_COLOR.g, G3C.OUTLINE_COLOR.b, float(r.alpha))), "세로 줄 = 잉크 + 흰 심")
	check(e.layers.ring.multimesh.mesh == RL.mesh("aura", int(EK.EVENT_FX.supply.color)) and int(EK.EVENT_FX.supply.color) == int(C.GAME_LIGHT_ITEM), "보급 고리 = ring_look aura 메시 (아이템 빛 노랑)")
	var tris := 0
	for id in ["wind", "rain", "pillar", "lowgrav"]:
		tris = maxi(tris, (e.layers[id].multimesh.mesh as ArrayMesh).surface_get_array_len(0) / 3)
	check(tris <= 12, "줄·티끌 메시는 삼각형 12개 이하 (%d)" % tris)
	# 티끌 = 위 끝 마름모 (가로세로 같은 크기) + 아래로 흐려지는 꼬리
	var g: Dictionary = EK.EVENT_FX.lowgrav
	var mv: PackedVector3Array = (e.layers.lowgrav.multimesh.mesh as ArrayMesh).surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var long := 1.0 + float(g.tail)
	check(mv.size() == 9 and near((mv[1].x - mv[5].x) * long, 1.0) and near(mv[0].y - mv[2].y, 1.0) and near(mv[8].x, -0.5) and near(mv[1].x, 0.5), "티끌 메시: 마름모 높이 × (1 + tail) = 폭, 꼬리 끝이 맨 아래")
	check(_has_color(e.layers.lowgrav.multimesh.mesh, Color(1, 1, 1, 0)) and _has_color(e.layers.lowgrav.multimesh.mesh, Color(1, 1, 1, float(g.tail_alpha))) and _has_color(e.layers.lowgrav.multimesh.mesh, Color.WHITE), "꼬리는 끝으로 갈수록 흐려짐")
	e.free()
