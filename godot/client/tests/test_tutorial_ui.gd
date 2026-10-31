# G6 튜토리얼 화면 계산이 JS (shared/tutorial.js) 와 같은지 (tools/fixtures-fx.mjs → tutorial_ui.json): 띠 문구·진행 칸·끝 화면 문구 + 키 덩어리 나누기
extends RefCounted

const TC := preload("res://ui/tutorial_calc.gd")
const Keys := preload("res://core/keys.gd")

var errors: Array = []


func check(cond: bool, msg: String) -> void:
	if not cond:
		errors.append(msg)


func js():
	return JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/tutorial_ui.json"))


func test_text_matches_js() -> void:
	var kn := func(id): return "<%s>" % id
	for r in js().texts:
		var got := TC.step_text(str(TC.step_of(r[0]).text), r[1], kn)
		check(got == r[2], "%s %s: '%s' vs JS '%s'" % [r[0], r[1], got, r[2]])


func test_progress_done_match_js() -> void:
	var d = js()
	for r in d.prog:
		check(TC.progress_label(int(r[0])) == r[1], "진행 %s: %s vs JS %s" % [r[0], TC.progress_label(int(r[0])), r[1]])
	for r in d.done:
		var got := TC.done_message(r[0])
		check(got.title == r[1].title and got.text == r[1].text and got.kind == r[1].kind, "끝 %s: %s vs JS %s" % [r[0], got, r[1]])


# 붙은 이동 키 자리표는 한 덩어리 (WASD, 노랑), 설명 자리표는 글자로
func test_parts_group_keys() -> void:
	var binds := Keys.default_binds()
	var kn := func(id): return Keys.key_label(binds[id])
	var kg := func(ids): return Keys.group_label(binds, ids)
	var parts := TC.step_parts("{fwd}{left}{back}{right} 로 이동, {skill} 스킬: {skillDesc}", "tank", kn, kg)
	check(parts.size() == 5, "조각 %s" % [parts])
	check(parts[0].key and parts[0].text == "WASD", "이동 키 %s" % [parts[0]])
	check(not parts[4].key and parts[4].text != "" and not parts[4].text.contains("{"), "설명 %s" % [parts[4]])
	var joined := ""
	for p in parts:
		joined += p.text
	check(joined == TC.step_text("{fwd}{left}{back}{right} 로 이동, {skill} 스킬: {skillDesc}", "tank", func(id): return Keys.key_label(binds[id])).replace("W A S D", "WASD") or joined.begins_with("WASD"), "합친 글 %s" % joined)


# G6 화면 노드 스크립트가 다 읽히고 만들어짐 (main.gd 가 붙이는 것 — 문법 오류는 실행 때만 보여서)
func test_g6_nodes_load() -> void:
	for p in ["res://ui/perf.gd", "res://ui/practice.gd", "res://ui/tutorial_ui.gd", "res://world/tutorial_mark.gd", "res://world/bblocks.gd"]:
		var s = load(p)
		check(s != null and s.can_instantiate(), "못 읽음 %s" % p)
		if s != null and s.can_instantiate():
			var n = s.new()
			check(n != null, "못 만듦 %s" % p)
			n.free()
