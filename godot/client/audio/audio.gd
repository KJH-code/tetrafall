# 소리 (G5, audio/audio.tscn — main.gd 가 있으면 붙임). 서버 이벤트·상태 → 효과음·곡·앰비언트·위험 지속음.
# 어느 이벤트에 어느 소리가 나는지는 client/main.js (handleEvent·feelEvent·onState) 의 sound.play 줄 그대로.
# 화면 쪽 소리 (건축가 폭발·화살 박힘·위험 차오름·KO 스매시·마지막 킬·슬로모션) 는 View.sound_cue 신호로 받음
extends Node

const C := preload("res://core/config.gd")
const SM := preload("res://audio/sound_math.gd")
const Co := preload("res://core/coords.gd")
const Sfx := preload("res://audio/sfx.gd")
const MusicNode := preload("res://audio/music.gd")

var sfx: Sfx
var music: MusicNode
var last_countdown := -1
var last_danger = null


func _ready() -> void:
	sfx = Sfx.new()
	sfx.name = "Sfx"
	add_child(sfx)
	music = MusicNode.new()
	music.name = "Music"
	music.sfx = sfx
	add_child(music)
	_apply_settings()
	View.changed.connect(func(k): if k == "sfx" or k == "music": _apply_settings())
	View.sound_cue.connect(_on_cue)
	Store.state_changed.connect(_on_state)
	Store.game_event.connect(_on_event)
	PlayerInput.action_sent.connect(_on_action)


func _apply_settings() -> void:
	sfx.set_volume(float(View.settings.get("sfx", 1.0)))
	music.set_volume(float(View.settings.get("music", 1.0)))


func _process(dt: float) -> void:
	# 내 귀 = 지금 카메라 (G1 이 그림). 없으면 내 몸
	var cam := get_viewport().get_camera_3d()
	var ear_z = null
	if cam != null:
		var g := Co.game(cam.global_position)
		sfx.listener = Vector4(g.x, g.y, g.z, Co.yaw_of(cam))
		ear_z = g.z
	music.update(Store.state if Store.in_room() else {}, dt, ear_z)


# ---------- 도움 ----------
func _me() -> Dictionary:
	return Store.me()


# 내 몸에서 거리 (main.js distToMe). 나를 모르면 null
func _dist(x, y, z = 0.0):
	var p := _me()
	if p.is_empty() or x == null:
		return null
	return sqrt((float(x) - p.x) ** 2 + (float(y) - p.y) ** 2 + ((float(z) if z != null else 0.0) - p.z) ** 2)


func _dist_p(p: Dictionary):
	return null if p.is_empty() else _dist(p.x, p.y, p.z)


func _pos(d: Dictionary, dz := 0.0) -> Vector3:
	return Vector3(d.x, d.y, float(d.get("z", 0.0)) + dz)


func _mine(e: Dictionary, key := "who") -> bool:
	return e.has(key) and Store.my_id != null and int(e[key]) == Store.my_id


func _pl(id) -> Dictionary:
	return Store.player(id) if id != null else {}


func _weapon(chr) -> String:
	return str(chr) if chr != null and C.SFX_WEAPONS.has(chr) else "none"


# ---------- 내 행동 (서버 응답 전에 바로, main.js onLocalAction) ----------
func _on_action(a: Dictionary) -> void:
	var p := _me()
	if a.get("name") == "push" and Store.phase() == "playing" and not p.is_empty() and p.alive and not p.get("controlling", false) and not p.get("stunned", false):
		sfx.play("swing." + _weapon(p.get("char")))


