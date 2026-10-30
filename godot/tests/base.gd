# 테스트 공통: 판 만들기·틱 돌리기·검사
extends RefCounted

const Game := preload("res://sim/game.gd")
const C := preload("res://sim/config.gd")
const TICK := 1000.0 / C.TICK_RATE

var errors: Array = []


# 2인 평지, 블록 안 떨어짐 (테스트가 직접 넣음). JS 테스트 setup 과 같음
func setup() -> Game:
	var g := Game.new()
	g.add_player(1)
	g.add_player(2)
	g.start_round()
	g.next_spawn_at = INF
	return g


func run(g: Game, ms: float) -> void:
	var t := 0.0
	while t < ms - 1e-6:
		g.tick(TICK)
		t += TICK


func check(cond: bool, msg: String) -> void:
	if not cond:
		errors.append(msg)


func near(a: float, b: float, tol: float, msg: String) -> void:
	if absf(a - b) > tol:
		errors.append("%s: %s, 기대 %s (±%s)" % [msg, a, b, tol])


# 2인 닌자 (캐릭터 켬), 평지, 블록 안 떨어짐
func setup_ninja() -> Game:
	var g := Game.new(Callable(), true)
	g.add_player(1)
	g.add_player(2)
	g.start_round()
	g.next_spawn_at = INF
	return g
