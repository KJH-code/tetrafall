# 시작점. 명령줄(-- 뒤)로 실행 모드를 고름:
#   --server [--port 3100] [--rounds N]   헤드리스 서버 (판정 권위, 30Hz)
#   --client [--url ws://127.0.0.1:3100] [--bot] [--quit-after-rounds N]   클라 (--bot 이면 자동 입력)
# 웹 내보내기는 항상 클라 (주소는 ?server=ws://… 또는 지금 페이지의 호스트:3100)
extends Node

const Server := preload("res://net/server.gd")
const Client := preload("res://client/client.gd")


func _ready() -> void:
	var args := parse_args(OS.get_cmdline_user_args())
	if OS.has_feature("web"):
		args["client"] = true
		var q = JavaScriptBridge.eval("new URLSearchParams(location.search).get('server') || ('ws://' + location.hostname + ':3100')", true)
		args["url"] = str(q)
		var b = JavaScriptBridge.eval("new URLSearchParams(location.search).has('bot')", true)
		if b:
			args["bot"] = true
	var node: Node
	if args.has("server"):
		node = Server.new()
	else:
		node = Client.new()
	node.set("args", args)
	add_child(node)


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
