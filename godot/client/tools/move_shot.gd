# 1인칭 팔 이동 중 모습 찍기 (W28): 걷기·달리기·점프·낙하·공중 대시·평타 순간의 1인칭 화면을 캐릭터마다 저장.
# 판 없이 1인칭 팔 (chars/viewmodel.gd) 만 하늘·땅 배경 위에 (tools/vm_shots.gd 와 같은 방식).
# xvfb-run -a -s "-screen 0 1280x720x24" godot --path godot/client --resolution 1280x720 -s res://tools/move_shot.gd -- <폴더> <캐릭터> [--ext]
extends SceneTree

const C := preload("res://core/config.gd")

# [이름, 공중, 걷는 속도 비율 (hs / MOVE_SPEED), 걸음 위상, vz, 공중 대시, 평타 단계 (""=없음), u]
const SHOTS := [
	["idle", false, 0.0, 0.0, 0.0, 0.0, "", 0.0],
	["walk_a", false, 1.0, 0.0, 0.0, 0.0, "", 0.0],
	["walk_b", false, 1.0, 1.57, 0.0, 0.0, "", 0.0],
	["walk_c", false, 1.0, 3.14, 0.0, 0.0, "", 0.0],
	["walk_d", false, 1.0, 4.71, 0.0, 0.0, "", 0.0],
	["jump_up", true, 1.0, 0.0, 7.0, 0.0, "", 0.0],
	["fall", true, 1.0, 0.0, -9.0, 0.0, "", 0.0],
	["dash", true, 1.0, 0.0, 0.0, 1.0, "", 0.0],
	["atk_strike", false, 0.0, 0.0, 0.0, 0.0, "strike", 0.6],
	["atk_walk_strike", false, 1.0, 1.57, 0.0, 0.0, "strike", 0.6],
]

var out := ""
var ch := "ninja"
var b = null
var vm = null
var si := 0
var step := 0
var t := 1.0


func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	out = a[0] if a.size() > 0 else "user://move_shot"
	ch = a[1] if a.size() > 1 else "ninja"
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
	vm = load("res://chars/viewmodel.gd").new()
	root.add_child(vm)


func _process(_delta: float) -> bool:
	if si >= SHOTS.size():
		return true
	var s: Array = SHOTS[si]
	var dt := 1.0 / 60.0
	if step == 0:
		t += dt
		var atk: Dictionary = C.BASIC_ATTACKS[ch].chain[0]
		var act = null
		if str(s[6]) != "":
			act = {"id": 1, "move": atk.name, "phase": s[6], "u": s[7], "air": false}
		var st := {"air": s[1], "walking": float(s[2]) > 0.0 and not s[1], "hs": float(s[2]) * C.MOVE_SPEED, "walk": s[3], "vz": s[4], "t": t, "stunned": false, "dancing": false, "emote": -1, "emoteT": 0.0, "victory": -1.0, "punch": 0.0, "holding": false, "hit": null,
			"act": act, "accF": 0.0, "accS": 0.0, "tumble": 0.0, "recover": 0.0, "land": 0.0, "flip": -1.0, "rag": false, "sniffAt": null, "idle": 0.0, "airDash": s[5], "bump": null, "whirl": -1.0, "dizzy": 0.0, "glide": false, "amp": false, "form": "", "loaded": false, "ammo": 3.0}
		b.hs = float(s[2]) * C.MOVE_SPEED
		b.walk = s[3]
		b.vz = s[4]
		b.t = t
		b._figure_anim(st, dt)
		b._apply(dt)
		b.cur_act = act
		vm.update(b, true, dt)
		step = 1
		return false
	step += 1
	if step >= 4:
		root.get_viewport().get_texture().get_image().save_png("%s/%s_%s.png" % [out, ch, s[0]])
		print("찍음 ", ch, " ", s[0])
		si += 1
		step = 0
	return false
