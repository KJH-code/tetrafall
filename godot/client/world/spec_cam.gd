# c10 관전 따라가기 카메라 (고도 판 전용 수치·순수 계산, 테스트 tests/test_feel.gd test_c10_spec_*).
# 예전: 대상 가슴 높이를 수평으로 봄 → 대상 둘레의 남의 몸·떨어지는 블록이 렌즈 앞을 덮고 바닥이 안 보였음 (저중력으로 뜬 대상은 하늘만).
# 지금: 3인칭 (C.TP_TILT) 처럼 조금 내려다보고 (tilt), 바라볼 점을 머리 위로 (look_up), 시선 위의 떨어지는 칸 앞으로도 당기고 (blocked),
# 그래도 렌즈 가까이 남는 떨어지는 칸은 옅게 그림 (cell_alpha — world/pieces_view.gd). C.SPECTATE_* (JS 에서 만든 값) 은 그대로 둠.
# c10-fix F1: 대상을 가리는 남의 몸 (시선이 그 몸 상자를 지남) 은 디더로 옅게 (sight_blockers·thin_step — world/cam_rig.gd spec_thin → chars/body.gd set_see_thru).
# 당기기로는 안 됨: 바로 옆 (0.6 m) 사람 앞으로 당기면 렌즈가 대상 몸에 닿음
# c11: 유령 투하 조준 상자의 면이 화면에서 대상 몸·이름표를 덮으면 면을 지움 (screen_rect·ghost_fill — world/ghost_aim.gd, 테두리는 남김),
# 아래 안내 띠의 조작 줄은 관전 시작·조작 뒤 hint_ms 동안만 (hint_full — ui/hud.gd _spectate)
# 쓰는 곳: world/cam_rig.gd (관전 갈래·pull_in·몸 옅게), world/pieces_view.gd (가까운 칸 옅게), world/ghost_aim.gd (조준 상자 면), ui/hud.gd (안내 띠 접기)
extends RefCounted

const SPEC := {
	"tilt": 0.45, # 마우스 pitch 에서 이만큼 더 내려다봄 (rad). 조작은 그대로 — pitch 0 이 이 각도
	"look_up": 1.4, # 바라볼 점 = 대상 발 + 이만큼 (m). C.SPECTATE_LOOK_UP 1.0 보다 높여 대상 발밑 바닥이 화면 가운데 아래에 옴
	"ease": 4.0, # 막힌 것이 사라져 다시 멀어지는 빠르기 (1/초, Cam.follow_dist — 당길 땐 바로)
	"fade": [1.2, 2.6], # 카메라에서 떨어지는 칸 가운데까지 거리 (m): [이 안은 fade_alpha, 이 밖은 그대로]
	"fade_alpha": 0.2, # 가장 옅을 때 알파 배율
	"thin_keep": 0.32, # c10-fix F1: 시선을 막는 남의 몸에 남길 화소 비율 (디더, 1 = 그대로). 다 지우지 않음 — 그 사람이 거기 있다는 것은 보여야 함 (이름표는 그대로)
	"thin_pad": [0.12, 0.28], # 몸 상자 (가로 ±C.PLAYER_HALF, 세로 C.PLAYER_HEIGHT) 를 이만큼 키워 시선과 겹침을 봄 (m): [옅게 시작, 옅은 몸이 되돌아가는 문턱] — 그 사이에선 지난 상태 그대로 (깜빡임 막기)
	"thin_hold_ms": 120, # 시선에서 벗어난 뒤에도 이만큼은 옅은 채 (ms, Net.now_ms). 길면 (250 이었음) 맞아서 날아가며 시선을 스친 몸이 화면 옆으로 간 뒤에도 옅은 채 남음
	"thin_ease_s": 0.12, # 옅어지고 되돌아오는 데 걸리는 시간 (초)
	"ghost_fill_hit": 0.0, # c11: 조준 상자가 화면에서 대상 (몸 + 이름표) 과 겹칠 때 면 알파 배율 (0 = 면 없음, 테두리만). 따라가기에서 화면 가운데 시선은 대상 뒤 약 2.9칸 바닥에 닿아 상자가 늘 대상 머리·이름표 위에 옴
	"ghost_pad": 12.0, # 겹침을 볼 때 대상 화면 사각형을 이만큼 키움 (px — 이름표 글자가 몸 상자보다 넓음)
	"ghost_label_up": 0.3, # 대상 사각형의 위 끝 = 이름표 높이 + 이만큼 (m, 이름·피해 % 두 줄 글자의 위쪽 절반)
	"hint_ms": 8000.0, # 아래 안내 띠의 조작 줄을 보여 주는 시간 (ms, Net.now_ms — 관전 시작·대상 바뀜·전체 보기 토글·휠 거리 뒤부터). 지나면 한 줄로 접힘
	"fade_order": 9, # c10-fix F2: 옅은 칸을 그리는 순서 (render_priority) — 착지 테·위험 표면 1, 판 빛 5, 발밑 고리 7, 표식 8 뒤 (칸 너머로 비침), 이름표 WC.LABEL_PRIORITY 11 앞
}


# 궤도 pitch (Cam.orbit_eye 에 넣는 값): 3인칭 TP_TILT 와 같은 꼴. 바로 위 (−90도) 는 넘지 않음
static func orbit_pitch(pitch: float, tilt: float = float(SPEC.tilt)) -> float:
	return maxf(-PI / 2 + 0.05, pitch - tilt)


# 떨어지는 조각 (스냅샷 pieces) 의 칸 자리 모음: Vector3i → true
static func cells_of(pieces) -> Dictionary:
	var cells := {}
	if not pieces is Array:
		return cells
	for pc in pieces:
		for c in pc.cells:
			cells[Vector3i(int(c[0]), int(c[1]), int(c[2]))] = true
	return cells


