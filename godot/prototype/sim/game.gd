# Tetrafall 게임 규칙 (서버 권위). server/game*.js 의 시제품 범위만 옮김:
# 격자·블록 낙하·착지·압사(머리 박음)·층 지우기·용암 / 이동·점프·2단 점프·대시·밀치기·% 넉백·콤보 / 낙사·판 끝.
# 노드·씬을 안 씀 (순수 계산). 무거워지면 이 파일 경계 그대로 C#/GDExtension 으로 뺄 수 있게 입력·출력은
# handle_input / handle_action / tick / snapshot 만.
extends RefCounted

const C := preload("res://sim/config.gd")
const Pieces := preload("res://sim/pieces.gd")
const Scorer := preload("res://sim/placement.gd")
const Bot := preload("res://sim/bot.gd")
const EPS := 1e-6


class Player:
	var id: int
	var slot: int
	var name: String
	var x := 0.0
	var y := 0.0
	var z := 0.0
	var yaw := 0.0
	var vz := 0.0
	var kbx := 0.0
	var kby := 0.0
	var grounded := true
	var alive := true
	var stun_until := 0.0
	var freeze_until := 0.0
	var push_ready_at := 0.0
	var dash_ready_at := 0.0
	var damage := 0
	var in_fwd := 0.0
	var in_strafe := 0.0
	var in_jump := false
	var air_jumps := 0
	var air_dashes := 0
	var air_jump_queued := false
	var jump_queued_until := 0.0
	var wall_bounced := false
	var combo_hits := 0
	var combo_start_at := 0.0
	var iframe_until := 0.0
	var last_hit := -1 # 마지막으로 나를 날린 사람 id (킬 판정)
	var death_cause := ""
	var wins := 0
	# 캐릭터 (Game.characters 일 때만, 시제품은 닌자만)
	var chr := ""
	var ult := 0.0
	var skill_ready_at := 0.0
	var atk = null # 평타 준비 중 {n, def, air, chained, at}
	var atk_queued := false
	var atk_landed := false
	var cast_queued := "" # 평타 중에 누른 F·R ('skill' | 'ult')
	var chain_n := 0
	var chain_until := 0.0
	var air_n := 0
	var launch_until := 0.0
	var empower_until := 0.0
	var star2 = null # 표창 둘째 발 {at, n, air, def, chained}
	var touch_piece := 0
	var windup = null # F 지상 준비 {at, yaw}
	var streak := 0
	var streak_until := 0.0
	var counter_at := -1.0


class Piece:
	var id := 0
	var shape := ""
	var rot := 0
	var cells: Array = []
	var px := 0
	var py := 0
	var pz := 0
	var land_z := 0
	var fits := false
	var step_ms := 0.0
	var next_step_at := 0.0


var W := C.GRID_W
var D := C.GRID_D
var H := C.GRID_H
var grid := PackedByteArray()
var grid_version := 0
var pieces: Array = []
var piece_counter := 0
var piece_cells := {} # Vector3i -> 블록 id (충돌용)
var time := 0.0 # 게임 시간 ms
var phase := "lobby" # lobby | playing | over
var players := {} # id -> Player (넣은 순서 유지)
var rng := RandomNumberGenerator.new()
var events: Array = []
var log_fn: Callable
var lava := {"active": false, "z": C.LAVA_START_Z, "started_at": 0.0}
var base_avg_height := 0.0
var round_number := 0
var round_start_time := 0.0
var round_end_time := 0.0
var winner_id := -1
var deaths: Array = []
var next_spawn_at := 0.0
var spawn_points: Array = []
var bots := {} # 봇 플레이어 id -> Bot (id 는 음수, JS 판과 같음)
var bot_counter := 0
var prof := {} # 구간별 누적 µs (profile 켜면, tests/bench.gd 가 씀)
var profile := false
var characters := false # 캐릭터(평타·F·R) 켬. 서버 방은 켬, 예전 규칙 테스트는 끔 (JS 판과 같음)


func _init(log_callable: Callable = Callable(), with_characters := false) -> void:
	log_fn = log_callable
	characters = with_characters
	rng.seed = 1
	set_field_size(C.GRID_W)


func log_line(m: String) -> void:
	if log_fn.is_valid():
		log_fn.call(m)


func emit(e: Dictionary) -> void:
	events.append(e)


func drain_events() -> Array:
	var out := events
	events = []
	return out


# ---------- 격자 ----------
static func spawn_points_for(w: int, d: int, inset: float) -> Array:
	var pts := [[inset, inset], [w - inset, d - inset], [w - inset, inset], [inset, d - inset], [w / 2.0, inset], [w / 2.0, d - inset], [inset, d / 2.0], [w - inset, d / 2.0]]
	var out := []
	for p in pts:
		out.append({"x": p[0], "y": p[1], "yaw": atan2(d / 2.0 - p[1], w / 2.0 - p[0])})
	return out


func set_field_size(size: int) -> void:
	H = C.GRID_H
	W = size
	D = size
	spawn_points = spawn_points_for(W, D, C.SPAWN_INSET)
	grid = PackedByteArray()
	grid.resize(W * D * H)


func field_size_for(n: int) -> int:
	var keys: Array = C.FIELD_SIZES.keys()
	keys.sort()
	var best: int = C.FIELD_SIZES[keys[0]]
	for k in keys:
		if n >= k:
			best = C.FIELD_SIZES[k]
	return best


func area_scale() -> float:
	return float(W * D) / float(C.GRID_W * C.GRID_D)


func in_xy(cx: int, cy: int) -> bool:
	return cx >= 0 and cx < W and cy >= 0 and cy < D


func idx(cx: int, cy: int, cz: int) -> int:
	return (cz * D + cy) * W + cx


func grid_at(cx: int, cy: int, cz: int) -> int:
	if not in_xy(cx, cy) or cz < 0 or cz >= H:
		return 0
	return grid[idx(cx, cy, cz)]


# 플레이어 충돌용: 바닥, 쌓인 블록, 떨어지는 블록
func solid_at(cx: int, cy: int, cz: int) -> bool:
	if cz < 0:
		return in_xy(cx, cy) # 필드 안은 바닥, 밖은 허공
	if in_xy(cx, cy) and cz < H and grid[idx(cx, cy, cz)] != 0:
		return true
	return piece_cells.has(Vector3i(cx, cy, cz))


func column_top(cx: int, cy: int) -> int:
	for z in range(H - 1, -1, -1):
		if grid[idx(cx, cy, z)] != 0:
			return z + 1
	return 0


func avg_height() -> float:
	var s := 0
	for x in W:
		for y in D:
			s += column_top(x, y)
	return float(s) / float(W * D)


# ---------- 플레이어·판 ----------
func add_player(id: int, pname := "") -> Player:
	var used := {}
	for p in players.values():
		used[p.slot] = true
	var slot := -1
	for s in C.MAX_PLAYERS:
		if not used.has(s):
			slot = s
			break
	if slot < 0:
		return null
	var p := Player.new()
	p.id = id
	p.slot = slot
	p.name = pname if pname != "" else "P%d" % (slot + 1)
	var sp: Dictionary = spawn_points[slot % spawn_points.size()]
	p.x = sp.x
	p.y = sp.y
	p.yaw = sp.yaw
	p.alive = phase != "playing" # 판 중 난입은 관전
	p.chr = C.CHAR_NINJA if characters else ""
	players[id] = p
	return p


