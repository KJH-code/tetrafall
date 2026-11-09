# W40 1인칭 팔이 3인칭 클립 곡선을 받는 모습 전후: 평타·스킬 동작의 준비·타격·회복 순간을 1인칭 팔로 그려 한 장에 이어 붙임 (VM clip_arm 0 = 전, 기본 = 후).
# 3인칭 몸이 게임처럼 _figure_anim → _apply → _sync_bones → ext.sync (클립 층) 를 한 뒤 viewmodel.update.
# xvfb-run -a -s "-screen 0 1280x720x24" godot --path godot/client --resolution 1280x720 -s res://tools/vm_clip_shot.gd -- <out.png> <캐릭터> <동작,동작,…> [--off]
extends SceneTree

const C := preload("res://core/config.gd")
const PH := [["wind", 0.7], ["strike", 0.5], ["strike", 1.0], ["rec", 0.4]]

var out := ""
var b = null
var vm = null
var moves: Array = []
var mi := 0
var pi := 0
var step := 0
var tiles: Array = []
var air := false
var t := 1.0


func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	out = a[0]
	var ch: String = a[1]
	moves = str(a[2]).split(",")
	var VM = load("res://chars/viewmodel.gd")
	if a.has("--off"):
		VM.clip_arm = 0.0
	if a.has("--k"):
		VM.clip_arm = float(a[a.find("--k") + 1])
	load("res://chars/body.gd").use_ext = true
	RenderingServer.set_default_clear_color(Color(0.45, 0.7, 0.95))
	var cam := Camera3D.new()
	cam.position = Vector3(0, 1.6, 0)
	root.add_child(cam)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-1.0, 0.4, 0)
	root.add_child(sun)
	b = load("res://chars/chars.gd").make_body(ch, Color(0.85, 0.2, 0.2))
	vm = VM.new()
	root.add_child(vm)


func _state(move: String, ph: String, u: float) -> Dictionary:
	var m: Dictionary = load("res://chars/moves.gd").MOVES.get(move, {})
	var fl: bool = bool(m.get("float", false))
	return {"air": fl, "walking": false, "hs": 0.0, "walk": 0.0, "vz": 0.0, "t": t, "stunned": false, "dancing": false, "emote": -1, "emoteT": 0.0, "victory": -1.0, "punch": 0.0,
		"holding": false, "hit": null, "act": {"id": 1, "move": move, "phase": ph, "u": u, "air": fl}, "accF": 0.0, "accS": 0.0, "tumble": 0.0, "recover": 0.0, "land": 0.0, "flip": -1.0, "rag": false,
		"sniffAt": null, "idle": 0.0, "airDash": 0.0, "bump": null, "whirl": -1.0, "dizzy": 0.0, "glide": false, "amp": false, "form": "", "loaded": false, "ammo": 3.0}


var wait := 0


func _process(_d: float) -> bool:
	if wait > 0:
		wait -= 1
		if wait == 0:
			tiles.append(root.get_viewport().get_texture().get_image())
			pi += 1
			step = 0
		return false
	if mi >= moves.size():
		_save()
		return true
	if pi >= PH.size():
		pi = 0
		mi += 1
		return false
	t += 1.0 / 60.0
	var st := _state(moves[mi], PH[pi][0], PH[pi][1])
	b._figure_anim(st, 1.0 / 60.0)
	b._apply(1.0 / 60.0)
	b._sync_bones()
	b.cur_act = st.act
	if b.ext != null:
		b.ext.cloth_t = Time.get_ticks_msec() * 0.001 - 1.0 / 60.0
		b.ext.sync(st)
	vm.update(b, true, 1.0 / 60.0)
	step += 1
	if step >= 6: # 같은 자세로 몇 프레임 머물러 쌍둥이 (process_priority 100) 가 맞추게 한 뒤 저장
		wait = 3
	return false


func _save() -> void:
	var w: int = tiles[0].get_width() / 2
	var h: int = tiles[0].get_height() / 2
	var sheet := Image.create(w * PH.size(), h * moves.size(), false, Image.FORMAT_RGBA8)
	for i in tiles.size():
		var im: Image = tiles[i]
		im.resize(w, h)
		sheet.blit_rect(im, Rect2i(0, 0, w, h), Vector2i((i % PH.size()) * w, (i / PH.size()) * h))
	sheet.save_png(out)
	print("TF 저장 ", out, " ", moves)
