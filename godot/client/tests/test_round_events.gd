# 돌발 이벤트 알림 글 (ui/round_event_text.gd): 종류마다 한 줄, 돌풍은 방향 화살표 (게임 좌표 → 화면 축), 모르는 것은 빈 글
extends RefCounted

const T := preload("res://ui/round_event_text.gd")

var errors: Array = []


func check(cond: bool, msg: String) -> void:
	if not cond:
		errors.append(msg)


func test_round_event_text_kinds() -> void:
	check(T.text({"type": "roundEvent", "kind": "rain", "ms": 6000}) == "블록 폭우!", "폭우: '%s'" % T.text({"kind": "rain"}))
	check(T.text({"type": "roundEvent", "kind": "supply", "ms": 0}) == "보급!", "보급: '%s'" % T.text({"kind": "supply"}))
	# 돌풍: 서버 방향 4개 (+x, -x, +y, -y) → 화면 화살표
	var want := [[1, 0, "돌풍 →"], [-1, 0, "돌풍 ←"], [0, 1, "돌풍 ↑"], [0, -1, "돌풍 ↓"]]
	for w in want:
		var got := T.text({"type": "roundEvent", "kind": "wind", "ms": 5000, "dir": {"x": w[0], "y": w[1]}})
		check(got == w[2], "돌풍 (%s, %s): '%s' vs '%s'" % [w[0], w[1], got, w[2]])
	# JSON 숫자는 float 로 옴. 스냅샷 모양 (left) 도 같은 글
	check(T.text({"kind": "wind", "left": 1200.0, "dir": {"x": 0.0, "y": -1.0}}) == "돌풍 ↓", "스냅샷 돌풍")
	check(T.text({"kind": "rain", "left": 300.0, "dir": null}) == "블록 폭우!", "스냅샷 폭우 (dir null)")


func test_round_event_text_unknown_empty() -> void:
	check(T.text({}) == "", "빈 이벤트")
	check(T.text({"kind": "meteor"}) == "", "모르는 종류")
	check(T.text({"kind": null}) == "", "kind null")
	check(T.text({"kind": "wind"}) == "", "방향 없는 돌풍")
	check(T.text({"kind": "wind", "dir": null}) == "", "방향 null 돌풍")
	check(T.text({"kind": "wind", "dir": {"x": 0, "y": 0}}) == "", "방향 0 돌풍")