func add_bot() -> Player:
	bot_counter += 1
	var id := -bot_counter
	var p := add_player(id)
	if p == null:
		return null
	p.name += "(봇)"
	bots[id] = Bot.new(id, rng.randi())
	return p


func remove_player(id: int) -> void:
	bots.erase(id)
	var p: Player = players.get(id)
	if p == null:
		return
	if phase == "playing" and p.alive:
		kill(p, "left")
	players.erase(id)
	check_round_end()


func on_field(p: Player) -> bool:
	return p.alive


func can_start() -> bool:
	return players.size() >= C.MIN_PLAYERS and phase != "playing"


func start_round() -> bool:
	if not can_start():
		return false
	set_field_size(field_size_for(players.size()))
	# 시제품은 평지만 (shared/maps.js 지형은 범위 밖)
	base_avg_height = avg_height()
	grid_version += 1
	pieces = []
	piece_cells.clear()
	lava = {"active": false, "z": C.LAVA_START_Z, "started_at": 0.0}
	deaths = []
	events = []
	winner_id = -1
	round_number += 1
	for p in players.values():
		var sp: Dictionary = spawn_points[p.slot % spawn_points.size()]
		p.x = sp.x
		p.y = sp.y
		p.z = 0.0
		p.yaw = sp.yaw
		p.vz = 0.0
		p.kbx = 0.0
		p.kby = 0.0
		p.grounded = true
		p.alive = true
		p.stun_until = 0.0
		p.freeze_until = 0.0
		p.push_ready_at = 0.0
		p.dash_ready_at = 0.0
		p.damage = 0
		p.combo_hits = 0
		p.iframe_until = 0.0
		p.last_hit = -1
		p.death_cause = ""
		p.jump_queued_until = 0.0
		p.air_jump_queued = false
		p.ult = 0.0
		p.skill_ready_at = 0.0
		p.atk = null
		p.atk_queued = false
		p.atk_landed = false
		p.cast_queued = ""
		p.chain_n = 0
		p.chain_until = 0.0
		p.air_n = 0
		p.launch_until = 0.0
		p.empower_until = 0.0
		p.star2 = null
		p.touch_piece = 0
		p.windup = null
		p.streak = 0
		p.streak_until = 0.0
		p.counter_at = -1.0
	phase = "playing"
	round_start_time = time
	next_spawn_at = time + C.FIRST_SPAWN_DELAY_MS
	var names := []
	for p in players.values():
		names.append(p.name)
	log_line("===== ROUND %d 시작 (%d명: %s, %dx%d) =====" % [round_number, players.size(), " ".join(names), W, D])
	return true


func kill(p: Player, cause: String, by := -1) -> void:
	if not p.alive:
		return
	p.alive = false
	p.death_cause = cause
	var credit := by if by >= 0 else p.last_hit
	if credit == p.id or not players.has(credit):
		credit = -1
	var t := time - round_start_time
	deaths.append({"name": p.name, "cause": cause, "t": t, "killer": players[credit].name if credit >= 0 else ""})
	emit({"type": "death", "who": p.id, "cause": cause, "by": credit, "x": p.x, "y": p.y, "z": p.z})
	log_line("  [사망] %s %s @ %.1fs (위치 %.1f, %.1f, %.1f, 피해 %d%%%s)" % [p.name, cause, t / 1000.0, p.x, p.y, p.z, p.damage, (", 킬 " + players[credit].name) if credit >= 0 else ", 킬 없음"])


func check_round_end() -> void:
	if phase != "playing":
		return
	var alive := []
	for p in players.values():
		if p.alive:
			alive.append(p)
	if alive.size() <= 1:
		end_round(alive[0] if alive.size() == 1 else null)


func end_round(winner: Player) -> void:
	phase = "over"
	round_end_time = time
	winner_id = winner.id if winner else -1
	if winner:
		winner.wins += 1
	var ds := []
	for d in deaths:
		ds.append("%s %s@%.1fs" % [d.name, d.cause, d.t / 1000.0])
	log_line("===== ROUND %d 종료 | 길이 %.1fs | 승자: %s =====" % [round_number, (time - round_start_time) / 1000.0, winner.name if winner else "무승부"])
	log_line("  사망: %s" % (", ".join(ds) if ds.size() else "없음"))
	emit({"type": "roundOver", "winner": winner_id})


# ---------- 틱 ----------
func tick(dt_ms: float) -> void:
	time += dt_ms
	if phase != "playing":
		return
	var t := Time.get_ticks_usec() if profile else 0
	for id in bots:
		var bp: Player = players.get(id)
		if bp and bp.alive:
			bots[id].update(self, bp)
	t = _prof("bots", t)
	update_pieces()
	t = _prof("pieces", t)
	var remaining := dt_ms / 1000.0
	while remaining > 0.0:
		var h := minf(remaining, C.MAX_STEP_DT)
		for p in players.values():
			if on_field(p):
				integrate_player(p, h)
		remaining -= h
	t = _prof("physics", t)
	update_combat()
	t = _prof("combat", t)
	for p in players.values():
		if on_field(p) and p.z < C.FALL_DEATH_Z:
			kill(p, "fall")
	update_lava(dt_ms)
	t = _prof("lava", t)
	check_round_end()


func _prof(key: String, t0: int) -> int:
	if not profile:
		return 0
	var t := Time.get_ticks_usec()
	prof[key] = prof.get(key, 0) + t - t0
	return t


# ---------- 입력 ----------
func handle_input(id: int, fwd: float, strafe: float, jump: bool, yaw: float) -> void:
	var p: Player = players.get(id)
	if p == null:
		return
	p.in_fwd = clampf(fwd, -1.0, 1.0) if is_finite(fwd) else 0.0
	p.in_strafe = clampf(strafe, -1.0, 1.0) if is_finite(strafe) else 0.0
	p.in_jump = jump
	if is_finite(yaw):
		p.yaw = yaw


func handle_action(id: int, action: String) -> void:
	var p: Player = players.get(id)
	if p == null or phase != "playing" or not p.alive:
		return
	var stunned := time < p.stun_until
	match action:
		"jump":
			if not p.grounded:
				p.air_jump_queued = true
			else:
				p.jump_queued_until = time + C.JUMP_BUFFER_MS
		"dash":
			if stunned or time < p.dash_ready_at:
				return
			if not p.grounded and p.air_dashes <= 0:
				return
			dash(p)
		"push":
			if stunned:
				return
			if p.chr != "":
				basic_press(p) # 캐릭터 평타
				return
			if time < p.push_ready_at:
				return
			push(p)
		"skill": # F
			if stunned or p.chr == "" or time < p.skill_ready_at:
				return
			cast(p, "skill")
		"ult": # R: 게이지가 다 차면
			if stunned or p.chr == "" or p.ult < C.ULT_MAX:
				return
			cast(p, "ult")


