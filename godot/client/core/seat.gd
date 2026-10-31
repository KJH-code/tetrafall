# 재접속 자리 토큰 (client/seat.js): 방 코드마다 저장 → 창을 닫았다 다시 열어도·끊겼다 붙어도 같은 자리 (서버 rejoin)
extends RefCounted

# 브라우저처럼 창(실행)끼리 같은 저장소 → 같은 방이면 같은 자리 (JS 탭 둘과 같음). 시험에서 사람 둘이면 --profile 로 나눔
static var profile := ""


static func _path() -> String:
	return "user://seats%s.json" % ("-" + profile if profile != "" else "")


static func _load() -> Dictionary:
	if not FileAccess.file_exists(_path()):
		return {}
	var d = JSON.parse_string(FileAccess.get_file_as_string(_path()))
	return d if typeof(d) == TYPE_DICTIONARY else {}


static func _save(d: Dictionary) -> void:
	var f := FileAccess.open(_path(), FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(d))


static func token(code: String) -> String:
	return str(_load().get(code.to_upper(), ""))


static func save(code: String, tok: String) -> void:
	if code == "" or tok == "":
		return
	var d := _load()
	d[code.to_upper()] = tok
	_save(d)


static func drop(code: String) -> void:
	var d := _load()
	if d.erase(code.to_upper()):
		_save(d)
