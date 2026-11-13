# W46 걸음 QA (렌더·서버 없이 결정적): 4명 × 방향 (앞·뒤·좌·우·대각) × 속도 (걷기·달리기) 로 일정 속도 합성 이동을 몸 동작 층 (Ext.sync) 에 먹이고
#  ① 발 미끄러짐 — 접지 = 두 발 중 낮은 쪽 (발목·발가락 중 낮은 점의 높이) 이 두 발 전체 최저 + NEAR 안인 연속 구간. 접지 동안 발 월드 속도 (몸 이동 더함) 의 중앙값 ÷ 몸 속도 = 비
#     (0 = 딱 붙음, 1 = 몸 따라 스케이트, 2 = 몸의 두 배 속도로 뒤로 끌림). 중앙값이라 접지 앞뒤 가장자리에 스치는 프레임에 안 흔들림. 서 있을 때는 접지이 0 개로 나와야 함 (오탐 확인)
#  ② 다리 튐 — 허벅지·무릎·발 뼈 회전 각속도 (60Hz 표본당 °) 의 최악값과 임계 (35°/60°) 넘은 수 (모션 QA 와 같은 검출기)
# 같은 일을 재연 (motion_qa) 으로 하면 접지이 캐릭터마다 1~8개뿐이라 신뢰할 수 없었음 (W44) — 여기는 방향·속도마다 4초 (접지 8~18개) 를 결정적으로 잼.
# godot --headless --path godot/client -s res://tools/gait_qa.gd -- [캐릭터 ,로 이음 기본 ninja,tank,hunter,hook] [--csv 파일] [--quick (걷기 앞·뒤·왼, 달리기 앞·뒤·왼)]
#   [--sweep (캐릭터마다 걷기·달리기 박자 배율 × 보폭 k 격자: 앞 이동 비·다리 튐 표)] [--rate-walk R --rate-run R --k-walk K --k-run K --c-walk C --c-run C (cfg.clips.stride 덮어쓰기, 확인용)]
extends SceneTree

const C := preload("res://core/config.gd")
const G := preload("res://core/gait_qa.gd")
const Motion_ := preload("res://chars/ext_motion.gd")