# ---------- 플레이어 물리 ----------
func move_dir(p: Player) -> Vector2:
	if p.in_fwd == 0.0 and p.in_strafe == 0.0:
		return Vector2.ZERO
	var x := cos(p.yaw) * p.in_fwd + sin(p.yaw) * p.in_strafe
	var y := sin(p.yaw) * p.in_fwd - cos(p.yaw) * p.in_strafe
	var l := sqrt(x * x + y * y)
	if l == 0.0:
		l = 1.0
	return Vector2(x / l, y / l)


func integrate_player(p: Player, dt: float) -> void:
	if time < p.freeze_until:
		return # 히트스톱
	var stunned := time < p.stun_until
	var ix := 0.0
	var iy := 0.0
	if p.grounded:
		p.air_jumps = C.AIR_JUMPS
		p.air_dashes = C.AIR_DASHES
	if not stunned:
		var mv := move_dir(p)
		var speed := C.MOVE_SPEED * (C.BASIC_FINISH_MOVE_MULT if p.atk != null and p.atk.def.get("finish", false) else 1.0) # 마무리 타 준비 중
		ix = mv.x * speed
		iy = mv.y * speed
		if (p.in_jump or time < p.jump_queued_until) and p.grounded:
			p.vz = C.JUMP_SPEED
			p.grounded = false
			p.jump_queued_until = 0.0
		elif p.air_jump_queued and not p.grounded and p.air_jumps > 0:
			p.vz = C.AIR_JUMP_SPEED
			p.air_jumps -= 1
			emit({"type": "airJump", "who": p.id})
	p.air_jump_queued = false
	var damp := exp(-(C.KB_DAMPING_GROUND if p.grounded else C.KB_DAMPING_AIR) * dt)
	p.kbx *= damp
	p.kby *= damp
	if absf(p.kbx) < 0.01:
		p.kbx = 0.0
	if absf(p.kby) < 0.01:
		p.kby = 0.0
	p.vz -= C.GRAVITY * dt
	move_axis(p, 0, (ix + p.kbx) * dt)
	move_axis(p, 1, (iy + p.kby) * dt)
	p.grounded = false
	move_axis(p, 2, p.vz * dt)


func overlapping_solid(x0: float, x1: float, y0: float, y1: float, z0: float, z1: float) -> Array:
	var out := []
	for cz in range(floori(z0 + EPS), floori(z1 - EPS) + 1):
		for cy in range(floori(y0 + EPS), floori(y1 - EPS) + 1):
			for cx in range(floori(x0 + EPS), floori(x1 - EPS) + 1):
				if solid_at(cx, cy, cz):
					out.append(Vector3i(cx, cy, cz))
	return out


func player_hits(p: Player) -> Array:
	return overlapping_solid(p.x - C.PLAYER_HALF, p.x + C.PLAYER_HALF, p.y - C.PLAYER_HALF, p.y + C.PLAYER_HALF, p.z, p.z + C.PLAYER_HEIGHT)


# axis: 0 = x, 1 = y, 2 = z
func move_axis(p: Player, axis: int, delta: float) -> void:
	if delta == 0.0:
		return
	if axis == 0:
		p.x += delta
	elif axis == 1:
		p.y += delta
	else:
		p.z += delta
	var hits := player_hits(p)
	if hits.is_empty():
		return
	if axis == 2:
		if delta < 0.0:
			var top := -INF
			for h in hits:
				top = maxf(top, h.z + 1)
			p.z = top
			p.vz = 0.0
			p.grounded = true
		else:
			var bottom := INF
			for h in hits:
				bottom = minf(bottom, h.z)
			p.z = bottom - C.PLAYER_HEIGHT
			p.vz = 0.0
		return
	var edge: float
	if delta > 0.0:
		edge = INF
		for h in hits:
			edge = minf(edge, h[axis])
		edge -= C.PLAYER_HALF
	else:
		edge = -INF
		for h in hits:
			edge = maxf(edge, h[axis] + 1)
		edge += C.PLAYER_HALF
	if axis == 0:
		p.x = edge
	else:
		p.y = edge
	# 넉백으로 날아가다 벽에 박히면 그 속도를 위로 바꿔 넘김 (맞을 때마다 한 번)
	var speed := absf(p.kbx if axis == 0 else p.kby)
	if time < p.stun_until and speed >= C.WALL_BOUNCE_MIN_SPEED:
		if not p.wall_bounced:
			p.wall_bounced = true
			p.vz = maxf(p.vz, minf(C.WALL_BOUNCE_MAX_UP, speed * C.WALL_BOUNCE_RATIO))
			p.grounded = false
		if p.vz > 0.0:
			return
	if axis == 0:
		p.kbx = 0.0
	else:
		p.kby = 0.0


# ---------- 전투 ----------
func dash(p: Player) -> void:
	var d := Vector2(cos(p.yaw), sin(p.yaw))
	var mv := move_dir(p)
	if mv != Vector2.ZERO:
		d = mv
	p.kbx = d.x * C.DASH_SPEED
	p.kby = d.y * C.DASH_SPEED
	p.dash_ready_at = time + C.DASH_COOLDOWN_MS
	if not p.grounded:
		p.air_dashes -= 1
	emit({"type": "dash", "who": p.id})


func push(p: Player) -> void:
	p.push_ready_at = time + C.PUSH_COOLDOWN_MS
	emit({"type": "swing", "who": p.id})
	var falling := not p.grounded and p.vz < 0.0 # 치명타: 떨어지면서 때림
	var fx := cos(p.yaw)
	var fy := sin(p.yaw)
	var cos_half := cos(deg_to_rad(C.PUSH_HALF_ANGLE_DEG))
	for t in players.values():
		if t == p or not on_field(t):
			continue
		var dx: float = t.x - p.x
		var dy: float = t.y - p.y
		var dist := sqrt(dx * dx + dy * dy)
		if dist > C.PUSH_RANGE or absf(t.z - p.z) > C.PLAYER_HEIGHT:
			continue
		if dist > EPS and (dx * fx + dy * fy) / dist < cos_half:
			continue
		var crit: bool = falling and p.z - t.z >= C.CRIT_MIN_HEIGHT
		var gain := roundi(C.PUSH_DAMAGE * C.CRIT_DAMAGE_MULT) if crit else C.PUSH_DAMAGE
		var hit := apply_knockback(t, fx, fy, C.PUSH_KB_SPEED * (C.CRIT_KB_MULT if crit else 1.0), C.PUSH_KB_UP, C.STUN_MS, gain, p.id)
		var stop := C.HITSTOP_MS * (C.CRIT_HITSTOP_MULT if crit else 1.0)
		if hit:
			p.freeze_until = time + stop
			t.freeze_until = time + stop
		emit({"type": "hit", "by": p.id, "target": t.id, "ok": hit, "crit": hit and crit})
		log_line("  [밀치기] %s → %s %s" % [p.name, t.name, ("넉백%s (%s %d%%)" % [" 치명타" if crit else "", t.name, t.damage]) if hit else "무적이라 무시"])


func invulnerable(t: Player) -> bool:
	if t.combo_hits > 0 and time >= t.stun_until:
		end_combo(t)
	return time < t.iframe_until


func foe(p: Player, t: Player) -> bool:
	return t != p and on_field(t)


