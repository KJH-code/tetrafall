# W31 적응형 3D 해상도 계산 (world/adapt_calc.gd): 목표 프레임, 오르내림, 히스테리시스 (진동 없음), 바닥·천장, CPU 병목이면 가만히, 히치 무시, MSAA 낮춤.
# 가짜 GPU 부하: 프레임 시간 = max(CPU, 가득 그릴 때 GPU ms × 배율²) (+ 잡음, V-Sync 면 목표 칸으로 올림) 을 계산기 입력으로 흉내냄
extends RefCounted

const WC := preload("res://world/world_config.gd")
const AC := preload("res://world/adapt_calc.gd")
const Gfx := preload("res://world/gfx.gd")

var errors: Array = []


func check(cond: bool, msg: String) -> void:
	if not cond:
		errors.append(msg)


# 가짜 장면: gpu_full ms (배율 1), cpu ms. vsync 면 16.67 칸으로 올림. 돌려주기 {scale, changes_after, trace}
func _run(ctl, frames: int, gpu_full: float, cpu: float, vsync: bool, know_gpu: bool, seed_ := 1, spikes := false) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_
	var trace := []
	var tgt: float = ctl.target
	for i in frames:
		var g: float = gpu_full * ctl.scale * ctl.scale * (1.0 + rng.randf_range(-0.03, 0.03))
		var f: float = maxf(cpu, g)
		if vsync:
			f = ceilf(f / tgt - 0.02) * tgt
		if spikes and i % 97 == 0:
			f += 60.0
		ctl.push(f, cpu, g if know_gpu else 0.0)
		trace.append(ctl.scale)
	return trace


# 같은 배율이 계속된 마지막 구간 앞에서 배율이 바뀐 횟수 (진동 측정)
func _flips(trace: Array, from: int) -> int:
	var n := 0
	for i in range(maxi(1, from), trace.size()):
		if absf(float(trace[i]) - float(trace[i - 1])) > 0.0001:
			n += 1
	return n


func test_target_ms() -> void:
	check(absf(AC.target_ms(60.0) - 16.6667) < 0.01, "60Hz = 16.7ms")
	check(absf(AC.target_ms(144.0) - 16.6667) < 0.01, "144Hz 도 60fps 목표 (해상도를 지나치게 깎지 않음)")
	check(absf(AC.target_ms(30.0) - 33.333) < 0.01 and absf(AC.target_ms(20.0) - 33.333) < 0.01, "느린 모니터는 30fps 까지")
	check(absf(AC.target_ms(-1.0) - 16.6667) < 0.01 and absf(AC.target_ms(0.0) - 16.6667) < 0.01, "주사율 모르면 60")


func test_trimmed_mean() -> void:
	var a := []
	for i in 19:
		a.append(10.0)
	a.append(200.0)
	check(absf(AC.trimmed_mean(a, 0.2) - 10.0) < 0.001, "히치 한 번은 평균에서 빠짐")
	check(AC.trimmed_mean([], 0.2) == 0.0 and AC.trimmed_mean([5.0], 0.2) == 5.0, "빈 열·한 개")


func test_fast_gpu_stays_at_ceiling() -> void:
	var c := AC.Ctl.new(1.0, AC.target_ms(60.0))
	var t := _run(c, 2000, 6.0, 4.0, true, false)
	check(c.scale == 1.0 and _flips(t, 1) == 0, "빠르면 1.0 그대로 (scale %.2f)" % c.scale)
	check(not c.cut, "MSAA 그대로")


func test_slow_gpu_goes_down_quickly_and_settles() -> void:
	for vs in [true, false]:
		for kg in [true, false]:
			var c := AC.Ctl.new(1.0, AC.target_ms(60.0))
			var t := _run(c, 60, 30.0, 4.0, vs, kg) # 1초: 30ms 가득 → 0.6~0.75 근처로 빨리 내려와야
			check(c.scale < 0.8, "1초 안에 내림 (vsync %s, gpu알림 %s): %.2f" % [vs, kg, c.scale])
			check(c.scale >= 0.6, "바닥 위")
			var t2 := _run(c, 3000, 30.0, 4.0, vs, kg, 2)
			# 정착: 마지막 20초 (1200프레임) 동안 배율이 바뀐 횟수가 적어야 (프로브 간격이 점점 늘어남)
			var flips := _flips(t2, t2.size() - 1200)
			check(flips <= 8, "정착 뒤 진동 없음 (vsync %s, gpu알림 %s): 마지막 20초 %d번 바뀜" % [vs, kg, flips])
			# 정착한 배율의 시간이 목표 안이어야 (평균)
			var g: float = 30.0 * c.scale * c.scale
			check(g <= 16.667 * 1.2 or c.scale <= 0.61, "정착 배율에서 목표 근처 (%.2f → %.1fms)" % [c.scale, g])


