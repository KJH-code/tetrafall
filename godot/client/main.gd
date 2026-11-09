# 시작 씬 (G0). 명령줄 (-- 뒤) 또는 웹 주소로 접속하고, 화면 묶음 씬을 붙임 (godot/PLAN.md 7절):
#   world/world.tscn (G1 판 그리기) 이 있으면 그것, 없으면 core/dev_view.gd (상자 그림)
#   ui/ui.tscn (G4 메뉴·HUD) 이 있으면 그것, 없으면 core/dev_ui.gd (개발용 버튼)
#   audio/audio.tscn (G5 소리) 이 있으면 붙임
# 옵션: --server ws://주소 (기본 ws://127.0.0.1:3000, 웹은 페이지 주소) · --room 코드 (바로 들어감) · --name 이름 · --profile 이름 (자리 토큰 저장 나눔)
#   성능 재연 (W12): --rec <파일> (판을 녹화) · --replay <파일> (서버 없이 같은 판을 다시 돌려 잼, core/replay.gd)
#   자동 확인: --auto host|guest [--bots N] [--drop-at 초] [--quit-after-rounds N] [--quit-after 초] [--shot 파일.png --shot-after 초]
extends Node
const Opts := preload("res://core/opts.gd")

const C := preload("res://core/config.gd")
const AutoPilot := preload("res://core/autopilot.gd")
const Seat := preload("res://core/seat.gd")

var args := {}


func _boot(what: String) -> void: # W41 --boot-log: 켜는 동안 단계별 ms (엔진 시작부터)
	if args.has("boot-log"):
		print("[켜기] %6.0fms  %s" % [Time.get_ticks_msec(), what])


func _ready() -> void:
	args = parse_args(Opts.args())
	_boot("main _ready 시작")
	if Opts.web():
		# 웹: 주소 뒤 ?room=코드&server=ws://…&auto=host&bots=3 … 를 명령줄 옵션처럼 (값 없는 건 true)
		var q = JSON.parse_string(str(JavaScriptBridge.eval("JSON.stringify(Object.fromEntries(new URLSearchParams(location.search)))", true)))
		if typeof(q) == TYPE_DICTIONARY:
			for k in q:
				args[k] = q[k] if str(q[k]) != "" else true
	var world := _scene_or("res://world/world.tscn", "res://core/dev_view.gd")
	_boot("world 불러옴")
	add_child(world)
	_boot("world 붙임")
	if ResourceLoader.exists("res://title/title.gd"): # 타이틀 + 메뉴 3D 배경: 켜져 있는 동안 판 (world) 은 숨김 (빛·안개가 섞이지 않게)
		var title: Node = load("res://title/title.gd").new()
		title.active_changed.connect(func(on): world.visible = not on)
		title.skip = args.has("room") or args.has("replay") or (args.has("auto") and not args.has("title")) # 확인용: --auto … --title <테마> 면 타이틀부터
		title.fixed_theme = str(args.get("title", ""))
		title.auto_press = float(args.get("title-press", -1))
		add_child(title)
	_boot("title 붙임")
	add_child(_scene_or("res://ui/ui.tscn", "res://core/dev_ui.gd"))
	_boot("ui 붙임")
	for g6 in ["res://ui/perf.gd", "res://ui/practice.gd", "res://ui/tutorial_ui.gd", "res://world/tutorial_mark.gd"]: # G6: F3 성능 표시·연습 창·튜토리얼 (띠·목표 칸 빛)
		if ResourceLoader.exists(g6):
			add_child(load(g6).new())
	_boot("F3·연습·튜토리얼 붙임")
	if ResourceLoader.exists("res://audio/audio.tscn"):
		add_child(load("res://audio/audio.tscn").instantiate())
	_boot("audio 붙임")
	Seat.profile = str(args.get("profile", ""))
	if args.has("room"):
		Store.pending_code = str(args.room).to_upper() # (타이틀은 --room 이면 건너뜀)
	if args.has("auto"):
		var ap := AutoPilot.new()
		ap.args = args
		add_child(ap)
	if args.has("rec") or args.has("replay"): # 성능 재연 (W12, core/replay.gd): 녹화는 판과 같이, 재연은 서버 없이
		var rp: Node = load("res://core/replay.gd").new()
		rp.args = args
		add_child(rp)
		if args.has("replay"):
			return
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