# 카운터히트 대상: 빗나간 평타의 후딜, F 준비 중
func busy(t: Player) -> bool:
	return (time < t.push_ready_at and t.atk == null and not t.atk_landed) or t.windup != null


# 맞기 전까지 쌓인 % 로 수평 넉백을 키우고 그다음에 쌓는다 (위로 튀는 속도는 그대로).
# heavy: 콤보 중에도 넉백을 안 줄임. fixed: 평타 중간 타 (넉백 고정). finish: 평타 마무리 타. chained: 연타를 이어 가는 타 (시간 마무리 아님)
func apply_knockback(t: Player, dx: float, dy: float, speed: float, up: float, stun_ms: float, gain: int, by: int, heavy := false, fixed_kb := false, finish := false, chained := false) -> bool:
	if invulnerable(t):
		return false
	t.combo_hits = t.combo_hits + 1 if time < t.stun_until and t.combo_hits > 0 else 1
	if t.combo_hits == 1:
		t.combo_start_at = time
	# 카운터히트: 맞는 쪽이 공격 동작 중 (이미 경직 중이면 아님)
	var counter := by >= 0 and t.chr != "" and time >= t.stun_until and busy(t)
	if counter:
		stun_ms *= C.COUNTER_STUN_MULT
		t.counter_at = time
		emit({"type": "counter", "by": by, "target": t.id})
		log_line("  [카운터] %s → %s" % [players[by].name if players.has(by) else "?", t.name])
	var finisher := t.combo_hits >= 2 and (finish or (time - t.combo_start_at >= C.COMBO_MS and not chained))
	var fixed := fixed_kb and not finisher
	if not fixed:
		speed *= C.COMBO_FINISH_KB if finisher else (1.0 if heavy else C.COMBO_LIGHT_KB)
	if t.combo_hits >= 2:
		emit({"type": "combo", "by": by, "target": t.id, "n": t.combo_hits, "finish": finisher})
	# 맞아서 끊긴 공격: 안 나간 평타는 후딜 없음, 준비 중 F 는 쿨타임 안 씀
	if t.atk != null:
		emit({"type": "interrupt", "who": t.id, "kind": "basic"})
		t.push_ready_at = time
	if t.windup != null:
		emit({"type": "interrupt", "who": t.id, "kind": "skill"})
		t.skill_ready_at = time
		t.windup = null
	t.atk = null
	t.star2 = null
	t.streak = 0
	t.atk_queued = false
	t.cast_queued = ""
	t.chain_n = 0
	if by >= 0 and by != t.id:
		t.last_hit = by
		var hitter: Player = players.get(by)
		if hitter:
			hitter.streak = hitter.streak + 1 if time < hitter.streak_until else 1
			hitter.streak_until = time + C.STREAK_MS
	var taken := C.NINJA_KB_TAKEN if t.chr == C.CHAR_NINJA else 1.0 # 닌자 약점: 잘 밀림
	var mult := 1.0 if fixed else (C.DAMAGE_KB_BASE + t.damage * C.DAMAGE_KB_PER_PERCENT) * taken
	t.damage += gain
	gain_ult(t, by, gain)
	var l := sqrt(dx * dx + dy * dy)
	if l == 0.0:
		l = 1.0
	t.kbx = dx / l * speed * mult
	t.kby = dy / l * speed * mult
	t.vz = up
	t.grounded = false
	t.wall_bounced = false
	t.stun_until = time + stun_ms
	t.freeze_until = time + C.HITSTOP_MS * (C.COUNTER_HITSTOP_MULT if counter else 1.0)
	if finisher:
		end_combo(t, t.stun_until, true)
	return true


# 필살기 게이지: 피해 % 를 주거나 받은 만큼
func gain_ult(t: Player, by: int, gain: int) -> void:
	if gain <= 0:
		return
	t.ult = minf(C.ULT_MAX, t.ult + gain * C.ULT_PER_DAMAGE)
	if by >= 0 and by != t.id and players.has(by):
		var b: Player = players[by]
		b.ult = minf(C.ULT_MAX, b.ult + gain * C.ULT_PER_DAMAGE)


func end_combo(t: Player, from := -1.0, finished := false) -> void:
	if from < 0.0:
		from = time
	if t.combo_hits >= 2:
		log_line("  [콤보] → %s %d타%s" % [t.name, t.combo_hits, " 마무리" if finished else ""])
	t.combo_hits = 0
	t.iframe_until = from + C.COMBO_IFRAME_MS


# ---------- 캐릭터: 평타·F·R (game-combat.js), 닌자 (char-ninja.js) ----------
# 틱마다: 콤보 끝·평타 판정·표창 둘째 발·닌자 패시브·F 준비 끝·기억한 F/R·평타 선입력
func update_combat() -> void:
	for p in players.values():
		if p.combo_hits > 0 and time >= p.stun_until:
			end_combo(p)
		if not on_field(p):
			p.atk = null
			p.atk_queued = false
			p.cast_queued = ""
			p.star2 = null
			p.windup = null
			continue
		if p.atk != null and time >= p.atk.at:
			basic_hit(p)
		if p.star2 != null and time >= p.star2.at:
			var s2: Dictionary = p.star2
			p.star2 = null
			if star_shot(p, s2.n, s2.air, s2.def, 2, s2.chained):
				p.atk_landed = true
				ninja_cd_cut(p)
		if p.chr == C.CHAR_NINJA:
			ninja_touch(p)
		if p.windup != null and time >= p.windup.at:
			fire_windup(p)
		if p.cast_queued != "" and p.atk == null and (p.atk_landed or time >= p.push_ready_at):
			cast_queued_now(p)
		elif p.atk_queued and p.atk == null and time >= p.push_ready_at:
			p.atk_queued = false
			if time >= p.stun_until:
				basic_start(p)


# F·R 캔슬: 맞힌 평타의 후딜이면 끊고 바로, 평타 준비 중·빗나간 후딜이면 기억했다가
func cast(p: Player, kind: String) -> void:
	if p.atk != null or (time < p.push_ready_at and not p.atk_landed):
		p.cast_queued = kind
		p.atk_queued = false
		return
	if time < p.push_ready_at:
		p.push_ready_at = time
	if kind == "skill":
		use_skill(p)
	else:
		use_ult(p)


func cast_queued_now(p: Player) -> void:
	var kind := p.cast_queued
	p.cast_queued = ""
	if time < p.stun_until or (time < p.skill_ready_at if kind == "skill" else p.ult < C.ULT_MAX):
		emit({"type": "castDrop", "who": p.id, "kind": kind})
		return
	cast(p, kind)


func basic_press(p: Player) -> void:
	if p.atk != null or time < p.push_ready_at:
		p.atk_queued = true
		return
	basic_start(p)


