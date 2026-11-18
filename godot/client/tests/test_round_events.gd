# 돌발 이벤트 알림 글 (ui/round_event_text.gd): 종류마다 한 줄, 돌풍은 방향 화살표 (게임 좌표 → 보는 방향 기준), 모르는 것은 빈 글.
# 진행 중 띠 (status): 스냅샷 roundEvent 의 남은 초까지
extends RefCounted

const T := preload("res://ui/round_event_text.gd")
const SM := preload("res://audio/sound_math.gd")
const BM := preload("res://world/bolt_fx_math.gd")
const HM := preload("res://world/hand_aim_math.gd")
const RL := preload("res://world/ring_look.gd")
const FM := preload("res://fx/fx_math.gd")
const C := preload("res://core/config.gd")
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


# ---------- c9 번개 (서버 bolt): 알림 글·띠·알림음, 예고 고리·번개 띠 계산 (world/bolt_fx_math.gd) ----------
func test_bolt_text_status() -> void:
	for yaw in [0.0, UP, PI]:
		var got := T.text({"type": "roundEvent", "kind": "bolt", "ms": 6000}, yaw)
		check(got == "번개! 바닥 고리 밖으로", "번개: '%s'" % got)
		check(T.text({"kind": "bolt", "left": 300.0, "dir": null}, yaw) == got, "스냅샷 번개")
		check(T.status({"kind": "bolt", "left": 2300.0, "dir": null}, yaw) == "번개 3초", "번개 2.3초: '%s'" % T.status({"kind": "bolt", "left": 2300.0}, yaw))
		check(T.status({"kind": "bolt", "left": 6000}, yaw) == "번개 6초", "번개 딱 6초")
		check(T.status({"kind": "bolt", "left": 1.0}, yaw) == "번개 1초", "번개 1ms 남아도 1초")
		check(T.status({"kind": "bolt", "left": 0.0}, yaw) == "", "번개 left 0")
		check(T.status({"kind": "bolt"}, yaw) == "", "번개 left 없음")


# 이벤트 시작 알림음: 보급은 줍는 소리, 나머지는 전부 시작 신호 "go" (이미 있는 효과음 키), 종류가 비면 안 냄.
# c9 리뷰 F5: 압사 경고 "danger"·예고 째깍 "tick"·낙뢰 "crit" 과 다른 키여야 함 (같은 소리면 생존 신호가 흐려짐), 구운 소리 목록에 있어야 함 (없으면 소리 없이 넘어감)
func test_bolt_event_cue() -> void:
	check(SM.event_cue("supply") == "pickup", "보급: %s" % SM.event_cue("supply"))
	var man = JSON.parse_string(FileAccess.get_file_as_string("res://audio/baked/manifest.json"))
	var sfx: Dictionary = man.get("sfx", {}) if man is Dictionary else {}
	check(not sfx.is_empty(), "audio/baked/manifest.json sfx 목록을 못 읽음")
	for k in ["rain", "wind", "lowgrav", "ice", "bolt"]:
		var cue := SM.event_cue(k)
		check(cue == "go", "%s: %s" % [k, cue])
		check(not (cue in ["danger", "tick", "crit", "pickup"]), "%s: 알림음 '%s' 가 압사 경고·예고·낙뢰·보급 소리와 겹침" % [k, cue])
		check(sfx.has(cue), "%s: 알림음 '%s' 가 구운 소리 목록에 없음" % [k, cue])
	check(sfx.has(SM.event_cue("supply")), "보급 알림음이 구운 소리 목록에 없음")
	check(SM.event_cue("") == "" and SM.event_cue(null) == "", "빈 종류")


# c9 리뷰 F2·F6 내가 예고 고리 안인가 (화면 신호 ui/bolt_alert.gd · 소리 audio.gd 가 같이 씀): 살아서 필드에 있고, 수평 반지름 안·발 높이 차 안 (서버 Game.BoltStrike 와 같은 식)
func test_bolt_alert_in_ring() -> void:
	var me := {"id": 2.0, "x": 5.0, "y": 5.0, "z": 2.0, "alive": true}
	check(BM.in_ring(me, 5.0, 5.0, 2.0, 1.2), "한가운데")
	check(BM.in_ring(me, 5.0 + 1.19, 5.0, 2.0, 1.2), "반지름 바로 안")
	check(not BM.in_ring(me, 5.0 + 1.21, 5.0, 2.0, 1.2), "반지름 바로 밖")
	check(BM.in_ring(me, 5.0, 5.0, 2.0 + float(BM.ALERT.height), 1.2) and BM.in_ring(me, 5.0, 5.0, 2.0 - float(BM.ALERT.height), 1.2), "높이 차 딱 %s: 맞는 높이" % BM.ALERT.height)
	check(not BM.in_ring(me, 5.0, 5.0, 2.0 + float(BM.ALERT.height) + 0.1, 1.2) and not BM.in_ring(me, 5.0, 5.0, 2.0 - float(BM.ALERT.height) - 0.1, 1.2), "높이 차가 넘으면 아님")
	check(is_equal_approx(float(BM.ALERT.height), 3.0), "서버 EVENT_BOLT_HEIGHT (ConfigEvents.cs) 와 같은 값: %s" % BM.ALERT.height)
	# F6: 죽은 나 (서버는 죽은 자리도 스냅샷에 보냄 — 관전·부활 대기) · 블록 마스터 (살아 있지만 필드에 없음) · 나 없음 (관전자) 은 아님
	var dead := me.duplicate()
	dead["alive"] = false
	check(not BM.in_ring(dead, 5.0, 5.0, 2.0, 1.2), "죽은 나 + 근처 예고: 내 고리 아님")
	var master := me.duplicate()
	master["master"] = true
	check(not BM.in_ring(master, 5.0, 5.0, 2.0, 1.2), "블록 마스터: 내 고리 아님")
	check(not BM.in_ring({}, 5.0, 5.0, 2.0, 1.2), "나 없음")
	check(not BM.in_ring({"alive": true}, 5.0, 5.0, 2.0, 1.2), "자리 없는 나")


# 화면 신호: 내가 안에 있는 예고 가운데 가장 먼저 떨어질 것의 남은 시간, 고리 밖으로 나가면 없음, 떨어진 번개가 내 자리인지, 초 글자, 가장자리 테 알파
func test_bolt_alert_pick_edge() -> void:
	var me := {"id": 2.0, "x": 5.0, "y": 5.0, "z": 0.0, "alive": true}
	var list := []
	BM.warn_add(list, {"type": "boltWarn", "id": 1.0, "x": 5.3, "y": 5.0, "z": 0.0, "r": 1.2, "ms": 1200.0}, 1000.0)
	BM.warn_add(list, {"type": "boltWarn", "id": 2.0, "x": 9.0, "y": 5.0, "z": 0.0, "r": 1.2, "ms": 1200.0}, 1000.0) # 남의 고리
	BM.warn_add(list, {"type": "boltWarn", "id": 3.0, "x": 4.6, "y": 5.2, "z": 0.0, "r": 1.2, "ms": 1200.0}, 700.0) # 먼저 뜬 내 고리
	var w := BM.alert_pick(list, me, 1300.0)
	check(not w.is_empty() and is_equal_approx(float(w.left), 600.0) and is_equal_approx(float(w.ms), 1200.0), "먼저 떨어질 내 고리: %s" % [w])
	check(is_equal_approx(float(BM.alert_pick(list, me, 5000.0).left), 0.0), "예정 시각이 지나도 (떨어짐 이벤트 전) 0 아래로 안 감")
	var away := me.duplicate()
	away["x"] = 7.0 # 세 고리 모두 밖 (4.6·5.3 에서 1.2 넘음, 9.0 에서 2.0)
	check(BM.alert_pick(list, away, 1300.0).is_empty(), "고리 밖으로 나가면 신호 없음")
	var dead := me.duplicate()
	dead["alive"] = false
	check(BM.alert_pick(list, dead, 1300.0).is_empty(), "죽은 나: 신호 없음")
	check(BM.alert_pick([], me, 1300.0).is_empty(), "예고 없음")
	# 떨어진 번개
	check(BM.struck(me, {"type": "bolt", "id": 1.0, "x": 5.3, "y": 5.0, "z": 0.0, "r": 1.2, "hits": [2.0]}), "맞은 사람 목록에 나")
	check(BM.struck(me, {"type": "bolt", "id": 1.0, "x": 5.3, "y": 5.0, "z": 0.0, "r": 1.2, "hits": []}), "안 맞았어도 (무적) 내 자리")
	check(BM.struck(me, {"type": "bolt", "id": 1.0, "x": 9.0, "y": 5.0, "z": 0.0, "r": 1.2, "hits": [1.0, 2.0]}), "hits 에 내 id")
	check(not BM.struck(me, {"type": "bolt", "id": 2.0, "x": 9.0, "y": 5.0, "z": 0.0, "r": 1.2, "hits": [1.0]}), "남의 자리")
	check(not BM.struck(dead, {"type": "bolt", "id": 1.0, "x": 5.3, "y": 5.0, "z": 0.0, "r": 1.2, "hits": []}), "죽은 나")
	check(not BM.struck({}, {"type": "bolt", "id": 1.0, "x": 5.3, "y": 5.0, "z": 0.0, "r": 1.2, "hits": []}), "나 없음")
	# 글자: 본문에 이미 있는 낱말로, 압사 경고 글과 다름
	check(str(BM.ALERT.text) == "번개! 고리 밖으로", "글: %s" % BM.ALERT.text)
	check(BM.alert_sec(600.0) == "0.6초" and BM.alert_sec(1200.0) == "1.2초" and BM.alert_sec(-5.0) == "0.0초", "초 글자: %s %s" % [BM.alert_sec(600.0), BM.alert_sec(-5.0)])
	# 가장자리 테: 밖·안 맞음 = 0, 안 = edge 범위 안에서 깜빡, 떨어진 순간 hit_alpha → hit_ms 뒤 0
	var e: Array = BM.ALERT.edge
	check(BM.alert_edge(false, 1234.0, -1.0e9) == 0.0, "밖: 테 끔")
	var lo := INF
	var hi := -INF
	for i in 48:
		var k := BM.alert_edge(true, 1000.0 + i * 10.0, -1.0e9)
		lo = minf(lo, k)
		hi = maxf(hi, k)
	check(lo >= float(e[0]) - 1e-6 and hi <= float(e[1]) + 1e-6 and hi - lo > 0.2, "안: %s~%s 사이 깜빡 (얻음 %s~%s)" % [e[0], e[1], lo, hi])
	check(is_equal_approx(BM.alert_edge(false, 2000.0, 2000.0), float(BM.ALERT.hit_alpha)), "떨어진 순간")
	var half := BM.alert_edge(false, 2000.0 + float(BM.ALERT.hit_ms) / 2.0, 2000.0)
	check(is_equal_approx(half, float(BM.ALERT.hit_alpha) / 2.0), "절반 지남: %s" % half)
	check(BM.alert_edge(false, 2000.0 + float(BM.ALERT.hit_ms), 2000.0) == 0.0, "hit_ms 뒤 끔")
	check(float(e[1]) <= 0.75 and float(BM.ALERT.y) > 0.55 and float(BM.ALERT.y) < 0.8, "테는 경직 테 (0.75) 보다 진하지 않게, 판은 가운데 아래")
	# 판 자리: 1인칭은 조준점 아래, 3인칭·하늘 시점은 조준점 위 (가운데 아래의 내 몸·발밑 고리를 안 덮게) — 어느 쪽이든 위 묶음 (압사 경고) 아래
	check(BM.alert_y("first") == float(BM.ALERT.y) and BM.alert_y("third") == float(BM.ALERT.y_up) and BM.alert_y("sky") == float(BM.ALERT.y_up), "시점별 판 자리")
	check(float(BM.ALERT.y_up) > 0.25 and float(BM.ALERT.y_up) < 0.45, "3인칭 판 자리 %s: 위 묶음 아래·조준점 위" % BM.ALERT.y_up)