func test_gpu_known_climbs_back_without_oscillation() -> void:
	# GPU 시간을 알면 여유를 보고 올라가고, 맞는 자리에서 멈춤 (진동 없음)
	var c := AC.Ctl.new(1.0, AC.target_ms(60.0), WC.ADAPT, 0.6)
	var t := _run(c, 2400, 22.0, 4.0, false, true)
	check(c.scale >= 0.78 and c.scale <= 0.87 and 22.0 * c.scale * c.scale <= 16.7, "22ms 가득 → 16.7ms 목표면 약 0.8~0.85 (%.2f)" % c.scale)
	check(_flips(t, 1200) == 0, "마지막 절반 동안 배율 고정 (%d번)" % _flips(t, 1200))


func test_scene_gets_lighter_goes_up_slowly() -> void:
	var c := AC.Ctl.new(1.0, AC.target_ms(60.0))
	_run(c, 300, 40.0, 4.0, false, true)
	var low: float = c.scale
	check(low <= 0.7, "무거운 장면에서 내려감 %.2f" % low)
	# 장면이 가벼워짐: 올릴 땐 천천히 — 처음 1초 (3창) 동안은 한 단계도 안 오름
	var before: float = c.scale
	_run(c, 60, 8.0, 4.0, false, true)
	check(c.scale == before, "올릴 땐 바로 안 올림 (1초 뒤 %.2f → %.2f)" % [before, c.scale])
	_run(c, 1500, 8.0, 4.0, false, true)
	check(c.scale == 1.0, "충분히 지나면 천장까지 (%.2f)" % c.scale)


func test_floor_and_ceiling() -> void:
	var c := AC.Ctl.new(1.0, AC.target_ms(60.0))
	_run(c, 1500, 200.0, 4.0, false, true)
	check(c.scale == WC.ADAPT.min, "바닥 %.2f" % c.scale)
	# 천장이 낮은 화질 (낮음 0.5): 바닥도 천장 아래로
	var d := AC.Ctl.new(0.5, AC.target_ms(60.0))
	check(d.floor_s == 0.5 and d.scale == 0.5, "천장 0.5 면 바닥도 0.5")
	_run(d, 600, 8.0, 4.0, false, true)
	check(d.scale == 0.5, "천장 못 넘음")
	var e := AC.Ctl.new(0.87, AC.target_ms(60.0))
	_run(e, 1500, 5.0, 4.0, false, true)
	check(e.scale == 0.87, "천장 0.87 이 정확히 (%.2f)" % e.scale)
	e.set_ceiling(0.7)
	check(e.scale == 0.7, "천장을 낮추면 배율도 따라 내려감")


func test_cpu_bound_leaves_scale_alone() -> void:
	# 프레임이 길어도 CPU 일이 대부분이면 (30ms 중 28ms) 해상도를 안 깎음
	var c := AC.Ctl.new(1.0, AC.target_ms(60.0))
	_run(c, 600, 5.0, 28.0, false, false)
	check(c.scale == 1.0 and c.changes == 0, "CPU 병목이면 그대로 (%.2f)" % c.scale)
	# GPU 시간이 따로 있어도 (알림) GPU 가 목표 안이면 그대로
	var d := AC.Ctl.new(1.0, AC.target_ms(60.0))
	_run(d, 600, 5.0, 28.0, false, true)
	check(d.scale == 1.0, "GPU 시간이 목표 안이면 그대로")


func test_spikes_ignored() -> void:
	var c := AC.Ctl.new(1.0, AC.target_ms(60.0))
	var t := _run(c, 3000, 8.0, 4.0, true, false, 3, true)
	check(c.scale == 1.0 and _flips(t, 1) == 0, "가끔 튀는 프레임 (히치) 은 무시 (%.2f)" % c.scale)


func test_msaa_cut_at_floor_and_restart() -> void:
	var c := AC.Ctl.new(1.0, AC.target_ms(60.0))
	_run(c, 200, 200.0, 4.0, false, true)
	check(c.scale == 0.6 and not c.cut, "바닥 도달, 아직 MSAA 그대로")
	_run(c, 20 * int(WC.ADAPT.cut_windows) + 40, 200.0, 4.0, false, true)
	check(c.cut, "바닥에서도 느리면 MSAA 낮춤")
	c.restart()
	check(not c.cut and c.scale == 0.6, "판이 끝나면 MSAA 되돌림, 배율은 그대로")


