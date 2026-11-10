# W23 외부 몸 동작 클립 (예: 닌자 ninja_anim.glb — tools/blender/tripo/anim_ninja.py 로 만든 키프레임 동작).
# 코드 구동 (figure_motion·래그돌이 우리 관절을 돌려 뼈에 옮김) 이 기본이고, 클립이 있는 상태 (서 있기·달리기·공중·평타·스킬) 에서만
# 뼈 회전을 클립 쪽으로 섞음 (Ext.sync). 맞음·경직·낙사·일어나기·도발·승리 같은 상태는 늘 코드 (래그돌) — 힘 빠진 몸은 물리가 맡음.
# 여기는 순수 계산 (노드 없음): 상태 (body._anim_state 와 같은 모양) → 어느 클립을 몇 초에 재생할지. 파일 읽기는 load_lib.
extends RefCounted

const C := preload("res://core/config.gd")

# 공격 눈금 (초, 클립 안): 준비 u 0~1 → 0~WIND, 타격 u → WIND~STRIKE, 회복 u → STRIKE~REC (anim_ninja.py WIND·STRIKE·REC 와 같음, cfg.clips.marks 로 덮음)
const MARKS := [0.30, 0.40, 0.80]


# 클립 파일 (.glb 안 AnimationPlayer) → {이름: {anim, len, rot: {뼈 이름: 트랙}, pos: {뼈 이름: 트랙}}}. 뼈 이름은 고도가 바꾼 뒤 이름 (':' → '_')
static func load_lib(path: String) -> Dictionary:
	var out := {}
	if path == "" or not ResourceLoader.exists(path):
		return out
	var scene = _take(path)
	if not (scene is PackedScene):
		return out
	var root: Node = (scene as PackedScene).instantiate()
	for ap in root.find_children("*", "AnimationPlayer", true, false):
		for nm in (ap as AnimationPlayer).get_animation_list():
			var an: Animation = (ap as AnimationPlayer).get_animation(nm)
			var rot := {}
			var pos := {}
			for i in an.get_track_count():
				var bone := String(an.track_get_path(i).get_concatenated_subnames())
				match an.track_get_type(i):
					Animation.TYPE_ROTATION_3D:
						rot[bone] = i
					Animation.TYPE_POSITION_3D:
						pos[bone] = i
			out[str(nm)] = {"anim": an, "len": an.length, "rot": rot, "pos": pos}
		break
	root.free()
	return out