# 몇 번째 타인지 정하고 준비 시작. 지상·공중 각각 이어 치기 창 안이면 다음 타, 아니면 1타
func basic_start(p: Player) -> void:
	var set_: Dictionary = C.BASIC_ATTACKS[p.chr]
	var air := not p.grounded
	var live := time < p.chain_until
	var n: int
	if air:
		n = p.air_n + 1 if p.air_n > 0 and live and p.air_n < set_.air.size() else 1
	else:
		n = p.chain_n + 1 if p.chain_n > 0 and live and p.chain_n < set_.chain.size() else 1
	var def: Dictionary = set_.air[n - 1] if air else set_.chain[n - 1]
	# 닌자 R 강화: 지상 1~3타와 공중 평타가 표창 2연발 (4타 올려 차기는 그대로)
	if p.chr == C.CHAR_NINJA and time < p.empower_until and (air or n <= 3):
		def = def.duplicate()
		def.name = "표창"
		def.windup = C.NINJA_STAR.windup
		def.step = 0
		def.star = true
	var chained: bool = ((p.air_n > 0 and live) or time < p.launch_until) if air else n > 1
	p.atk = {"n": n, "def": def, "air": air, "chained": chained, "at": time + def.windup}
	p.atk_landed = false
	p.push_ready_at = time + def.windup + def.rec
	emit({"type": "attack", "who": p.id, "n": n, "air": air, "name": def.name, "windup": def.windup, "finish": def.get("finish", false), "star": def.get("star", false)})
	if def.windup <= 0:
		basic_hit(p)


# 판정: 앞으로 step 만큼 나가며 부채꼴 안을 침. 중간 타는 고정 넉백, 마무리 타는 % 배율
func basic_hit(p: Player) -> void:
	var a: Dictionary = p.atk
	p.atk = null
	var n: int = a.n
	var def: Dictionary = a.def
	var air: bool = a.air
	var chained: bool = a.chained
	var set_: Dictionary = C.BASIC_ATTACKS[p.chr]
	if def.get("star", false):
		star_volley(p, n, air, def, chained)
		return
	var fx := cos(p.yaw)
	var fy := sin(p.yaw)
	if def.step:
		# 앞으로 나가되 앞 상대를 지나치지 않게 (BASIC_STEP_GAP 앞에서 멈춤)
		var step: float = def.step
		for t in players.values():
			if not foe(p, t) or absf(t.z - p.z) > C.PLAYER_HEIGHT:
				continue
			var along: float = (t.x - p.x) * fx + (t.y - p.y) * fy
			var side: float = absf((t.x - p.x) * fy - (t.y - p.y) * fx)
			if along > 0 and side < C.BASIC_STEP_GAP:
				step = minf(step, maxf(0.0, along - C.BASIC_STEP_GAP))
		move_axis(p, 0, fx * step)
		move_axis(p, 1, fy * step)
	emit({"type": "swing", "who": p.id, "n": n})
	var cos_half := cos(deg_to_rad(C.PUSH_HALF_ANGLE_DEG))
	var falling := not p.grounded and p.vz < 0.0
	var finish: bool = def.get("finish", false)
	var single: bool = air and set_.air.size() == 1
	var landed: Player = null
	for t in players.values():
		if t == p or not on_field(t):
			continue
		var dx: float = t.x - p.x
		var dy: float = t.y - p.y
		var dist := sqrt(dx * dx + dy * dy)
		if dist > C.PUSH_RANGE or absf(t.z - p.z) > C.PLAYER_HEIGHT:
			continue
		if dist > C.BASIC_STEP_GAP and (dx * fx + dy * fy) / dist < cos_half:
			continue # 몸이 붙어 있으면 방향 상관없이
		var crit: bool = air and falling and p.z - t.z >= C.CRIT_MIN_HEIGHT # 치명타는 공중 평타만
		var gain: int = roundi(def.dmg * C.CRIT_DAMAGE_MULT) if crit else int(def.dmg)
		var speed: float = def.kb * (C.CRIT_KB_MULT if crit else 1.0)
		var hit := apply_knockback(t, fx, fy, speed, def.up, def.stun, gain, p.id, finish, not single and not finish, finish, chained)
		if hit:
			var stop: float = (C.BASIC_FINISH_HITSTOP_MS if finish else (C.HITSTOP_MS if single else C.BASIC_HITSTOP_MS)) * (C.CRIT_HITSTOP_MULT if crit else 1.0) * (C.COUNTER_HITSTOP_MULT if t.counter_at == time else 1.0)
			p.freeze_until = time + stop
			t.freeze_until = time + stop
			if landed == null:
				landed = t
		emit({"type": "hit", "by": p.id, "target": t.id, "ok": hit, "crit": hit and crit, "n": n, "air": air, "finish": finish})
		log_line("  [평타] %s → %s %s %s" % [p.name, t.name, ("넉백%s (%s %d%%)" % [" 치명타" if crit else "", t.name, t.damage]) if hit else "무적이라 무시", def.name])
	basic_chain(p, n, air, landed != null, def)


# 평타 한 타가 끝난 뒤: 이어 치기 번호·창, 맞혔는지, 닌자 F 쿨 감소. 빗나가도 다음 타로 (허공 이어 치기)
func basic_chain(p: Player, n: int, air: bool, landed: bool, def: Dictionary) -> void:
	var set_: Dictionary = C.BASIC_ATTACKS[p.chr]
	if not air and n == set_.chain.size() and not def.get("finish", false):
		p.launch_until = time + def.rec + C.BASIC_CHAIN_WINDOW_MS # 띄우는 마지막 지상 타 뒤 공중 1타가 연타로 이어짐
	if air:
		p.air_n = n if n < set_.air.size() else 0
		if p.air_n > 0 or p.chain_n > 0:
			p.chain_until = time + C.BASIC_CHAIN_WINDOW_MS
	elif n < set_.chain.size():
		p.chain_n = n
		p.chain_until = time + C.BASIC_CHAIN_WINDOW_MS
	else:
		p.chain_n = 0
	p.atk_landed = landed
	if landed:
		ninja_cd_cut(p)


# 닌자 적중 보상: 평타가 맞을 때마다 F 쿨 줄어듦
func ninja_cd_cut(p: Player) -> void:
	if p.chr == C.CHAR_NINJA:
		p.skill_ready_at = maxf(time, p.skill_ready_at - C.NINJA_HIT_CD_CUT_MS)


# 닌자 R 강화 표창 2연발: 첫 발은 지금, 둘째 발은 NINJA_STAR.gap 뒤. 즉시 판정
func star_volley(p: Player, n: int, air: bool, def: Dictionary, chained: bool) -> void:
	var landed := star_shot(p, n, air, def, 1, chained)
	basic_chain(p, n, air, landed, def)
	p.star2 = {"at": time + C.NINJA_STAR.gap, "n": n, "air": air, "def": def, "chained": chained}