# ---------- 상태 (main.js onState·HUD) ----------
func _on_state(st: Dictionary, prev: Dictionary) -> void:
	var ph := str(st.get("phase", ""))
	var pph := str(prev.get("phase", ""))
	if ph == "countdown":
		var n := maxi(1, ceili(float(st.round.countdownLeft) / 1000.0))
		if n != last_countdown:
			last_countdown = n
			sfx.play("tick")
	else:
		last_countdown = -1
	if pph == "countdown" and ph == "playing":
		sfx.play("go")
	if pph == "playing" and ph == "over" and st.get("practice") == null:
		sfx.play("win")
	# 압사 경고 (머리 위 블록이 곧 깜): 없다가 생기면 삑삑
	var p := _me()
	var danger = p.get("danger") if not p.is_empty() and p.alive and ph == "playing" else null
	if danger != null and last_danger == null:
		sfx.play("danger")
	last_danger = danger


# ---------- 이벤트 (main.js handleEvent·feelEvent 의 sound.play 그대로) ----------
func _on_event(e: Dictionary) -> void:
	var me_id = Store.my_id
	var t := str(e.get("type", ""))
	match t:
		"swing":
			if _mine(e):
				return # 내 건 클릭할 때 이미 냄
			var a := _pl(e.get("who"))
			if not a.is_empty():
				sfx.play("swing." + _weapon(a.get("char")), _dist_p(a), _pos(a))
		"hit":
			_hit(e)
		"fire":
			var a := _pl(e.get("who"))
			if not a.is_empty():
				sfx.play("fire.none", 0.0 if _mine(e) else _dist_p(a))
		"melt":
			var c = e.get("cells", [null])[0]
			if c != null:
				sfx.play("sizzle", _dist(c[0] + 0.5, c[1] + 0.5, c[2]), Vector3(c[0] + 0.5, c[1] + 0.5, c[2]))
		"land":
			var cx := 0.0
			var cy := 0.0
			var cz := INF
			for c in e.cells:
				cx += c[0] + 0.5
				cy += c[1] + 0.5
				cz = minf(cz, c[2])
			cx /= e.cells.size()
			cy /= e.cells.size()
			sfx.play("land", _dist(cx, cy, cz), Vector3(cx, cy, cz))
		"death":
			var tp := _pl(e.get("who"))
			if tp.is_empty():
				return
			var d = 0.0 if _mine(e) else _dist_p(tp)
			var pos := _pos(tp, 0.8)
			if _mine(e):
				sfx.play("lose", 0.0)
			match str(e.get("cause", "")):
				"crush":
					sfx.play("crush", d, pos)
					sfx.play("land", d, pos)
				"lava":
					sfx.play("lavaDeath." + SM.hazard_style(Store.state), d, pos)
				"fall":
					sfx.play("fall", d, pos)
		"airJump":
			var a := _pl(e.get("who"))
			if not a.is_empty():
				sfx.play("airJump", 0.0 if _mine(e) else _dist_p(a))
		"pickup":
			if _mine(e):
				sfx.play("pickup")
		"bombPlace":
			sfx.play("tick", 0.0 if _mine(e) else _dist(e.x + 0.5, e.y + 0.5, e.z))
		"boom":
			sfx.play("boom", _dist(e.x, e.y, e.z), _pos(e))
		"throw":
			var a := _pl(e.get("who"))
			if not a.is_empty():
				sfx.play("swing.none", 0.0 if _mine(e) else _dist_p(a))
		"lava":
			sfx.play("rise." + SM.hazard_style(Store.state))
		"clear":
			sfx.play("clear")
		"mark": # 사냥꾼 표식 +1: 쇠 '팅' (개수만큼 높게, 꽉 차면 두 번) — 붙인 사람·붙은 사람만 (sound.js mark)
			if _mine(e, "by") or _mine(e, "target"):
				sfx.play("mark.%d" % clampi(int(e.get("n", 1)), 1, int(C.HUNTER_MARK_MAX)), 0.0)
		"leap", "star", "rush":
			sfx.play("swing.none", 0.0 if _mine(e) else _dist(e.from.x, e.from.y, e.from.z))
		"aim":
			if me_id != null and e.get("targets", []).has(float(me_id)):
				sfx.play("tick", 0.0)
		"shot":
			var chr = _pl(e.get("who")).get("char")
			sfx.play("fire.hunter" if chr == "hunter" else "fire.none", 0.0 if _mine(e) else _dist(e.from.x, e.from.y, e.from.z), _pos(e.from))
		"ultRefund":
			if _mine(e):
				sfx.play("pickup", 0.0)
		"skill", "ult":
			var a := _pl(e.get("who"))
			if not a.is_empty():
				sfx.play("boom" if t == "ult" else "swing.none", 0.0 if _mine(e) else _dist_p(a))
		"wallKick":
			var d = 0.0 if _mine(e) else _dist(e.x, e.y, e.z)
			sfx.play("airJump", d)
			sfx.play("land", d)
		"armor":
			var a := _pl(e.get("who"))
			if not a.is_empty():
				sfx.play("crit", 0.0 if _mine(e) else _dist_p(a))
		"armorBreak":
			var a := _pl(e.get("who"))
			if not a.is_empty():
				sfx.play("crush", 0.0 if _mine(e) else _dist_p(a))
		"quakeRise":
			var c = e.get("cells", [null])[0]
			if c != null:
				var d = _dist(c[0] + 0.5, c[1] + 0.5, c[2])
				sfx.play("land", d)
				sfx.play("boom", (d if d != null else 0.0) + 3)
		"quakeFall":
			var cs: Array = e.get("gone", e.get("cells", []))
			if cs.is_empty():
				cs = e.get("cells", [])
			if not cs.is_empty():
				sfx.play("land", _dist(cs[0][0] + 0.5, cs[0][1] + 0.5, cs[0][2]))
		"ninjaTouch":
			var a := _pl(e.get("who"))
			if not a.is_empty():
				sfx.play("tap", 0.0 if _mine(e) else _dist_p(a))
		"bblock":
			var c = e.cells[0]
			sfx.play("bbRise.big" if e.get("kind") == "big" else "bbRise", 0.0 if _mine(e) else _dist(c[0] + 0.5, c[1] + 0.5, c[2]))
		"bblockGone":
			var c = e.cells[0]
			sfx.play("bbBreak", _dist(c[0] + 0.5, c[1] + 0.5, c[2]))
		"bigBombWarn":
			var c = e.cells[floori(e.cells.size() / 2.0)]
			var ticks := SM.big_ticks(float(e.get("ms", C.BUILDER_BIG_FUSE_MS)))
			for i in ticks.size():
				var last: bool = i == ticks.size() - 1
				get_tree().create_timer(ticks[i] / 1000.0).timeout.connect(func(): sfx.play("bbTick.strong" if last else "bbTick", _dist(c[0] + 0.5, c[1] + 0.5, c[2])))
		"skillWindup":
			var a := _pl(e.get("who"))
			sfx.play("tick", 0.0 if _mine(e) else _dist_p(a))
		"hookThrow":
			var a := _pl(e.get("who"))
			var d = 0.0 if _mine(e) else _dist_p(a)
			var pos = null if a.is_empty() else _pos(a)
			sfx.play("swing.hook", d, pos)
			sfx.play("latch", d, pos)
		"hook":
			if e.has("block") and e.block != null:
				var c := Vector3(e.block[0] + 0.5, e.block[1] + 0.5, e.block[2] + 0.5)
				sfx.play("land", 0.0 if _mine(e) else _dist(c.x, c.y, c.z))
		"bang":
			var d = 0.0 if _mine(e) else _dist(e.x, e.y, e.z)
			sfx.play("fire.none", d)
			sfx.play("boom", d)
		"noteFire":
			sfx.play("pickup", 0.0 if _mine(e) else _dist(e.x, e.y, e.z))
		"ghostDrop":
			sfx.play("tap", _dist(e.x + 0.5, e.y + 0.5, e.z))
		"headBonk":
			var d = 0.0 if _mine(e) else _dist(e.x, e.y, e.z)
			sfx.play("tap", d)
			sfx.play("land", d)
		"dive":
			sfx.play("swing.none", 0.0 if _mine(e) else _dist(e.x, e.y, e.z))
		"diveEnd":
			if e.get("what") == "land":
				sfx.play("land", 0.0 if _mine(e) else _dist(e.x, e.y, e.z))
		"glideRing":
			sfx.play("glideRing.strong" if e.get("hits", []).size() > 0 else "glideRing", 0.0 if _mine(e) else _dist(e.x, e.y, e.z), _pos(e))
		"form":
			var d = 0.0 if _mine(e) else (_dist(e.x, e.y, e.z) if e.has("x") else null)
			sfx.play("strum.metal" if e.get("form") == "metal" else "strum", d)
			if e.get("form") == "metal":
				sfx.play("boom", d)
		"song":
			sfx.play("strum", 0.0 if _mine(e) else _dist(e.x, e.y, e.z), _pos(e))
		"amp":
			var a := _pl(e.get("who"))
			sfx.play("boom", 0.0 if _mine(e) else _dist_p(a))
		"shellFire":
			sfx.play("boom", 0.0 if _mine(e) else _dist(e.x, e.y, e.z))
		"blockBreak":
			var cs: Array = e.get("cells", [])
			if not cs.is_empty():
				sfx.play("shatter", 0.0 if _mine(e) else _dist(cs[0][0] + 0.5, cs[0][1] + 0.5, cs[0][2]))
		"reload":
			if e.has("ammo"):
				if _mine(e):
					sfx.play("latch", 0.0)
			else:
				var a := _pl(e.get("who"))
				sfx.play("latch", 0.0 if _mine(e) else _dist_p(a), null if a.is_empty() else _pos(a))
		"blockGrab":
			sfx.play("tear", 0.0 if _mine(e) else _dist(e.from[0] + 0.5, e.from[1] + 0.5, e.from[2]))
		"respawn":
			if _mine(e) and Store.state.get("practice") == null:
				sfx.play("go")


