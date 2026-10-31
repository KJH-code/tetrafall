# 대기실 둘레 무대 확인용 스샷 (title_stage.gd ring): godot --path godot/client --resolution 1280x720 -s res://tools/stage_shot.gd -- <테마> <저장 png> [판 칸 수 14]
# 섬 자리는 빈 상자로, 카메라는 대기실처럼 섬 옆 위에서
extends SceneTree

var st
var cam := Camera3D.new()
var frames := 0
var args: PackedStringArray


func _initialize() -> void:
	args = OS.get_cmdline_user_args()
	var C = load("res://core/config.gd")
	var Co = load("res://core/coords.gd")
	var w := float(args[2]) if args.size() > 2 else 14.0
	var R: float = w * C.LOBBY_DARK.clear + 3
	st = load("res://title/title_stage.gd").new(args[0], {"low": false, "logoW": 0, "logoH": 0, "camDist": R, "ring": true, "clear": R, "floorZ": -float(C.LOBBY_DARK.drop)})
	root.add_child(st)
	var island := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = Vector3(w, 6, w)
	island.mesh = b
	island.position = Vector3(0, -3, 0)
	root.add_child(island)
	cam.environment = st.env
	cam.fov = 60
	root.add_child(cam)
	cam.look_at_from_position(Co.gxyz(0, -R * 1.1, 9), Vector3.ZERO, Vector3.UP)
	cam.current = true


func _process(_d: float) -> bool:
	frames += 1
	st.update(frames / 60.0, 1.0, 360.0)
	if frames < 8:
		return false
	root.get_texture().get_image().save_png(args[1])
	return true
