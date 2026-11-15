# 적응형 3D 해상도 계산 (W31 2026-11-08, PC 최적화 2차 — 지속 비용): 판 중 프레임 시간을 보고 GPU 가 병목일 때만 3D 렌더 배율을 서서히 조절.
# 순수 계산 (노드 없음, 테스트 tests/test_adapt.gd). 적용은 world/gfx.gd (Viewport.scaling_3d_scale).
# 규칙: 프레임을 WINDOW 개씩 모아 위쪽 TRIM 을 버린 평균 (히치 한 번에 흔들리지 않게) 으로 판단.
#  - 내릴 때는 빠르게: 목표보다 DOWN 배 넘게 느리고 GPU 쪽 (렌더 GPU 시간이 있으면 그것이 목표 초과, 없으면 프레임 − CPU 일이 많이 남음 = 기다리는 중) 이면
#    다음 창에 곧바로 sqrt(목표/실제) 만큼 (한 번에 DOWN_MIN~DOWN_MAX) 내림. CPU 가 병목이면 배율을 건드리지 않음 (해상도로 안 풀림).
#  - 올릴 때는 천천히: 목표를 맞춘 창이 UP_HOLD 개 연속이고 (올린 뒤 예상 시간도 여유 안) 이면 UP_STEP 만큼. 올렸다가 곧 도로 내렸으면 (프로브 실패)
#    다음 올리기까지 기다림이 두 배씩 (FAILS_MAX 까지) — V-Sync 로 프레임이 목표에 붙어 여유를 알 수 없을 때도 진동이 점점 드물어짐.
#  - 천장 = 화질이 정한 배율 (gfx_calc), 바닥 = min(ADAPT.min, 천장). 바닥에서도 느리면 CUT_WINDOWS 창 뒤 MSAA 한 단계 (cut) — 판이 끝나면 되돌림.
#  - W45 몸 압박 (press 1·2): MSAA 를 낮춘 뒤에도 계속 느리면 (바닥 연속 창 수가 cut_windows + press_windows × 단계) 한 단계씩 — 1 = 먼 몸 외곽선 앞당김·먼 몸 자세 LOD, 2 = 먼 몸 그림자 거리 줄임.
#    순서 = 해상도 → MSAA → 몸 압박 1 → 2. 해상도가 바닥이 아니거나 (내릴 여지) 한 창이라도 목표 안이면 연속이 끊겨 단계가 안 오름. 판이 끝나면 (restart) 전부 되돌림.
extends RefCounted

const WC := preload("res://world/world_config.gd")


# 목표 프레임 시간 (ms): 모니터 주사율 (모르면 60) 을 hz_min~hz_max 로 — 144Hz 모니터여도 60fps 만 맞추면 됨 (해상도를 지나치게 깎지 않게)
static func target_ms(refresh_hz: float, cfg: Dictionary = WC.ADAPT) -> float:
	var hz := refresh_hz if refresh_hz > 0.0 else 60.0
	return 1000.0 / clampf(hz, float(cfg.hz_min), float(cfg.hz_max))


static func trimmed_mean(a: Array, trim: float) -> float:
	return Ctl.trimmed_mean(a, trim)


static func mean(a: Array) -> float:
	return Ctl.mean(a)


static func quant(x: float) -> float:
	return Ctl.quant(x)