# 화면 신호 노드 (ui/bolt_alert.gd — 트리 밖에서 이벤트·프레임을 직접 넣어 봄): 내 고리면 판이 켜지고 글·초가 맞음, 남의 고리·죽은 나는 꺼짐, 내 자리에 떨어지면 테가 켜짐, 판 중이 아니면 다 비움
func test_bolt_alert_node() -> void:
	var A = load("res://ui/bolt_alert.gd")
	var a = A.new()
	var me := {"id": 2.0, "x": 5.0, "y": 5.0, "z": 0.0, "alive": true}
	a.refresh(me, 0.0, true)
	check(not a.plate.visible and not a.edge.visible, "예고 없음: 꺼짐")
	a.on_event({"type": "boltWarn", "id": 7.0, "x": 5.2, "y": 5.0, "z": 0.0, "r": 1.2, "ms": 1200.0}, me, 1000.0)
	a.refresh(me, 1300.0, true)
	check(a.plate.visible and a.text.text == "번개! 고리 밖으로" and a.sec.text == "0.9초", "내 고리: 판 켜짐 '%s' %s" % [a.text.text, a.sec.text])
	check(is_equal_approx(a.left01, 0.75) and a.edge.visible and a.edge.modulate.a > 0.0, "막대 %s · 테 %s" % [a.left01, a.edge.modulate.a])
	var away := me.duplicate()
	away["x"] = 8.0
	a.refresh(away, 1400.0, true)
	check(not a.plate.visible and not a.edge.visible, "고리 밖으로 나감: 꺼짐")
	var dead := me.duplicate()
	dead["alive"] = false
	a.refresh(dead, 1400.0, true)
	check(not a.plate.visible and not a.edge.visible, "죽은 나: 꺼짐")
	# 내 자리에 떨어짐: 예고가 지워지고 판은 꺼지고 테만 한 번
	a.on_event({"type": "bolt", "id": 7.0, "x": 5.2, "y": 5.0, "z": 0.0, "r": 1.2, "hits": [2.0]}, me, 2200.0)
	a.refresh(me, 2250.0, true)
	check(a.warns.is_empty() and not a.plate.visible and a.edge.visible and a.edge.modulate.a > 0.5, "떨어진 직후: 판 꺼짐·테 %s" % a.edge.modulate.a)
	a.refresh(me, 2200.0 + float(BM.ALERT.hit_ms) + 1.0, true)
	check(not a.edge.visible, "테 사라짐")
	# 남의 자리에 떨어진 번개는 테 없음
	a.on_event({"type": "bolt", "id": 9.0, "x": 12.0, "y": 5.0, "z": 0.0, "r": 1.2, "hits": [1.0]}, me, 5000.0)
	a.refresh(me, 5010.0, true)
	check(not a.edge.visible, "남의 자리 번개: 테 없음")
	# 판 중이 아니면 비움
	a.on_event({"type": "boltWarn", "id": 8.0, "x": 5.0, "y": 5.0, "z": 0.0, "r": 1.2, "ms": 1200.0}, me, 6000.0)
	a.refresh(me, 6100.0, true)
	check(a.plate.visible, "다시 내 고리")
	a.refresh(me, 6200.0, false)
	check(a.warns.is_empty() and not a.plate.visible and not a.edge.visible, "판 끝: 다 비움")
	a.free()


# 예고 고리: 처음에 조금 크게 떴다가 곧 맞는 반지름 그대로, 알파는 곧 1, 채운 원은 떨어지는 순간 고리 안쪽 끝에 닿음
func test_bolt_warn_curves() -> void:
	var r := 1.2
	check(is_equal_approx(BM.warn_radius(0.0, r), r * float(BM.WARN.pop)), "처음 반지름: %s" % BM.warn_radius(0.0, r))
	var prev := BM.warn_radius(0.0, r)
	for i in range(1, 21):
		var u := i / 20.0
		var now := BM.warn_radius(u, r)
		check(now <= prev + 1e-6 and now >= r - 1e-6, "반지름은 줄어들기만, 맞는 반지름 아래로 안 감 (u %s: %s)" % [u, now])
		prev = now
	for u in [float(BM.WARN.pop_u), 0.5, 1.0, 1.7]:
		check(is_equal_approx(BM.warn_radius(u, r), r), "pop_u 뒤로는 맞는 반지름: u %s → %s" % [u, BM.warn_radius(u, r)])
	check(BM.warn_alpha(0.0) == 0.0 and BM.warn_alpha(float(BM.WARN.fade_u)) == 1.0 and BM.warn_alpha(1.0) == 1.0, "알파 0 → 1")
	check(BM.warn_alpha(float(BM.WARN.fade_u) / 2.0) > 0.4 and BM.warn_alpha(float(BM.WARN.fade_u) / 2.0) < 0.6, "알파 중간")
	# 채움: fill_r0 → 고리 안쪽 끝 (띠 첫 안 반지름), 고르게 커짐
	var inner := float(BM.WARN.bands[0][0])
	check(is_equal_approx(BM.fill_frac(0.0), float(BM.WARN.fill_r0)), "처음 채움")
	check(is_equal_approx(BM.fill_frac(1.0), inner) and is_equal_approx(BM.fill_frac(3.0), inner), "다 찬 채움 = 고리 안쪽 끝 (%s)" % BM.fill_frac(1.0))
	check(is_equal_approx(BM.fill_frac(0.5), (float(BM.WARN.fill_r0) + inner) / 2.0), "절반")
	check(BM.fill_frac(-1.0) == BM.fill_frac(0.0), "음수 u")
	# 흐른 비율
	check(BM.warn_u(100.0, 100.0, 1200.0) == 0.0 and BM.warn_u(700.0, 100.0, 1200.0) == 0.5 and BM.warn_u(5000.0, 100.0, 1200.0) == 1.0, "warn_u")
	check(BM.warn_u(0.0, 0.0, 0.0) == 1.0, "ms 0")
	# 띠 폭 = 반지름의 24% (F 예고 고리와 같은 굵기), 띠는 흰 심 + 바깥 잉크 테 — 사람 색 없음
	check(is_equal_approx(BM.band_frac(), 0.24) and is_equal_approx(BM.band_frac(), RL.band_frac("windup")), "띠 폭: %s" % BM.band_frac())
	var paints := {}
	for b in BM.WARN.bands:
		paints[str(b[2])] = true
		paints[str(b[3])] = true
	check(not paints.has("tint") and paints.has("core") and paints.has("ink"), "칠: %s" % str(paints.keys()))
	check(str(BM.WARN.bands.back()[3]) == "ink", "바깥 테는 잉크")
	check(float(BM.WARN.lift) > float(RL.WINDUP.lift) and float(RL.WINDUP.lift) > float(RL.AURA.lift), "띄움: 발밑 고리 < F 예고 < 번개 예고")
	check(int(BM.WARN.priority) == 9, "그리는 순서 9")
	check(is_equal_approx(BM.fill_color(1.0).a, 0.28) and is_equal_approx(BM.fill_color(0.5).a, 0.14), "채움 알파")
	check(BM.fill_color(1.0).is_equal_approx(Color(Color8(0xff, 0xf0, 0xa0), 0.28)), "채움 색")
	check(BM.ring_color(0.5) == Color(1, 1, 1, 0.5), "고리 색 (정점 색 그대로 × 알파)")


# 예고 메시 하나에 고리 + 채운 원: 인스턴스 기저가 하나만 고름 (다른 쪽은 넓이 0 으로 눌림) → MultiMesh 하나로 둘 다
func _tri_area(arr: PackedVector3Array, b: Basis, from: int, to: int) -> float:
	var sum := 0.0
	for i in range(from, to, 3):
		sum += ((b * arr[i + 1]) - (b * arr[i])).cross((b * arr[i + 2]) - (b * arr[i])).length() / 2.0
	return sum


