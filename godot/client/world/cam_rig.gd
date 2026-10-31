# 카메라 (render.js render 끝 부분 + main.js 관전 조작): 1인칭 · 3인칭 (어깨 너머, 막히면 당김) · 관전 따라가기·전체 보기 (camera.js 궤도)
# · 하늘 시점 (블록 조종·마스터: 비스듬한 원근, 90도 돌리기, 1인칭에서 날아오름). 계산은 게임 좌표, 마지막에 Co.gxyz 로 고도 좌표
# 정하는 것: View.mode ("first" | "third" | "sky" | "spectate"), View.spectate_target, PlayerInput.sky
extends Node3D

const C := preload("res://core/config.gd")
const Co := preload("res://core/coords.gd")
const Keys := preload("res://core/keys.gd")
const Cam := preload("res://world/cam_math.gd")
const SkyV := preload("res://world/sky_view.gd")
const WC := preload("res://world/world_config.gd")
const Vic := preload("res://world/victory.gd")

var cam := Camera3D.new()
var sky_blend := 0.0 # 0 = 1·3인칭, 1 = 하늘 (SKY_TRANSITION_MS 동안 섞임)
var sky_yaw := 0.0 # 하늘 화면 위쪽 방향 (게임 yaw)
var sky_yaw_shown = null
var tp_dist = null # 3인칭 실제 거리 (막히면 줄어듦)
var overview_z = null
var spec := {"target": null, "overview": false, "round": null, "dist": C.SPECTATE_DIST, "overview_dist": C.SPECTATE_OVERVIEW_DIST}
var eye := {"x": 0.0, "y": 0.0, "z": 0.0} # 이번 프레임 카메라 (게임 좌표) — 확인용
var hook = null # KO 연출 등이 카메라를 덮어씀: Callable(cam: Camera3D) (render.js camHook)
var over_at = null # 판 끝 시각 (ms, 연습이면 null)
var vic_plan = null # Vic.plan (슬로모션이 이어지는 동안 클로즈업 시작을 뒤로 밂)
var vic_t := 0.0 # 바라볼 점 at 에서 카메라 자리 to 쪽으로 걸으며 처음 막히는 곳 (격자 칸·떨어지는 블록 칸) 앞에 카메라 (camera.js orbitEye 처럼)
# — 승자가 벽·블록을 보고 서 있으면 카메라가 칸 속에 들어가 화면이 한 색이 되던 것
func pull_in(at: Dictionary, to: Dictionary, solid: Callable) -> Dictionary:
	var cells := {}
	for pc in Store.state.get("pieces", []):
		for c in pc.cells:
			cells[Vector3i(int(c[0]), int(c[1]), int(c[2]))] = true
	var dv := Vector3(to.x - at.x, to.y - at.y, to.z - at.z)
	var dist := dv.length()
	if dist < 1e-6:
		return to
	var dir := dv / dist
	var t := WC.VICTORY_PULL[1]
	while t <= dist:
		var x: float = at.x + dir.x * t
		var y: float = at.y + dir.y * t
		var z: float = at.z + dir.z * t
		if solid.call(x, y, z) or cells.has(Vector3i(floori(x), floori(y), floori(z))):
			var d := maxf(WC.VICTORY_PULL[1], t - WC.VICTORY_PULL[0])
			return {"x": at.x + dir.x * d, "y": at.y + dir.y * d, "z": at.z + dir.z * d}
		t += 0.1
	return to


# 승자·셀카 카메라가 날아간 시간 (초)
var last_phase := ""
var ghost_aim = null # world/ghost_aim.gd 노드 (World 가 넣음)
var ghost_refuse_at := -1e9 # 안 되는 투하를 누른 시각 (G4 조준 원 흔들림 자리)
var field_size = null # 그리는 판 크기 (World 가 정함: 대기실 미리보기면 미리보기 판)
var force := "" # 확인용 (명령줄 --world-view): "over" 늘 전체 보기 (WC.OVER_POSE), "third"·"first" 시점 고정


func _ready() -> void:
	cam.fov = C.FOV_DEFAULT
	cam.near = WC.CAM_CLIP[0]
	cam.far = WC.CAM_CLIP[1]
	add_child(cam)
	cam.current = true
	PlayerInput.ui_action.connect(_on_ui)


func third() -> bool:
	if force == "third" or force == "first":
		return force == "third"
	return bool(View.settings.get("third", false))


