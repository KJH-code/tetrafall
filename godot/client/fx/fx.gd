# G5 효과 (godot/PLAN.md 7절): 서버 이벤트 → 파편·고리·흔들림·KO 연출 (main.js feelEvent·handleEvent 의 fx.*·ko.* 줄 그대로).
# world.gd 가 fx_root 에 붙이고 setup(rig) 을 부름. 카메라는 rig.hook 으로 흔들림·마지막 킬 줌 (하늘 시점이면 안 함, render.js 와 같음).
# 몸 쪽 (renderer.hitReact·skillMove·trail·blockPulse·lightBurst 등) 은 G2·G1·G3 몫이라 여기 없음.
# 다른 묶음이 읽는 것: View.time_scale (KO 슬로모션·히트스톱, 프레임 dt 에 곱함) · effects.squash_amount(id)·punch_amount(id) (몸)
extends Node3D

const C := preload("res://core/config.gd")
const FM := preload("res://fx/fx_math.gd")
const Effects := preload("res://fx/effects.gd")
const KO := preload("res://fx/ko.gd")
const Bodies := preload("res://world/bodies.gd")

var effects: Node3D
var ko: Node3D
var rig = null # world/cam_rig.gd
var last_scale := 1.0
var events := 0 # 효과를 낸 이벤트 수 (헤드리스 확인용)
var demo_next := -1.0 # 확인용 (명령줄 --fx-demo): 판 중 1.2초마다 가짜 맞음·낙사·폭발


func _init() -> void:
	effects = Effects.new()
	ko = KO.new()
	ko.fx = effects
	ko.color_of = func(id):
		var p := Store.player(id) if id != null else {}
		return Bodies.player_color(p, Store.state) if not p.is_empty() else 0xffffff
	ko.low_gfx = func(): return bool(View.settings.get("lowGfx", false))
	ko.field = func():
		var f: Dictionary = Store.state.get("field", {})
		return Vector2(float(f.get("w", C.GRID_W)), float(f.get("d", C.GRID_W)))
	add_child(effects)
	add_child(ko)


func _ready() -> void:
	add_to_group("fx")
	if OS.get_cmdline_user_args().has("--fx-demo"):
		demo_next = 0.0
	Store.game_event.connect(on_event)
	PlayerInput.action_sent.connect(_on_action)


func setup(cam_rig) -> void:
	rig = cam_rig
	rig.hook = _cam_hook


func _process(dt: float) -> void:
	var s: float = ko.time_scale()
	View.time_scale = s
	if s != last_scale:
		last_scale = s
		View.sound_cue.emit("slowmo", {"scale": s})
	if demo_next >= 0.0 and Store.phase() == "playing" and Effects.now_ms() >= demo_next:
		demo_next = Effects.now_ms() + 1200.0
		_demo()
	var sdt := minf(0.1, dt) * s
	ko.cam = rig.cam if rig != null else get_viewport().get_camera_3d()
	ko.update(sdt)
	effects.update(sdt, rig.cam if rig != null else get_viewport().get_camera_3d())


func _cam_hook(cam: Camera3D) -> void:
	if rig != null and rig.sky_blend > 0.0:
		return
	var o: Vector3 = effects.shake_offset()
	if o != Vector3.ZERO:
		cam.position += Vector3(o.x, o.z, -o.y)
	ko.cam_hook(cam)


func _demo() -> void:
	var ps: Array = Store.state.get("players", [])
	if ps.size() < 2:
		return
	var a: Dictionary = ps[0]
	var b: Dictionary = ps[1]
	var f: Dictionary = Store.state.field
	on_event({"type": "hit", "by": a.id, "target": b.id, "ok": true, "crit": randf() < 0.5})
	on_event({"type": "boom", "x": f.w / 2.0, "y": f.d / 2.0, "z": 2.0})
	on_event({"type": "death", "who": b.id, "cause": "fall", "x": -1.0, "y": f.d / 2.0, "z": -2.0, "out": {"x": -1, "y": 0}})


# 내 밀치기는 서버를 기다리지 않고 바로 팔을 뻗음 (main.js onLocalAction)
func _on_action(a: Dictionary) -> void:
	var p := Store.me()
	if a.get("name") == "push" and Store.phase() == "playing" and not p.is_empty() and p.alive and not p.get("controlling", false) and not p.get("stunned", false):
		effects.start_punch(Store.my_id)