# 표창 한 발: 보는 방향 좁은 각 안 가장 가까운 상대 하나. 마무리 타 자리면 둘째 발이 그 타의 마무리
func star_shot(p: Player, n: int, air: bool, def: Dictionary, shot: int, chained: bool) -> bool:
	var S: Dictionary = C.NINJA_STAR
	var fx := cos(p.yaw)
	var fy := sin(p.yaw)
	var cos_half := cos(deg_to_rad(S.angle))
	var best: Player = null
	var bd := INF
	for t in players.values():
		if t == p or not on_field(t):
			continue
		var dx: float = t.x - p.x
		var dy: float = t.y - p.y
		var dist := sqrt(dx * dx + dy * dy)
		if dist > S.range or absf(t.z - p.z) > S.range or dist < EPS or (dx * fx + dy * fy) / dist < cos_half:
			continue
		if dist < bd:
			bd = dist
			best = t
	var fin: bool = shot == 2 and def.get("finish", false)
	emit({"type": "star", "who": p.id, "shot": shot, "target": best.id if best else -1})
	if best == null:
		return false
	var falling := not p.grounded and p.vz < 0.0
	var crit: bool = air and falling and p.z - best.z >= C.CRIT_MIN_HEIGHT
	var dmg: int = def.dmg if fin else S.dmg
	var gain: int = roundi(dmg * C.CRIT_DAMAGE_MULT) if crit else dmg
	var hit := apply_knockback(best, fx, fy, (def.kb if fin else S.kb) * (C.CRIT_KB_MULT if crit else 1.0), def.up if fin else S.up, def.stun if fin else S.stun, gain, p.id, fin, not fin, fin, chained or shot == 2)
	if hit:
		best.freeze_until = time + (C.BASIC_FINISH_HITSTOP_MS if fin else C.BASIC_HITSTOP_MS) * (C.CRIT_HITSTOP_MULT if crit else 1.0) * (C.COUNTER_HITSTOP_MULT if best.counter_at == time else 1.0)
	emit({"type": "hit", "by": p.id, "target": best.id, "ok": hit, "crit": hit and crit, "n": n, "air": air, "finish": fin, "star": true})
	log_line("  [평타] %s → %s %s 표창" % [p.name, best.name, ("넉백 (%s %d%%)" % [best.name, best.damage]) if hit else "무적이라 무시"])
	return hit


func use_skill(p: Player) -> bool:
	if p.windup != null:
		return false
	p.skill_ready_at = time + C.SKILL_CD_MS[p.chr]
	if p.grounded and C.SKILL_WINDUP_CHARS.has(p.chr):
		# 이동 스킬 지상 예고: SKILL_WINDUP_MS 뒤 누른 순간 방향으로
		p.windup = {"at": time + C.SKILL_WINDUP_MS, "yaw": p.yaw}
		emit({"type": "skillWindup", "who": p.id, "ms": C.SKILL_WINDUP_MS})
		log_line("  [스킬] %s 닌자 F 준비" % p.name)
		return true
	return fire_skill(p)


func fire_windup(p: Player) -> void:
	var yaw := p.yaw
	p.yaw = p.windup.yaw
	p.windup = null
	if not fire_skill(p):
		log_line("  [스킬] %s 닌자 F 못 나감 (자리 없음, 쿨타임 안 씀)" % p.name)
	p.yaw = yaw


func fire_skill(p: Player) -> bool:
	if not ninja_blink(p):
		p.skill_ready_at = time
		return false
	if p.chain_n > 0 and time < p.chain_until:
		p.chain_until = time + C.BASIC_CHAIN_WINDOW_MS # 평타 → 스킬 → 평타
	emit({"type": "skill", "who": p.id, "x": p.x, "y": p.y, "z": p.z})
	return true


func use_ult(p: Player) -> bool:
	if p.windup != null:
		return false
	ninja_empower(p)
	p.ult = 0.0
	emit({"type": "ult", "who": p.id})
	return true


# 순간 베기: 보는 방향으로 NINJA_BLINK_DIST 만큼 (블록 앞까지, 상대가 있으면 그 바로 뒤까지) 순간이동하며 지나간 길의 상대를 벰.
# 블록에 막히면 벽 차기 (위로 튀어 오름 + 작은 충격파)
func ninja_blink(p: Player) -> bool:
	var fx := cos(p.yaw)
	var fy := sin(p.yaw)
	var from := Vector3(p.x, p.y, p.z)
	var best := 0.0
	var blocked := false
	var d := 0.1
	while d <= C.NINJA_BLINK_DIST + 1e-9:
		var x := p.x + fx * d
		var y := p.y + fy * d
		var z := p.z + 0.05 # 발이 바닥에 살짝 안 걸리게
		if not overlapping_solid(x - C.PLAYER_HALF, x + C.PLAYER_HALF, y - C.PLAYER_HALF, y + C.PLAYER_HALF, z, z + C.PLAYER_HEIGHT).is_empty():
			blocked = true
			break
		best = d
		d += 0.1
	if best < 0.3 and not blocked:
		return false
	var wall := best
	for t in players.values():
		if not foe(p, t) or absf(t.z - p.z) > C.PLAYER_HEIGHT:
			continue
		var along := _on_path(from, fx, fy, t, best)
		if along >= 0.0:
			best = minf(best, along + C.NINJA_BLINK_BEHIND)
	p.x += fx * best
	p.y += fy * best
	emit({"type": "blink", "who": p.id})
	var n := 0
	for t in players.values():
		if not foe(p, t) or absf(t.z - p.z) > C.PLAYER_HEIGHT:
			continue
		if _on_path(from, fx, fy, t, best) < 0.0:
			continue
		var hit := apply_knockback(t, fx, fy, C.NINJA_SLASH_KB_SPEED, C.NINJA_SLASH_KB_UP, C.NINJA_SLASH_STUN_MS, C.NINJA_SLASH_DAMAGE, p.id)
		if hit:
			n += 1
		emit({"type": "hit", "kind": "slash", "by": p.id, "target": t.id, "ok": hit})
	var kicked := blocked and best >= wall - 1e-9 # 상대 뒤에서 먼저 멈췄으면 벽 차기 아님
	log_line("  [스킬] %s 순간 베기 %.1f칸%s%s" % [p.name, best, (" (%d명)" % n) if n else "", " 벽 차기" if kicked else ""])
	if kicked:
		ninja_wall_kick(p, fx, fy)
	return true


# 지나갈 선분에서 NINJA_SLASH_WIDTH 안이면 선분 위 거리, 아니면 -1
func _on_path(from: Vector3, fx: float, fy: float, t: Player, length: float) -> float:
	var along := (t.x - from.x) * fx + (t.y - from.y) * fy
	if along < 0.0 or along > length:
		return -1.0
	var ox := from.x + fx * along - t.x
	var oy := from.y + fy * along - t.y
	return along if sqrt(ox * ox + oy * oy) <= C.NINJA_SLASH_WIDTH else -1.0


func ninja_wall_kick(p: Player, fx: float, fy: float) -> void:
	p.vz = C.NINJA_WALLKICK_UP
	p.grounded = false
	p.kbx = 0.0
	p.kby = 0.0
	for t in players.values():
		if not foe(p, t):
			continue
		var dx: float = t.x - p.x
		var dy: float = t.y - p.y
		var d := sqrt(dx * dx + dy * dy)
		if d > C.NINJA_WALLKICK_RANGE or absf(t.z - p.z) > C.PLAYER_HEIGHT:
			continue
		var hit := apply_knockback(t, dx if d > 0.05 else -fx, dy if d > 0.05 else -fy, C.NINJA_WALLKICK_KB_SPEED, C.NINJA_WALLKICK_KB_UP, C.NINJA_WALLKICK_STUN_MS, C.NINJA_WALLKICK_DAMAGE, p.id)
		emit({"type": "hit", "kind": "wallkick", "by": p.id, "target": t.id, "ok": hit})
	emit({"type": "wallKick", "who": p.id})
	log_line("  [스킬] %s 벽 차기" % p.name)


