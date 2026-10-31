# G5 효과 계산이 JS (client/effects.js·ko.js) 와 같은지 (tools/fixtures-fx.mjs 가 뽑은 정답) + 효과 노드가 이벤트를 받아 파편·줄기·소리 신호를 내는지
extends RefCounted

const C := preload("res://core/config.gd")
const Co := preload("res://core/coords.gd")
const FM := preload("res://fx/fx_math.gd")
const Effects := preload("res://fx/effects.gd")
const KO := preload("res://fx/ko.gd")
const FX := preload("res://fx/fx.gd")

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