func test_bolt_warn_mesh_picks_ring_or_fill() -> void:
	var mesh := BM.warn_mesh()
	check(mesh.get_surface_count() == 1, "표면 하나")
	var v: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var ring_n := int(BM.WARN.pieces) * int(BM.WARN.arc_seg) * BM.WARN.bands.size() * 6
	var fill_n := int(BM.WARN.fill_seg) * 3
	check(v.size() == ring_n + fill_n, "정점 수 %d (고리 %d + 원 %d)" % [v.size(), ring_n, fill_n])
	check(int(BM.WARN.pieces) == 8, "8조각")
	# 고리 넓이 = 띠 넓이 × (1 − 틈) (마디로 나눈 다각형이라 조금 작음), 원 넓이 ≈ π r²
	var r := 1.2
	var rb := BM.ring_basis(r, 0.7)
	var want_ring := PI * r * r * (1.0 - 0.76 * 0.76) * (1.0 - float(BM.WARN.gap))
	var got_ring := _tri_area(v, rb, 0, ring_n)
	check(got_ring > want_ring * 0.97 and got_ring <= want_ring + 1e-4, "고리 기저: 고리 넓이 %s (바라는 값 %s)" % [got_ring, want_ring])
	check(_tri_area(v, rb, ring_n, v.size()) < 1e-6, "고리 기저: 원은 눌려 넓이 0 (%s)" % _tri_area(v, rb, ring_n, v.size()))
	var fb := BM.fill_basis(0.5)
	var got_fill := _tri_area(v, fb, ring_n, v.size())
	check(got_fill > PI * 0.25 * 0.98 and got_fill <= PI * 0.25 + 1e-4, "원 기저: 원 넓이 %s" % got_fill)
	check(_tri_area(v, fb, 0, ring_n) < 1e-6, "원 기저: 고리는 눌려 넓이 0")
	# 둘 다 바닥 (고도 y = 0) 에 누움, 반지름 안
	for i in v.size():
		var p := (rb if i < ring_n else fb) * v[i]
		check(absf(p.y) < 1e-6 and Vector2(p.x, p.z).length() <= (r if i < ring_n else 0.5) + 1e-5, "바닥·반지름 안: %s" % p)
	# 다시 불러도 같은 메시 (한 번만 만듦)
	check(BM.warn_mesh() == mesh, "메시 기억")
	BM.clear_static()


# 번개 띠: 지그재그는 id 마다 정해진 모양 (바닥 가운데 → 꼭대기), 3단 (바깥 잉크 → 연노랑 → 흰 심), 금방 사라짐
func test_bolt_zigzag_layers() -> void:
	var h := float(BM.STRIKE.height)
	check(h >= 3.0, "띠 높이 3칸 이상: %s" % h)
	for id in [1, 2, 17, 400]:
		var a := BM.zigzag(id, h)
		check(a == BM.zigzag(id, h), "같은 id 는 같은 모양")
		check(a.size() == int(BM.STRIKE.joints) + 1, "점 수 %d" % a.size())
		check(a[0] == Vector2.ZERO, "바닥 점은 한가운데")
		check(is_equal_approx(a[a.size() - 1].y, h), "꼭대기 높이 %s" % a[a.size() - 1].y)
		for i in range(1, a.size()):
			check(a[i].y > a[i - 1].y, "위로만 올라감 (id %d, %d번)" % [id, i])
			check(absf(a[i].x) <= float(BM.STRIKE.amp) + 1e-6 and absf(a[i].x) >= float(BM.STRIKE.amp) * 0.45 - 1e-6, "꺾임 폭 안 (id %d: %s)" % [id, a[i].x])
			if i >= 2:
				check(signf(a[i].x) != signf(a[i - 1].x), "좌우 번갈아 꺾임")
	check(BM.zigzag(1, h) != BM.zigzag(2, h), "id 가 다르면 모양이 다름")
	var L: Array = BM.STRIKE.layers
	check(L.size() == 3 and str(L[0][1]) == "ink" and str(L[1][1]) == "glow" and str(L[2][1]) == "core", "3단: 잉크 테 · 연노랑 · 흰 심")
	check(float(L[0][0]) > float(L[1][0]) and float(L[1][0]) > float(L[2][0]), "바깥 단이 더 넓음")
	check(is_equal_approx(BM.layer_color("ink", 1.0).a, RL.INK_ALPHA) and BM.layer_color("core", 0.5) == Color(1, 1, 1, 0.5), "단 색")
	check(BM.layer_color("glow", 1.0).is_equal_approx(Color8(0xff, 0xf0, 0xa0)), "연노랑")
	# 수명 0.25초: 처음엔 알파 1, 끝으로 갈수록 0, 지나면 -1
	check(float(BM.STRIKE.life_ms) == 250.0, "수명")
	check(BM.strike_alpha(0.0) == 1.0 and BM.strike_alpha(float(BM.STRIKE.life_ms) * float(BM.STRIKE.hold)) == 1.0, "처음 알파 1")
	check(BM.strike_alpha(200.0) > 0.0 and BM.strike_alpha(200.0) < 1.0 and BM.strike_alpha(249.0) < 0.05, "끝으로 갈수록 0")
	check(BM.strike_alpha(250.0) == -1.0 and BM.strike_alpha(900.0) == -1.0, "수명 뒤 -1")
	check(BM.top_alpha(0.0) == 1.0 and BM.top_alpha(1.0 - float(BM.STRIKE.top_fade)) == 1.0 and BM.top_alpha(1.0) == 0.0, "꼭대기로 갈수록 옅게")
	# 바닥 고리 0.3초: 커지며 옅어짐
	var f0 := BM.flash(0.0, 1.2)
	var f1 := BM.flash(150.0, 1.2)
	check(is_equal_approx(f0.x, 1.2 * float(BM.STRIKE.flash_r0)) and is_equal_approx(f0.y, float(BM.STRIKE.flash_alpha)), "바닥 고리 처음: %s" % f0)
	check(f1.x > f0.x and f1.y < f0.y and f1.y > 0.0, "커지며 옅어짐: %s" % f1)
	check(BM.flash(300.0, 1.2).y == -1.0, "0.3초 뒤 끝")


# 화면 상한: 가까운 번개는 화면 높이의 45% 까지만 (높이·폭 같이 줄임), 먼 번개는 그대로, 카메라 뒤·바로 앞이면 안 그림 (0)
func test_bolt_strike_capped() -> void:
	var h := float(BM.STRIKE.height)
	var w := BM.strike_width()
	var cap := float(BM.STRIKE.cap)
	check(is_equal_approx(cap, 0.45), "상한 0.45")
	for fov in [C.FOV_DEFAULT, 60.0, 100.0]:
		# 카메라 공간: 바닥 점이 눈보다 1.5칸 아래, 앞 d 칸 (보는 쪽 −z), 위 = +y
		for d in [0.6, 1.5, 3.0, 6.0, 9.0, 14.0, 40.0]:
			var foot := Vector3(0.4, -1.5, -d)
			var k := BM.strike_cap(h, foot, Vector3.UP, fov)
			check(k > 0.0 and k <= 1.0, "배율 0~1 (fov %s d %s: %s)" % [fov, d, k])
			var span := FM.plume_span(h * k, w * k, foot, Vector3.UP, fov, int(BM.STRIKE.cap_seg), float(BM.STRIKE.cap_near))
			check(span <= cap + 1e-3, "비친 크기 ≤ 상한 (fov %s d %s: %s)" % [fov, d, span])
			# 화면에 비친 세로 길이 (바닥 → 꼭대기) 도 상한 안
			var t := 2.0 * tan(deg_to_rad(fov) / 2.0)
			var tall := absf((foot.y + h * k) / (d * t) - foot.y / (d * t))
			check(tall <= cap + 1e-3, "세로 길이 ≤ 상한 (fov %s d %s: %s)" % [fov, d, tall])
			if k < 1.0:
				check(span > cap * 0.98, "줄였으면 상한에 딱 (fov %s d %s: %s)" % [fov, d, span])
		check(BM.strike_cap(h, Vector3(0, -1.5, -40.0), Vector3.UP, fov) == 1.0, "멀면 그대로 (fov %s)" % fov)
		check(BM.strike_cap(h, Vector3(0, -1.5, -3.0), Vector3.UP, fov) < 1.0, "가까우면 줄임 (fov %s)" % fov)
		check(BM.strike_cap(h, Vector3(0, -1.5, 2.0), Vector3.UP, fov) == 0.0, "카메라 뒤 (fov %s)" % fov)
		check(BM.strike_cap(h, Vector3(0, -1.5, -0.01), Vector3.UP, fov) == 0.0, "발밑 (fov %s)" % fov)
	# 위에서 내려다봐도 (띠가 카메라 쪽으로 솟음) 상한 안
	var up := Vector3(0, 0.6, 0.8) # 카메라 공간에서 위 = 화면 위 + 카메라 쪽
	var k2 := BM.strike_cap(h, Vector3(0, -1.0, -9.0), up, C.FOV_DEFAULT)
	check(k2 > 0.0 and FM.plume_span(h * k2, w * k2, Vector3(0, -1.0, -9.0), up, C.FOV_DEFAULT, int(BM.STRIKE.cap_seg), float(BM.STRIKE.cap_near)) <= cap + 1e-3, "내려다볼 때: %s" % k2)