const DIRS := {"앞": [1.0, 0.0], "뒤": [-1.0, 0.0], "왼": [0.0, 1.0], "오른": [0.0, -1.0], "앞왼 대각": [0.7071, 0.7071], "뒤오른 대각": [-0.7071, -0.7071]} # [앞, 왼쪽] (mvF·mvS 와 같은 뜻)
var SWEEP_RATES: Array = [0.7, 0.85, 1.0, 1.15, 1.3, 1.6] # --sweep-rates 0.5,0.6 로 덮음
var SWEEP_KS: Array = [0.8, 1.0, 1.2, 1.4]
const SPEEDS := {"walk": 0.45, "run": 1.0}


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var a := OS.get_cmdline_user_args()
	var chars: PackedStringArray = ["ninja", "tank", "hunter", "hook"]
	var csv_path := ""
	var ov := {}
	var quick := false
	var sweep := false
	var cloth_mode := false
	var i := 0
	while i < a.size():
		if a[i] == "--csv" and i + 1 < a.size():
			csv_path = a[i + 1]
			i += 1
		elif a[i] == "--quick":
			quick = true
		elif a[i] == "--cloth": # 천 사슬 끝 떨림 (직선 이동·좌우 지그재그)
			cloth_mode = true
		elif a[i] == "--sweep":
			sweep = true
		elif a[i] == "--sweep-rates":
			SWEEP_RATES = Array(a[i + 1].split(",")).map(func(x): return float(x))
			i += 1
		elif a[i] == "--sweep-ks":
			SWEEP_KS = Array(a[i + 1].split(",")).map(func(x): return float(x))
			i += 1
		elif a[i].begins_with("--rate-") or a[i].begins_with("--k-") or a[i].begins_with("--c-"):
			ov[a[i].substr(2)] = float(a[i + 1])
			i += 1
		elif not a[i].begins_with("--"):
			chars = a[i].split(",")
		i += 1
	var Body = load("res://chars/body.gd")
	Body.use_ext = true
	var vp := SubViewport.new()
	root.add_child(vp)
	var csv := ["char,dir,speed,stances,bad,mean_ratio,max_ratio,still_stances,leg_pops,body_pops,worst_deg,worst_bone"]
	for ch in chars:
		var b = Body.new()
		b.build(ch, Color(0.2, 0.5, 1.0), true)
		vp.add_child(b)
		await process_frame
		var r0: Dictionary = G.rig(b, ch)
		var X = r0.X
		var strd: Dictionary = (X.info.cfg.get("clips", {}) as Dictionary).get("stride", {})
		for nm in ["walk", "run"]:
			if strd.has(nm) and (ov.has("rate-" + nm) or ov.has("k-" + nm) or ov.has("c-" + nm)):
				var arr: Array = (strd[nm] as Array).duplicate()
				arr[0] = ov.get("k-" + nm, arr[0])
				arr[1] = ov.get("c-" + nm, arr[1])
				arr[2] = ov.get("rate-" + nm, arr[2])
				strd[nm] = arr
		Motion_.clock = func(): return G.vt[0]
		if cloth_mode:
			for zig in [false, true]:
				var cj: Dictionary = G.measure_cloth(r0, C.MOVE_SPEED, zig)
				print("TGC %s %s: 천 끝 뼈 %d · 표본간 각속도 변화 평균 %.2f° · 방향 반전 %.0f%% · 최대 각속도 %.1f°" % [ch, "좌우 지그재그" if zig else "직선 이동", cj.bones, cj.jerk, cj.flip * 100.0, cj.peak])
		elif sweep:
			for clip in ["walk", "run"]:
				if not strd.has(clip):
					continue
				var base: Array = (strd[clip] as Array).duplicate()
				var spd: float = C.MOVE_SPEED * (0.45 if clip == "walk" else 1.0)
				for rate in SWEEP_RATES:
					for k in SWEEP_KS:
						strd[clip] = [k, base[1], rate]
						var r: Dictionary = G.measure(r0, spd, spd, 0.0)
						print("TGS %s %s rate %.2f k %.1f: 비 %.2f (접지 %d) · 다리 튐 %d 최악 %.1f°" % [ch, clip, rate, k, r.mean, r.n_st, r.leg_pops, r.worst])
				strd[clip] = base
		else:
			for sp in ["stand"] + SPEEDS.keys():
				for dn in DIRS.keys():
					if sp == "stand" and dn != "앞":
						continue
					if quick and not (dn in ["앞", "뒤", "왼"]):
						continue
					var spd: float = 0.0 if sp == "stand" else C.MOVE_SPEED * float(SPEEDS[sp])
					var d: Array = DIRS[dn]
					var r: Dictionary = G.measure(r0, spd, float(d[0]) * spd, float(d[1]) * spd)
					print("TGQ %s %s %s: 접지 %d (밀림 %d, 비 평균 %.2f 최대 %.2f, 정지 끌림 %d) · 다리 튐 %d 몸 튐 %d · 다리 최악 %.1f° (%s)" % [ch, sp, dn if sp != "서기" else "-", r.n_st, r.bad, r.mean, r.max, r.still, r.leg_pops, r.body_pops, r.worst, r.worst_bone])
					csv.append("%s,%s,%s,%d,%d,%.3f,%.3f,%d,%d,%d,%.1f,%s" % [ch, dn, sp, r.n_st, r.bad, r.mean, r.max, r.still, r.leg_pops, r.body_pops, r.worst, r.worst_bone])
		Motion_.clock = Callable()
		b.queue_free()
	if csv_path != "":
		var fh := FileAccess.open(csv_path, FileAccess.WRITE)
		fh.store_string("\n".join(csv) + "\n")
	quit()
