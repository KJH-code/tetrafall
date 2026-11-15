# 돌발 이벤트 알림 글 (ui/round_event_text.gd): 종류마다 한 줄, 돌풍은 방향 화살표 (게임 좌표 → 보는 방향 기준), 모르는 것은 빈 글.
# 진행 중 띠 (status): 스냅샷 roundEvent 의 남은 초까지
extends RefCounted

const T := preload("res://ui/round_event_text.gd")
const UP := PI / 2.0 # 게임 +y 를 보는 yaw (예전 고정 축 표와 같은 답)

var errors: Array = []


func check(cond: bool, msg: String) -> void:
	if not cond:
		errors.append(msg)


func test_round_event_text_kinds() -> void:
	# 폭우·보급은 보는 방향과 상관없음
	for yaw in [0.0, UP, PI]:
		check(T.text({"type": "roundEvent", "kind": "rain", "ms": 6000}, yaw) == "블록 폭우!", "폭우: '%s'" % T.text({"kind": "rain"}, yaw))
		check(T.text({"type": "roundEvent", "kind": "supply", "ms": 0}, yaw) == "보급!", "보급: '%s'" % T.text({"kind": "supply"}, yaw))
	# 돌풍: 서버 방향 4개 (+x, -x, +y, -y) → 화면 화살표. +y 를 보고 있을 때 (yaw π/2) 게임 +x = 화면 오른쪽
	var want := [[1, 0, "돌풍 →"], [-1, 0, "돌풍 ←"], [0, 1, "돌풍 ↑"], [0, -1, "돌풍 ↓"]]
	for w in want:
		var got := T.text({"type": "roundEvent", "kind": "wind", "ms": 5000, "dir": {"x": w[0], "y": w[1]}}, UP)
		check(got == w[2], "돌풍 (%s, %s): '%s' vs '%s'" % [w[0], w[1], got, w[2]])
	# JSON 숫자는 float 로 옴. 스냅샷 모양 (left) 도 같은 글
	check(T.text({"kind": "wind", "left": 1200.0, "dir": {"x": 0.0, "y": -1.0}}, UP) == "돌풍 ↓", "스냅샷 돌풍")
	check(T.text({"kind": "rain", "left": 300.0, "dir": null}, UP) == "블록 폭우!", "스냅샷 폭우 (dir null)")


# 돌풍 화살표는 보는 방향 기준: 몸이 밀리는 쪽이 화면에서 어느 쪽인지 (yaw 반시계, 앞 = (cos, sin))
func test_round_event_arrow_follows_view() -> void:
	# [yaw, dx, dy, 화살표]
	var rows := [
		[0.0, 1, 0, "↑"], [0.0, -1, 0, "↓"], [0.0, 0, 1, "←"], [0.0, 0, -1, "→"], # +x 를 봄: +x 바람은 앞으로 밀림
		[PI, 1, 0, "↓"], [PI, -1, 0, "↑"], [PI, 0, 1, "→"], [PI, 0, -1, "←"], # -x 를 봄
		[-UP, 1, 0, "←"], [-UP, -1, 0, "→"], [-UP, 0, 1, "↓"], [-UP, 0, -1, "↑"], # -y 를 봄
		[UP + TAU, 1, 0, "→"], [UP - 3.0 * TAU, 0, 1, "↑"], # 여러 바퀴 돈 yaw (마우스로 계속 돌면 쌓임)
		[UP + 0.6, 1, 0, "→"], [UP - 0.6, 0, 1, "↑"], [0.6, 1, 0, "↑"], [PI - 0.6, 0, 1, "→"], # 비스듬히 봐도 가까운 쪽
	]
	for r in rows:
		var dir := {"x": float(r[1]), "y": float(r[2])}
		check(T.arrow(dir, r[0]) == r[3], "yaw %.2f 돌풍 (%s, %s): '%s' vs '%s'" % [r[0], r[1], r[2], T.arrow(dir, r[0]), r[3]])
		check(T.text({"kind": "wind", "dir": dir}, r[0]) == "돌풍 %s" % r[3], "yaw %.2f 글" % r[0])
	# 한 바퀴 도는 동안 같은 바람의 화살표가 네 방향을 다 지남 (고정 축이 아님)
	var seen := {}
	for i in 16:
		seen[T.arrow({"x": 1.0, "y": 0.0}, TAU * i / 16.0 + 0.1)] = true
	check(seen.size() == 4, "yaw 한 바퀴에 화살표 %d가지: %s" % [seen.size(), str(seen.keys())])