# 가림 검사: 격자 (solid: Callable(x, y, z) -> bool) 이거나 떨어지는 칸 (cells_of)
static func blocked(solid: Callable, cells: Dictionary) -> Callable:
	if cells.is_empty():
		return solid
	return func(x: float, y: float, z: float) -> bool:
		return solid.call(x, y, z) or cells.has(Vector3i(floori(x), floori(y), floori(z)))


# 카메라에서 dist (m) 떨어진 칸의 알파 배율: fade[0] 안 = fade_alpha, fade[1] 밖 = 1, 사이는 곧게
static func cell_alpha(dist: float, cfg: Dictionary = SPEC) -> float:
	var f: Array = cfg.fade
	var k := clampf((dist - float(f[0])) / (float(f[1]) - float(f[0])), 0.0, 1.0)
	return lerpf(float(cfg.fade_alpha), 1.0, k)


# ---- c10-fix F1 대상을 가리는 남의 몸 ----

# 선분 a → b 가 상자 [lo, hi] 를 지나는가 (끝점이 안에 있어도 참)
static func seg_hits_box(a: Vector3, b: Vector3, lo: Vector3, hi: Vector3) -> bool:
	var t0 := 0.0
	var t1 := 1.0
	var d := b - a
	for i in 3:
		if absf(d[i]) < 1e-9:
			if a[i] < lo[i] or a[i] > hi[i]:
				return false
			continue
		var u0: float = (lo[i] - a[i]) / d[i]
		var u1: float = (hi[i] - a[i]) / d[i]
		t0 = maxf(t0, minf(u0, u1))
		t1 = minf(t1, maxf(u0, u1))
		if t0 > t1:
			return false
	return true


# 시선을 막는 몸의 id (작은 것부터). eye: 카메라, ends: 시선 끝점들 (바라볼 점·대상 발), others: id → 발 자리 (대상은 뺀 것) — 모두 게임 좌표 (z 가 위).
# 몸 상자 = 발 자리에서 가로 ±half·세로 0..height 를 pad 만큼 키운 것. 눈 → 끝점 선분 가운데 하나라도 지나면 막는 몸
static func sight_blockers(eye: Vector3, ends: Array, others: Dictionary, pad: float, half: float, height: float) -> Array:
	var out := []
	for id in others:
		var s: Vector3 = others[id]
		var lo := Vector3(s.x - half - pad, s.y - half - pad, s.z - pad)
		var hi := Vector3(s.x + half + pad, s.y + half + pad, s.z + height + pad)
		for e in ends:
			if seg_hits_box(eye, e, lo, hi):
				out.append(id)
				break
	out.sort()
	return out


# 옅게 할 몸들의 다음 상태. prev·돌려주는 값: id → {"k": 지금 남길 비율 (1 = 그대로), "at": 마지막으로 시선을 막은 시각 ms}.
# hit: 좁은 문턱 (thin_pad[0]) 으로 막는 id, near: 넓은 문턱 (thin_pad[1]) 으로 막는 id — 이미 옅은 몸은 near 에만 있어도 계속 막는 것으로 침.
# 막는 동안 + 그 뒤 thin_hold_ms 는 thin_keep 쪽으로, 지나면 1 쪽으로 thin_ease_s 에 걸쳐 감. 1 로 다 돌아온 몸은 빠짐
static func thin_step(prev: Dictionary, hit: Array, near: Array, now_ms: float, dt: float, cfg: Dictionary = SPEC) -> Dictionary:
	var out := {}
	var keep := float(cfg.thin_keep)
	var step: float = (1.0 - keep) * dt / maxf(1e-6, float(cfg.thin_ease_s))
	var ids := {}
	for id in prev:
		ids[id] = true
	for id in hit:
		ids[id] = true
	for id in ids:
		var was = prev.get(id)
		var blocking: bool = hit.has(id) or (was != null and near.has(id))
		var at: float = now_ms if blocking else float(was.at)
		var want: float = keep if blocking or now_ms - at < float(cfg.thin_hold_ms) else 1.0
		var k: float = move_toward(float(was.k) if was != null else 1.0, want, step)
		if k < 1.0 or want < 1.0:
			out[id] = {"k": k, "at": at}
	return out


# ---- c11 유령 조준 상자가 대상을 안 덮게 + 안내 띠 접기 ----

# 화면 점들의 바깥 사각형 (점이 없으면 빈 Rect2)
static func screen_rect(points: PackedVector2Array) -> Rect2:
	if points.is_empty():
		return Rect2()
	var lo := points[0]
	var hi := points[0]
	for p in points:
		lo = lo.min(p)
		hi = hi.max(p)
	return Rect2(lo, hi - lo)


# 조준 상자 면의 알파 배율. box: 조준 칸의 화면 사각형, target: 대상 (몸 + 이름표) 의 화면 사각형, following: 관전 따라가기인가.
# 따라가기에서 target 을 ghost_pad 만큼 키운 것과 box 가 겹치면 ghost_fill_hit, 아니면 1 (전체 보기는 늘 1 — 면 + 테두리 예전 그대로)
static func ghost_fill(box: Rect2, target: Rect2, following: bool, cfg: Dictionary = SPEC) -> float:
	if not following:
		return 1.0
	return float(cfg.ghost_fill_hit) if target.grow(float(cfg.ghost_pad)).intersects(box, true) else 1.0


# 안내 띠에 조작 줄까지 보여 줄 때인가: 마지막 조작 (t_last_ms — 관전 시작 포함) 뒤 hint_ms 가 안 지났으면 참
static func hint_full(now_ms: float, t_last_ms: float, cfg: Dictionary = SPEC) -> bool:
	return now_ms - t_last_ms < float(cfg.hint_ms)
