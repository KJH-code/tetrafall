# W4 화면 노드를 실제로 만들어 값을 읽는 테스트: 점수 띠 다시 그리기 (JS scoreKey) · 화면별 핵심 크기·여백·글자 크기 (JS index.html 과 대조해 고친 값)
# 러너 (_initialize) 동안엔 root 가 트리 밖이라 _ready 가 안 불림 → 직접 부르고, 끝에 지움
extends RefCounted

const C := preload("res://core/config.gd")
const S := preload("res://ui/ui_style.gd")

var errors: Array = []


func check(cond: bool, msg: String) -> void:
	if not cond:
		errors.append(msg)


func _make(path: String) -> Node:
	var n: Node = load(path).new()
	n._ready()
	return n


func _player(id: int, slot: int, wins: int) -> Dictionary:
	return {"id": id, "slot": slot, "name": "P%d" % (slot + 1), "nick": "", "wins": wins, "score": 0, "color": slot, "alive": true}


# hud.score_band: 같은 스냅샷이면 점수 띠 노드를 그대로 둠 (JS updateScore scoreKey), 승수가 바뀌면 다시 만듦 — 예전엔 스냅샷마다 (30Hz) 다 지우고 새로
func test_score_band_rebuilds_only_on_change() -> void:
	var keep := [Store.my_id, Store.room]
	Store.my_id = 1
	Store.room = {"code": "ABCD"}
	var hud = _make("res://ui/hud.gd")
	var st := {"phase": "lobby", "mode": "survival", "teamMode": false, "players": [_player(1, 0, 0), _player(2, 1, 0), _player(3, 2, 0)], "round": {"n": 0}}
	var vp := Vector2(1280, 720)
	hud.score_band(st, vp, true)
	var first: Array = hud.score_bar.get_children()
	check(first.size() > 0 and hud.score_panel.visible, "대기실 점수 띠가 보임 (%d칸)" % first.size())
	hud.score_band(st.duplicate(true), vp, true) # 다음 스냅샷 (내용 같음)
	var second: Array = hud.score_bar.get_children()
	check(second == first and first.all(func(c): return is_instance_valid(c)), "같은 스냅샷 두 번이면 노드 그대로")
	var st2: Dictionary = st.duplicate(true)
	st2.players[1].wins = 1
	hud.score_band(st2, vp, true)
	check(not first.any(func(c): return is_instance_valid(c)), "승수가 바뀌면 다시 만듦")
	var third: Array = hud.score_bar.get_children()
	hud.score_panel.visible = false # ui.gd 가 메뉴 화면에서 숨김 → 다시 대기실이면 내용이 같아도 보여야 함
	hud.score_band(st2, vp, true)
	check(hud.score_panel.visible and hud.score_bar.get_children() != third, "밖에서 숨겼으면 다시 그림")
	# 판 중 (킬 점수전): 남은 시간 글자가 바뀔 때만
	var k := {"phase": "playing", "mode": "kills", "teamMode": false, "players": [_player(1, 0, 0), _player(2, 1, 0)], "round": {"n": 1, "left": 60000.0, "killsTarget": 5}}
	hud.score_band(k, vp, false)
	var kc: Array = hud.score_bar.get_children()
	var k2: Dictionary = k.duplicate(true)
	k2.round.left = 60010.0 # 같은 '1:00'
	hud.score_band(k2, vp, false)
	check(hud.score_bar.get_children() == kc, "남은 시간 글자가 같으면 그대로")
	k2.round.left = 58000.0
	hud.score_band(k2, vp, false)
	check(hud.score_bar.get_children() != kc, "남은 시간 글자가 바뀌면 다시")
	hud.free()
	Store.my_id = keep[0]
	Store.room = keep[1]