# 맞음 (main.js feelEvent hit): 치명타 딩 + 맞은 쪽·때린 쪽·남으로 나눠 '퍽' (무기·세기·콤보 순번)
func _hit(e: Dictionary) -> void:
	var tp := _pl(e.get("target"))
	var a := _pl(e.get("by"))
	if tp.is_empty() or not e.get("ok", false):
		return
	if e.get("crit", false):
		sfx.play("crit", 0.0 if _mine(e, "by") or _mine(e, "target") else _dist_p(tp), _pos(tp))
	var tier := SM.hit_tier(e)
	var key := SM.hit_key(a.get("char"), a.get("bard", {}).get("form") if a.get("bard") is Dictionary else null, tier, SM.hit_step(e))
	var vol := SM.hit_vol(tier)
	if _mine(e, "target"):
		sfx.play("hurt")
		sfx.play(key, 0.0, null, vol)
	elif _mine(e, "by"):
		sfx.play(key, null, null, vol)
	else:
		sfx.play(key, _dist_p(tp), _pos(tp), vol)


# ---------- 화면 쪽 소리 (View.sound_cue) ----------
func _on_cue(kind: String, i: Dictionary) -> void:
	var pos = Vector3(i.x, i.y, i.get("z", 0.0)) if i.has("x") else null
	var d = _dist(i.x, i.y, i.get("z", 0.0)) if i.has("x") else null
	match kind:
		"ui":
			sfx.play(str(i.get("key", "")))
		"blast":
			sfx.play("boom", d, pos)
			if i.get("wood", false):
				sfx.play("bbBlast.strong" if i.get("big", false) else "bbBlast", d, pos)
		"arrowStuck":
			sfx.play("land", d)
		"hazardRise":
			sfx.play("rise." + str(i.get("style", SM.hazard_style(Store.state))), null, pos)
		"smash", "koCrush":
			var strong: bool = i.get("me", false) or i.get("near", false)
			sfx.play(kind + (".strong" if strong else ""), 0.0 if i.get("me", false) else null, pos)
		"final":
			sfx.play("final", null, pos, 1.0, 0.0, true)
			music.duck(C.KO_FINAL_MS / 1000.0)
		"slowmo":
			sfx.slowmo(float(i.get("scale", 1.0)))