class Ctl:
	extends RefCounted
	var cfg: Dictionary
	var target := 16.667
	var ceil_s := 1.0 # 천장 (화질이 정한 배율)
	var floor_s := 0.6
	var scale := 1.0 # 지금 배율
	var cut := false # 바닥에서도 느려서 MSAA 를 한 단계 낮춰야 함
	var press := 0 # W45 몸 압박 단계 (0·1·2): MSAA 낮춤 뒤에도 느릴 때
	var windows := 0 # 지금까지 판단한 창 수 (확인용)
	var changes := 0 # 배율이 바뀐 횟수 (확인용)
	var _f: Array = []
	var _w: Array = []
	var _g: Array = []
	var _good := 0 # 연속으로 올려도 될 만한 창
	var _fails := 0 # 올렸다가 곧 내린 횟수 (기다림 2^fails 배)
	var _since_up := 99
	var _ban := 2.0 # 올리기 실패한 배율 (이 배율 이상은 _ban_left 창 동안 안 올라감)
	var _ban_left := 0
	var _floor_streak := 0
	var _hist: Array = [] # W41: 최근 보통 프레임 (스파이크 제외) — 스파이크 판정 기준 중앙값
	var _settle := 0 # W41: 배율을 바꾼 뒤 이만큼의 창은 판단 안 함 (3D 버퍼를 다시 만든 직후 프레임이 느림)
	var spikes := 0 # 버린 스파이크 프레임 수 (확인용)

	func _init(ceiling: float, target_ms_: float, cfg_: Dictionary = WC.ADAPT, start := -1.0) -> void:
		cfg = cfg_
		target = target_ms_
		set_ceiling(ceiling)
		scale = ceil_s if start < 0.0 else clampf(start, floor_s, ceil_s)

	func set_ceiling(c: float) -> void:
		ceil_s = clampf(c, 0.1, 1.0)
		floor_s = minf(float(cfg.min), ceil_s)
		scale = clampf(scale, floor_s, ceil_s)

	func set_target(t: float) -> void:
		target = t

	# 판이 끝났거나 새로 시작: 모았던 프레임·올리기 기다림을 비우고 MSAA 되돌림 (배율은 그대로 — 다음 판도 이 근처에서 시작)
	func restart() -> void:
		_f = []
		_w = []
		_g = []
		_good = 0
		_floor_streak = 0
		cut = false
		press = 0
		_ban_left = 0
		_hist = []
		_settle = 0

	# 프레임 하나: frame_ms = 프레임 간격, work_ms = CPU 일 (스크립트 + 렌더 CPU, 모르면 −1), gpu_ms = 렌더 GPU 시간 (모르면 0). 창이 차서 판단했고 배율·cut 이 바뀌었으면 참
	func push(frame_ms: float, work_ms := -1.0, gpu_ms := 0.0) -> bool:
		# W41 스파이크 (로딩·첫 사용·히치): 최근 보통 프레임 중앙값의 spike 배 넘고 spike_min ms 넘으면 판단에서 뺌 (히치 하나가 창 20% 를 넘겨 GPU 병목으로 오판하지 않게). 계속 느린 기계는 중앙값이 같이 올라 스파이크가 아님
		if _hist.size() >= 10 and frame_ms > float(cfg.get("spike_min", 25.0)):
			var sorted := _hist.duplicate()
			sorted.sort()
			if frame_ms > float(sorted[sorted.size() / 2]) * float(cfg.get("spike", 3.0)):
				spikes += 1
				return false
		_hist.append(frame_ms)
		if _hist.size() > int(cfg.get("hist", 40)):
			_hist.pop_front()
		_f.append(frame_ms)
		_w.append(work_ms)
		_g.append(gpu_ms)
		if _f.size() < int(cfg.window):
			return false
		var ch := false
		if _settle > 0:
			_settle -= 1 # 바꾼 직후 창은 건너뜀
		else:
			ch = _decide()
			if ch and cfg.get("settle", 0) > 0:
				_settle = int(cfg.settle)
		_f = []
		_w = []
		_g = []
		return ch

	func _decide() -> bool:
		windows += 1
		var f := trimmed_mean(_f, float(cfg.trim))
		var w := -1.0
		if not _w.is_empty() and float(_w[0]) >= 0.0:
			w = mean(_w)
		var g := mean(_g)
		var load := g if g > 0.0 else f
		var over := load > target * float(cfg.down)
		var gpu_bound := g > 0.0 or w < 0.0 or w <= f * float(cfg.cpu_bound)
		var changed := false
		_since_up += 1
		if _ban_left > 0:
			_ban_left -= 1
		if _since_up == int(cfg.probe_windows) + 1 and _fails > 0:
			_fails -= 1 # 올린 자리가 버텼음 → 기다림 줄임
		if over:
			_good = 0
			if gpu_bound:
				if scale > floor_s + 0.001:
					var before := scale
					var raw := scale * sqrt(clampf(target * float(cfg.aim) / load, 0.2, 1.0))
					var step := clampf(scale - raw, float(cfg.down_min), float(cfg.down_max))
					scale = maxf(floor_s, quant(scale - step))
					if _since_up <= int(cfg.probe_windows): # 올렸다가 곧 도로 내림 = 프로브 실패: 그 배율은 한동안 다시 안 올림
						_ban = before - 0.001
						_ban_left = int(cfg.ban_windows) << _fails
						_fails = mini(_fails + 1, int(cfg.fails_max))
					_since_up = 99
					_floor_streak = 0
					changed = true
					changes += 1
				else:
					_floor_streak += 1
					if _floor_streak >= int(cfg.cut_windows) and not cut:
						cut = true
						changed = true
					elif cut and press < int(cfg.get("press_max", 0)) and _floor_streak >= int(cfg.cut_windows) + int(cfg.get("press_windows", 9)) * (press + 1):
						press += 1 # W45: MSAA 도 낮췄는데 계속 느림 → 몸 압박 한 단계 (먼 몸만)
						changed = true
		else:
			_floor_streak = 0
			if scale < ceil_s - 0.001 and load <= target * float(cfg.up_meet):
				var nxt := minf(ceil_s, quant(scale + float(cfg.up_step)))
				if _ban_left > 0 and nxt >= _ban:
					_good = 0
					return changed
				var pred := load * pow(nxt / scale, 2.0)
				var ok := true
				if g > 0.0 or load <= target * float(cfg.headroom):
					ok = pred <= target * float(cfg.up_pred) # 여유를 아는 경우: 올린 뒤 예상이 목표 안
				if ok:
					_good += 1
				else:
					_good = 0
				if _good >= int(cfg.up_hold) * (1 << _fails):
					scale = nxt
					_good = 0
					_since_up = 0
					changed = true
					changes += 1
			else:
				_good = 0
		return changed

	# 큰 쪽 trim 비율을 버린 평균 (히치 제외)
	static func trimmed_mean(a: Array, trim: float) -> float:
		if a.is_empty():
			return 0.0
		var s := a.duplicate()
		s.sort()
		var n := maxi(1, s.size() - int(floor(s.size() * trim)))
		var t := 0.0
		for i in n:
			t += float(s[i])
		return t / n

	static func mean(a: Array) -> float:
		if a.is_empty():
			return 0.0
		var t := 0.0
		for x in a:
			t += float(x)
		return t / a.size()

	static func quant(x: float) -> float:
		return roundf(x * 100.0) / 100.0
