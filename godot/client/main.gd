# 시작 씬 (G0). 명령줄 (-- 뒤) 또는 웹 주소로 접속하고, 화면 묶음 씬을 붙임 (godot/PLAN.md 7절):
#   world/world.tscn (G1 판 그리기) 이 있으면 그것, 없으면 core/dev_view.gd (상자 그림)
#   ui/ui.tscn (G4 메뉴·HUD) 이 있으면 그것, 없으면 core/dev_ui.gd (개발용 버튼)
#   audio/audio.tscn (G5 소리) 이 있으면 붙임
# 옵션: --server ws://주소 (기본 ws://127.0.0.1:3000, 웹은 페이지 주소) · --room 코드 (바로 들어감) · --name 이름 · --profile 이름 (자리 토큰 저장 나눔)
#   자동 확인: --auto host|guest [--bots N] [--drop-at 초] [--quit-after-rounds N] [--quit-after 초] [--shot 파일.png --shot-after 초]
extends Node

const C := preload("res://core/config.gd")
const AutoPilot := preload("res://core/autopilot.gd")
const Seat := preload("res://core/seat.gd")

var args := {}


func _ready() -> void:
	args = parse_args(OS.get_cmdline_user_args())
	if OS.has_feature("web"):
		# 웹: 주소 뒤 ?room=코드&server=ws://…&auto=host&bots=3 … 를 명령줄 옵션처럼 (값 없는 건 true)
		var q = JSON.parse_string(str(JavaScriptBridge.eval("JSON.stringify(Object.fromEntries(new URLSearchParams(location.search)))", true)))
		if typeof(q) == TYPE_DICTIONARY:
			for k in q:
				args[k] = q[k] if str(q[k]) != "" else true
	add_child(_scene_or("res://world/world.tscn", "res://core/dev_view.gd"))
	add_child(_scene_or("res://ui/ui.tscn", "res://core/dev_ui.gd"))
	for g6 in ["res://ui/perf.gd", "res://ui/practice.gd", "res://ui/tutorial_ui.gd", "res://world/tutorial_mark.gd"]: # G6: F3 성능 표시·연습 창·튜토리얼 (띠·목표 칸 빛)
		if ResourceLoader.exists(g6):
			add_child(load(g6).new())
	if ResourceLoader.exists("res://audio/audio.tscn"):
		add_child(load("res://audio/audio.tscn").instantiate())
	Seat.profile = str(args.get("profile", ""))
	if args.has("room"):
		Store.pending_code = str(args.room).to_upper()
	if args.has("auto"):
		var ap := AutoPilot.new()
		ap.args = args
		add_child(ap)
	Net.start(Net.default_url(args))


func _scene_or(scene_path: String, fallback_script: String) -> Node:
	if ResourceLoader.exists(scene_path):
		return load(scene_path).instantiate()
	var n: Node = load(fallback_script).new()
	n.name = fallback_script.get_file().get_basename()
	return n


static func parse_args(list: PackedStringArray) -> Dictionary:
	var out := {}
	var i := 0
	while i < list.size():
		var a := list[i]
		if a.begins_with("--"):
			var k := a.substr(2)
			if i + 1 < list.size() and not list[i + 1].begins_with("--"):
				out[k] = list[i + 1]
				i += 1
			else:
				out[k] = true
		i += 1
	return out
