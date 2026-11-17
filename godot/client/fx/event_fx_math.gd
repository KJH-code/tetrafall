# c9-u3 돌발 이벤트 세계 연출 순수 계산: 줄·티끌·판을 어디에 얼마나 진하게 그릴지 (게임 좌표: x, y 바닥 · z 위). 그리기는 fx/event_fx.gd, 수치는 fx/event_fx_config.gd EVENT_FX,
# 테스트 tests/test_fx.gd test_c9_*. 난수 대신 번호 해시 → 같은 시각이면 늘 같은 자리 (견본 사진이 찍을 때마다 같음)
extends RefCounted


# 번호 i·갈래 salt → 0~1 (늘 같은 값)
static func h01(i: int, salt: int) -> float:
	var n := (i * 374761393 + salt * 668265263 + 1013904223) & 0x7fffffff
	n = ((n ^ (n >> 13)) * 1274126177) & 0x7fffffff
	n = n ^ (n >> 16)
	return float(n & 0xffffff) / float(0x1000000)


# 이 종류를 그리나: 스냅샷 roundEvent {kind, left, dir} 가 표 (running) 에 있는 종류이고 아직 남았을 때만 그 kind, 아니면 "" (모르는 종류·끝남·방향 없는 돌풍)
static func running_kind(ev, running: Array) -> String:
	if not (ev is Dictionary):
		return ""
	var k := str(ev.get("kind", ""))
	if not running.has(k) or ev.get("left") == null or float(ev.get("left")) <= 0.0:
		return ""
	if k == "wind" and wind_dir(ev.get("dir")) == Vector2.ZERO:
		return ""
	return k


# 돌풍 방향 (게임 x, y 단위 벡터). 없으면 ZERO
static func wind_dir(dir) -> Vector2:
	if not (dir is Dictionary):
		return Vector2.ZERO
	var v := Vector2(float(dir.get("x", 0.0)), float(dir.get("y", 0.0)))
	return v.normalized() if v.length() > 1e-6 else Vector2.ZERO


# 들어올 때·끝날 때 알파: left = 남은 ms, total = 이벤트 길이 ms (못 받았으면 처음 본 left). 시작 뒤 fade_in 초에 0 → 1, 끝나기 fade_out 초 전부터 1 → 0
static func fade(left: float, total: float, common: Dictionary) -> float:
	if left <= 0.0:
		return 0.0
	var fi := float(common.fade_in) * 1000.0
	var fo := float(common.fade_out) * 1000.0
	var a_in := clampf((total - left) / fi, 0.0, 1.0) if fi > 0.0 else 1.0
	var a_out := clampf(left / fo, 0.0, 1.0) if fo > 0.0 else 1.0
	return minf(a_in, a_out)


# 그릴 개수: 돌풍 = 판 크기 따라 선형, 저중력 = 넓이에 비례 (최소 min), 폭우 = 고정. 그래픽 낮춤이면 × common.low_k. 판이 없거나 (0) 모르는 종류면 0
static func count(kind: String, field: Vector3i, low: bool, cfg: Dictionary) -> int:
	if field.x <= 0 or field.y <= 0 or not cfg.has(kind):
		return 0
	var k: Dictionary = cfg[kind]
	var n := 0.0
	match kind:
		"wind":
			var u := clampf((float(maxi(field.x, field.y)) - float(k.size[0])) / (float(k.size[1]) - float(k.size[0])), 0.0, 1.0)
			n = lerpf(float(k.n[0]), float(k.n[1]), u)
		"lowgrav":
			n = maxf(float(k.min), float(k.n) * float(field.x * field.y) / (float(k.ref) * float(k.ref)))
		"rain":
			n = float(k.n)
		_:
			return 0
	if low:
		n *= float(cfg.common.low_k)
	return maxi(1, roundi(n))


# 가장자리에서 흐려짐: 구간 [lo, hi] 안의 v 가 끝에서 edge 안이면 0 → 1
static func edge_k(v: float, lo: float, hi: float, edge: float) -> float:
	if edge <= 0.0:
		return 1.0
	return clampf(minf(v - lo, hi - v) / edge, 0.0, 1.0)


