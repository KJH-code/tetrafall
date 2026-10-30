# 서버 쪽 봇 (아주 단순): server/bot.js 처럼 handle_input / handle_action 만 씀 (판정 특혜 없음).
# 떨어지는 블록 밑·가장자리면 비키고, 아니면 가장 가까운 상대를 쫓아 평타·F·R. 막히면 점프
# JS 봇(1천 줄 넘음)보다 훨씬 단순 → 8명 판이 끝까지 도는지·틱 시간 확인용
extends RefCounted

const C := preload("res://sim/config.gd")

var id := 0
var think_at := 0.0
var fwd := 0.0
var yaw := 0.0
var jump := false
var rng := RandomNumberGenerator.new()


func _init(player_id: int, seed_value: int) -> void:
	id = player_id
	rng.seed = seed_value


func update(g, p) -> void:
	if g.time >= think_at:
		think_at = g.time + C.BOT_THINK_MS
		think(g, p)
	g.handle_input(id, fwd, 0.0, jump, yaw)


func think(g, p) -> void:
	jump = false
	var cx: float = g.W / 2.0
	var cy: float = g.D / 2.0
	# 1. 떨어지는 블록이 내 기둥 위에 있으면 가운데 쪽으로 틀어 비킴
	for pc in g.pieces:
		for c in pc.cells:
			var x: int = pc.px + c.x
			var y: int = pc.py + c.y
			if absf(x + 0.5 - p.x) < 0.9 and absf(y + 0.5 - p.y) < 0.9 and pc.pz > p.z:
				yaw = atan2(cy - p.y, cx - p.x) + (1.2 if rng.randf() < 0.5 else -1.2)
				fwd = 1.0
				return
	# 2. 가장자리면 안쪽으로
	var edge := 1.0
	if p.x < edge or p.y < edge or p.x > g.W - edge or p.y > g.D - edge:
		yaw = atan2(cy - p.y, cx - p.x)
		fwd = 1.0
		if not p.grounded:
			g.handle_action(id, "jump") # 공중이면 2단 점프로 복귀
		return
	# 3. 가장 가까운 상대
	var best = null
	var bd := INF
	for t in g.players.values():
		if t == p or not t.alive:
			continue
		var d := Vector2(t.x - p.x, t.y - p.y).length()
		if d < bd:
			bd = d
			best = t
	if best == null:
		fwd = 0.0
		return
	yaw = atan2(best.y - p.y, best.x - p.x)
	fwd = 1.0 if bd > 1.0 else 0.0
	if bd < 1.7:
		g.handle_action(id, "push")
	elif bd < 4.0 and g.time >= p.skill_ready_at and rng.randf() < 0.2:
		g.handle_action(id, "skill")
	if p.ult >= C.ULT_MAX and bd < 3.0:
		g.handle_action(id, "ult")
	# 앞 칸이 높으면 점프
	var fx := floori(p.x + cos(yaw) * 0.6)
	var fy := floori(p.y + sin(yaw) * 0.6)
	if g.in_xy(fx, fy) and g.column_top(fx, fy) > p.z + 0.3:
		jump = true
	if rng.randf() < 0.03:
		g.handle_action(id, "dash")