# ---------- 도움 ----------
func _pl(id) -> Dictionary:
	return Store.player(id) if id != null else {}


func _mine(e: Dictionary, key := "who") -> bool:
	return e.get(key) != null and Store.my_id != null and int(e[key]) == Store.my_id


func _dist(x, y, z = 0.0):
	var p := Store.me()
	if p.is_empty():
		return null
	return Vector3(float(x) - p.x, float(y) - p.y, (float(z) if z != null else 0.0) - p.z).length()


func _dist_p(p: Dictionary):
	return null if p.is_empty() else _dist(p.x, p.y, p.z)


# 거리가 있고 r 보다 가까움 (JS 의 undefined < r 은 거짓)
static func _near(d, r: float) -> bool:
	return d != null and float(d) < r


static func _at(p: Dictionary, dz := 0.0) -> Vector3:
	return Vector3(float(p.x), float(p.y), float(p.get("z", 0.0)) + dz)


static func _cell(c: Array, dz := 0.0) -> Vector3:
	return Vector3(float(c[0]) + 0.5, float(c[1]) + 0.5, float(c[2]) + dz)


func _later(ms: float, f: Callable) -> void:
	get_tree().create_timer(ms / 1000.0).timeout.connect(f)


# ---------- 이벤트 ----------
func on_event(e: Dictionary) -> void:
	var t := str(e.get("type", ""))
	# 닌자 표창에 맞음: 판정은 즉시지만 맞는 효과는 표창이 날아가 닿을 때
	if t == "hit" and e.get("star", false) and not e.get("late", false):
		var late := e.duplicate()
		late.late = true
		_later(C.STAR_FLY_MS, on_event.bind(late))
		return
	var fxd := _feel(e, t)
	fxd = _skill(e, t) or fxd
	if fxd:
		events += 1


# main.js feelEvent: 맞음·착지·죽음·폭발 등 공통 타격감
func _feel(e: Dictionary, t: String) -> bool:
	var fx = effects
	match t:
		"swing":
			if not _mine(e) and not _pl(e.get("who")).is_empty():
				fx.start_punch(e.who)
				return true
		"hit":
			var tp := _pl(e.get("target"))
			var a := _pl(e.get("by"))
			if tp.is_empty():
				return false
			var chest := _at(tp, 1.0)
			if not e.get("ok", false):
				fx.burst(chest, null, 0xaaaaaa, 4, 2.0, 0.06, 0.25) # 무적이라 무시: 작은 회색 먼지만
				return true
			var dir = null
			if not a.is_empty():
				var v := Vector2(tp.x - a.x, tp.y - a.y)
				var l := v.length() if v.length() > 0 else 1.0
				dir = {"x": v.x / l, "y": v.y / l}
			var kind = e.get("kind")
			var heavy: bool = e.get("crit", false) or kind == "blast" or kind == "bigbomb"
			if e.get("crit", false):
				fx.burst(chest, dir, 0xffd030, int(C.FX_PARTICLES * 2), 8.0, 0.12, 0.6)
				fx.ring(chest, 0xffd030, 4.2)
			fx.burst(chest, dir, 0xffee40 if kind == "projectile" else (0xffa040 if heavy else 0xfff2c0), int(C.FX_PARTICLES * (2 if heavy else 1)), 7.0 if heavy else 5.0)
			fx.ring(chest, 0xffee40 if kind == "projectile" else (0xff8a10 if heavy else 0xffffff), 3.4 if heavy else 2.4)
			fx.hit_squash(e.target)
			if _mine(e, "target"):
				fx.shake(C.FX_SHAKE_HURT * (1.6 if heavy else 1.0))
			elif _mine(e, "by"):
				fx.shake(C.FX_SHAKE_HIT * (2.0 if heavy else 1.0), 150.0)
			return true
		"land":
			var cells: Array = e.get("cells", [])
			if cells.is_empty():
				return false
			var cx := 0.0
			var cy := 0.0
			var cz := INF
			for c in cells:
				cx += c[0] + 0.5
				cy += c[1] + 0.5
				cz = minf(cz, c[2])
				fx.burst(Vector3(c[0] + 0.5, c[1] + 0.5, c[2]), null, 0x9a9a9a, 5, 2.8, 0.09, 0.4)
				fx.burst(Vector3(c[0] + 0.5, c[1] + 0.5, c[2] + 0.05), {"x": 0, "y": 0}, 0xb0aaa4, 2, 0.5, 0.2, 1.3) # 천천히 가라앉는 먼지
			if _near(_dist(cx / cells.size(), cy / cells.size(), cz), 3.5):
				fx.shake(0.08, 180.0)
			return true
		"finalKill":
			ko.final(e)
			return true
		"death":
			var tp := _pl(e.get("who"))
			if tp.is_empty():
				return false
			var me := _mine(e)
			var d = 0.0 if me else _dist_p(tp)
			ko.death(e, me, d)
			if e.get("cause") == "crush":
				fx.burst(_at(tp, 0.8), null, 0xff3030, 22, 6.0, 0.12, 0.6)
				fx.burst(_at(tp, 0.1), null, 0x9a9a9a, 14, 3.5, 0.12, 0.6) # 깔린 자리 먼지
				if me:
					fx.shake(0.35, 450.0)
				elif _near(d, 4.0):
					fx.shake(0.1, 200.0)
			return true
		"airJump":
			var a := _pl(e.get("who"))
			if not a.is_empty():
				fx.burst(_at(a, 0.05), null, 0xffffff, 8, 2.5, 0.08, 0.35)
				return true
		"boom":
			var d = _dist(e.x, e.y, e.z)
			var at := _at(e)
			fx.burst(at, null, 0xff7020, 40, 9.0, 0.16, 0.7)
			fx.burst(at, null, 0x555555, 24, 5.0, 0.12, 0.9)
			fx.ring(at, 0xffa040, 4.5)
			if _near(d, 6.0):
				fx.shake(0.35 * (1.0 - float(d) / 6.0), 450.0)
			return true
		"throw":
			if _mine(e):
				fx.start_punch(Store.my_id)
				return true
		"lava":
			fx.shake(0.12, 900.0)
			return true
	return false