# 줄·티끌의 높이 (z) 는 전부 그 자리 바닥 위 높이 — 그리는 쪽이 surface_at (기둥 꼭대기·위험 액체 표면) 을 더함 (지형이 높은 맵·액체가 차오른 판에서 묻히지 않게)
# 돌풍 줄 n 개. 한 줄 = [가운데 (게임 Vector3), 길이, 알파 배율]. 긴 축 = dir, 시각 t (초) 에 dir 쪽으로 speed 칸/초. 줄 전체가 필드 + margin 안 — 넘으면 반대편에서 다시 나옴
static func wind_rows(n: int, field: Vector3i, t: float, dir: Vector2, w: Dictionary, margin: float) -> Array:
	var rows := []
	for i in n:
		var length := lerpf(float(w.len[0]), float(w.len[1]), h01(i, 1))
		var hx := absf(dir.x) * length * 0.5
		var hy := absf(dir.y) * length * 0.5
		var lo := Vector2(-margin + hx, -margin + hy)
		var hi := Vector2(field.x + margin - hx, field.y + margin - hy)
		var go := float(w.speed) * (1.0 + float(w.jitter) * (h01(i, 5) * 2.0 - 1.0)) * t
		var x := lo.x + fposmod(h01(i, 2) * (hi.x - lo.x) + dir.x * go, hi.x - lo.x)
		var y := lo.y + fposmod(h01(i, 3) * (hi.y - lo.y) + dir.y * go, hi.y - lo.y)
		var k := 1.0
		if absf(dir.x) > 0.01:
			k = minf(k, edge_k(x, lo.x, hi.x, float(w.edge)))
		if absf(dir.y) > 0.01:
			k = minf(k, edge_k(y, lo.y, hi.y, float(w.edge)))
		rows.append([Vector3(x, y, lerpf(float(w.z[0]), float(w.z[1]), h01(i, 4))), length, k])
	return rows


# 저중력 티끌 n 개. 한 줄 = [자리 (게임 Vector3), 색 번호 (0·1 번갈아), 알파 배율, 옆 흔들림 (게임 x 에 더할 값)]. 필드 안 바닥에서 올라 높이 z[0]~z[1] 을 되풀이, 양 끝에서 흐려짐
static func mote_rows(n: int, field: Vector3i, t: float, g: Dictionary) -> Array:
	var rows := []
	var z0 := float(g.z[0])
	var span := float(g.z[1]) - z0
	for i in n:
		var up := float(g.speed) * (1.0 + float(g.jitter) * (h01(i, 15) * 2.0 - 1.0)) * t
		var z := z0 + fposmod(h01(i, 13) * span + up, span)
		var sway := sin(t * float(g.sway[1]) + h01(i, 14) * TAU) * float(g.sway[0])
		rows.append([Vector3(h01(i, 11) * field.x, h01(i, 12) * field.y, z), i % 2, edge_k(z, z0, z0 + span, float(g.edge)), sway])
	return rows


# 블록 폭우 세로 줄 n 개. 한 줄 = [가운데 (게임 Vector3), 알파 배율]. 필드 안 (x, y), 줄 전체가 높이 z[0]~z[1] 안에서 speed 칸/초로 내려옴
static func rain_rows(n: int, field: Vector3i, t: float, r: Dictionary) -> Array:
	var rows := []
	var half := float(r.len) * 0.5
	var lo := float(r.z[0]) + half
	var hi := float(r.z[1]) - half
	for i in n:
		var down := float(r.speed) * (1.0 + float(r.jitter) * (h01(i, 24) * 2.0 - 1.0)) * t
		var z := hi - fposmod(h01(i, 23) * (hi - lo) + down, hi - lo)
		rows.append([Vector3(h01(i, 21) * field.x, h01(i, 22) * field.y, z), edge_k(z, lo, hi, float(r.edge))])
	return rows