# R 강화: NINJA_EMPOWER_MS 동안 지상 1~3타·공중 평타가 표창 2연발
func ninja_empower(p: Player) -> void:
	p.empower_until = time + C.NINJA_EMPOWER_MS
	emit({"type": "empower", "who": p.id, "ms": C.NINJA_EMPOWER_MS})
	log_line("  [필살] %s 강화 (%d초 표창)" % [p.name, int(C.NINJA_EMPOWER_MS / 1000)])


# 패시브: 공중에서 떨어지는 블록에 닿으면 (밟거나 옆면) 공중 점프 회복. 한 블록에 한 번
func ninja_touch(p: Player) -> void:
	if p.grounded and not standing_on_piece(p):
		p.touch_piece = 0
		return
	var pad := 0.06
	var x0 := p.x - C.PLAYER_HALF - pad
	var x1 := p.x + C.PLAYER_HALF + pad
	var y0 := p.y - C.PLAYER_HALF - pad
	var y1 := p.y + C.PLAYER_HALF + pad
	var z0 := p.z - pad
	var z1 := p.z + C.PLAYER_HEIGHT + pad
	for pc in pieces:
		if pc.id == p.touch_piece:
			continue
		var touch := false
		for c in pc.cells:
			var cx: int = pc.px + c.x
			var cy: int = pc.py + c.y
			if cx < x1 and cx + 1 > x0 and cy < y1 and cy + 1 > y0 and pc.pz < z1 and pc.pz + 1 > z0:
				touch = true
				break
		if not touch:
			continue
		p.touch_piece = pc.id
		p.air_jumps = C.AIR_JUMPS
		emit({"type": "ninjaTouch", "who": p.id})
		return


func standing_on_piece(p: Player) -> bool:
	var z := roundi(p.z) - 1
	for x in range(floori(p.x - C.PLAYER_HALF), floori(p.x + C.PLAYER_HALF) + 1):
		for y in range(floori(p.y - C.PLAYER_HALF), floori(p.y + C.PLAYER_HALF) + 1):
			if piece_cells.has(Vector3i(x, y, z)):
				return true
	return false


# ---------- 블록 ----------
func piece_world_cells(pc: Piece) -> Array:
	var out := []
	for c in pc.cells:
		out.append(Vector3i(pc.px + c.x, pc.py + c.y, pc.pz))
	return out


func refresh_piece_cells() -> void:
	piece_cells.clear()
	for pc in pieces:
		for c in piece_world_cells(pc):
			piece_cells[c] = pc.id


func compute_land_z(pc: Piece) -> int:
	var land := 0
	for c in pc.cells:
		land = maxi(land, column_top(pc.px + c.x, pc.py + c.y))
	return land


func update_landing(pc: Piece) -> void:
	pc.land_z = compute_land_z(pc)
	pc.fits = not (pc.land_z + 1 > H or pc.land_z > pc.pz)


func make_piece(shape: String, rot: int, px: int, py: int, pz: int) -> Piece:
	var pc := Piece.new()
	pc.shape = shape
	pc.rot = rot
	pc.cells = Pieces.rotated_cells(shape, rot)
	pc.px = px
	pc.py = py
	pc.pz = pz
	update_landing(pc)
	return pc


# 떨어지는 블록 넣기 (테스트·자동 블록 공통)
func add_falling(pc: Piece, step_ms: float) -> Piece:
	piece_counter += 1
	pc.id = piece_counter
	pc.step_ms = step_ms
	pc.next_step_at = time + step_ms
	pieces.append(pc)
	refresh_piece_cells()
	return pc


func elapsed() -> float:
	return time - round_start_time


func ramp_t() -> float:
	return clampf(elapsed() / C.RAMP_FULL_MS, 0.0, 1.0)


func auto_fall_step_ms() -> float:
	return lerpf(C.AUTO_FALL_STEP_MS, C.AUTO_FALL_STEP_MIN_MS, ramp_t())


func auto_spawn_delay_ms() -> float:
	return lerpf(C.AUTO_SPAWN_DELAY_MS, C.AUTO_SPAWN_DELAY_MIN_MS, ramp_t())


func target_concurrent() -> int:
	var n := mini(C.CONCURRENT_MAX, C.CONCURRENT_START + floori(elapsed() / C.CONCURRENT_RAMP_MS))
	return maxi(1, roundi(n * area_scale()))


# 자동 블록 자리: 들어갈 수 있는 (모양, 회전, 위치) 중 가중 무작위. 가중치 = exp(CLEAR_BIAS × 점수) (placement.gd).
# 다른 블록과 같은 기둥은 피함 (그림자가 겹치지 않게). JS 와 같게 무작위 모양을 먼저 뽑음 (CLEAR_PICK_SHAPE 면 안 씀)
func choose_auto_placement() -> Piece:
	var random_shape: String = Pieces.SHAPE_NAMES[floori(rng.randf() * Pieces.SHAPE_NAMES.size())]
	var cands := auto_candidates(random_shape)
	if cands.is_empty():
		return null
	var pick: Array = pick_candidate(cands, rng.randf())
	return make_piece(pick[0], pick[1], pick[2], pick[3], C.PIECE_SPAWN_Z)


func column_tops() -> PackedInt32Array:
	var tops := PackedInt32Array()
	tops.resize(W * D)
	for y in D:
		for x in W:
			tops[y * W + x] = column_top(x, y)
	return tops


# 후보 [모양, 회전, px, py, 점수] (JS chooseAutoPlacement 와 같은 순서)
func auto_candidates(random_shape: String) -> Array:
	var shapes: Array = Pieces.SHAPE_NAMES if C.CLEAR_BIAS > 0 and C.CLEAR_PICK_SHAPE else [random_shape]
	var sc := Scorer.new(W, D, column_tops())
	var busy_cols := PackedByteArray()
	busy_cols.resize(W * D)
	for pc in pieces:
		for c in pc.cells:
			if in_xy(pc.px + c.x, pc.py + c.y):
				busy_cols[(pc.py + c.y) * W + pc.px + c.x] = 1
	var cands := []
	for shape in shapes:
		for r in 4:
			var cells := Pieces.rotated_cells(shape, r)
			var f := Pieces.footprint(cells)
			for px in range(0, W - f.x + 1):
				for py in range(0, D - f.y + 1):
					var land := 0
					var hit := false
					for c in cells:
						var i: int = (py + c.y) * W + px + c.x
						if busy_cols[i]:
							hit = true
						land = maxi(land, sc.tops[i])
					if land + 1 > H or land > C.PIECE_SPAWN_Z or hit:
						continue
					var score := sc.score(cells, px, py, land) if C.CLEAR_BIAS > 0 else 0
					cands.append([shape, r, px, py, score])
	return cands


# u (0~1 무작위) 로 가중 뽑기
func pick_candidate(cands: Array, u: float) -> Array:
	var best := -INF
	for c in cands:
		best = maxf(best, c[4])
	var ws := PackedFloat64Array()
	ws.resize(cands.size())
	var total := 0.0
	for i in cands.size():
		ws[i] = exp(C.CLEAR_BIAS * (cands[i][4] - best)) # best 기준으로 빼서 넘침 방지
		total += ws[i]
	var x := u * total
	for i in cands.size():
		x -= ws[i]
		if x <= 0.0:
			return cands[i]
	return cands[-1]