# 화면 위쪽 방향 고르기 (hud_extra.gd _view_yaw): 하늘 시점 > 클로즈업 (이모트 셀카) > 보는 방향
func test_round_event_view_yaw() -> void:
	check(is_equal_approx(T.view_yaw(0.7), 0.7), "보통: 보는 방향")
	check(is_equal_approx(T.view_yaw(0.7, null, null), 0.7), "null 둘: 보는 방향")
	check(is_equal_approx(T.view_yaw(0.7, 1.9), 1.9), "하늘 시점: sky_yaw")
	check(is_equal_approx(T.view_yaw(0.7, 0.0), 0.0), "하늘 시점 sky_yaw 0 도 하늘 (null 과 다름)")
	check(is_equal_approx(T.view_yaw(0.7, null, 0.3), 0.3 + PI), "셀카: 몸 yaw 의 반대")
	check(is_equal_approx(T.view_yaw(0.7, null, 0.0), PI), "셀카 몸 yaw 0 도 셀카 (null 과 다름)")
	check(is_equal_approx(T.view_yaw(0.7, 1.9, 0.3), 1.9), "하늘 시점이 클로즈업을 덮음 (cam_rig place 순서)")
	# 이모트 셀카: 카메라가 몸 앞 (cos yaw, sin yaw) 에서 몸을 돌아봄 → 앞·뒤, 좌·우가 1·3인칭과 반대
	# [몸 yaw, dx, dy, 셀카 화살표, 1·3인칭 화살표]
	var rows := [
		[0.0, 1, 0, "↓", "↑"], [0.0, -1, 0, "↑", "↓"], [0.0, 0, 1, "→", "←"], [0.0, 0, -1, "←", "→"], # 리뷰 반례: yaw 0 셀카 중 (1, 0) 돌풍 = 카메라 쪽 (아래)
		[UP, 1, 0, "←", "→"], [UP, 0, 1, "↓", "↑"], [-UP, 0, 1, "↑", "↓"], [PI, 1, 0, "↑", "↓"],
		[UP + 0.6, 1, 0, "←", "→"], [0.6 + TAU, 1, 0, "↓", "↑"],
	]
	for r in rows:
		var e := {"kind": "wind", "dir": {"x": float(r[1]), "y": float(r[2])}}
		var selfie := T.text(e, T.view_yaw(r[0], null, r[0]))
		var plain := T.text(e, T.view_yaw(r[0]))
		check(selfie == "돌풍 %s" % r[3], "셀카 yaw %.2f 돌풍 (%s, %s): '%s' vs '돌풍 %s'" % [r[0], r[1], r[2], selfie, r[3]])
		check(plain == "돌풍 %s" % r[4], "보통 yaw %.2f 돌풍 (%s, %s): '%s' vs '돌풍 %s'" % [r[0], r[1], r[2], plain, r[4]])
	# 셀카 카메라 자리로 직접 확인: 눈 = 몸 + 앞 × 거리, 보는 쪽 = 몸 − 눈. 바람이 눈 쪽으로 불면 화면 아래 (↓), 눈에서 멀어지면 ↑
	for i in 12:
		var yaw := TAU * i / 12.0 + 0.2
		var to_eye := {"x": cos(yaw), "y": sin(yaw)}
		var away := {"x": -cos(yaw), "y": -sin(yaw)}
		check(T.arrow(to_eye, T.view_yaw(yaw, null, yaw)) == "↓", "셀카 yaw %.2f: 카메라 쪽 바람은 ↓" % yaw)
		check(T.arrow(away, T.view_yaw(yaw, null, yaw)) == "↑", "셀카 yaw %.2f: 카메라 반대쪽 바람은 ↑" % yaw)


func test_round_event_text_unknown_empty() -> void:
	for yaw in [0.0, UP]:
		check(T.text({}, yaw) == "", "빈 이벤트")
		check(T.text({"kind": "meteor"}, yaw) == "", "모르는 종류")
		check(T.text({"kind": null}, yaw) == "", "kind null")
		check(T.text({"kind": "wind"}, yaw) == "", "방향 없는 돌풍")
		check(T.text({"kind": "wind", "dir": null}, yaw) == "", "방향 null 돌풍")
		check(T.text({"kind": "wind", "dir": {"x": 0, "y": 0}}, yaw) == "", "방향 0 돌풍")