# 예고 목록: 더하기 (같은 id·빠진 값 무시) · 떨어지면 지우기 (모르는 id 는 그대로) · 예정 시각이 한참 지난 것 지우기 · 판 중이 아니면 비움
func test_bolt_warn_list() -> void:
	var list := []
	var e := {"type": "boltWarn", "id": 3.0, "x": 4.5, "y": 6.25, "z": 2.0, "r": 1.2, "ms": 1200.0} # JSON 숫자는 float
	check(BM.warn_add(list, e, 1000.0) and list.size() == 1, "더함")
	var w: Dictionary = list[0]
	check(w.id == 3 and w.x == 4.5 and w.y == 6.25 and w.z == 2.0 and w.r == 1.2 and w.t0 == 1000.0 and w.ms == 1200.0, "항목: %s" % str(w))
	check(not BM.warn_add(list, e, 1500.0) and list.size() == 1 and list[0].t0 == 1000.0, "같은 id 는 무시 (처음 것 그대로)")
	check(BM.warn_add(list, {"id": 4, "x": 1, "y": 2, "z": 0, "r": 1.2, "ms": 1200}, 1100.0) and list.size() == 2, "정수 값도")
	for bad in [{}, {"id": 5}, {"id": 5, "x": 1.0}, {"id": 5, "x": 1.0, "y": 1.0, "r": 1.2, "ms": 0.0}, {"id": 5, "x": 1.0, "y": 1.0, "r": 0.0, "ms": 1200.0}, {"id": null, "x": 1.0, "y": 1.0, "r": 1.2, "ms": 1200.0}]:
		check(not BM.warn_add(list, bad, 1100.0) and list.size() == 2, "빠진 값은 무시: %s" % str(bad))
	check(BM.warn_find(list, 4) == 1 and BM.warn_find(list, 99) == -1, "찾기")
	check(not BM.warn_remove(list, 99.0) and not BM.warn_remove(list, null) and list.size() == 2, "모르는 id 는 그대로")
	check(BM.warn_remove(list, 3.0) and list.size() == 1 and list[0].id == 4, "떨어진 예고를 지움")
	# 예정 시각 (t0 + ms) 뒤 grace_ms 까지는 남고, 그 뒤엔 지움
	var due := 1100.0 + 1200.0
	check(BM.warn_expire(list, due + float(BM.WARN.grace_ms)) == 0 and list.size() == 1, "여유 안")
	check(BM.warn_expire(list, due + float(BM.WARN.grace_ms) + 1.0) == 1 and list.is_empty(), "여유 뒤 지움")
	check(BM.warn_expire(list, 1e9) == 0, "빈 목록")
	check(BM.keep("playing") and not BM.keep("over") and not BM.keep("lobby") and not BM.keep("countdown") and not BM.keep(""), "판 중에만")
	check(int(BM.WARN.max) >= 4 and int(BM.STRIKE.max) >= 4, "8명 판 한 차례 (4개) 를 다 그림")


# ---------- c11-u1: 손 아이템 조준 미리보기 · 놓인 폭탄 고리 · '폭탄!' 화면 신호 (world/hand_aim_math.gd) ----------
func _c11_me(aim) -> Dictionary:
	return {"id": 2.0, "x": 5.5, "y": 2.5, "z": 0.0, "alive": true, "team": null, "aim": aim}


func _c11_rows(rows: Array, kind: String) -> Array:
	return rows.filter(func(r): return str(r.kind) == kind)


# 설치 블록: 놓일 2칸에 흰 상자 (칸 가운데) + 칸마다 노란 모서리 막대 12개, 못 놓는 자리면 전부 빨강
func test_c11_aim_brick_rows() -> void:
	var A: Dictionary = HM.HAND_AIM
	var aim := {"kind": "brick", "cells": [[5.0, 6.0, 1.0], [5.0, 7.0, 1.0]], "z": 1.0, "spawnZ": 4.0, "ok": true}
	for mode in ["first", "third"]:
		var rows := HM.aim_rows(_c11_me(aim), mode, false, 0x50c050)
		var boxes := _c11_rows(rows, "box")
		var edges := _c11_rows(rows, "edge")
		check(boxes.size() == 2 and edges.size() == 24 and rows.size() == 26, "%s: 상자 2 · 테 24 (얻음 %d · %d · 모두 %d)" % [mode, boxes.size(), edges.size(), rows.size()])
		check(boxes.size() == 2 and (boxes[0].at as Vector3).is_equal_approx(Vector3(5.5, 6.5, 1.5)) and (boxes[1].at as Vector3).is_equal_approx(Vector3(5.5, 7.5, 1.5)), "상자 자리 = 칸 + 0.5")
		for b in boxes:
			check(int(b.color) == 0xffffff and is_equal_approx(float(b.alpha), 0.28) and (b.size as Vector3).x < 1.0 and (b.size as Vector3).x > 0.95, "상자: 흰색 · 알파 0.28 · 칸보다 조금 작게 (%s %s %s)" % [b.color, b.alpha, b.size])
		for e in edges:
			var sz: Vector3 = e.size
			var d: Vector3 = (e.at as Vector3) - Vector3(5.5, 6.5 if (e.at as Vector3).y < 7.0 else 7.5, 1.5)
			check(int(e.color) == 0xf0d060 and is_equal_approx(sz[sz.max_axis_index()], 1.0) and is_equal_approx(sz[sz.min_axis_index()], 0.04), "테: 노랑 · 길이 1 · 굵기 0.04 (%s %s)" % [e.color, sz])
			check(absf(d.x) <= 0.5 and absf(d.y) <= 0.5 and absf(d.z) <= 0.5, "테 막대는 칸 안쪽에 붙음 (%s)" % d)
	check(int(A.edge_color) == 0xf0d060 and is_equal_approx(float(A.edge_w), 0.04) and is_equal_approx(float(A.box_alpha), 0.28), "표 값")
	# 못 놓는 자리 (떨어지는 블록이 있음·내 머리 위): 상자·테 전부 빨강
	var bad := aim.duplicate()
	bad["ok"] = false
	var rows_bad := HM.aim_rows(_c11_me(bad), "first", false, 0x50c050)
	check(rows_bad.size() == 26, "못 놓는 자리도 같은 수 (%d)" % rows_bad.size())
	for r in rows_bad:
		check(int(r.color) == 0xff2020, "못 놓는 자리: %s 색 %x" % [r.kind, int(r.color)])
	# 모서리 막대 12개: 축마다 넷, 서로 다른 자리
	var bars := HM.edge_bars(Vector3(0.5, 0.5, 0.5))
	var seen := {}
	for b in bars:
		seen[str(b[0])] = true
	check(bars.size() == 12 and seen.size() == 12, "막대 12개 (서로 다른 자리 %d)" % seen.size())
	# 양면 반투명 상자: 면 둘이 겹쳐 box_alpha
	var fa := HM.face_alpha(0.28)
	check(is_equal_approx(1.0 - (1.0 - fa) * (1.0 - fa), 0.28) and HM.face_alpha(0.0) == 0.0 and HM.face_alpha(1.0) == 1.0, "면 알파 %s" % fa)


# 폭탄: 부서질 9칸에 주황 납작 판 + 폭탄 자리 (첫 칸) 가운데에 사람이 맞는 반지름의 내 색 고리
func test_c11_aim_bomb_rows() -> void:
	var cells := [[5.0, 6.0, 0.0]]
	for dx in [-1, 0, 1]:
		for dy in [-1, 0, 1]:
			if dx != 0 or dy != 0:
				cells.append([5.0 + dx, 6.0 + dy, 0.0])
	var aim := {"kind": "bomb", "cells": cells, "ok": true}
	var rows := HM.aim_rows(_c11_me(aim), "first", false, 0x50c050)
	var pads := _c11_rows(rows, "pad")
	var rings := _c11_rows(rows, "ring")
	check(pads.size() == 9 and rings.size() == 1 and rows.size() == 10 and _c11_rows(rows, "edge").is_empty(), "판 9 · 고리 1 (얻음 %d · %d · 모두 %d)" % [pads.size(), rings.size(), rows.size()])
	for i in pads.size():
		var p: Dictionary = pads[i]
		var at: Vector3 = p.at
		var sz: Vector3 = p.size
		check(is_equal_approx(at.x, float(cells[i][0]) + 0.5) and is_equal_approx(at.y, float(cells[i][1]) + 0.5), "판 %d 자리 = 칸 + 0.5" % i)
		# 판은 얇게 (양면을 그려서 두꺼우면 비스듬히 볼 때 이웃 판과 겹친 띠가 줄무늬로 보임 — JS 판 0.12 보다 얇음)
		check(int(p.color) == 0xff5030 and is_equal_approx(float(p.alpha), 0.35) and is_equal_approx(sz.z, float(HM.HAND_AIM.pad_h)) and sz.z <= 0.05 and sz.x < 1.0 and sz.x > 0.9, "판: 주황 · 알파 0.35 · 얇음 (%x %s %s)" % [int(p.color), p.alpha, sz])
		check(at.z - sz.z / 2.0 > 0.0 and at.z + sz.z / 2.0 < 0.2, "판은 바닥 바로 위 (%s)" % at.z)
	if rings.size() == 1:
		var r: Dictionary = rings[0]
		var at: Vector3 = r.at
		check(is_equal_approx(float(r.r), float(C.BOMB_BLAST_RANGE)) and is_equal_approx(float(r.r), 2.0), "고리 반지름 = BOMB_BLAST_RANGE (%s)" % r.r)
		check(is_equal_approx(at.x, 5.5) and is_equal_approx(at.y, 6.5) and at.z > 0.0 and at.z < 0.1, "고리 가운데 = 첫 칸 + 0.5 (%s)" % at)
		check(int(r.color) == 0x50c050, "고리 = 내 색 (%x)" % int(r.color))
	# 못 놓는 자리: 판은 빨강
	var bad := aim.duplicate()
	bad["ok"] = false
	for p in _c11_rows(HM.aim_rows(_c11_me(bad), "third", false, 0x50c050), "pad"):
		check(int(p.color) == 0xff2020, "못 놓는 자리 판 색 %x" % int(p.color))
	# 필드 가장자리: 서버가 필드 밖 칸을 빼고 보냄 → 온 칸만
	var edge_aim := {"kind": "bomb", "cells": cells.slice(0, 6), "ok": true}
	check(_c11_rows(HM.aim_rows(_c11_me(edge_aim), "first", false, 0x50c050), "pad").size() == 6, "가장자리: 온 칸만")
	check(int(HM.HAND_AIM.priority) + 1 < 10, "그리는 순서는 이름표 외곽선 (10) 아래")


# 안 그리는 때: 죽음 · 하늘 시점 · 관전 · 조준 값 없음 (넉백 글러브·빈손) · 판 중이 아님 · 나 없음
func test_c11_aim_off() -> void:
	var aim := {"kind": "brick", "cells": [[5.0, 6.0, 0.0], [5.0, 7.0, 0.0]], "z": 0.0, "spawnZ": 3.0, "ok": true}
	var me := _c11_me(aim)
	check(HM.aim_on(me, "first", false) and HM.aim_on(me, "third", false), "1·3인칭: 켬")
	var dead := me.duplicate()
	dead["alive"] = false
	check(HM.aim_rows(dead, "first", false, 0).is_empty(), "죽음: 0줄")
	check(HM.aim_rows(me, "sky", false, 0).is_empty(), "하늘 시점: 0줄")
	check(HM.aim_rows(me, "spectate", false, 0).is_empty() and HM.aim_rows(me, "first", true, 0).is_empty(), "관전: 0줄")
	check(HM.aim_rows(_c11_me(null), "first", false, 0).is_empty(), "조준 값 null (넉백 글러브): 0줄")
	var no_aim := me.duplicate()
	no_aim.erase("aim")
	check(HM.aim_rows(no_aim, "first", false, 0).is_empty(), "조준 값 없음: 0줄")
	check(HM.aim_rows(_c11_me({"kind": "brick", "cells": [], "z": 0.0, "ok": false}), "first", false, 0).is_empty(), "칸 없음 (조준이 필드 밖): 0줄")
	check(HM.aim_rows(me, "first", false, 0, false).is_empty(), "판 중이 아님: 0줄")
	check(HM.aim_rows({}, "first", false, 0).is_empty(), "나 없음: 0줄")


