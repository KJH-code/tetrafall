# G4 화면이 기억하는 것 (JS localStorage tf-name·tf-color·tf-char·tf-tutorial 자리): user://ui.json
extends RefCounted

const PATH := "user://ui.json"
static var _data = null


static func _load() -> Dictionary:
	if _data == null:
		_data = {}
		if FileAccess.file_exists(PATH):
			var d = JSON.parse_string(FileAccess.get_file_as_string(PATH))
			if d is Dictionary:
				_data = d
	return _data


static func get_value(key: String, fallback = null):
	return _load().get(key, fallback)


static func set_value(key: String, value) -> void:
	_load()[key] = value
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(_data))
