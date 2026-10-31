# 웹 내보내기만: 곡 녹음본을 pck 에서 빼고 (첫 받기 ~4MB 줄임) 내보내는 폴더의 music/ 에 원본 ogg 를 복사. PC 판은 그대로
@tool
extends EditorExportPlugin

const SRC := "res://audio/baked/"
const DIR := "music"
var _web := false
var _out := ""


func _get_name() -> String:
	return "TetrafallWebMusic"


static func is_song(path: String) -> bool:
	return path.begins_with(SRC + "music.") and path.ends_with(".ogg")


func _export_begin(features: PackedStringArray, _is_debug: bool, path: String, _flags: int) -> void:
	_web = features.has("web")
	_out = (path if path.is_absolute_path() else ProjectSettings.globalize_path("res://").path_join(path)).get_base_dir().path_join(DIR)


func _export_file(path: String, _type: String, _features: PackedStringArray) -> void:
	if _web and is_song(path):
		skip()


func _export_end() -> void:
	if not _web:
		return
	DirAccess.make_dir_recursive_absolute(_out)
	var n := 0
	for f in DirAccess.get_files_at(SRC):
		if is_song(SRC + f):
			DirAccess.copy_absolute(ProjectSettings.globalize_path(SRC + f), _out.path_join(f))
			n += 1
	print("웹 곡 따로: %d개 → %s" % [n, _out])
