# W43 클립 이음새 점검: 반복 클립의 처음·끝 자세 차이 (루프 튐) 와, 클립 사이 (콤보 연결·서기→걷기·달리기·착지) 자세 차이를 뼈 회전 각 (도) 로 잰다.
# 값이 크면 (평균 > 12°, 가장 큰 뼈 > 35°) 이어 붙일 때 튀어 보임. godot --headless --path godot/client -s res://tools/clip_pops.gd -- [캐릭터 ,로 이음 기본 4명]
extends SceneTree

const Clips := preload("res://chars/ext_clips.gd")
const Ext := preload("res://chars/external.gd")


func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	var chars: PackedStringArray = (a[0] if a.size() > 0 else "ninja,tank,hunter,hook").split(",")
	for ch in chars:
		var info = Ext.load_char(ch)
		if info == null:
			continue
		var cc: Dictionary = info.cfg.get("clips", {})
		var lib := Clips.load_lib(str(cc.get("file", "")))
		print("== ", ch, " 클립 ", lib.size())
		var rows := []
		# 루프 이음새
		for nm in lib:
			var d: Dictionary = lib[nm]
			var an: Animation = d.anim
			if an.loop_mode != Animation.LOOP_NONE or nm in ["idle", "walk", "run", "fall"]:
				rows.append(["반복 " + str(nm), _diff(d, 0.0, d, d.len)])
		# 이어 붙임: 이름 → 그 클립의 t (초)
		var pairs := [["idle", 0.0, "walk", 0.0], ["idle", 0.0, "run", 0.0], ["walk", 0.0, "run", 0.0], ["run", 0.0, "idle", 0.0], ["walk", 0.0, "idle", 0.0], ["land", 0.3, "idle", 0.0], ["fall", 0.0, "land", 0.0]]
		var mv: Dictionary = cc.get("moves", {})
		var marks: Array = cc.get("marks", [0.3, 0.4, 0.8])
		for m in mv:
			pairs.append(["idle", 0.0, str(mv[m]), 0.0])
			pairs.append([str(mv[m]), float(marks[2]), "idle", 0.0])
		for m in mv: # 공중 동작은 낙하·점프 뒤에 이어짐
			for src in [["fall", 0.0], ["fall", 0.4], ["jump", 0.4]]:
				pairs.append([src[0], float(src[1]), str(mv[m]), 0.0])
			pairs.append([str(mv[m]), float(marks[2]), "fall", 0.0])
		for p in pairs:
			if lib.has(p[0]) and lib.has(p[2]):
				rows.append(["%s@%.2f → %s@%.2f" % [p[0], p[1], p[2], p[3]], _diff(lib[p[0]], float(p[1]), lib[p[2]], float(p[3]))])
		var seen := {}
		for r in rows:
			if seen.has(r[0]):
				continue
			seen[r[0]] = true
			var flag := ""
			if r[1].mean > 12.0 or r[1].max > 35.0:
				flag = "  <- 튐"
			print("  %-34s 평균 %5.1f°  최대 %5.1f° (%s)%s" % [r[0], r[1].mean, r[1].max, r[1].bone, flag])
	quit()


# 두 클립 (a at ta, b at tb) 의 뼈 회전 차이: 공통 뼈마다 각 (도), 평균·최대
func _diff(a: Dictionary, ta: float, b: Dictionary, tb: float) -> Dictionary:
	var sum := 0.0
	var n := 0
	var mx := 0.0
	var mb := ""
	for bn in a.rot:
		if not b.rot.has(bn):
			continue
		var qa: Quaternion = (a.anim as Animation).rotation_track_interpolate(int(a.rot[bn]), clampf(ta, 0.0, float(a.len)))
		var qb: Quaternion = (b.anim as Animation).rotation_track_interpolate(int(b.rot[bn]), clampf(tb, 0.0, float(b.len)))
		var d := rad_to_deg(qa.angle_to(qb))
		sum += d
		n += 1
		if d > mx:
			mx = d
			mb = String(bn).trim_prefix("mixamorig_")
	return {"mean": sum / maxf(1.0, n), "max": mx, "bone": mb}