# main.js handleEvent: 캐릭터 스킬·아이템 등 이벤트별 파편·고리·흔들림
func _skill(e: Dictionary, t: String) -> bool:
	var fx = effects
	var me := _mine(e)
	match t:
		"mark", "markGone":
			var tp := _pl(e.get("target"))
			if tp.is_empty():
				return false
			if t == "mark":
				fx.burst(_at(tp, C.PLAYER_HEIGHT + 0.3), null, 0xff3a2a, 10 + int(e.get("n", 0)) * 4, 2.5, 0.08, 0.4)
			else:
				fx.burst(_at(tp, C.PLAYER_HEIGHT + 0.3), null, 0x886666, 5, 1.2, 0.06, 0.3)
		"leapWarn":
			var a := _pl(e.get("who"))
			if a.is_empty():
				return false
			fx.burst(_at(a, 0.1), null, 0xc0a070, 6, 1.5, 0.08, 0.3)
		"leap":
			fx.burst(_at(e.from, 0.1), null, 0xc0a070, 14, 3.5, 0.11, 0.45)
			var to := _at(e.to, 0.1)
			_later(float(e.get("ms", 0)), func(): fx.burst(to, null, 0xc0a070, 12, 3.0, 0.1, 0.4))
		"skill", "ult":
			var a := _pl(e.get("who"))
			if a.is_empty():
				return false
			var ult := t == "ult"
			fx.burst(_at(a, 0.9), null, int(C.ULT_AURA_COLOR if ult else C.SKILL_AURA_COLOR), 22 if ult else 10, 4.0, 0.1, 0.45)
		"blink":
			fx.burst(Vector3(e.from.x, e.from.y, e.to.z + 0.8), null, 0x404060, 10, 2.0, 0.1, 0.4)
			fx.burst(_at(e.to, 0.8), null, 0x404060, 10, 2.0, 0.1, 0.4)
		"wallKick":
			var wall := Vector3(e.x + e.dir.x * 0.5, e.y + e.dir.y * 0.5, e.z + 0.6)
			fx.ring(wall, 0xffffff, 3.0, 0.3)
			fx.ring(_at(e, 0.1), 0xffffff, C.NINJA_WALLKICK_RANGE * 2, 0.35, true)
			fx.burst(wall, {"x": -e.dir.x, "y": -e.dir.y}, 0xb0a090, 14, 4.0, 0.1, 0.45)
			if _near(0.0 if me else _dist(e.x, e.y, e.z), 3.0):
				fx.shake(0.12, 180.0)
		"empower", "armor", "amp", "reload", "spin", "ninjaTouch", "glide", "practiceReset", "charChange":
			return _at_player(e, t)
		"armorBreak":
			var a := _pl(e.get("who"))
			if a.is_empty():
				return false
			var pos := _at(a, 1.0)
			fx.burst(pos, null, 0xd8f0ff, 30, 9.0, 0.11, 0.6)
			fx.burst(pos, null, 0x9ab8d0, 16, 6.0, 0.08, 0.5)
			fx.ring(pos, 0xd8f0ff, 3.4, 0.3)
		"quakeRise":
			var cells: Array = e.get("cells", [])
			if cells.is_empty():
				return false
			var sum := Vector3.ZERO
			for c in cells:
				fx.burst(_cell(c, 0.1), null, int(C.QUAKE_COLOR), 6, 4.0, 0.12, 0.5)
				fx.burst(_cell(c, 0.6), {"x": 0, "y": 0}, 0x6a5e52, 2, 5.0, 0.16, 0.5) # 튀는 흙덩이
				sum += Vector3(c[0], c[1], c[2])
			sum /= cells.size()
			fx.ring(Vector3(sum.x + 0.5, sum.y + 0.5, sum.z + 0.05), int(C.QUAKE_COLOR), 6.0, 0.35, true)
			if _near(_dist(sum.x + 0.5, sum.y + 0.5, sum.z), 8.0):
				fx.shake(0.28, 350.0)
		"quakeFall":
			var cells = e.get("gone", e.get("cells", []))
			if cells == null or cells.is_empty():
				return false
			for c in cells:
				fx.burst(_cell(c, 0.1), null, int(C.QUAKE_COLOR), 4, 2.0, 0.1, 0.45)
		"charge":
			fx.burst(_at(e, 0.2), null, 0xc0a070, 14, 3.0, 0.12, 0.5)
		"slamWarn":
			# 솟을 고리 땅이 떨림: 예고 동안 고리 자리에서 흙먼지가 톡톡 + 가까우면 화면이 살짝 떨림
			var ms := float(e.get("ms", 0))
			var r := float(e.r)
			var c := _at(e, 0.05)
			for k in maxi(1, floori(ms / 90.0)):
				_later(k * 90.0, func():
					for n in 4:
						var ang := randf() * TAU
						var rr := r + randf() * C.TANK_RING_WIDTH
						fx.burst(c + Vector3(cos(ang) * rr, sin(ang) * rr, 0), {"x": 0, "y": 0}, int(C.QUAKE_COLOR), 1, 1.2, 0.1, 0.4))
			if _near(_dist(e.x, e.y, e.z), r + C.TANK_RING_WIDTH + 1.5):
				fx.shake(0.05, ms)
		"slam":
			fx.ring(_at(e, 0.1), 0xc0b090, float(e.r) * 2, 0.4, true)
			fx.burst(_at(e, 0.2), null, 0xc0b090, 28, 7.0, 0.14, 0.6)
			var m := Store.me()
			if not m.is_empty() and Vector2(m.x - e.x, m.y - e.y).length() < float(e.r) * 2:
				fx.shake(0.25, 350.0)
		"padBoost":
			if e.get("cell") == null:
				return false
			fx.burst(_cell(e.cell, 1.0), {"x": 0, "y": 0}, 0xffffff, 10, 3.0, 0.1, 0.4)
		"hook":
			if e.get("target") != null or e.get("block") == null:
				return false
			fx.burst(_cell(e.block, 0.5), null, 0x9a8a78, 8, 2.5, 0.08, 0.4) # 블록에 걸림: 돌가루
		"bang":
			var f := Vector2(cos(e.yaw), sin(e.yaw))
			var muzzle := Vector3(e.x + f.x * 0.75, e.y + f.y * 0.75, e.z + 1.15)
			fx.burst(muzzle, {"x": f.x * 1.5, "y": f.y * 1.5}, 0xffb030, 22, 9.0, 0.12, 0.25)
			fx.burst(muzzle, {"x": f.x, "y": f.y}, 0xffffe0, 10, 6.0, 0.16, 0.12)
			fx.burst(muzzle, {"x": f.x * 0.3, "y": f.y * 0.3}, 0x8a8a8a, 16, 1.5, 0.16, 1.4)
			fx.ring(muzzle, 0xffd080, 2.4, 0.18)
			if _near(0.0 if me else _dist(e.x, e.y, e.z), 4.0):
				fx.shake(0.18 if me else 0.1, 200.0)
		"noteFire":
			var dir = {"x": e.dir.x, "y": e.dir.y} if e.get("dir") != null else null
			fx.burst(_at(e), dir, int(C.BARD_NOTE_COLOR), 6, 3.0, 0.06, 0.3)
		"noteEnd":
			if e.get("what") != "expire":
				fx.burst(_at(e), null, int(C.BARD_NOTE_COLOR), 10, 3.0, 0.07, 0.4)
			else:
				fx.burst(_at(e), null, int(C.BARD_NOTE_COLOR), 4, 1.0, 0.05, 0.3)
		"headBonk":
			if not me:
				return false
			fx.shake(C.HEAD_BONK_SHAKE, 160.0)
		"diveEnd":
			var d = 0.0 if me else _dist(e.x, e.y, e.z)
			if not _near(d, 3.0) or (e.get("what") != "land" and e.get("what") != "hit"):
				return false
			if e.what == "land":
				fx.shake(0.25 if me else 0.1, 250.0)
			else:
				fx.shake(0.3 if me else 0.12, 250.0)
		"rush":
			fx.burst(_at(e.from, 0.1), null, 0xc0a070, 14, 3.5, 0.11, 0.45)
		"shellFire":
			if not me:
				return false
			var big: bool = e.get("big", false)
			fx.shake(0.3 if big else 0.14, 300.0 if big else 160.0)
		"blockBreak":
			var cells: Array = e.get("cells", [])
			if cells.is_empty():
				return false
			if _near(0.0 if me else _dist(cells[0][0] + 0.5, cells[0][1] + 0.5, cells[0][2]), 3.0):
				fx.shake(0.18 if e.get("big", false) else 0.08, 160.0)
		_:
			return false
	return true


