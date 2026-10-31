# 플레이어 화면 위치 보간 (client/interp.js 그대로 — tests/test_interp.gd 가 JS 와 같은 값인지 봄).
# 서버는 30Hz 로 스냅샷을 보내고 도착 간격은 들쭉날쭉 → 스냅샷을 서버 시각(state.time)으로 쌓고, 화면은 '추정 서버 시각 - 지연' 을 두 스냅샷 사이에서 고름
extends RefCounted

const C := preload("res://core/config.gd")


# 화면 시계: 서버 시각을 로컬 시각으로 옮겨 재고, 프레임마다 dt 만큼 고르게 흐름
class SnapClock:
	var samples: Array = [] # 최근 (서버 시각 - 도착 시각)
	var offset = null
	var t = null # 화면 서버 시각 (지연 0 기준, ms)
	var last_server := -INF

	func reset() -> void:
		samples = []
		offset = null
		t = null
		last_server = -INF

	# 스냅샷 도착: server_ms = state.time, now_ms = 받은 로컬 시각. 서버 시각이 뒤로 가면 (새 방) 처음부터
	func on_snapshot(server_ms: float, now_ms: float) -> void:
		if server_ms < last_server - C.INTERP_RESET_MS:
			reset()
		last_server = server_ms
		samples.append(server_ms - now_ms)
		if samples.size() > C.INTERP_CLOCK_SAMPLES:
			samples.pop_front()
		offset = samples.max()

	# 프레임마다: 화면 서버 시각을 dt 만큼 흘리고, 목표와의 차이는 천천히 메움. 아직 모르면 null
	func advance(now_ms: float, dt_ms: float):
		if offset == null:
			return null
		var target: float = now_ms + offset
		if t == null or absf(target - t) > C.INTERP_RESET_MS:
			t = target
		else:
			var err: float = target - (t + dt_ms)
			t += dt_ms + maxf(-dt_ms * C.INTERP_CLOCK_SLEW, minf(dt_ms * C.INTERP_CLOCK_SLEW, err))
		return t


# 플레이어 한 명의 스냅샷 기록 [[t, x, y, z], ...] (서버 시각 오름차순, 게임 좌표 x, y 바닥 · z 위).
# Vector4 가 아니라 float 배열: 고도 Vector 는 32비트라 서버 시각(ms) 이 몇 시간이면 ms 단위로 뭉개짐. GDScript float 는 64비트 (JS 와 같음)
static func push_track(track: Array, t: float, x: float, y: float, z: float) -> void:
	if not track.is_empty():
		var last: Array = track[-1]
		if t <= last[0]:
			if t == last[0]:
				track[-1] = [t, x, y, z]
				return
			track.clear()
		elif sqrt((x - last[1]) * (x - last[1]) + (y - last[2]) * (y - last[2]) + (z - last[3]) * (z - last[3])) > C.INTERP_TELEPORT:
			track.clear() # 순간이동·부활: 이어 그리지 않음
	track.append([t, x, y, z])
	while track.size() > C.INTERP_TRACK_LEN:
		track.pop_front()


# 시각 t 의 위치 (계산은 64비트, 돌려줄 때만 Vector3). 기록 사이면 선형 보간, 앞이면 첫 값, 뒤면 마지막 두 점으로 extrap_ms 까지만 내다봄. 기록이 없으면 null
static func sample_track(track: Array, t: float, extrap_ms: float):
	var n := track.size()
	if n == 0:
		return null
	var first: Array = track[0]
	if n == 1 or t <= first[0]:
		return Vector3(first[1], first[2], first[3])
	var i := n - 1
	while i > 0 and track[i - 1][0] > t:
		i -= 1
	var a: Array = track[maxi(0, i - 1)]
	var b: Array = track[i]
	var u: float
	if t >= b[0]:
		var span: float = b[0] - a[0]
		u = minf(t - b[0], extrap_ms) / span if span > 0 else 0.0
		return Vector3(b[1] + (b[1] - a[1]) * u, b[2] + (b[2] - a[2]) * u, b[3] + (b[3] - a[3]) * u)
	u = (t - a[0]) / (b[0] - a[0])
	return Vector3(a[1] + (b[1] - a[1]) * u, a[2] + (b[2] - a[2]) * u, a[3] + (b[3] - a[3]) * u)