func _on_ui(id: String, pressed: bool) -> void:
	if not pressed:
		return
	if id == "view":
		View.set_setting("third", not third())
	elif (id == "viewL" or id == "viewR") and PlayerInput.sky:
		var y := SkyV.turn_yaw(PlayerInput.yaw, 1 if id == "viewL" else -1)
		PlayerInput.set_yaw_pitch(y, PlayerInput.pitch)
		sky_yaw = y


# ---------- 관전 (main.js spectating·nextTarget·마우스·휠·점프 키) ----------
func spectating() -> bool:
	var ph := Store.phase()
	var me := Store.me()
	return (ph == "playing" or ph == "countdown") and not me.is_empty() and not me.alive


func alive_others() -> Array:
	var out := []
	for p in Store.state.get("players", []):
		if p.alive and not p.get("master", false) and (Store.my_id == null or int(p.id) != Store.my_id):
			out.append(p)
	out.sort_custom(func(a, b): return a.slot < b.slot)
	return out


func next_target(dir := 1) -> void:
	var list := alive_others()
	if list.is_empty():
		spec.target = null
		return
	var i := -1
	for k in list.size():
		if spec.target != null and int(list[k].id) == int(spec.target):
			i = k
	spec.target = int(list[(i + dir + list.size()) % list.size()].id)
	spec.overview = false


func _unhandled_input(e: InputEvent) -> void:
	if not spectating() or PlayerInput.ui_blocking:
		return
	if e is InputEventMouseButton and e.pressed:
		match e.button_index:
			MOUSE_BUTTON_LEFT:
				var cd = Store.me().get("ghostCd")
				if cd == null:
					if PlayerInput.locked:
						next_target(1)
				elif ghost_aim != null and ghost_aim.aim != null and float(cd) == 0.0:
					Store.send_room({"type": "ghostDrop", "x": ghost_aim.aim.x, "y": ghost_aim.aim.y}) # 유령 투하 판: 클릭 = 조준한 칸에 떨어뜨리기 (다음 사람은 점프 키)
				else:
					ghost_refuse_at = Time.get_ticks_msec() * 1.0
			MOUSE_BUTTON_RIGHT:
				spec.overview = not spec.overview
			MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN:
				var k: float = C.SPECTATE_ZOOM_STEP if e.button_index == MOUSE_BUTTON_WHEEL_DOWN else 1.0 / C.SPECTATE_ZOOM_STEP
				if spec.overview or Store.player(spec.target).is_empty():
					spec.overview_dist = clampf(spec.overview_dist * k, C.SPECTATE_OVERVIEW_MIN, C.SPECTATE_OVERVIEW_MAX)
				else:
					spec.dist = clampf(spec.dist * k, C.SPECTATE_DIST_MIN, C.SPECTATE_DIST_MAX)
	elif e is InputEventKey and e.pressed and not e.echo:
		if Keys.norm_code(Keys.event_code(e)) == str(PlayerInput.binds.get("jump", "")):
			next_target(1)


func update_spectate() -> void:
	var rd = Store.state.get("round", {})
	var n = rd.get("n") if typeof(rd) == TYPE_DICTIONARY else null
	if spec.round != n:
		spec.merge({"target": null, "overview": false, "round": n}, true)
	if not spectating():
		View.spectate_target = null
		return
	var t := Store.player(spec.target)
	if not spec.overview and (t.is_empty() or not t.alive):
		next_target()
	View.spectate_target = null if spec.overview else spec.target


# ---------- 프레임 앞: 시점 정하기 (몸 숨김에 씀) ----------
func pre(dt: float) -> void:
	var me := Store.me()
	var sky: bool = not me.is_empty() and me.alive and (me.get("controlling", false) or me.get("master", false))
	if sky and not PlayerInput.sky:
		# 조종 시작: 보던 방향을 90도 단위로 맞추고 그 방향을 하늘 화면 위쪽으로
		var snapped := roundf(PlayerInput.yaw / (PI / 2.0)) * (PI / 2.0)
		PlayerInput.set_yaw_pitch(snapped, PlayerInput.pitch)
		sky_yaw = snapped
	PlayerInput.sky = sky
	var step := dt * 1000.0 / C.SKY_TRANSITION_MS
	sky_blend = minf(1.0, sky_blend + step) if sky else maxf(0.0, sky_blend - step)
	update_spectate()
	update_victory()
	var mode := "spectate"
	if sky:
		mode = "sky"
	elif not me.is_empty() and me.alive:
		mode = "third" if third() else "first"
	View.set_mode(mode)


