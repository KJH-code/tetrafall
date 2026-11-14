# W54 사거리·타이밍 맞추기: 서버 규칙 (BASIC_ATTACKS) 은 그대로, 보이는 쪽 (타격 앞당김 W54_LEAD_BY · 앞딛기 W54_LUNGE) 만. 끄기 --old-moves
extends RefCounted

const K := preload("res://chars/chars_config.gd")
const C := preload("res://core/config.gd")
const Clips := preload("res://chars/ext_clips.gd")
const Chars := preload("res://chars/chars.gd")
const Opts := preload("res://core/opts.gd")

var errors: Array = []


func check(cond: bool, msg: String) -> void:
	if not cond:
		errors.append(msg)


func _reset() -> void:
	Opts.override = null
	K.w54_frac_force = -1.0


# 서버 규칙을 이 작업이 안 바꿨다는 고정: 4명 평타의 준비·후딜·사거리·step (v0.1.21 값). 바꾸면 이 표를 일부러 고쳐야 함
const SERVER := {
	"tank": [[120, 300, 1.8, 0.4], [150, 350, 1.8, 0.8], [300, 500, 1.8, 0.3], [150, 400, 1.8, 0.0]],
	"ninja": [[60, 150, 1.8, 0.3], [60, 150, 1.8, 0.3], [70, 170, 1.8, 0.3], [120, 350, 1.8, 0.2], [60, 150, 1.8, 0.0], [100, 450, 1.8, 0.0]],
	"hunter": [[100, 250, 1.8, 0.3], [100, 250, 1.8, 0.3], [200, 450, 1.8, 0.4], [150, 400, 1.8, 0.0]],
	"hook": [[150, 300, 1.8, 0.0], [150, 300, 1.8, 0.4], [200, 450, 1.8, 0.3], [150, 400, 1.8, 0.0]],
}


func test_server_rules_untouched() -> void:
	for ch in SERVER:
		var set: Dictionary = C.BASIC_ATTACKS[ch]
		var defs: Array = (set.chain as Array) + (set.air as Array)
		check(defs.size() == (SERVER[ch] as Array).size(), "%s 평타 수" % ch)
		for i in mini(defs.size(), (SERVER[ch] as Array).size()):
			var d: Dictionary = defs[i]
			var e: Array = SERVER[ch][i]
			check(float(d.windup) == float(e[0]) and float(d.rec) == float(e[1]), "%s %s 준비·후딜" % [ch, d.name])
			check(float(d.get("range", C.PUSH_RANGE)) == float(e[2]) and float(d.get("step", 0.0)) == float(e[3]), "%s %s 사거리·step" % [ch, d.name])
	check(C.PUSH_RANGE == 1.8 and C.PLAYER_HALF == 0.3, "PUSH_RANGE·PLAYER_HALF")
	var tang: Dictionary = (C.BASIC_ATTACKS.hook.chain[2] as Dictionary).loaded
	check(float(tang.range) == 2.0 and float(tang.windup) == 200.0, "갈고리 탕")


func _windup_of(ch: String, mv: String) -> float:
	var set: Dictionary = C.BASIC_ATTACKS[ch]
	for d in (set.chain as Array) + (set.air as Array):
		if str(d.name) == mv:
			return float(d.windup) / 1000.0
		if d.has("loaded") and str(d.loaded.name) == mv:
			return float(d.loaded.windup) / 1000.0
	return -1.0


func test_tables_valid_and_speed_cap() -> void:
	_reset()
	var old_speed := (0.40 - 0.30) / C.FIGURE_STRIKE_S # 예전 타격 구간 클립 배속
	for ch in K.W54_LEAD_BY:
		for mv in K.W54_LEAD_BY[ch]:
			var ws := _windup_of(ch, str(mv))
			check(ws > 0.0, "앞당김 표 동작이 서버 평타에 있음: %s %s" % [ch, mv])
			var f: float = K.W54_LEAD_BY[ch][mv]
			check(f >= 0.0 and f <= 1.0, "frac 0~1: %s %s" % [ch, mv])
			var ld := Clips.lead_s(ws, f)
			check(ld > 0.0 and ld <= K.W54_LEAD_S + 1e-9 and ld <= ws * K.W54_LEAD_MAX_FRAC + 1e-9, "앞당김 길이 한계: %s %s" % [ch, mv])
			if ld > 0.0:
				var r1 := f * 0.10 / ld
				var r2 := (1.0 - f) * 0.10 / C.FIGURE_STRIKE_S
				check(r1 <= old_speed * 1.01 and r2 <= old_speed * 1.01, "휘두름 배속이 예전 (%.2f) 이하: %s %s (%.2f·%.2f)" % [old_speed, ch, mv, r1, r2])
	for ch in K.W54_LUNGE:
		for mv in K.W54_LUNGE[ch]:
			check(_windup_of(ch, str(mv)) > 0.0, "앞딛기 표 동작이 서버 평타에 있음: %s %s" % [ch, mv])
			check(float(K.W54_LUNGE[ch][mv]) > 0.0 and float(K.W54_LUNGE[ch][mv]) <= K.W54_LUNGE_MAX, "앞딛기 ≤ 한계: %s %s" % [ch, mv])
	check(K.W54_LUNGE_MAX <= 0.2 + 1e-9, "앞딛기 한계 0.2m 이하")
	check(K.lead_frac("tank", "없는 동작") < 0.0, "표에 없으면 앞당김 없음")