func update_spawning() -> void:
	if time < next_spawn_at:
		return
	if pieces.size() >= target_concurrent():
		return
	var t0 := Time.get_ticks_usec() if profile else 0
	var pc := choose_auto_placement()
	if profile:
		prof["placement"] = prof.get("placement", 0) + Time.get_ticks_usec() - t0
		prof["placement_n"] = prof.get("placement_n", 0) + 1
	if pc:
		add_falling(pc, auto_fall_step_ms())
	next_spawn_at = time + auto_spawn_delay_ms()


func remove_piece(pc: Piece) -> void:
	pieces.erase(pc)
	refresh_piece_cells()


# 한 칸 아래에 다른 블록이 있으면 true (그 블록이 비킬 때까지 기다린다)
func blocked_by_piece(pc: Piece) -> bool:
	for c in piece_world_cells(pc):
		var other = piece_cells.get(c - Vector3i(0, 0, 1))
		if other != null and other != pc.id:
			return true
	return false


func update_pieces() -> void:
	update_spawning()
	for pc in pieces.duplicate():
		while pieces.has(pc) and time >= pc.next_step_at:
			if pc.pz <= pc.land_z:
				land_piece(pc)
				break
			pc.next_step_at += pc.step_ms
			if blocked_by_piece(pc):
				continue
			pc.pz -= 1
			refresh_piece_cells()
			crush_check(pc)
			if pc.pz <= pc.land_z:
				land_piece(pc)
				break


# 블록 칸이 플레이어 AABB 와 겹치면 압사 (머리 박음이면 살아남음)
func crush_check(pc: Piece) -> void:
	var cells := piece_world_cells(pc)
	for p in players.values():
		if not on_field(p):
			continue
		for c in cells:
			if c.x < p.x + C.PLAYER_HALF - EPS and c.x + 1 > p.x - C.PLAYER_HALF + EPS \
					and c.y < p.y + C.PLAYER_HALF - EPS and c.y + 1 > p.y - C.PLAYER_HALF + EPS \
					and c.z < p.z + C.PLAYER_HEIGHT - EPS and c.z + 1 > p.z + EPS:
				if head_bonk(p, pc):
					break
				kill(p, "crush")
				break


# 블록 아래면 ~ 몸 아래 기둥 꼭대기(필드 밖이면 끝없이) 빈 공간이 CRUSH_ESCAPE_CELLS 이상이면 압사 대신 밀어 내림
func head_bonk(p: Player, pc: Piece) -> bool:
	var bottom := pc.pz
	var floor_z := -INF
	var h := C.PLAYER_HALF - EPS
	for cx in range(floori(p.x - h), floori(p.x + h) + 1):
		for cy in range(floori(p.y - h), floori(p.y + h) + 1):
			if not in_xy(cx, cy):
				continue
			var top := 0
			for z in range(mini(bottom, H) - 1, -1, -1):
				var other = piece_cells.get(Vector3i(cx, cy, z))
				if grid[idx(cx, cy, z)] != 0 or (other != null and other != pc.id):
					top = z + 1
					break
			floor_z = maxf(floor_z, top)
	if bottom - floor_z < C.CRUSH_ESCAPE_CELLS:
		return false
	p.z = bottom - C.PLAYER_HEIGHT
	p.vz = minf(p.vz, 0.0)
	p.grounded = false
	p.stun_until = maxf(p.stun_until, time + C.HEAD_BONK_STUN_MS)
	emit({"type": "headBonk", "who": p.id})
	log_line("  [머리 박음] %s ← %s" % [p.name, pc.shape])
	return true


func land_piece(pc: Piece) -> void:
	var cell := Pieces.cell_of_shape(pc.shape)
	var cells := piece_world_cells(pc)
	for c in cells:
		if c.z >= 0 and c.z < H:
			grid[idx(c.x, c.y, c.z)] = cell
	emit({"type": "land", "cells": cells.map(func(c): return [c.x, c.y, c.z])})
	remove_piece(pc)
	grid_version += 1
	clear_layers()
	for other in pieces:
		update_landing(other)
	next_spawn_at = maxf(next_spawn_at, time + auto_spawn_delay_ms())


# 한 층이 꽉 차면 제거하고 위의 블록·플레이어를 내린다 (용암도 같이)
func clear_layers() -> void:
	var layer := W * D
	var full := []
	for z in H:
		var ok := true
		for i in layer:
			if grid[z * layer + i] == 0:
				ok = false
				break
		if ok:
			full.append(z)
	if full.is_empty():
		return
	var next := PackedByteArray()
	next.resize(grid.size())
	var dst := 0
	for z in H:
		if full.has(z):
			continue
		for i in layer:
			next[dst * layer + i] = grid[z * layer + i]
		dst += 1
	grid = next
	grid_version += 1
	for p in players.values():
		var shift := 0
		for z in full:
			if p.z >= z + 1 - 1e-3:
				shift += 1
		p.z -= shift
	if lava.active:
		lava.z -= full.filter(func(z): return z < lava.z).size()
	emit({"type": "clear", "n": full.size()})
	log_line("  [층 클리어] z=%s" % str(full))


# ---------- 용암 ----------
func update_lava(dt_ms: float) -> void:
	if not lava.active:
		if avg_height() - base_avg_height < C.LAVA_TRIGGER_AVG_HEIGHT:
			return
		lava.active = true
		lava.z = C.LAVA_START_Z
		lava.started_at = time
		emit({"type": "lava"})
		log_line("  [용암] 상승 시작 @ %.1fs" % (elapsed() / 1000.0))
		return
	lava.z = minf(H + 1, lava.z + dt_ms / C.LAVA_RISE_MS_PER_CELL)
	for p in players.values():
		if not on_field(p) or p.z >= lava.z - 0.05:
			continue
		var in_field: bool = p.x >= 0 and p.x < W and p.y >= 0 and p.y < D
		kill(p, "lava" if in_field else "fall")


# ---------- 스냅샷 (클라 그리기용) ----------
# 격자는 바뀐 판(grid_version)만 보내도 되게 따로
func snapshot() -> Dictionary:
	var ps := []
	for p in players.values():
		ps.append([p.id, p.slot, p.name, snappedf(p.x, 0.001), snappedf(p.y, 0.001), snappedf(p.z, 0.001), snappedf(p.yaw, 0.001), p.alive, p.damage, time < p.stun_until, p.wins, p.chr, int(p.ult)])
	var pcs := []
	for pc in pieces:
		var cs := []
		for c in piece_world_cells(pc):
			cs.append([c.x, c.y, c.z])
		pcs.append({"s": pc.shape, "c": cs, "l": pc.land_z})
	return {
		"type": "state", "t": time, "phase": phase, "W": W, "D": D, "H": H, "round": round_number,
		"winner": winner_id, "gv": grid_version, "lava": lava.z if lava.active else -99.0,
		"players": ps, "pieces": pcs,
	}
