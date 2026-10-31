# 타이틀 화면 확인용 스샷: godot --path godot/client --resolution 1280x720 -s res://tools/title_shot.gd -- <테마> <ms> <저장 png> [menu|exit] [low]
# 그 테마 타이틀 장면을 ms 만큼 (1/60초씩) 돌린 뒤 찍음. menu = 처음부터 메뉴 카메라, exit = ms 전에 눌러 빠져나가기
extends SceneTree

const Scene := preload("res://title/title_scene.gd")

var sc
var args: PackedStringArray
var left := 0.0
var frames := 0


func _initialize() -> void:
	args = OS.get_cmdline_user_args()
	sc = Scene.new()
	root.add_child(sc)
	sc.setup(args[0], {"menu": args.has("menu"), "low": args.has("low")})
	sc.cam.current = true
	left = float(args[1])


func _process(_d: float) -> bool:
	frames += 1
	if frames < 3:
		return false
	if left > 0.0:
		var steps := 0
		while left > 0.0 and steps < 40:
			sc.step(1.0 / 60.0)
			left -= 1000.0 / 60.0
			steps += 1
			if args.has("exit") and left < 1600.0:
				sc.press()
		return false
	if frames < 1000 and not has_meta("wait"):
		set_meta("wait", frames)
	if frames - int(get_meta("wait")) < 3:
		sc.step(1.0 / 60.0)
		return false
	root.get_texture().get_image().save_png(args[2])
	return true
