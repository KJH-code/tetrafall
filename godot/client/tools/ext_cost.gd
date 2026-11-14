# W40 외부 몸 가산 층 비용: 8명 (닌자·탱크·사냥꾼·갈고리 x2) 을 N 프레임 sync 해 천 시뮬 / 시선·숨쉬기 층의 ms/프레임을 잼 (렌더 없음).
# godot --headless --path godot/client -s res://tools/ext_cost.gd -- [프레임 수, 기본 600]
# W49: 끝의 '옛 모션 프리셋'·'최소 프리셋' 줄 = 설정 창 프리셋 (chars_config.gd EXT_MOTION_PRESETS) 일 때 비용 — 꺼진 가산 층은 건너뜀
extends SceneTree


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var a := OS.get_cmdline_user_args()
	var n: int = int(a[0]) if a.size() > 0 else 600
	var T = load("res://tests/test_w40.gd").new()
	var M = load("res://chars/ext_motion.gd")
	M.bodies.clear()
	var bodies := []
	var i := 0
	for ch in ["ninja", "tank", "hunter", "hook", "ninja", "tank", "hunter", "hook"]:
		var b = T._body(ch)
		var h := Node3D.new()
		h.position = Vector3(i * 1.5, 0, 0)
		h.add_child(b)
		bodies.append([b, h])
		i += 1
	var chains := 0
	for e in bodies:
		chains += e[0].ext.cloths.size()
	print("TF 몸 8, 천 줄 ", chains)
	var K = load("res://chars/chars_config.gd")
	for mode in ["둘 다", "W43 끔", "천 끔", "가산 끔", "둘 다 끔", "옛 모션 프리셋", "최소 프리셋"]: # 마지막 둘 = W49 설정 창 프리셋 (K.set_flags — 가산 층 플래그가 꺼지면 계산을 건너뜀, 비용 0 확인). W43 끔 = 방향·기울임·전환·일어나기·무기 흔들림 (move_off, 팔 흔들림 폭 포함)
		var saved := []
		K.set_flags(K.preset_flags("old") if mode == "옛 모션 프리셋" else (K.preset_flags("min") if mode == "최소 프리셋" else null))
		for e in bodies:
			var X = e[0].ext
			saved.append(X.cloths.duplicate())
			if mode == "천 끔" or mode == "둘 다 끔":
				X.cloths.clear()
			X.extra_off = mode == "가산 끔" or mode == "둘 다 끔"
			X.move_off = mode == "W43 끔"
		var t0 := Time.get_ticks_usec()
		for f in n:
			var st: Dictionary = T._st({"walking": true, "hs": 4.5, "walk": f * 0.2, "t": f / 60.0, "mvF": 4.5 * (1.0 if f % 120 < 90 else -1.0), "vw": Vector2(4.5, 0.0)})
			for e in bodies:
				(e[1] as Node3D).position.x += 0.075
				e[0].ext.cloth_t = Time.get_ticks_msec() * 0.001 - 1.0 / 60.0
				e[0].ext.extra_t = e[0].ext.cloth_t
				e[0].ext.last_t = e[0].ext.cloth_t
				e[0].ext.sync(st)
		var ms := (Time.get_ticks_usec() - t0) / 1000.0 / n
		print("TF %s: %.3f ms/프레임 (8명)" % [mode, ms])
		for k in bodies.size():
			bodies[k][0].ext.cloths = saved[k]
	K.set_flags(null)
	quit()