# 판 끝 연출 단계 (client/main.js 판 끝 + overStage): playing → over 에 승자 고르기, 마지막 킬 슬로모션 (View.time_scale < 1) 이 이어지면 클로즈업을 그 뒤로
func update_victory() -> void:
	var st := Store.state
	var ph := Store.phase()
	var now := Time.get_ticks_msec() * 1.0
	if last_phase == "playing" and ph == "over" and st.get("practice") == null:
		over_at = now
		View.victory_id = Vic.star_of(st)
		vic_plan = Vic.plan(View.victory_id != null, 0.0, reduced())
	last_phase = ph
	if ph != "over" or over_at == null:
		over_at = null
		vic_plan = null
		View.victory_id = null
		View.victory_stage = "lobby"
		return
	var t: float = now - over_at
	var stg := Vic.stage(vic_plan, t)
	if View.time_scale < 1.0 and (stg == "slow" or stg == "closeup"):
		vic_plan = Vic.plan(View.victory_id != null, t + 1.0, reduced()) # 아직 슬로모션: 클로즈업은 끝난 뒤
		stg = Vic.stage(vic_plan, t)
	View.victory_stage = stg


func reduced() -> bool:
	return bool(View.settings.get("reducedMotion", false)) or bool(View.settings.get("lowGfx", false))


# 1인칭이면 내 몸 숨김 (3인칭은 카메라가 머리 속으로 당겨졌을 때만)
func hide_me() -> bool:
	var me := Store.me()
	if me.is_empty() or not me.alive or sky_blend > 0.0 or close_id() != null or force == "over":
		return false
	return not third() or (tp_dist if tp_dist != null else C.TP_DIST) < C.TP_HIDE_DIST


# ---------- 카메라 놓기 ----------
# shown: id -> 화면 위치 (게임 좌표 Vector3, Bodies.shown). solid: Callable(x, y, z) -> bool (격자)
func place(dt: float, shown: Dictionary, solid: Callable) -> void:
	var st := Store.state
	var f: Dictionary = st.get("field", {"w": C.GRID_W, "d": C.GRID_W})
	var w: float = f.w if field_size == null else field_size.x
	var d: float = f.d if field_size == null else field_size.y
	var me := Store.me()
	var yaw := PlayerInput.yaw
	var pitch := PlayerInput.pitch
	var look := {}
	var mine = shown.get(Store.my_id) if Store.my_id != null else null
	if force == "over":
		me = {}
		yaw = WC.OVER_POSE[0]
		pitch = WC.OVER_POSE[1]
	if not me.is_empty() and me.alive and third() and mine != null:
		var s: Vector3 = mine
		var pivot := {"x": s.x + sin(yaw) * C.TP_SIDE, "y": s.y - cos(yaw) * C.TP_SIDE, "z": s.z + C.TP_PIVOT_UP}
		var orbit := maxf(-PI / 2 + 0.05, pitch - C.TP_TILT)
		var want: float = Cam.orbit_eye(pivot, yaw, orbit, C.TP_DIST, solid, 0.1, C.TP_CAM_MARGIN).dist
		tp_dist = Cam.follow_dist(tp_dist, want, dt, C.TP_EASE_OUT)
		var e := Cam.orbit_eye(pivot, yaw, orbit, tp_dist)
		eye = {"x": e.x, "y": e.y, "z": maxf(s.z + C.TP_MIN_Z, e.z)}
		var cp := cos(pitch)
		look = {"x": pivot.x + cp * cos(yaw) * C.TP_LOOK_AHEAD, "y": pivot.y + cp * sin(yaw) * C.TP_LOOK_AHEAD, "z": pivot.z + sin(pitch) * C.TP_LOOK_AHEAD}
	elif not me.is_empty() and me.alive and mine != null:
		var s: Vector3 = mine
		eye = {"x": s.x, "y": s.y, "z": s.z + C.EYE_HEIGHT}
		var cp := cos(pitch)
		look = {"x": eye.x + cp * cos(yaw), "y": eye.y + cp * sin(yaw), "z": eye.z + sin(pitch)}
	elif force != "over" and View.spectate_target != null and shown.has(int(View.spectate_target)):
		var s: Vector3 = shown[int(View.spectate_target)]
		look = {"x": s.x, "y": s.y, "z": s.z + C.SPECTATE_LOOK_UP}
		eye = Cam.orbit_eye(look, yaw, pitch, spec.dist, solid, 0.1, C.SPECTATE_CAM_MARGIN)
	else:
		# 전체 보기: 필드 가운데, 살아 있는 사람들 높이로 천천히 따라 올라감
		var sum := 0.0
		var n := 0
		for p in st.get("players", []):
			if p.alive and shown.has(int(p.id)):
				sum += shown[int(p.id)].z
				n += 1
		var want := sum / n + C.SPECTATE_LOOK_UP if n > 0 else 2.0
		if overview_z == null:
			overview_z = want
		overview_z += (want - overview_z) * (1.0 - exp(-C.SPECTATE_OVERVIEW_FOLLOW * dt))
		look = {"x": w / 2.0, "y": d / 2.0, "z": overview_z}
		var e := Cam.orbit_eye(look, yaw, pitch, spec.overview_dist * Cam.overview_scale(maxf(w, d), C.GRID_W))
		eye = {"x": e.x, "y": e.y, "z": maxf(0.5, e.z)}
	if not (not me.is_empty() and me.alive and third()):
		tp_dist = null
	victory_camera(dt, shown, look, solid)
	var fov: float = float(View.settings.get("fov", C.FOV_DEFAULT))
	var at := Co.gxyz(eye.x, eye.y, eye.z)
	var to := Co.gxyz(look.x, look.y, look.z)
	sky_yaw_shown = sky_yaw if sky_yaw_shown == null or sky_blend == 0.0 else SkyV.ease_yaw(sky_yaw_shown, sky_yaw, minf(1.0, dt * 1000.0 / C.SKY_VIEW.turnMs * 3.0))
	if sky_blend > 0.0:
		var vp := get_viewport().get_visible_rect().size
		var P := SkyV.sky_pose(w, d, sky_yaw_shown, vp.x / maxf(1.0, vp.y))
		var t := sky_blend * sky_blend * (3.0 - 2.0 * sky_blend)
		fov = lerpf(fov, P.fov, t)
		at = at.lerp(Co.gxyz(P.pos[0], P.pos[1], P.pos[2]), t)
		to = to.lerp(Co.gxyz(P.look[0], P.look[1], P.look[2]), t)
	cam.fov = fov
	cam.position = at
	if not at.is_equal_approx(to):
		var dirv := (to - at).normalized()
		cam.look_at(to, Vector3.UP if absf(dirv.y) < 0.999 else Vector3.FORWARD)
	if hook != null and close_id() == null:
		hook.call(cam)


