# 웹 내보내기만: 곡 녹음본을 pck 에서 빼고 (첫 받기 ~4MB 줄임) 내보내는 폴더의 music/ 에 원본 ogg 를 복사. PC 판은 그대로
# W53: 효과음 녹음본 (audio/baked/*.wav, 타이틀·앰비언트 핑 제외 — 그건 첫 화면에 바로 필요) 도 첫 pck 에서 빼고 내보내는 폴더의 sfx.pck 한 덩어리 (PCKPacker) 로.
# 화면 (audio/sfx_pack.gd) 이 첫 화면 뒤 받아 ProjectSettings.load_resource_pack 으로 붙임 (웹 첫 받기 br ~1.5MB 줄임). PC·옛 웹 빌드는 pck 안 그대로
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


# W53: 첫 pck 에서 빼 sfx.pck 로 보낼 효과음 (wav 만 — 타이틀·앰비언트 핑은 첫 화면부터 쓰니 그대로)
static func is_lazy_sfx(path: String) -> bool:
	if not (path.begins_with(SRC) and path.ends_with(".wav")):
		return false
	var f := path.get_file()
	return not (f.begins_with("title.") or f.begins_with("ambientPing."))


func _export_file(path: String, _type: String, _features: PackedStringArray) -> void:
	if _web and (is_song(path) or is_lazy_sfx(path)):
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
	_pack_sfx()


# W53: 뺀 효과음 wav 를 한 묶음으로 — 안에는 내보낸 pck 와 같은 모양 (가져온 .sample + 옛 파일 이름 자리의 .import 가 가져온 경로를 가리킴)
func _pack_sfx() -> void:
	var pck := PCKPacker.new()
	var dest := _out.get_base_dir().path_join("sfx.pck")
	if pck.pck_start(dest) != OK:
		push_error("웹 효과음 묶음 시작 실패: %s" % dest)
		return
	var n := 0
	for f in DirAccess.get_files_at(SRC):
		if not is_lazy_sfx(SRC + f):
			continue
		var cfg := ConfigFile.new()
		if cfg.load(SRC + f + ".import") != OK:
			push_error("가져오기 파일 없음: %s" % f)
			continue
		var imported := str(cfg.get_value("remap", "path", ""))
		if imported == "" or not FileAccess.file_exists(imported):
			push_error("가져온 파일 없음: %s" % f)
			continue
		pck.add_file(imported, ProjectSettings.globalize_path(imported))
		pck.add_file(SRC + f + ".import", ProjectSettings.globalize_path(SRC + f + ".import"))
		n += 1
	pck.flush()
	print("웹 효과음 묶음: wav %d개 → %s" % [n, dest])
