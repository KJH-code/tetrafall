# W46 모션 개선 4차: 걸음 (박자 배율·보폭 k 를 접지 발 미끄러짐 중앙값 비로 다시 고름, 옆걸음 골반 yaw) — core/gait_qa.gd 합성 이동으로 잼 (tools/gait_qa.gd 와 같은 측정)
extends RefCounted

const Body := preload("res://chars/body.gd")
const G := preload("res://core/gait_qa.gd")
const C := preload("res://core/config.gd")
const Motion_ := preload("res://chars/ext_motion.gd")
const K := preload("res://chars/chars_config.gd")

var errors: Array = []
const CHARS := ["ninja", "tank", "hunter", "hook"]
# 앞으로 걷기·달리기 접지 비 상한 (W46 값 0.09~0.21 (닌자 걷기 0.59) + 여유 — W45 이전 박자 ×1.6 보폭 ×1.4 는 1.4~2.6)
const FWD_MAX := {"ninja": {"walk": 0.75, "run": 0.30}, "tank": {"walk": 0.35, "run": 0.25}, "hunter": {"walk": 0.25, "run": 0.25}, "hook": {"walk": 0.25, "run": 0.20}}
const SIDE_RUN_MAX := 0.6 # 옆으로 달리기 (W46 전 0.73~0.8)


func check(cond: bool, msg: String) -> void:
	if not cond:
		errors.append(msg)


func _rig(ch: String) -> Array:
	var was: bool = Body.use_ext
	Body.use_ext = true
	var b = Body.new()
	b.build(ch, Color(0.2, 0.5, 1.0), true)
	Body.use_ext = was
	return [b, G.rig(b, ch)]


func test_gait_slip_and_pops() -> void:
	for ch in CHARS:
		var pr := _rig(ch)
		var rg: Dictionary = pr[1]
		Motion_.clock = func(): return G.vt[0]
		var stand: Dictionary = G.measure(rg, 0.0, 0.0, 0.0)
		check(int(stand.n_st) == 0 and int(stand.still) == 0, "%s 서 있을 땐 접지 구간·끌림 0 (오탐 없음): %s" % [ch, stand])
		for nm in ["walk", "run"]:
			var spd: float = C.MOVE_SPEED * (0.45 if nm == "walk" else 1.0)
			var f: Dictionary = G.measure(rg, spd, spd, 0.0)
			var bk: Dictionary = G.measure(rg, spd, -spd, 0.0)
			check(int(f.n_st) >= 3, "%s %s 앞 접지 구간 %d >= 3" % [ch, nm, f.n_st])
			check(float(f.mean) <= float(FWD_MAX[ch][nm]), "%s %s 앞 발 미끄러짐 비 %.2f <= %.2f" % [ch, nm, f.mean, FWD_MAX[ch][nm]])
			check(float(bk.mean) <= float(FWD_MAX[ch][nm]), "%s %s 뒤 발 미끄러짐 비 %.2f <= %.2f" % [ch, nm, bk.mean, FWD_MAX[ch][nm]])
			if nm == "run":
				check(int(f.leg_pops) <= 2, "%s 달리기 다리 팝 %d <= 2 (W45 이전 20~60)" % [ch, f.leg_pops])
				check(float(f.worst) < 35.0, "%s 달리기 다리 최악 각속도 %.1f° < 35° (W45 이전 56~69)" % [ch, f.worst])
				var sd: Dictionary = G.measure(rg, spd, 0.0, spd)
				check(float(sd.mean) <= SIDE_RUN_MAX, "%s 옆 달리기 발 미끄러짐 비 %.2f <= %.2f" % [ch, sd.mean, SIDE_RUN_MAX])
		Motion_.clock = Callable()
		(pr[0] as Node).free()


func test_dir_counter_sums_to_one() -> void:
	var s := 0.0
	for e in K.EXT_DIR_COUNTER:
		s += float(e[1])
	check(absf(s - 1.0) < 1e-6, "골반 yaw 되돌림 몫 합 1 (%.3f)" % s)
	check(K.EXT_DIR_MAX_DEG >= 60.0 and K.EXT_DIR_GAIN >= 0.9, "옆걸음 골반 yaw 넉넉히")