# 클로즈업 대상: 판 끝 승자 (closeup 동안) 또는 내 이모트 셀카 (살아서 이모트 중, 하늘 시점 아님)
func close_id():
	if View.victory_stage == "closeup" and View.victory_id != null:
		return View.victory_id
	var me := Store.me()
	if not me.is_empty() and me.alive and int(me.get("emote", -1)) >= 0 and sky_blend == 0.0 and force == "":
		return Store.my_id
	return null


# 승자·셀카 카메라 (render.js victoryCamera): 대상 앞 VICTORY_DIST·VICTORY_UP 으로 VICTORY_FLY_S 동안 날아감 (움직임 줄이기면 바로)
func victory_camera(dt: float, shown: Dictionary, look: Dictionary, solid: Callable) -> void:
	var id = close_id()
	var p := Store.player(id)
	if id == null or p.is_empty() or not shown.has(int(id)):
		vic_t = 0.0
		return
	vic_t += dt
	var s: Vector3 = shown[int(id)]
	var k := 1.0 if reduced() else minf(1.0, vic_t / C.VICTORY_FLY_S)
	var t := k * k * (3.0 - 2.0 * k)
	var yaw: float = p.yaw
	var front := {"x": s.x + cos(yaw) * C.VICTORY_DIST, "y": s.y + sin(yaw) * C.VICTORY_DIST, "z": s.z + C.VICTORY_UP}
	var lava: Dictionary = Store.state.get("lava", {})
	if lava.get("active", false): # 위험이 차오른 판: 카메라가 표면 아래로 들어가지 않게 (표면 판 밑이면 화면이 한 색)
		front.z = maxf(front.z, float(lava.z) + WC.CAM_ABOVE_HAZARD)
	var up: float = C.VICTORY_LOOK_UP if View.victory_stage == "closeup" and id == View.victory_id else 0.0
	var at := {"x": s.x, "y": s.y, "z": s.z + C.PLAYER_HEIGHT * 0.55 + up}
	front = pull_in(at, front, solid)
	for a in ["x", "y", "z"]:
		eye[a] = lerpf(eye[a], front[a], t)
		look[a] = lerpf(look[a], at[a], t)
