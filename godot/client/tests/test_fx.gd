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
	check(fx.rings.any(func(m): return m.visible), "고리가 보임")
	for i in 100:
		fx.update(0.02, null)
	check(fx.alive_particles() == 0, "2초 뒤 파편 %d" % fx.alive_particles())
	check(not fx.rings.any(func(m): return m.visible), "고리 사라짐")
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
	var ring_mat: StandardMaterial3D = fx.rings[0].material_override
	var box_mat: StandardMaterial3D = fx.mm.mesh.material
	for m in [ring_mat, box_mat]:
		check(m.distance_fade_mode == BaseMaterial3D.DISTANCE_FADE_PIXEL_ALPHA and m.distance_fade_max_distance > m.distance_fade_min_distance, "가까우면 흐려짐 %s" % m)
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
	# 지상 F 준비: 그 사람 발밑 (화면 위치) 흰 고리, 커짐 1.8, 준비 시간 동안, 눕힘
	var rec := FxRec.new()
	bf.effects = rec
	bf.bodies = {"shown": {5: Vector3(1, 2, 3)}}
	bf.on_event({"type": "skillWindup", "who": 5, "ms": 400})
	check(rec.rings == [[Vector3(1, 2, 3.05), 0xffffff, 1.8, 0.4, true]], "준비 고리 (흰, 1.8, ms) %s" % [rec.rings])
	rec.rings.clear()
	bf.on_event({"type": "skillWindup", "who": 5})
	check(rec.rings.size() == 1 and is_equal_approx(rec.rings[0][3], C.SKILL_WINDUP_MS / 1000.0), "ms 없으면 SKILL_WINDUP_MS")
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