# c11-fix F1 (나): 3인칭 조준 고리는 가는 선 꼴 ("aim") — 예전 windup (띠 폭 = 반지름의 24% = 0.48칸, 흰 심 + 색 띠) 은 바로 옆의 내 발밑 고리·스킬 준비 고리와 같은 꼴이라 크기·자리로만 갈렸음.
# 1인칭은 예전 그대로 (windup). 놓인 폭탄의 끊긴 흰 고리와도 모양으로 갈림 (이어진 내 색 선 · 흰 심 없음)
func test_c11_fix_aim_ring_look() -> void:
	var aim := {"kind": "bomb", "cells": [[5.0, 6.0, 0.0], [4.0, 6.0, 0.0]], "ok": true}
	var first := _c11_rows(HM.aim_rows(_c11_me(aim), "first", false, 0x50c050), "ring")
	var third := _c11_rows(HM.aim_rows(_c11_me(aim), "third", false, 0x50c050), "ring")
	check(first.size() == 1 and str(first[0].look) == "windup", "1인칭: 예전 고리 꼴 그대로 (%s)" % [first])
	check(third.size() == 1 and str(third[0].look) == "aim" and HM.ring_look("third") == "aim" and HM.ring_look("first") == "windup" and HM.ring_look("zzz") == "windup", "3인칭: 가는 선 꼴 (%s)" % [third])
	check(is_equal_approx(float(third[0].r), float(first[0].r)) and (third[0].at as Vector3).is_equal_approx(first[0].at) and int(third[0].color) == 0x50c050, "자리·반지름·색은 같음")
	var L: Dictionary = RL.LOOKS["aim"]
	var paints := []
	for b in L.bands:
		paints.append(str(b[2]))
		paints.append(str(b[3]))
	check(not paints.has("core") and paints.has("tint") and paints.has("ink"), "가는 선: 내 색 + 잉크 테, 흰 심 없음 (%s)" % [paints])
	check(is_equal_approx(float((L.bands as Array).back()[1]), 1.0), "바깥 끝 = 반지름 1 (맞는 범위 그대로)")
	var w_aim: float = RL.band_frac("aim") * float(C.BOMB_BLAST_RANGE)
	var w_old: float = RL.band_frac("windup") * float(C.BOMB_BLAST_RANGE)
	check(w_aim <= 0.16 and w_aim >= 0.08 and w_aim <= w_old / 3.0, "선 폭 %.2f칸 (0.08 ~ 0.16, 예전 %.2f칸의 1/3 이하)" % [w_aim, w_old])
	# 꼴 (띠 폭 ÷ 반지름) 이 발밑 고리 (1 − inner = 28%) 의 1/3 이하 — 비율이 같으면 큰 발밑 고리로 읽힘
	var foot: Dictionary = preload("res://world/world_config.gd").FOOT_RING
	check(RL.band_frac("aim") <= (1.0 - float(foot.inner)) / 3.0, "띠 폭 비 %.2f 가 발밑 고리 (%.2f) 의 1/3 이하" % [RL.band_frac("aim"), 1.0 - float(foot.inner)])
	var m: ArrayMesh = RL.mesh("aim", 0x50c050)
	check(m != null and m.get_surface_count() == 1 and m == RL.mesh("aim", 0x50c050) and m != RL.mesh("windup", 0x50c050), "메시: 표면 하나 · 색마다 한 번 · windup 과 다른 메시")


# c11-fix F1 (가): 3인칭에서 폭탄 조준 판·고리를 몸 너머로 한 벌 더 옅게 (깊이 검사 없는 재질). 1인칭·설치 블록은 안 그림, 몸 뒤 부분 알파는 원래의 절반 이하
func test_c11_fix_aim_xray() -> void:
	check(HM.aim_xray("third", "bomb") and not HM.aim_xray("first", "bomb") and not HM.aim_xray("third", "brick") and not HM.aim_xray("sky", "bomb") and not HM.aim_xray("spectate", "bomb"), "3인칭의 폭탄 조준만")
	var k := float(HM.HAND_AIM.xray)
	check(k > 0.0 and k <= 0.5 and is_equal_approx(HM.xray_alpha(0.8), 0.8 * k), "몸 뒤 부분 = 원래 알파 × %.2f (절반 이하)" % k)
	# 판: 양면이라 면 둘을 지남 — 몸 뒤 부분의 합친 알파가 원래 (pad_alpha) 의 절반 이하, 그래도 0.1 은 넘음 (보임)
	var fa := HM.face_alpha(float(HM.HAND_AIM.pad_alpha))
	var behind := 1.0 - (1.0 - fa * k) * (1.0 - fa * k)
	check(behind <= float(HM.HAND_AIM.pad_alpha) * 0.5 and behind >= 0.1, "판 몸 뒤 알파 %.3f (원래 %.2f 의 절반 이하, 0.1 이상)" % [behind, HM.HAND_AIM.pad_alpha])
	# 몸에 안 가린 부분 = 원래 + 한 벌 더: 화풍 기준서 반투명 상한 0.55 안
	var front := 1.0 - (1.0 - float(HM.HAND_AIM.pad_alpha)) * (1.0 - behind)
	check(front <= 0.55, "판 앞 부분 합친 알파 %.3f ≤ 0.55" % front)
	check(HM.xray_alpha(float(HM.HAND_AIM.ring_alpha)) <= float(HM.HAND_AIM.ring_alpha) * 0.5, "고리 몸 뒤 알파 %.2f (원래 %.2f 의 절반 이하)" % [HM.xray_alpha(float(HM.HAND_AIM.ring_alpha)), HM.HAND_AIM.ring_alpha])
	# 재질: 고리 재질에서 깊이 검사만 끔 — 그 모양이 미리 그리기 표 안 (처음 쓸 때 셰이더를 안 만듦)
	const WS := preload("res://world/warm_scan.gd")
	const MF := preload("res://core/mat_first.gd")
	var xm: StandardMaterial3D = RL.xray_material(0.4, 7)
	var nm: StandardMaterial3D = RL.material(0.4, 7)
	check(xm.no_depth_test and not nm.no_depth_test and is_equal_approx(xm.albedo_color.a, 0.4) and xm.render_priority == 7, "깊이 검사 끔 · 알파·순서는 넣은 값")
	check(MF.mat_key(xm) == MF.mat_key(nm).replace("dt0", "dt1"), "고리 재질과 깊이 검사만 다름: %s" % MF.mat_key(xm))
	var have := []
	for key in WS.STD_KEYS:
		have.append(MF.mat_key(WS.std_material(key)))
	check(have.has(MF.mat_key(xm)) and WS.STD_KEYS.has([0, 1, 0, 2, 1, 0, 1, 0, 0, 0, 2]), "몸 너머 재질 모양이 미리 그리기 표 안")
	check(have.has(MF.mat_key(nm)), "원래 고리 재질 모양도 그대로 표 안")
	# 노드 (트리 밖에서 _ready 를 직접): 3인칭 폭탄 → 한 벌 더 보임 (판 묶음을 같이 씀·고리 메시 같음), 1인칭·설치 블록 → 숨김
	var ha = load("res://world/hand_aim.gd").new()
	ha._ready()
	var cells := [[5.0, 6.0, 0.0]]
	for dx in [-1, 0, 1]:
		for dy in [-1, 0, 1]:
			if dx != 0 or dy != 0:
				cells.append([5.0 + dx, 6.0 + dy, 0.0])
	var me := _c11_me({"kind": "bomb", "cells": cells, "ok": true})
	me["color"] = 0
	me["slot"] = 0
	var st := {"phase": "playing", "teamMode": false, "players": [me], "bombs": []}
	ha.update(st, me, "third", false, 1000.0)
	check(ha.box_mmi.visible and ha.box_mm.visible_instance_count == 9 and ha.ring.visible, "3인칭: 판 9 · 고리")
	check(ha.xray_mmi.visible and ha.ring_xray.visible and ha.xray_mmi.multimesh == ha.box_mm and ha.ring_xray.mesh == ha.ring.mesh, "3인칭: 몸 너머 한 벌 (같은 판 묶음·같은 고리 메시)")
	check(ha.ring_xray.transform.is_equal_approx(ha.ring.transform) and ha.ring_kind == "aim", "몸 너머 고리 자리 = 고리 자리 · 가는 선 꼴")
	check((ha.xray_mmi.material_override as StandardMaterial3D).no_depth_test and (ha.ring_xray.material_override as StandardMaterial3D).no_depth_test and not (ha.box_mmi.material_override as StandardMaterial3D).no_depth_test and not (ha.ring.material_override as StandardMaterial3D).no_depth_test, "한 벌 더만 깊이 검사 끔")
	check(is_equal_approx((ha.xray_mmi.material_override as StandardMaterial3D).albedo_color.a, k) and is_equal_approx((ha.ring_xray.material_override as StandardMaterial3D).albedo_color.a, float(HM.HAND_AIM.ring_alpha) * k), "한 벌 더의 알파 = 원래 × xray")
	ha.update(st, me, "first", false, 1033.0)
	check(ha.box_mmi.visible and ha.ring.visible and not ha.xray_mmi.visible and not ha.ring_xray.visible and ha.ring_kind == "windup", "1인칭: 예전 그대로 (한 벌 더 없음 · 예전 고리 꼴)")
	var brick := _c11_me({"kind": "brick", "cells": [[5.0, 6.0, 0.0], [5.0, 7.0, 0.0]], "z": 0.0, "spawnZ": 3.0, "ok": true})
	brick["color"] = 0
	brick["slot"] = 0
	ha.update(st, brick, "third", false, 1066.0)
	check(ha.box_mmi.visible and ha.edge_mmi.visible and not ha.xray_mmi.visible and not ha.ring_xray.visible and not ha.ring.visible, "3인칭 설치 블록: 한 벌 더 없음")
	ha.update(st, me, "third", false, 1100.0)
	check(ha.xray_mmi.visible, "다시 폭탄: 켜짐")
	ha.update(st, _c11_me(null), "third", false, 1133.0)
	check(not ha.box_mmi.visible and not ha.xray_mmi.visible and not ha.ring_xray.visible and not ha.ring.visible, "든 것이 없어지면 다 숨김 (그리기 0)")
	ha.free()