# 점 p 에서 선분 a–b 까지 거리
static func seg_dist(p: Vector3, a: Vector3, b: Vector3) -> float:
	var ab := b - a
	var l2 := ab.length_squared()
	if l2 < 1e-12:
		return p.distance_to(a)
	return p.distance_to(a + ab * clampf((p - a).dot(ab) / l2, 0.0, 1.0))


# 카메라 가까이면 안 그림: 카메라에서 거리 d 가 near 안이면 0, near + soft 부터 1 (사이는 곧게)
static func near_k(d: float, common: Dictionary) -> float:
	var near := float(common.near)
	if d < near:
		return 0.0
	var soft := float(common.near_soft)
	return clampf((d - near) / soft, 0.0, 1.0) if soft > 0.0 else 1.0


# 멀어도 가늘어지지 않게: 표의 크기 size 와 카메라 거리 d × thin 중 큰 쪽
static func wide(size: float, d: float, thin: float) -> float:
	return maxf(size, d * thin)


# 줄을 카메라 쪽으로 돌려 세움 (어느 좌표든): 메시의 긴 축 (X, 길이 1) = axis × length, 폭 (Y, 1) = width, 앞면 (+Z) 이 카메라 쪽. axis 는 단위 벡터
static func streak_xform(center: Vector3, axis: Vector3, length: float, width: float, cam: Vector3) -> Transform3D:
	var to_cam := cam - center
	var side := to_cam.cross(axis)
	if side.length_squared() < 1e-10: # 카메라가 줄의 긴 축 위: 아무 옆으로
		side = Vector3.UP.cross(axis) if absf(axis.dot(Vector3.UP)) < 0.99 else Vector3.RIGHT.cross(axis)
	side = side.normalized()
	return Transform3D(Basis(axis * length, side * width, axis.cross(side)), center)


# 기둥마다 꼭대기 높이 (칸 (x, y) = y × w + x, 빈 기둥 0). grid = 격자 (칸 (x, y, z) = (z × d + y) × w + x, 0 = 빈칸), field = (w, d, h). 격자가 아직 없으면 빈 배열
static func column_tops(grid: PackedByteArray, field: Vector3i) -> PackedInt32Array:
	var tops := PackedInt32Array()
	if field.x <= 0 or field.y <= 0 or grid.size() < field.x * field.y * field.z:
		return tops
	var layer := field.x * field.y
	tops.resize(layer)
	for col in layer:
		for z in range(field.z - 1, -1, -1):
			if grid[z * layer + col] != 0:
				tops[col] = z + 1
				break
	return tops


# 게임 (x, y) 자리의 바닥 높이: 그 기둥 꼭대기 (필드 밖이면 가장 가까운 가장자리 칸, tops 가 없으면 0), 위험 액체 (lava_on) 표면이 더 높으면 그 표면
static func surface_at(tops: PackedInt32Array, field: Vector3i, x: float, y: float, lava_on: bool, lava_z: float) -> float:
	var top := 0.0
	if field.x > 0 and field.y > 0 and tops.size() == field.x * field.y:
		top = float(tops[clampi(floori(y), 0, field.y - 1) * field.x + clampi(floori(x), 0, field.x - 1)])
	return maxf(top, lava_z) if lava_on else top


# 흐르는 줄이 바닥 높이를 따라감: 지금 높이 cur 가 target 쪽으로 초당 rate 배율로 (계단을 넘을 때 툭 뛰지 않게)
static func follow(cur: float, target: float, dt: float, rate: float) -> float:
	return lerpf(cur, target, clampf(dt * rate, 0.0, 1.0))


