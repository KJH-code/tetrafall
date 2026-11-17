# 돌발 이벤트 알림 글 (ui/round_event_text.gd): 종류마다 한 줄, 돌풍은 방향 화살표 (게임 좌표 → 보는 방향 기준), 모르는 것은 빈 글.
# 진행 중 띠 (status): 스냅샷 roundEvent 의 남은 초까지
extends RefCounted

const T := preload("res://ui/round_event_text.gd")
const SM := preload("res://audio/sound_math.gd")
const BM := preload("res://world/bolt_fx_math.gd")
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


# 이벤트 시작 알림음: 보급은 줍는 소리, 나머지는 전부 경고음 (이미 있는 효과음 키), 종류가 비면 안 냄
func test_bolt_event_cue() -> void:
	check(SM.event_cue("supply") == "pickup", "보급: %s" % SM.event_cue("supply"))
	for k in ["rain", "wind", "lowgrav", "ice", "bolt"]:
		check(SM.event_cue(k) == "danger", "%s: %s" % [k, SM.event_cue(k)])
	check(SM.event_cue("") == "" and SM.event_cue(null) == "", "빈 종류")


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