func test_vsync_probe_backoff() -> void:
	# V-Sync 에 붙어 GPU 시간을 모르는 경우: 올렸다가 실패하면 기다림이 길어짐 (프로브 간격 증가)
	var c := AC.Ctl.new(1.0, AC.target_ms(60.0))
	var t := _run(c, 6000, 24.0, 4.0, true, false) # 100초
	var ups := []
	for i in range(1, t.size()):
		if float(t[i]) > float(t[i - 1]) + 0.0001:
			ups.append(i)
	check(ups.size() >= 1, "프로브는 함")
	if ups.size() >= 4:
		var gap1: int = ups[1] - ups[0]
		var gap_last: int = ups[ups.size() - 1] - ups[ups.size() - 2]
		check(gap_last >= gap1, "프로브 간격이 점점 늘어남 (%d → %d)" % [gap1, gap_last])
	# 마지막 40초 동안 목표 못 맞춘 시간 (프로브 한 창씩) 이 5% 미만
	var bad := 0
	var g_full := 24.0
	for i in range(t.size() - 2400, t.size()):
		var f: float = ceilf(g_full * float(t[i]) * float(t[i]) / 16.667 - 0.02) * 16.667
		if f > 17.0:
			bad += 1
	check(bad < 2400 * 0.06, "정착 뒤 느린 프레임 비율 낮음 (%d / 2400)" % bad)


# 적용 노드: 판 중이면 계산기 배율이 창에, 판이 끝나면 화질이 정한 배율로 (창·MSAA)
func test_gfx_node_applies_adaptive_scale() -> void:
	var root: Window = (Engine.get_main_loop() as SceneTree).root
	var keep = [root.msaa_3d, root.scaling_3d_scale, WC.level, WC.msaa_cut, View_settings_gfx(), View.settings.get("lowGfx", false)]
	var g = Gfx.new()
	g.forced = "high"
	g.apply(false, root)
	var base: float = Gfx.plan.scale
	g.ctl = AC.Ctl.new(base, AC.target_ms(60.0))
	g.adapting = true
	g.ctl.scale = 0.7
	g._apply_adapt()
	check(is_equal_approx(root.scaling_3d_scale, 0.7) and is_equal_approx(Gfx.scale_now, 0.7), "판 중: 계산기 배율이 창에 (%.2f)" % root.scaling_3d_scale)
	check(root.msaa_3d == WC.MSAA_3D_PC, "MSAA 그대로")
	g.ctl.cut = true
	g._apply_adapt()
	check(WC.msaa_cut and root.msaa_3d == Viewport.MSAA_2X, "바닥에서도 느리면 MSAA 4× → 2×")
	g.apply(false, root) # 창 크기가 바뀌거나 설정이 바뀌어도 적응 배율 유지
	check(is_equal_approx(root.scaling_3d_scale, 0.7), "apply 가 적응 배율을 덮지 않음")
	g.adapting = false
	g._apply_adapt()
	check(is_equal_approx(root.scaling_3d_scale, base) and not WC.msaa_cut and root.msaa_3d == WC.MSAA_3D_PC, "판이 끝나면 화질 배율·MSAA 로 (%.2f)" % root.scaling_3d_scale)
	check(Gfx.adapt_info == "", "안 돌면 F3 한 줄 없음")
	g.free()
	Gfx.adapting = false
	root.msaa_3d = keep[0]
	root.scaling_3d_scale = keep[1]
	WC.level = keep[2]
	WC.msaa_cut = keep[3]
	View_settings_restore(keep[4])
	View.settings["lowGfx"] = keep[5]


func View_settings_gfx() -> Array:
	return [Gfx.choice, Gfx.plan.duplicate(), Gfx.scale_now]


func View_settings_restore(a: Array) -> void:
	Gfx.choice = a[0]
	Gfx.plan = a[1]
	Gfx.scale_now = a[2]


func test_migrate_adapt_setting() -> void:
	check(View.migrate_adapt({}), "새 설치 (파일 없음/빈 값) 는 켬")
	check(View.migrate_adapt({"gfx": "auto"}) and View.migrate_adapt({"gfx": ""}), "자동 화질이면 켬")
	check(not View.migrate_adapt({"gfx": "high"}) and not View.migrate_adapt({"gfx": "low"}) and not View.migrate_adapt({"gfx": "medium"}), "예전 파일에서 화질을 직접 골랐으면 끔 (존중)")
	check(View.migrate_adapt({"gfx": "high", "adaptRes": true}) and not View.migrate_adapt({"adaptRes": false}), "저장된 값이 먼저")


func test_msaa_cut_steps() -> void:
	WC.msaa_cut = true
	check(WC.msaa_3d(false, false, "high") == Viewport.MSAA_2X and WC.msaa_3d(false, false, "medium") == Viewport.MSAA_DISABLED and WC.msaa_3d(false, false, "low") == Viewport.MSAA_DISABLED, "낮춤: 4×→2×, 2×→끔, 낮음은 이미 끔")
	WC.msaa_cut = false
	check(WC.msaa_3d(false, false, "high") == Viewport.MSAA_4X, "되돌리면 4×")