func _sel(phase: String, u: float, ws: float, lf: float) -> Dictionary:
	var cc := {"moves": {"m": "clip_m"}}
	return Clips.select(cc, {"act": {"id": 1, "move": "m", "phase": phase, "u": u, "air": false, "ws": ws, "lf": lf}}, 0.0)


func test_select_lead_continuity() -> void:
	_reset()
	var ws := 0.15
	var lf := 0.8
	var m0 := 0.30
	var m1 := 0.40
	var tl := m0 + (m1 - m0) * lf
	check(absf(float(_sel("wind", 0.0, ws, lf).t)) < 1e-9, "준비 시작 = 클립 0")
	check(absf(float(_sel("wind", 1.0, ws, lf).t) - tl) < 1e-6, "판정 순간 = 휘두름 %d%% 지점" % int(lf * 100.0))
	check(absf(float(_sel("strike", 0.0, ws, lf).t) - tl) < 1e-6, "타격 시작이 준비 끝과 이어짐 (끊김 없음)")
	check(absf(float(_sel("strike", 1.0, ws, lf).t) - m1) < 1e-6, "타격 끝 = 휘두름 끝")
	var ld := Clips.lead_s(ws, lf)
	check(absf(float(_sel("wind", 1.0 - ld / ws, ws, lf).t) - m0) < 1e-6, "앞당김이 시작되는 순간 = 준비 끝 자세 (눈금 0)")
	var prev := -1.0
	for i in 21:
		var t: float = _sel("wind", float(i) / 20.0, ws, lf).t
		check(t >= prev - 1e-9, "준비 중 클립 시각이 줄지 않음")
		prev = t
	# 회복은 그대로
	check(absf(float(_sel("rec", 0.0, ws, lf).t) - m1) < 1e-6, "회복 시작 = 휘두름 끝")


func test_old_moves_switch() -> void:
	_reset()
	check(not K.old_moves(), "기본 켬 (새)")
	check(absf(float(_sel("wind", 1.0, 0.15, 0.8).t) - 0.38) < 1e-6, "새: 준비 끝 0.38")
	Opts.override = ["--old-moves"]
	check(K.old_moves(), "--old-moves 로 끔")
	check(absf(float(_sel("wind", 1.0, 0.15, 0.8).t) - 0.30) < 1e-6, "끔: 준비 끝 = 예전 눈금 0.30")
	check(absf(float(_sel("strike", 0.0, 0.15, 0.8).t) - 0.30) < 1e-6 and absf(float(_sel("strike", 1.0, 0.15, 0.8).t) - 0.40) < 1e-6, "끔: 타격 구간 예전 그대로")
	_reset()
	# 표에 없는 동작 (lf -1) 과 준비 시간 모름 (ws 0) 은 예전 그대로
	check(absf(float(_sel("wind", 1.0, 0.15, -1.0).t) - 0.30) < 1e-6, "표에 없는 동작 = 예전")
	check(absf(float(_sel("wind", 0.5, 0.0, 0.8).t) - 0.15) < 1e-6, "준비 시간 모름 = 예전")


# 실제 몸: 앞딛기가 판정 순간에 켜지고 --old-moves 면 0, 서버 위치 (몸 중심 frame) 는 그대로
func test_lunge_on_real_body() -> void:
	_reset()
	var Body = load("res://chars/body.gd")
	var was: bool = Body.use_ext
	Body.use_ext = true
	var root: Window = (Engine.get_main_loop() as SceneTree).root
	var b = Chars.make_body("ninja", Color.RED)
	root.add_child(b)
	var st := {"air": false, "walking": false, "hs": 0.0, "walk": 0.0, "vz": 0.0, "t": 1.0, "stunned": false, "dancing": false, "emote": -1, "emoteT": 0.0, "victory": -1.0, "punch": 0.0,
		"holding": false, "hit": null, "act": null, "accF": 0.0, "accS": 0.0, "tumble": 0.0, "recover": 0.0, "land": 0.0, "flip": -1.0, "rag": false, "sniffAt": null, "idle": 0.0,
		"airDash": 0.0, "bump": null, "whirl": -1.0, "dizzy": 0.0, "glide": false, "amp": false, "form": "", "loaded": false, "ammo": 3.0}
	if b.ext == null:
		root.remove_child(b)
		b.free()
		Body.use_ext = was
		return
	var base: Vector3 = b.ext.base_origin
	st.act = {"id": 1, "move": "찌르기", "phase": "strike", "u": 0.5, "air": false, "ws": 0.06, "lf": -1.0}
	b._figure_anim(st, 0.05)
	b.ext.sync(st)
	check(absf(b.ext.transform.origin.x - (base.x + 0.2)) < 1e-4, "타격 중 앞딛기 +0.2 (실제 %.3f)" % (b.ext.transform.origin.x - base.x))
	check(absf(b.ext.transform.origin.y - base.y) < 1e-5 and absf(b.ext.transform.origin.z - base.z) < 1e-5, "앞으로만 밀림")
	Opts.override = ["--old-moves"]
	b.ext.sync(st)
	check(absf(b.ext.transform.origin.x - base.x) < 1e-5, "--old-moves 면 0")
	_reset()
	st.act = null
	b.ext.sync(st)
	check(absf(b.ext.transform.origin.x - base.x) < 1e-5, "공격이 끝나면 제자리")
	st.act = {"id": 2, "move": "찌르기", "phase": "rec", "u": 1.0, "air": false, "ws": 0.06, "lf": -1.0}
	b.ext.sync(st)
	check(absf(b.ext.transform.origin.x - base.x) < 1e-5, "회복 끝 = 제자리")
	root.remove_child(b)
	b.free()
	Body.use_ext = was