# 진행 중 띠 (hud_extra.gd refresh → status): 스냅샷 roundEvent {kind, left, dir} → '돌풍 ↓ 5초'·'블록 폭우 1초'. 남은 초는 올림
func test_round_event_status() -> void:
	var wind := {"kind": "wind", "left": 4200.0, "dir": {"x": 0.0, "y": -1.0}}
	check(T.status(wind, UP) == "돌풍 ↓ 5초", "돌풍: '%s'" % T.status(wind, UP))
	check(T.status({"kind": "rain", "left": 300.0, "dir": null}, UP) == "블록 폭우 1초", "폭우: '%s'" % T.status({"kind": "rain", "left": 300.0, "dir": null}, UP))
	check(T.status({"kind": "rain", "left": 6000.0}, 0.0) == "블록 폭우 6초", "딱 6초")
	check(T.status({"kind": "rain", "left": 5999.0}, 0.0) == "블록 폭우 6초", "5.999초 → 6초 (올림)")
	check(T.status({"kind": "rain", "left": 1.0}, 0.0) == "블록 폭우 1초", "1ms 남아도 1초")
	# 띠 없음: 진행 중 아님·보급·모르는 종류·방향 없는 돌풍
	for yaw in [0.0, UP]:
		check(T.status(null, yaw) == "", "null")
		check(T.status({}, yaw) == "", "빈 것")
		check(T.status({"kind": "rain", "left": 0.0}, yaw) == "", "left 0")
		check(T.status({"kind": "wind", "left": -5.0, "dir": {"x": 1.0, "y": 0.0}}, yaw) == "", "left 음수")
		check(T.status({"kind": "rain"}, yaw) == "", "left 없음")
		check(T.status({"kind": "rain", "left": null}, yaw) == "", "left null")
		check(T.status({"kind": "supply", "left": 3000.0}, yaw) == "", "보급")
		check(T.status({"kind": "meteor", "left": 3000.0}, yaw) == "", "모르는 종류")
		check(T.status({"kind": "wind", "left": 3000.0}, yaw) == "", "방향 없는 돌풍")
		check(T.status({"kind": "wind", "left": 3000.0, "dir": null}, yaw) == "", "방향 null 돌풍")
		check(T.status({"kind": "wind", "left": 3000.0, "dir": {"x": 0, "y": 0}}, yaw) == "", "방향 0 돌풍")
	# 화살표는 보는 방향 기준 (몸을 돌리면 띠도 따라 바뀜): 같은 ev 에 yaw 0 과 π/2
	check(T.status(wind, 0.0) != T.status(wind, UP), "yaw 가 달라도 글이 같음: '%s'" % T.status(wind, 0.0))
	check(T.status(wind, 0.0) == "돌풍 → 5초", "yaw 0: '%s'" % T.status(wind, 0.0))
	# 화살표는 시작 알림 (text) 과 같은 것
	for yaw in [0.0, UP, PI, -UP, 0.6]:
		check(T.status(wind, yaw) == "%s 5초" % T.text(wind, yaw), "yaw %.2f: 띠 '%s' vs 알림 '%s'" % [yaw, T.status(wind, yaw), T.text(wind, yaw)])


# 저중력·빙판 (서버 lowgrav·ice): 알림 한 줄은 보는 방향과 상관없음
func test_round_event_lowgrav_ice_text() -> void:
	for yaw in [0.0, UP, PI]:
		var low := T.text({"type": "roundEvent", "kind": "lowgrav", "ms": 6000}, yaw)
		var ice := T.text({"type": "roundEvent", "kind": "ice", "ms": 6000}, yaw)
		check(low == "저중력! 높이 뛰고 멀리 날아감", "저중력: '%s'" % low)
		check(ice == "빙판! 맞으면 멀리 미끄러짐", "빙판: '%s'" % ice)
		# 스냅샷 모양 (left, dir null) 도 같은 글
		check(T.text({"kind": "lowgrav", "left": 300.0, "dir": null}, yaw) == low, "스냅샷 저중력")
		check(T.text({"kind": "ice", "left": 300.0, "dir": null}, yaw) == ice, "스냅샷 빙판")


# 저중력·빙판 진행 중 띠: 남은 초는 올림 (폭우와 같은 규칙), left 0 이하·없음이면 ""
func test_round_event_lowgrav_ice_status() -> void:
	var rows := [["lowgrav", "저중력"], ["ice", "빙판"]]
	for r in rows:
		for yaw in [0.0, UP]:
			var got := T.status({"kind": r[0], "left": 2300.0, "dir": null}, yaw)
			check(got == "%s 3초" % r[1], "%s 2.3초: '%s'" % [r[0], got])
			check(T.status({"kind": r[0], "left": 2300}, 0) == "%s 3초" % r[1], "%s 정수 left·yaw" % r[0])
			check(T.status({"kind": r[0], "left": 6000.0}, yaw) == "%s 6초" % r[1], "%s 딱 6초" % r[0])
			check(T.status({"kind": r[0], "left": 1.0}, yaw) == "%s 1초" % r[1], "%s 1ms 남아도 1초" % r[0])
			check(T.status({"kind": r[0], "left": 0.0}, yaw) == "", "%s left 0" % r[0])
			check(T.status({"kind": r[0], "left": 0}, yaw) == "", "%s left 정수 0" % r[0])
			check(T.status({"kind": r[0], "left": -5.0}, yaw) == "", "%s left 음수" % r[0])
			check(T.status({"kind": r[0]}, yaw) == "", "%s left 없음" % r[0])
			check(T.status({"kind": r[0], "left": null}, yaw) == "", "%s left null" % r[0])