# 빙판 판을 깔 칸. 한 줄 = [칸 x, 칸 y, 윗면 높이 (기둥 꼭대기 + 들썩임), 가운데에서 거리 (칸)] — 거리 가까운 순서 (가운데에서 바깥으로 퍼지게).
# grid·field = column_tops 의 것. 위험 액체 (lava_on) 표면 lava_z 가 꼭대기 이상이면 잠긴 칸이라 뺌.
# bump: (없어도 됨) Callable(cx, cy, top) -> float 그 꼭대기 칸 윗면이 정수 높이에서 올라온 양 (world/foot_rings.gd top_bump — 테마 지형 칸의 높낮이)
static func ice_cells(grid: PackedByteArray, field: Vector3i, lava_on: bool, lava_z: float, bump := Callable()) -> Array:
	var rows := []
	var tops := column_tops(grid, field)
	if tops.is_empty():
		return rows
	var mid := Vector2(field.x * 0.5, field.y * 0.5)
	for cy in field.y:
		for cx in field.x:
			var top := tops[cy * field.x + cx]
			if lava_on and lava_z >= float(top):
				continue
			var up := float(bump.call(cx, cy, top)) if bump.is_valid() else 0.0
			rows.append([cx, cy, float(top) + up, Vector2(cx + 0.5, cy + 0.5).distance_to(mid)])
	rows.sort_custom(func(a: Array, b: Array) -> bool: return a[3] < b[3] if a[3] != b[3] else (a[1] * field.x + a[0]) < (b[1] * field.x + b[0]))
	return rows


# 퍼짐: 시작 뒤 t 초에 가운데에서 이 거리 (칸) 안의 판까지 보임. spread 초에 가장 먼 판 (far) 까지
static func ice_radius(t: float, far: float, spread: float) -> float:
	return far if spread <= 0.0 else far * clampf(t / spread, 0.0, 1.0)


# 거리 가까운 순서인 줄들 (ice_cells) 중 반지름 r 안의 개수
static func ice_shown(rows: Array, r: float) -> int:
	var n := 0
	for e in rows:
		if float(e[3]) > r:
			break
		n += 1
	return n


# 반짝 줄을 놓을 칸인가 (every 칸 중 1칸꼴, 칸 좌표 해시), 방향 (0·1 대각선 두 가지)
static func glint_at(cx: int, cy: int, every: int) -> bool:
	return every > 0 and int(h01(cx * 73 + cy * 151, 31) * every) == 0


static func glint_dir(cx: int, cy: int) -> int:
	return 0 if h01(cx * 73 + cy * 151, 32) < 0.5 else 1


# 아이템 자리 열쇠 (칸 x, y)
static func cell_key(it: Dictionary) -> String:
	return "%d,%d" % [int(floor(float(it.get("x", 0.0)))), int(floor(float(it.get("y", 0.0))))]


# 아이템 목록 → {자리 열쇠: 참}
static func item_cells(items) -> Dictionary:
	var out := {}
	if items is Array:
		for it in items:
			if it is Dictionary:
				out[cell_key(it)] = true
	return out


# 보급품: items 중 앞 스냅샷 (prev = item_cells) 에 없던 자리만. 한 줄 = [칸 x, 칸 y, 높이 z, 자리 열쇠] (같은 자리는 한 번)
static func new_cells(prev: Dictionary, items) -> Array:
	var out := []
	var seen := {}
	if items is Array:
		for it in items:
			if not (it is Dictionary):
				continue
			var key := cell_key(it)
			if prev.has(key) or seen.has(key):
				continue
			seen[key] = true
			out.append([int(floor(float(it.get("x", 0.0)))), int(floor(float(it.get("y", 0.0)))), float(it.get("z", 0.0)), key])
	return out


# 빛 기둥 알파 배율: 나온 뒤 age 초 → 1 에서 life 초에 0
static func pillar_k(age: float, life: float) -> float:
	return clampf(1.0 - age / life, 0.0, 1.0) if life > 0.0 else 0.0


# 보급 고리 [반지름, 알파 배율]: 나온 뒤 age 초, ring.ms 동안 r → r × grow (ease-out), 알파 1 → 0. 끝났으면 알파 0
static func ring_at(age: float, ring: Dictionary) -> Array:
	var u := clampf(age * 1000.0 / float(ring.ms), 0.0, 1.0)
	var k := 1.0 - u
	return [float(ring.r) * lerpf(1.0, float(ring.grow), 1.0 - k * k), k]