# 그 사람 자리에서 나는 것들 (빛·김·불꽃)
func _at_player(e: Dictionary, t: String) -> bool:
	var fx = effects
	var a := _pl(e.get("who"))
	if a.is_empty():
		return false
	match t:
		"empower":
			fx.burst(_at(a, 1.0), null, int(C.EMPOWER_GLOW), 24, 5.0, 0.1, 0.6)
		"armor":
			fx.burst(_at(a, 1.0), null, 0xfff0a0, 14, 6.0, 0.06, 0.3)
		"amp":
			fx.burst(_at(a, 1.0), null, int(C.BARD_AMP_COLOR), 16, 4.0, 0.08, 0.4)
		"reload":
			if e.get("ammo") != null:
				return false
			fx.burst(_at(a, 0.75), null, 0xffd040, 12, 3.0, 0.07, 0.35)
		"spin":
			fx.burst(_at(a, 1.1), {"x": 0, "y": 0}, 0xf4f4f4, 10 + roundi(float(e.get("cut", 0)) / 2.0), 4.0, 0.14, 0.7)
			fx.ring(_at(a, 0.9), 0xff6040, 2.6, 0.3)
		"ninjaTouch":
			fx.burst(_at(a), null, 0xffffff, 8, 2.5, 0.08, 0.35)
			fx.ring(_at(a, 0.05), 0xffffff, 1.4, 0.25, true)
			fx.burst(_at(a, 0.05), null, 0xfff4b0, 6, 3.0, 0.05, 0.25) # 반짝
		"glide":
			fx.ring(_at(a, 0.1), int(C.BARD_NOTE_COLOR), 0.6, 0.3, true)
		"practiceReset":
			fx.burst(_at(a, 0.6), null, 0xffffff, 12, 2.5, 0.12, 0.5)
		"charChange":
			fx.burst(_at(a, 0.8), null, Bodies.player_color(a, Store.state), 16, 3.0, 0.12, 0.5)
	return true