# 놓인 폭탄 고리: 채운 원은 놓은 순간 0 → 터지는 순간 1 (고리 안쪽 끝), 고리 반지름 = 사람이 맞는 범위, 자리 = 칸 가운데·칸 바닥 바로 위
func test_c11_bomb_ring_fill() -> void:
	check(is_equal_approx(float(C.BOMB_FUSE_MS), 1500.0), "도화선 %s" % C.BOMB_FUSE_MS)
	check(HM.bomb_fill(1500.0) == 0.0 and is_equal_approx(HM.bomb_fill(750.0), 0.5) and HM.bomb_fill(0.0) == 1.0, "찬 비율: %s %s %s" % [HM.bomb_fill(1500.0), HM.bomb_fill(750.0), HM.bomb_fill(0.0)])
	check(HM.bomb_fill(9999.0) == 0.0 and HM.bomb_fill(-5.0) == 1.0, "범위 밖 값은 0~1 로")
	var bombs := [{"id": 3.0, "x": 4.0, "y": 7.0, "z": 2.0, "left": 750.0}, {"id": 4.0, "x": 9.0, "y": 1.0, "z": 0.0, "left": 0.0}]
	var rows := HM.bomb_ring_rows(bombs, 2000.0)
	check(rows.size() == 2, "폭탄마다 한 줄 (%d)" % rows.size())
	if rows.size() == 2:
		var inner := float(BM.WARN.bands[0][0])
		var at: Vector3 = rows[0].at
		check(is_equal_approx(at.x, 4.5) and is_equal_approx(at.y, 7.5) and is_equal_approx(at.z, 2.0 + float(HM.BOMB_RING.lift)) and is_equal_approx(float(HM.BOMB_RING.lift), 0.04), "자리 %s" % at)
		check(is_equal_approx(float(rows[0].r), float(C.BOMB_BLAST_RANGE)), "고리 반지름 %s" % rows[0].r)
		check(is_equal_approx(float(rows[0].fill_r), 2.0 * inner * 0.5) and is_equal_approx(float(rows[1].fill_r), 2.0 * inner), "채운 원 반지름: 반 %s · 다 참 %s (고리 안쪽 끝 %s)" % [rows[0].fill_r, rows[1].fill_r, 2.0 * inner])
		check(is_equal_approx(float(rows[0].spin), float(HM.BOMB_RING.spin) * 2.0), "고리는 판 시계로 돎 (%s)" % rows[0].spin)
	check(HM.bomb_ring_rows(bombs, 2000.0, false).is_empty() and HM.bomb_ring_rows([], 2000.0).is_empty(), "판 중이 아니거나 폭탄이 없으면 0줄")
	var many := []
	for i in 20:
		many.append({"id": float(i), "x": float(i), "y": 0.0, "z": 0.0, "left": 100.0})
	check(HM.bomb_ring_rows(many, 0.0).size() == int(HM.BOMB_RING.max), "한 번에 그리는 수 상한")
	check(int(HM.BOMB_RING.fill) == 0xff8a30 and int(HM.BOMB_RING.fill) != int(BM.WARN.fill_color) and is_equal_approx(float(HM.BOMB_RING.fill_alpha), 0.4) and is_equal_approx(float(HM.BOMB_RING.ring_alpha), 0.9), "채운 원은 주황 (번개 연노랑과 다름)")


# 맞는 자리 판정 = 서버 Game.ExplodeBomb: 폭탄 칸 가운데에서 수평 2.0 안, 몸 가운데 높이 차 2.0 안
func test_c11_bomb_alert_range() -> void:
	var b := {"id": 1.0, "x": 5.0, "y": 5.0, "z": 0.0, "left": 900.0} # 가운데 (5.5, 5.5, 0.5)
	var half := float(C.PLAYER_HEIGHT) / 2.0
	var me := {"id": 2.0, "x": 5.5 + 2.0, "y": 5.5, "z": 0.5 - half, "alive": true}
	check(HM.bomb_in_range(me, b), "수평 2.0: 안")
	me["x"] = 5.5 + 2.01
	check(not HM.bomb_in_range(me, b), "수평 2.01: 밖")
	me["x"] = 5.5 + 1.2
	me["y"] = 5.5 + 1.6 # 빗변 2.0
	check(HM.bomb_in_range(me, b), "빗변 2.0: 안")
	me["y"] = 5.5 + 1.62
	check(not HM.bomb_in_range(me, b), "빗변이 넘으면 밖")
	me = {"id": 2.0, "x": 5.5, "y": 5.5, "z": 0.5 - half + 2.0, "alive": true}
	check(HM.bomb_in_range(me, b), "높이 차 2.0 (위): 안")
	me["z"] = 0.5 - half + 2.01
	check(not HM.bomb_in_range(me, b), "높이 차 2.01 (위): 밖")
	me["z"] = 0.5 - half - 2.0
	check(HM.bomb_in_range(me, b), "높이 차 2.0 (아래): 안")
	me["z"] = 0.5 - half - 2.01
	check(not HM.bomb_in_range(me, b), "높이 차 2.01 (아래): 밖")
	# 살아서 필드에 있을 때만
	me = {"id": 2.0, "x": 5.5, "y": 5.5, "z": 0.0, "alive": false}
	check(not HM.bomb_in_range(me, b), "죽은 나")
	check(not HM.bomb_in_range({"id": 2.0, "x": 5.5, "y": 5.5, "z": 0.0, "alive": true, "master": true}, b), "블록 마스터")
	check(not HM.bomb_in_range({}, b) and not HM.bomb_in_range({"alive": true}, b), "나 없음·자리 없음")


# 내 폭탄·같은 팀 폭탄은 뺌 (서버가 안 맞게 함), 주인을 모르는 폭탄은 위험. 주인은 bombPlace 의 칸으로 짝지어 폭탄 id 에 붙임
func test_c11_bomb_alert_skips_mine_team() -> void:
	var me := {"id": 2.0, "x": 5.5, "y": 5.5, "z": 0.0, "alive": true, "team": "red"}
	var st := {"teamMode": false, "players": [me, {"id": 3.0, "team": "red"}, {"id": 4.0, "team": "blue"}]}
	var team_st := st.duplicate()
	team_st["teamMode"] = true
	var bomb := {"id": 7.0, "x": 5.0, "y": 6.0, "z": 0.0, "left": 900.0}
	check(HM.owner_key(5.0, 6.0) == "5,6" and HM.owner_key(5, 6) == HM.owner_key(5.0, 6.0), "열쇠 (x·y 만) %s" % HM.owner_key(5.0, 6.0))
	# [주인, 팀전, 위험한가]
	for row in [[2.0, false, false], [3.0, false, true], [3.0, true, false], [4.0, true, true], [4.0, false, true], [9.0, true, true]]:
		var pending := []
		var owners := {}
		HM.owner_note(pending, {"type": "bombPlace", "who": row[0], "x": 5.0, "y": 6.0, "z": 0.0}, 1000.0)
		HM.owner_bind(owners, pending, [bomb], 1000.0)
		check(owners.get(7) == int(row[0]) and pending.is_empty(), "주인 붙음: %s" % [owners])
		var pick := HM.bomb_pick([bomb], owners, me, team_st if row[1] else st)
		check(pick.is_empty() != bool(row[2]), "주인 %s 팀전 %s → 위험 %s (얻음 %s)" % [row[0], row[1], row[2], pick])
	# 주인 모름 (판 중에 들어와 이벤트를 못 받음): 위험
	check(not HM.bomb_pick([bomb], {}, me, st).is_empty() and not HM.bomb_safe(null, me, team_st), "주인 모름 = 위험")
	# 다른 칸의 기억은 안 붙음, 같은 칸 둘은 온 차례대로
	var pending := []
	var owners := {}
	HM.owner_note(pending, {"type": "bombPlace", "who": 2.0, "x": 1.0, "y": 1.0, "z": 0.0}, 1000.0)
	HM.owner_bind(owners, pending, [bomb], 1000.0)
	check(owners.is_empty() and pending.size() == 1, "다른 칸: 안 붙음")
	HM.owner_note(pending, {"type": "bombPlace", "who": 4.0, "x": 5.0, "y": 6.0, "z": 0.0}, 1000.0)
	HM.owner_note(pending, {"type": "bombPlace", "who": 2.0, "x": 5.0, "y": 6.0, "z": 0.0}, 1000.0)
	var twin := {"id": 8.0, "x": 5.0, "y": 6.0, "z": 0.0, "left": 1400.0}
	HM.owner_bind(owners, pending, [bomb, twin], 1000.0)
	check(owners.get(7) == 4 and owners.get(8) == 2, "같은 칸 둘: %s" % [owners])
	# 붙은 뒤엔 높이가 바뀌어도 (발밑 블록이 부서짐·쌓임) 그대로, 없어진 폭탄은 지움
	var moved := twin.duplicate()
	moved["z"] = 3.0
	HM.owner_bind(owners, pending, [moved], 1000.0)
	check(owners.get(8) == 2 and not owners.has(7), "높이가 바뀐 내 폭탄은 그대로 내 것 · 터진 폭탄은 지움: %s" % [owners])
	HM.owner_note(pending, {"type": "bombPlace", "who": null, "x": 1.0, "y": 1.0, "z": 0.0}, 1000.0)
	check(pending.size() == 1, "값이 빠진 이벤트는 무시")
	for i in 40:
		HM.owner_note(pending, {"type": "bombPlace", "who": 1.0, "x": float(i), "y": 0.0, "z": 0.0}, 1000.0)
	check(pending.size() == int(HM.BOMB_ALERT.pending_max), "기억 수 상한 (%d)" % pending.size())


