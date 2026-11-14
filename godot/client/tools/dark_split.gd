# W51: 대기실 어두운 무대 소품 조각 시간 재기 — 테마마다 한 덩어리 (--no-dark-split) 와 끊어 지음 (DARK_STEP_MS) 의 조각 수·가장 긴 조각 ms·합 ms
# 사용: xvfb-run -a godot --path godot/client --rendering-method gl_compatibility -s res://tools/dark_split.gd -- [--reps 3] [--cut ms]
extends SceneTree


func _init() -> void:
	var C = load("res://core/config.gd")
	var WC = load("res://world/world_config.gd")
	var S = load("res://title/title_stage.gd")
	var args := OS.get_cmdline_user_args()
	var reps := 3
	var cut: float = WC.DARK_STEP_MS
	for i in args.size():
		if args[i] == "--reps":
			reps = int(args[i + 1])
		if args[i] == "--cut":
			cut = float(args[i + 1])
	print("테마\t한 덩어리 최대 ms\t끊음 조각 수\t끊음 최대 조각 ms\t합 ms (한 덩어리 → 끊음)  [끊는 시간 %.1f ms, %d번 중 가장 나쁜 값]" % [cut, reps])
	for id in C.TITLE_THEMES.keys():
		var worst := {}
		for mode in ["full", "cut"]:
			var mx := 0.0
			var tot := 0.0
			var cnt := 0
			for r in reps:
				var st = S.new(id, {"low": false, "logoW": 0, "logoH": 0, "camDist": 30.0, "ring": true, "clear": 20.0, "floorZ": -4.0, "defer": true})
				st.cut_override = -1.0 if mode == "full" else cut
				var m := 0.0
				var t := 0.0
				var n := 0
				while true:
					var t0 := Time.get_ticks_usec()
					var done: bool = st.setup_step()
					var ms := (Time.get_ticks_usec() - t0) / 1000.0
					m = maxf(m, ms)
					t += ms
					n += 1
					if done or n > 200:
						break
				mx = maxf(mx, m)
				tot = maxf(tot, t)
				cnt = maxi(cnt, n)
				st.free()
			worst[mode] = [mx, tot, cnt]
		print("%s\t%.1f\t%d\t%.1f\t%.1f → %.1f" % [id, worst.full[0], worst.cut[2], worst.cut[0], worst.full[1], worst.cut[1]])
	quit()
