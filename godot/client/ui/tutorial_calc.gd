# 튜토리얼 화면 계산 (shared/tutorial.js 의 화면 쪽 그대로): 단계 찾기·띠 문구 (자리표 → 키 이름·캐릭터 설명)·진행 칸·끝 화면 문구.
# 판정·지형은 서버. tests/test_tutorial_ui.gd 가 JS 와 비교
extends RefCounted

const C := preload("res://core/config.gd")


static func step_of(id) -> Dictionary:
	for st in C.TUTORIAL_STEPS:
		if st.id == id:
			return st
	return {}


# {키 id} → key_name.call(id), {skillDesc}·{ultDesc} → 고른 캐릭터 설명
static func step_text(text: String, character: String, key_name: Callable) -> String:
	var re := RegEx.create_from_string("\\{(\\w+)\\}")
	var out := ""
	var at := 0
	for m in re.search_all(text):
		out += text.substr(at, m.get_start() - at)
		var k := m.get_string(1)
		if k == "skillDesc":
			out += str(C.SKILL_DESC.get(character, ""))
		elif k == "ultDesc":
			out += str(C.ULT_DESC.get(character, ""))
		else:
			out += str(key_name.call(k))
		at = m.get_end()
	return out + text.substr(at)


# 띠 문구를 조각으로: [{text, key: bool}] — 붙어 있는 키 자리표 ({fwd}{left}{back}{right}) 는 한 덩어리 키 글자 (노랑), 나머지는 그냥 글자
static func step_parts(text: String, character: String, key_name: Callable, key_group: Callable) -> Array:
	var re := RegEx.create_from_string("((?:\\{\\w+\\})+)")
	var one := RegEx.create_from_string("\\{(\\w+)\\}")
	var out := []
	var at := 0
	for m in re.search_all(text):
		if m.get_start() > at:
			out.append({"text": text.substr(at, m.get_start() - at), "key": false})
		var ids := []
		for x in one.search_all(m.get_string(1)):
			ids.append(x.get_string(1))
		if not ids.has("skillDesc") and not ids.has("ultDesc"):
			out.append({"text": str(key_group.call(ids)), "key": true})
		else:
			out.append({"text": step_text(m.get_string(1), character, key_name), "key": false})
		at = m.get_end()
	if at < text.length():
		out.append({"text": text.substr(at), "key": false})
	return out


static func progress_label(i: int, n: int = C.TUTORIAL_STEPS.size()) -> String:
	return "%d / %d" % [mini(i + 1, n), n]


# 끝 화면 문구: 다 해냄 / 일부 넘김 / 다 넘김
static func done_message(results) -> Dictionary:
	var list: Array = results if results is Array else []
	var ok := list.count("ok")
	var n := list.size()
	var T: Dictionary = C.TUTORIAL_DONE_TEXT
	var kind := "all" if n > 0 and ok == n else ("some" if ok > 0 else "none")
	var pick: Dictionary = T[kind]
	return {"title": pick.title, "text": str(pick.text).replace("{ok}", str(ok)), "kind": kind}