# c11-fix F2: 주인 짝짓기는 x·y 칸으로만 — 서버는 bombPlace 를 낸 뒤 같은 틱에 폭탄 높이를 기둥 꼭대기로 다시 맞춤 (Game.Items.cs UpdateBombs) → 이벤트 z 와 첫 스냅샷 z 가 다를 수 있음.
# 예전 (z 까지 넣은 열쇠) 엔 이때 내 폭탄이 주인 없는 폭탄이 돼 '폭탄!' 판이 떴음
func test_c11_fix_owner_ignores_z() -> void:
	var me := {"id": 1.0, "x": 5.5, "y": 5.5, "z": 3.0, "alive": true, "team": null}
	var st := {"teamMode": false, "players": [me]}
	var pending := []
	var owners := {}
	HM.owner_note(pending, {"type": "bombPlace", "who": 1.0, "x": 5.0, "y": 5.0, "z": 4.0}, 1000.0) # 이벤트 z = 4
	var bombs := [{"id": 2.0, "x": 5.0, "y": 5.0, "z": 3.0, "left": 1466.0}] # 첫 스냅샷 z = 3 (같은 틱에 앞 폭탄이 터져 기둥이 낮아짐)
	HM.owner_bind(owners, pending, bombs, 1033.0)
	check(owners.get(2) == 1 and pending.is_empty(), "높이가 어긋나도 내 폭탄으로 짝지음: %s (남은 기억 %d)" % [owners, pending.size()])
	check(HM.bomb_pick(bombs, owners, me, st).is_empty(), "내 폭탄: 판 안 뜸 (얻음 %s)" % [HM.bomb_pick(bombs, owners, me, st)])
	# z 값이 아예 없는 이벤트도 받음 (열쇠에 안 쓰임), x·y 가 다르면 안 붙음
	HM.owner_note(pending, {"type": "bombPlace", "who": 1.0, "x": 7.0, "y": 5.0}, 1100.0)
	HM.owner_bind(owners, pending, bombs + [{"id": 3.0, "x": 7.0, "y": 6.0, "z": 0.0, "left": 1400.0}], 1133.0)
	check(not owners.has(3) and pending.size() == 1, "다른 칸: 안 붙음 %s" % [owners])


# c11-fix F2: 도화선 시간 (C.BOMB_FUSE_MS) 이 지난 기억은 버림 — 남으면 나중에 같은 칸에 놓인 남의 폭탄에 붙어 그 폭탄의 경고가 빠짐
func test_c11_fix_owner_expires() -> void:
	var fuse := float(C.BOMB_FUSE_MS)
	var me := {"id": 1.0, "x": 5.5, "y": 5.5, "z": 0.0, "alive": true, "team": null}
	var st := {"teamMode": false, "players": [me]}
	var pending := []
	var owners := {}
	HM.owner_note(pending, {"type": "bombPlace", "who": 1.0, "x": 5.0, "y": 5.0, "z": 0.0}, 1000.0) # 내 폭탄의 기억 — 스냅샷에 한 번도 안 잡힘 (짝 못 지음)
	HM.owner_bind(owners, pending, [], 1000.0 + fuse) # 딱 도화선 시간: 아직 남음
	check(pending.size() == 1, "도화선 시간까지는 남음 (%d)" % pending.size())
	var later := [{"id": 9.0, "x": 5.0, "y": 5.0, "z": 0.0, "left": 1400.0}] # 한참 뒤 같은 칸에 남 (이벤트를 못 받은) 의 폭탄
	HM.owner_bind(owners, pending, later, 1000.0 + fuse + 1.0)
	check(pending.is_empty() and not owners.has(9), "오래된 기억은 버림 — 남의 폭탄에 안 붙음: %s (남은 기억 %d)" % [owners, pending.size()])
	check(not HM.bomb_pick(later, owners, me, st).is_empty(), "그 폭탄은 위험으로 침 (판 뜸)")
	# owner_expire 만: 새 기억은 남기고 오래된 것만
	var mix := []
	HM.owner_note(mix, {"type": "bombPlace", "who": 2.0, "x": 1.0, "y": 1.0, "z": 0.0}, 0.0)
	HM.owner_note(mix, {"type": "bombPlace", "who": 3.0, "x": 2.0, "y": 1.0, "z": 0.0}, 900.0)
	HM.owner_note(mix, {"type": "bombPlace", "who": 4.0, "x": 3.0, "y": 1.0, "z": 0.0}, 100.0)
	HM.owner_expire(mix, fuse + 500.0)
	check(mix.size() == 1 and int(mix[0].who) == 3, "오래된 둘만 버림: %s" % [mix])
	# 화면 신호 노드도 같은 길: 오래된 내 기억 뒤 같은 칸 남의 폭탄 → 판이 뜸
	var a = load("res://ui/bomb_alert.gd").new()
	a.on_event({"type": "bombPlace", "who": 1.0, "x": 5.0, "y": 5.0, "z": 0.0}, 1000.0)
	a.refresh({"phase": "playing", "teamMode": false, "players": [me], "bombs": later}, me, 1000.0 + fuse + 50.0, true)
	check(a.plate.visible and a.pending.is_empty() and a.owners.is_empty(), "노드: 오래된 기억을 버리고 판을 띄움 (주인 %s)" % [a.owners])
	a.free()


# c11-fix F2: 같은 x·y 칸에 폭탄 둘 (높이가 달라도) → 기억이 온 차례대로 폭탄 차례에 붙음
func test_c11_fix_owner_same_cell_order() -> void:
	var pending := []
	var owners := {}
	HM.owner_note(pending, {"type": "bombPlace", "who": 4.0, "x": 5.0, "y": 6.0, "z": 0.0}, 1000.0)
	HM.owner_note(pending, {"type": "bombPlace", "who": 2.0, "x": 5.0, "y": 6.0, "z": 1.0}, 1200.0)
	var first := {"id": 7.0, "x": 5.0, "y": 6.0, "z": 2.0, "left": 1300.0}
	var second := {"id": 8.0, "x": 5.0, "y": 6.0, "z": 0.0, "left": 1500.0}
	HM.owner_bind(owners, pending, [first, second], 1233.0)
	check(owners.get(7) == 4 and owners.get(8) == 2 and pending.is_empty(), "한 스냅샷에 둘: 온 차례대로 %s" % [owners])
	# 스냅샷이 하나씩 와도 같음 (먼저 온 기억이 먼저 놓인 폭탄에)
	owners.clear()
	HM.owner_note(pending, {"type": "bombPlace", "who": 4.0, "x": 5.0, "y": 6.0, "z": 0.0}, 2000.0)
	HM.owner_bind(owners, pending, [first], 2033.0)
	HM.owner_note(pending, {"type": "bombPlace", "who": 2.0, "x": 5.0, "y": 6.0, "z": 1.0}, 2200.0)
	HM.owner_bind(owners, pending, [first, second], 2233.0)
	check(owners.get(7) == 4 and owners.get(8) == 2, "하나씩: %s" % [owners])
	var me := {"id": 2.0, "x": 5.5, "y": 5.5, "z": 0.0, "alive": true, "team": null}
	var pick := HM.bomb_pick([first, second], owners, me, {"teamMode": false, "players": [me]})
	check(not pick.is_empty() and is_equal_approx(float(pick.left), 1300.0), "남 (4) 의 폭탄만 위험: %s" % [pick])


# 여러 개면 가장 먼저 터질 것
func test_c11_bomb_alert_pick_soonest() -> void:
	var me := {"id": 2.0, "x": 5.5, "y": 5.5, "z": 0.0, "alive": true, "team": null}
	var st := {"teamMode": false, "players": [me]}
	var bombs := [
		{"id": 1.0, "x": 5.0, "y": 6.0, "z": 0.0, "left": 1200.0},
		{"id": 2.0, "x": 6.0, "y": 5.0, "z": 0.0, "left": 400.0},
		{"id": 3.0, "x": 12.0, "y": 5.0, "z": 0.0, "left": 100.0}, # 범위 밖
		{"id": 4.0, "x": 5.0, "y": 5.0, "z": 0.0, "left": 50.0}, # 내 폭탄
	]
	var pick := HM.bomb_pick(bombs, {4: 2}, me, st)
	check(not pick.is_empty() and is_equal_approx(float(pick.left), 400.0) and is_equal_approx(float(pick.ms), float(C.BOMB_FUSE_MS)), "가장 먼저 터질 남의 폭탄: %s" % [pick])
	check(BM.alert_sec(float(pick.get("left", 0.0))) == "0.4초", "초 글자")
	var away := me.duplicate()
	away["x"] = 9.0
	check(HM.bomb_pick(bombs, {4: 2}, away, st).is_empty(), "범위 밖으로 나가면 없음")
	check(HM.bomb_pick([], {}, me, st).is_empty(), "폭탄 없음")
	check(str(HM.BOMB_ALERT.text) == "폭탄! 고리 밖으로" and int(HM.BOMB_ALERT.glow) == 0xff8a30 and int(HM.BOMB_ALERT.glow) != int(BM.ALERT.glow), "글·색: 번개 판과 다름")