# 지금 상태에 맞는 클립 (없으면 {clip: ""} = 코드 구동). cc = cfg.clips, st = 몸 상태, air_t = 공중에 뜬 뒤 초
# 돌려줌: {clip, t (초), air (참이면 발이 바닥이 아님 — 발 바닥 맞추기 안 함), kind}
static func select(cc: Dictionary, st: Dictionary, air_t: float) -> Dictionary:
	var none := {"clip": "", "t": 0.0, "air": false, "kind": ""}
	if cc.is_empty():
		return none
	# W38 도발 (전용 도발 이모트)·승리 포즈 클립 (cfg.clips.taunt / victory): 힘 빠진 상태가 아니고 방금 맞은 게 아닐 때만 — 아니면 아래대로 코드
	var weak: bool = bool(st.get("stunned", false)) or float(st.get("recover", 0.0)) > 0.0 or float(st.get("tumble", 0.0)) > 0.0 or float(st.get("flip", -1.0)) >= 0.0 \
			or float(st.get("dizzy", 0.0)) > 0.0 or float(st.get("whirl", -1.0)) >= 0.0 or float(st.get("airDash", 0.0)) > 0.0 or bool(st.get("glide", false))
	var recent: bool = st.get("hit") is Dictionary and float(st.hit.get("age", 9.0)) < float(cc.get("hit_code_s", 0.4))
	if not weak and not recent and st.get("act") == null and not bool(st.get("air", false)):
		if float(st.get("victory", -1.0)) >= 0.0 and cc.has("victory"):
			return {"clip": str(cc.victory), "t": float(st.victory), "air": false, "kind": "pose", "loop": true}
		if int(st.get("emote", -1)) == int(C.EMOTE_CHAR) and cc.has("taunt"):
			return {"clip": str(cc.taunt), "t": float(st.get("emoteT", 0.0)), "air": false, "kind": "pose"}
	# 힘 빠진·특수 자세는 늘 코드 (래그돌이 힘 빠진 몸을 굴림)
	if bool(st.get("stunned", false)) or float(st.get("recover", 0.0)) > 0.0 or float(st.get("tumble", 0.0)) > 0.0 or float(st.get("flip", -1.0)) >= 0.0 \
			or float(st.get("dizzy", 0.0)) > 0.0 or float(st.get("whirl", -1.0)) >= 0.0 or int(st.get("emote", -1)) >= 0 or float(st.get("victory", -1.0)) >= 0.0 \
			or float(st.get("airDash", 0.0)) > 0.0 or bool(st.get("glide", false)):
		return none
	var hit = st.get("hit")
	if hit is Dictionary and float(hit.get("age", 9.0)) < float(cc.get("hit_code_s", 0.4)):
		return none
	var marks: Array = cc.get("marks", MARKS)
	var act = st.get("act")
	if act is Dictionary:
		if str(act.phase) == "broken":
			return none
		var nm = (cc.get("moves", {}) as Dictionary).get(str(act.move))
		if nm == null:
			return none
		var u: float = clampf(float(act.u), 0.0, 1.0)
		var t := 0.0
		match str(act.phase):
			"wind":
				t = u * float(marks[0])
			"strike":
				t = float(marks[0]) + u * (float(marks[1]) - float(marks[0]))
			_:
				t = float(marks[1]) + u * (float(marks[2]) - float(marks[1]))
		return {"clip": str(nm), "t": t, "air": bool(act.get("air", false)), "kind": "act"}
	if bool(st.get("air", false)):
		var vz: float = float(st.get("vz", 0.0))
		if vz > float(cc.get("rise_vz", 0.8)) and air_t < 0.6:
			return {"clip": str(cc.get("jump", "")), "t": air_t, "air": true, "kind": "jump"}
		return {"clip": str(cc.get("fall", "")), "t": air_t, "air": true, "kind": "fall"}
	if float(st.get("land", 0.0)) > 0.02 and cc.has("land"):
		return {"clip": str(cc.land), "t": clampf(1.0 - float(st.land), 0.0, 1.0), "air": false, "kind": "land", "norm": true}
	if bool(st.get("walking", false)):
		var amp: float = float(st.get("hs", 0.0)) / maxf(0.1, float(cc.get("run_speed", 4.5)))
		var nm2: String = str(cc.get("run", "")) if amp >= float(cc.get("run_from", 0.55)) else str(cc.get("walk", ""))
		var rate := 1.0 # W34 박자 배율 (cfg.clips.stride {클립: [k, c, 배율]}): 코드 걸음 위상이 몸 속도에 비례하니 클립도 비례, 배율만큼 더 빨리 돌려 한 바퀴 몸 이동 거리를 다리 길이에 맞춤
		var sd = (cc.get("stride", {}) as Dictionary).get(nm2)
		if sd is Array and sd.size() > 2:
			rate = float(sd[2])
		var lt := fposmod(float(st.get("walk", 0.0)) / TAU * rate, 1.0)
		var rev: bool = bool(st.get("rev", false)) # W43 뒤로 걸음: 같은 걸음 한 바퀴를 거꾸로 (발이 땅에서 앞으로 밀림)
		if rev:
			lt = fposmod(1.0 - lt, 1.0)
		return {"clip": nm2, "t": lt, "air": false, "kind": "loco", "norm": true, "rev": rev}
	return {"clip": str(cc.get("idle", "")), "t": float(st.get("t", 0.0)), "air": false, "kind": "idle", "loop": true}


# W30: 메뉴에서 미리 요청해 둔 (스레드) 파일이면 그 결과를, 아니면 그 자리에서 읽음
static var requested := {}


static func _take(path: String):
	if requested.has(path):
		requested.erase(path)
		return ResourceLoader.load_threaded_get(path)
	return load(path)
