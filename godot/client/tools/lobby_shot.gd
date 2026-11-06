# 대기실 큰 캐릭터 + 초상 (얼굴 256·온몸 128) 캡처 (W27): 캐릭터마다 stage_<id>.png, face_<id>.png, full_<id>.png (대기실이 처음 그리는 순간 ≈ 90 프레임 뒤)
# xvfb-run -a -s "-screen 0 1280x720x24" godot --path godot/client --rendering-driver opengl3 --resolution 1280x720 -s res://tools/lobby_shot.gd -- <폴더> [캐릭터,캐릭터…]
extends SceneTree

var out := ""
var ids: Array = []
var stage = null
var por = null
var step := 0
var frames := 0
var cur := 0
var color := Color(0.85, 0.2, 0.2)


func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	out = a[0] if a.size() > 0 else "user://lobby_shot"
	ids = (a[1].split(",") if a.size() > 1 else ["tank", "ninja", "hunter", "hook", "bard", "berserker", "cannon", "builder"])
	DirAccess.make_dir_recursive_absolute(out)
	RenderingServer.set_default_clear_color(Color(0.1, 0.1, 0.14))
	por = load("res://ui/portrait.gd").new()
	root.add_child(por)
	stage = load("res://ui/char_stage.gd").new()
	stage.size = Vector2(360, 520)
	root.add_child(stage)


func _process(_d: float) -> bool:
	frames += 1
	if cur >= ids.size():
		return true
	var id: String = ids[cur]
	var P = load("res://ui/portrait.gd")
	if step == 0:
		stage.show_char(id, color)
		step = 1
		frames = 0
	elif step == 1 and frames > 90:
		stage.vp.get_texture().get_image().save_png("%s/stage_%s.png" % [out, id])
		step = 2
		frames = 0
	elif step == 2:
		var f = P.tex(id, color, 256, false)
		var g = P.tex(id, color, 128, true)
		if f != null and g != null:
			f.get_image().save_png("%s/face_%s.png" % [out, id])
			g.get_image().save_png("%s/full_%s.png" % [out, id])
			cur += 1
			step = 0
		elif frames > 600:
			push_error("portrait timeout " + id)
			cur += 1
			step = 0
	return false
