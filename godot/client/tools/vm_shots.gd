# 1인칭 팔 화면 찍기 (W11): 탱크 몸 하나로 평타 1타 → 4타 → 1타를 실제 준비·타격·회복 시간 (60fps 걸음) 으로 이어 치며 정한 순간마다 화면 저장.
# 판 없이 1인칭 팔 (chars/viewmodel.gd) 만 하늘·땅 배경 위에 (판에서 --act-freeze 는 느린 화면에서 순간이 밀려서).
# xvfb-run -a -s "-screen 0 1280x720x24" godot --path godot/client --resolution 1280x720 -s res://tools/vm_shots.gd -- <폴더> [old] [캐릭터]
# old: 예전 (방패가 허리에 붙은 채 = JS) — Viewmodel.shield_hand 끔
extends SceneTree

const C := preload("res://core/config.gd")

# [동작 번호 (이어 치는 차례), 단계, u, 이름]
const SHOTS := [
	[2, "wind", 0.17, "3_0_reach"], [2, "wind", 0.33, "3_1_lift"], [2, "wind", 0.6, "3_2_wind"], [2, "strike", 0.6, "3_3_strike"], [2, "rec", 0.5, "3_4_rec"],
	[3, "wind", 0.6, "4_2_wind"], [3, "strike", 0.6, "4_3_strike"], [3, "rec", 0.5, "4_4_rec"],
	[4, "wind", 0.5, "1_after_put"], [4, "rec", 0.5, "1_after_free"],
]

var out := ""
var b = null
var vm = null
var frames: Array = [] # [동작 번호, 이름, 단계, u, 공중]
var fi := 0
var t := 1.0
var wait := -1
var shot_name := ""


func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	out = a[0] if a.size() > 0 else "user://vm_shots"
	var ch: String = a[2] if a.size() > 2 else "tank"
	var VM = load("res://chars/viewmodel.gd")
	VM.shield_hand = not (a.size() > 1 and a[1] == "old")
	DirAccess.make_dir_recursive_absolute(out)
	RenderingServer.set_default_clear_color(Color(0.45, 0.7, 0.95))
	var cam := Camera3D.new()
	cam.position = Vector3(0, 1.6, 0)
	root.add_child(cam)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(200, 200)
	ground.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.4, 0.75, 0.25)
	ground.material_override = gm
	root.add_child(ground)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-1.0, 0.4, 0)
	root.add_child(sun)
	var Chars = load("res://chars/chars.gd")
	b = Chars.make_body(ch, Color(0.85, 0.2, 0.2))
	vm = VM.new()
	root.add_child(vm)
	var sets: Dictionary = C.BASIC_ATTACKS[ch]
	var all: Array = sets.chain + sets.air + sets.chain
	var dt := 1.0 / 60.0
	for mi in all.size():
		for ph in [["wind", ceili(all[mi].windup / 1000.0 / dt)], ["strike", ceili(C.FIGURE_STRIKE_S / dt)], ["rec", ceili(all[mi].rec / 1000.0 / dt)]]:
			for i in ph[1]:
				frames.append([mi, all[mi].name, ph[0], (i + 1.0) / ph[1], mi >= sets.chain.size() and mi < sets.chain.size() + sets.air.size()])


func _process(_delta: float) -> bool:
	if wait > 0:
		wait -= 1
		return false
	if wait == 0:
		root.get_viewport().get_texture().get_image().save_png("%s/%s.png" % [out, shot_name])
		print("찍음 ", shot_name)
		wait = -1
	if fi >= frames.size():
		return true
	var f: Array = frames[fi]
	fi += 1
	var dt := 1.0 / 60.0
	t += dt
	var st := {"air": f[4], "walking": false, "hs": 0.0, "walk": 0.0, "vz": 0.0, "t": t, "stunned": false, "dancing": false, "emote": -1, "emoteT": 0.0, "victory": -1.0, "punch": 0.0, "holding": false, "hit": null,
		"act": {"id": f[0] + 1, "move": f[1], "phase": f[2], "u": f[3], "air": f[4]}, "accF": 0.0, "accS": 0.0, "tumble": 0.0, "recover": 0.0, "land": 0.0, "flip": -1.0, "rag": false, "sniffAt": null, "idle": 0.0, "airDash": 0.0, "bump": null, "whirl": -1.0, "dizzy": 0.0, "glide": false, "amp": false, "form": "", "loaded": false, "ammo": 3.0}
	b._figure_anim(st, dt)
	b._apply(dt)
	b.cur_act = st.act
	vm.update(b, true, dt)
	for s in SHOTS:
		if int(s[0]) == int(f[0]) and str(s[1]) == str(f[2]) and absf(float(s[2]) - float(f[3])) < 0.5 / _count(f[0], f[2]):
			shot_name = s[3]
			wait = 2 # 그린 뒤 저장
	return false


func _count(mi: int, ph: String) -> int:
	var n := 0
	for f in frames:
		if f[0] == mi and f[2] == ph:
			n += 1
	return n
