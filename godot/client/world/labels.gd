# 머리 위 이름표 순수 계산 (Store 없이 테스트). 정답 자료: tests/fixtures/labels.json
extends RefCounted

const C := preload("res://core/config.gd")


# 화면에서 겹치는 이름표 숨기기 (가까운 것이 이김): items = [{px: Vector2 화면 자리, dist, gap: Vector2 이 크기 안이면 겹침}]
# covers = 화면 사각형 (UI 판) — 그 안이면 숨김. 돌려줌: items 순서대로 보이나 (bool)
static func thin(items: Array, covers: Array = []) -> Array:
	var order := range(items.size())
	order.sort_custom(func(a, b): return items[a].dist < items[b].dist or (items[a].dist == items[b].dist and a < b))
	var out := []
	out.resize(items.size())
	var placed := []
	for i in order:
		var it: Dictionary = items[i]
		var ok := true
		for r in covers:
			if (r as Rect2).has_point(it.px):
				ok = false
		if ok:
			for q in placed:
				if absf(q.px.x - it.px.x) < (q.gap.x + it.gap.x) / 2 and absf(q.px.y - it.px.y) < (q.gap.y + it.gap.y) / 2:
					ok = false
					break
		out[i] = ok
		if ok:
			placed.append(it)
	return out


# 머리 위 이름표: 카메라에서 가까운 LABEL_FULL_N 명만 원래 크기, 나머지 작고 흐리게 (shared/hud-layout.js labelSizes). dists[i] → [scale, opacity]
static func label_sizes(dists: Array) -> Array:
	var order := []
	for i in dists.size():
		order.append([dists[i], i])
	order.sort_custom(func(a, b): return a[0] < b[0] or (a[0] == b[0] and a[1] < b[1])) # JS sort 는 안정 정렬
	var out := []
	for i in dists.size():
		out.append([1.0, 1.0])
	for rank in order.size():
		if rank >= C.LABEL_FULL_N:
			out[order[rank][1]] = [C.LABEL_FAR_SCALE, C.LABEL_FAR_OPACITY]
	return out