# c11-fix F8: 빠질 방향 (화면 기준) — 폭탄 가운데 → 나 방향을 카메라가 보는 쪽으로 돌림. 화면 좌표: x 오른쪽 +, y 아래 + (앞 = 위)
func test_c11_fix_escape_dir() -> void:
	var up := Vector2(0, -1)
	var down := Vector2(0, 1)
	var left := Vector2(-1, 0)
	var right := Vector2(1, 0)
	# 내가 +y 를 봄 (yaw 90° — 오른쪽 = +x): [폭탄 가운데 x, y, 화살표]
	var me := {"id": 2.0, "x": 5.5, "y": 5.5, "z": 0.0, "alive": true}
	for row in [[4.5, 5.5, right, "폭탄이 왼쪽 → 오른쪽으로"], [6.5, 5.5, left, "폭탄이 오른쪽 → 왼쪽으로"], [5.5, 4.5, up, "폭탄이 뒤 → 앞으로"], [5.5, 6.5, down, "폭탄이 앞 → 뒤로"]]:
		var d = HM.escape_dir(me, float(row[0]), float(row[1]), PI / 2.0)
		check(d != null and (d as Vector2).is_equal_approx(row[2]), "%s (얻음 %s)" % [row[3], d])
	# 같은 폭탄 (내 −x 쪽) 도 내가 보는 쪽에 따라 화면 방향이 바뀜: +x 를 보면 뒤에 있음 → 앞으로, −x 를 보면 앞 → 뒤로, −y 를 보면 오른쪽 → 왼쪽으로
	for row in [[0.0, up], [PI, down], [-PI / 2.0, left], [PI / 2.0, right]]:
		var d = HM.escape_dir(me, 4.5, 5.5, float(row[0]))
		check(d != null and (d as Vector2).is_equal_approx(row[1]), "yaw %.2f: %s (얻음 %s)" % [row[0], row[1], d])
	# 비스듬히: 단위 벡터
	var diag = HM.escape_dir(me, 4.5, 4.5, PI / 2.0)
	check(diag != null and is_equal_approx((diag as Vector2).length(), 1.0) and (diag as Vector2).x > 0.0 and (diag as Vector2).y < 0.0, "왼쪽 뒤 폭탄 → 오른쪽 앞 (%s)" % [diag])
	# 겹침 (수평 거리 < arrow_min): 방향이 안 정해짐 → null (화살표 숨김). 높이 차는 안 봄
	var near_me := float(HM.BOMB_ALERT.arrow_min)
	check(HM.escape_dir(me, 5.5, 5.5, 0.0) == null and HM.escape_dir(me, 5.5 + near_me * 0.9, 5.5, 0.0) == null, "폭탄과 겹쳐 섬: 화살표 없음")
	check(HM.escape_dir(me, 5.5 + near_me * 1.1, 5.5, 0.0) != null, "arrow_min 을 넘으면 그림")
	check(HM.escape_dir({}, 4.5, 5.5, 0.0) == null and HM.escape_dir({"alive": true}, 4.5, 5.5, 0.0) == null, "내 자리 없음: null")
	check(near_me > 0.0 and near_me <= 0.5, "겹침 문턱 %s (반 칸 이하)" % near_me)
	# bomb_pick 이 가장 급한 폭탄의 가운데를 돌려줌
	var st := {"teamMode": false, "players": [me]}
	var pick := HM.bomb_pick([{"id": 1.0, "x": 6.0, "y": 5.0, "z": 0.0, "left": 1200.0}, {"id": 2.0, "x": 4.0, "y": 5.0, "z": 0.0, "left": 400.0}], {}, me, st)
	check(is_equal_approx(float(pick.get("x", -1.0)), 4.5) and is_equal_approx(float(pick.get("y", -1.0)), 5.5) and is_equal_approx(float(pick.left), 400.0), "가장 급한 폭탄의 칸 가운데: %s" % [pick])
	# 화살표 도형: 끝 (가장 먼 꼭짓점) 이 가리키는 쪽, 칸 (한 변 arrow_px) 안
	var px := float(HM.BOMB_ALERT.arrow_px)
	var c := Vector2(px, px) / 2.0
	for dir in [right, left, up, down, Vector2(1, -1).normalized()]:
		var pts: PackedVector2Array = HM.arrow_points(dir, px, c)
		var tip := c
		var inside := true
		for q in pts:
			if (q - c).length() > (tip - c).length():
				tip = q
			inside = inside and (q - c).length() <= px * 0.5 + 0.01
		check(pts.size() == (HM.BOMB_ALERT.arrow as Array).size() and pts.size() >= 3 and inside, "도형 %s: 꼭짓점 %d 개, 칸 안" % [dir, pts.size()])
		check((tip - c).normalized().is_equal_approx(dir) and (tip - c).length() >= px * 0.4, "도형 끝이 %s 쪽 (얻음 %s)" % [dir, (tip - c).normalized()])
	check(px >= 24.0 and px <= 36.0, "화살표 칸 %spx (글 높이 안팎)" % px)


# c11-fix F8: 화면 신호 노드 (트리 밖 — 카메라 대신 스냅샷의 내 yaw·hold_yaw): 판이 뜨면 화살표 방향이 정해지고, 폭탄과 겹치면 비움, 판 폭은 화살표가 있든 없든 같음
func test_c11_fix_alert_arrow_node() -> void:
	var a = load("res://ui/bomb_alert.gd").new()
	var me := {"id": 2.0, "x": 5.5, "y": 5.5, "z": 0.0, "yaw": PI / 2.0, "alive": true, "team": null}
	var st := {"phase": "playing", "teamMode": false, "players": [me], "bombs": [{"id": 7.0, "x": 6.0, "y": 5.0, "z": 0.0, "left": 900.0}]}
	check(a.arrow != null and a.arrow.get_parent() == a.text.get_parent() and a.arrow.get_index() == a.text.get_index() + 1 and a.sec.get_index() == a.arrow.get_index() + 1, "화살표 칸: 글과 남은 초 사이")
	check(a.arrow.custom_minimum_size.is_equal_approx(Vector2.ONE * float(HM.BOMB_ALERT.arrow_px)) and a.arrow_dir == null, "칸 크기 고정 · 처음엔 방향 없음")
	a.refresh(st, me, 1000.0, true, "first", false)
	check(a.plate.visible and a.arrow_dir != null and (a.arrow_dir as Vector2).is_equal_approx(Vector2(-1, 0)), "폭탄이 오른쪽 (+x, 내가 +y 를 봄) → 왼쪽 화살표 (%s)" % [a.arrow_dir])
	var w0: float = a.plate.get_combined_minimum_size().x
	a.hold_yaw = 0.0 # 카메라가 +x 를 봄: 폭탄이 앞 → 뒤로
	a.refresh(st, me, 1033.0, true, "third", false)
	check((a.arrow_dir as Vector2).is_equal_approx(Vector2(0, 1)), "카메라가 폭탄 쪽을 봄 → 뒤로 (%s)" % [a.arrow_dir])
	a.hold_yaw = null
	var on_it := me.duplicate()
	on_it["x"] = 6.5
	on_it["y"] = 5.5
	a.refresh(st, on_it, 1066.0, true, "first", false)
	check(a.plate.visible and a.arrow_dir == null, "폭탄과 겹쳐 섬: 판은 뜨고 화살표만 비움")
	check(is_equal_approx(a.plate.get_combined_minimum_size().x, w0), "화살표가 없어도 판 폭 그대로 (%.0f → %.0f)" % [w0, a.plate.get_combined_minimum_size().x])
	# 판이 960×540 에도 들어가는 폭 (가운데 정렬 — 양옆 여유 포함)
	check(w0 <= 960.0 - 40.0, "판 폭 %.0f ≤ 920" % w0)
	a.free()


# 번개 판이 떠 있으면 폭탄 판은 숨김 (같은 자리). 화면 신호 노드 (ui/bomb_alert.gd — 트리 밖에서 이벤트·프레임을 직접 넣어 봄)
func test_c11_bomb_alert_hidden_under_bolt() -> void:
	var pick := {"left": 900.0, "ms": 1500.0}
	check(HM.bomb_alert_show(false, pick) and not HM.bomb_alert_show(true, pick) and not HM.bomb_alert_show(false, {}) and not HM.bomb_alert_show(true, {}), "판정")
	var a = load("res://ui/bomb_alert.gd").new()
	var me := {"id": 2.0, "x": 5.5, "y": 5.5, "z": 0.0, "alive": true, "team": null}
	var st := {"phase": "playing", "teamMode": false, "players": [me], "bombs": [{"id": 7.0, "x": 5.0, "y": 6.0, "z": 0.0, "left": 900.0}]}
	a.on_event({"type": "bombPlace", "who": 4.0, "x": 5.0, "y": 6.0, "z": 0.0}, 1000.0)
	a.refresh(st, me, 1000.0, true, "first", false)
	check(a.plate.visible and a.text.text == "폭탄! 고리 밖으로" and a.sec.text == "0.9초" and is_equal_approx(a.left01, 0.6), "남의 폭탄 범위 안: 판 '%s' %s 막대 %s" % [a.text.text, a.sec.text, a.left01])
	check(a.edge.visible and a.edge.modulate.a > 0.0 and a.owners.get(7) == 4, "가장자리 테 %s · 주인 %s" % [a.edge.modulate.a, a.owners])
	a.refresh(st, me, 1010.0, true, "first", true)
	check(not a.plate.visible and not a.edge.visible, "번개 판이 떠 있음: 폭탄 판·테 숨김")
	a.refresh(st, me, 1020.0, true, "third", false)
	check(a.plate.visible, "번개 판이 꺼지면 다시")
	var dead := me.duplicate()
	dead["alive"] = false
	a.refresh(st, dead, 1030.0, true)
	check(not a.plate.visible and not a.edge.visible, "죽은 나: 꺼짐")
	# 내 폭탄이면 안 뜸
	a.clear()
	a.on_event({"type": "bombPlace", "who": 2.0, "x": 5.0, "y": 6.0, "z": 0.0}, 2000.0)
	a.refresh(st, me, 2000.0, true)
	check(not a.plate.visible and not a.edge.visible, "내 폭탄: 안 뜸")
	# 터져서 없어지면 꺼지고, 판 중이 아니면 다 비움
	a.clear()
	a.refresh(st, me, 3000.0, true)
	check(a.plate.visible, "주인 모르는 폭탄: 뜸")
	var gone := st.duplicate()
	gone["bombs"] = []
	a.refresh(gone, me, 3100.0, true)
	check(not a.plate.visible and not a.edge.visible and a.owners.is_empty(), "폭탄이 없어짐: 꺼짐")
	a.on_event({"type": "bombPlace", "who": 4.0, "x": 5.0, "y": 6.0, "z": 0.0}, 3200.0)
	a.refresh(st, me, 3200.0, true)
	a.refresh(st, me, 3300.0, false)
	check(not a.plate.visible and not a.edge.visible and a.owners.is_empty() and a.pending.is_empty(), "판 끝: 다 비움")
	a.free()
