# 머리 위 이름표 순수 계산 (Store 없이 테스트). 정답 자료: tests/fixtures/labels.json
extends RefCounted

const C := preload("res://core/config.gd")


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
