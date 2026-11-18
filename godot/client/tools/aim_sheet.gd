# 조준 견본 (c11-u1): 서버·봇 없이 손 아이템 조준 미리보기 · 놓인 폭탄 범위 고리 (world/hand_aim.gd) · '폭탄!' 화면 신호 (ui/bomb_alert.gd) 를 정해진 판·카메라로 찍음
#   xvfb-run -a godot --path godot/client --resolution 1280x720 --rendering-driver opengl3 -s res://tools/aim_sheet.gd -- --out <폴더> [--only <파일 이름에 든 글자>]
# 나오는 파일 (10장):
#   aim-brick-fp.png  기본 1인칭 (눈높이 C.EYE_HEIGHT, 고개 0, 초원): 설치 블록을 든 내 4칸 앞에 흰 반투명 상자 2칸 + 노란 테
#   aim-brick-fp-bad.png  같은 자리가 못 놓는 자리 (ok = false): 전부 빨강
#   aim-bomb-fp.png  폭탄을 든 내 4칸 앞: 부서질 3×3 칸 주황 판 + 사람이 맞는 범위 고리 (내 색, 반지름 C.BOMB_BLAST_RANGE)
#   aim-bomb-third.png  같은 장면 3인칭 (내 몸·발밑과 따로 읽히는지)
#   aim-knock-fp.png  넉백 글러브를 든 나 (조준 값 null): 세계 표시 없음
#   bomb-alert-fp.png  남의 폭탄이 내 1칸 옆 (발밑이라 화면 밖): 판 '폭탄! 고리 밖으로' + 남은 초·막대 + 가장자리 주황 테
#   bomb-alert-fp-960.png  같은 장면을 960×540 창으로 (판이 화면 안인지)
#   bomb-ring-eye-meadow.png · bomb-ring-eye-volcano.png  눈높이 가까이: 왼쪽 = 놓인 폭탄 (남은 RING_LEFT ms) 둘레의 끊긴 고리 + 주황 원, 오른쪽 = 견줄 번개 예고 고리 (연노랑 원)
#   aim-low.png  그래픽 낮춤: 설치 블록 상자 + 앞쪽에 놓인 폭탄 고리
# 판 그리기 (world/world.tscn) 에 가짜 판 상태 (스냅샷 꼴) 를 넣음 — 1·3인칭 장면은 내가 있는 판이라 판 카메라 (world/cam_rig.gd) 그대로, 눈높이 장면은 이 도구의 카메라.
# 놓인 폭탄 고리 각도는 hand_aim.hold_spin 으로, 화면 신호·번개 예고 시각은 이 도구의 시계로 고정.
# 장마다 그린 수 (상자·테·고리·폭탄 고리) 를 기대 값과 견주고, 조준 고리가 화면 높이를 얼마나 덮는지 (상한 RING_CAP) 도 잼.
# 끝나면 저장한 파일 목록 (출력 줄 머리는 '효과 사진'), 종료 코드 0 (못 만든 사진·기대와 다른 수·스크립트 오류가 있으면 1, 그릴 수 없는 환경 (--headless) 이면 2)
extends SceneTree

const K := preload("res://tools/gallery_config.gd")
const C := preload("res://core/config.gd")
const Co := preload("res://core/coords.gd")
const WC := preload("res://world/world_config.gd")
const LP := preload("res://world/lobby_preview.gd")
const ExtMotion := preload("res://chars/ext_motion.gd")
const RL := preload("res://world/ring_look.gd")
const BM := preload("res://world/bolt_fx_math.gd")
const HM := preload("res://world/hand_aim_math.gd")

# [파일, 테마 이름, 그 테마 맵 id, 장면, 시점 (fp | third | eye), 그래픽 낮춤, 창 크기 (없으면 그대로), 기대 [상자·판 수, 테 수, 조준 고리, 폭탄 고리 수]]
const JOBS := [
	["aim-brick-fp.png", "meadow", "flat", "brick", "fp", false, null, [2, 24, false, 0]],
	["aim-brick-fp-bad.png", "meadow", "flat", "brick-bad", "fp", false, null, [2, 24, false, 0]],
	["aim-bomb-fp.png", "meadow", "flat", "bomb", "fp", false, null, [9, 0, true, 0]],
	["aim-bomb-third.png", "meadow", "flat", "bomb", "third", false, null, [9, 0, true, 0]],
	["aim-knock-fp.png", "meadow", "flat", "knock", "fp", false, null, [0, 0, false, 0]],
	["bomb-alert-fp.png", "meadow", "flat", "alert", "fp", false, null, [0, 0, false, 1]],
	["bomb-alert-fp-960.png", "meadow", "flat", "alert", "fp", false, Vector2i(960, 540), [0, 0, false, 1]],
	["bomb-ring-eye-meadow.png", "meadow", "flat", "ring", "eye", false, null, [0, 0, false, 1]],
	["bomb-ring-eye-volcano.png", "volcano", "bowl", "ring", "eye", false, null, [0, 0, false, 1]],
	["aim-low.png", "meadow", "flat", "low", "fp", true, null, [2, 24, false, 1]],
]
const ME_ID := 1
const FOE_ID := 2
const ME_AT := [0.5, 2.5] # 내 자리: 필드 가운데 칸 x + 이만큼, y (−y 쪽 변에서 셋째 칸)
const YAW := PI / 2.0 # 보는 쪽 (게임 +y)
const AIM_AHEAD := 4 # 조준 칸 = 내 칸에서 이만큼 앞 (고개 0 이면 서버 AimAnchor 가 BRICK_RANGE 끝 칸을 고름)
const ME_COLOR := 0 # 내 색 (PLAYER_PALETTE 첫 색 — 방장 기본)
const ALERT_BOMB := [1, 0, 900.0] # 화면 신호 장면: 남의 폭탄 [내 칸에서 dx, dy, 남은 ms]
const LOW_BOMB := [-2, 5, 600.0] # 그래픽 낮춤 장면: 앞쪽에 놓인 남의 폭탄 (맞는 범위 밖)
const RING_BOMB := [-1, 0] # 눈높이 장면: 놓인 폭탄 [필드 가운데 칸에서 dx, dy]
const RING_LEFT := 750.0 # 그 폭탄의 남은 ms (원이 반쯤 참)
const RING_MAN := [-2.3, 1.6] # 눈높이 장면: 크기 견줄 사람 (폭탄 가운데에서)
const BOLT_AT := [3.2, 0.5] # 견줄 번개 예고 고리 가운데 (필드 가운데에서)
const BOLT_R := 1.2 # 번개 맞는 반지름 (서버 EVENT_BOLT_RADIUS)
const BOLT_MS := 1200.0
const BOLT_U := 0.6 # 찍는 순간 번개 예고가 흐른 비율
const EYE_VIEW := [5.2, 20.0, 0.3] # 눈높이 카메라: [거리 (칸), 내려다보는 각 (도), 보는 높이 (칸)]
const SPIN := 0.4 # 놓인 폭탄 고리 각도 고정 (rad)
const ALERT_NOW := 120.0 # 화면 신호 시계 (ms): 가장자리 테 깜빡임이 가장 진한 때 (blink_ms 의 반)
const RING_CAP := 0.45 # 조준 고리가 덮는 화면 높이 상한 (fx_config SCREEN_CAP 과 같은 값)
const RING_SEG := 48 # 그 높이를 잴 때 고리 둘레를 나누는 수
const SIZE_FRAMES := 12 # 창 크기를 바꾼 뒤 찍기 전 그릴 프레임


# 도는 동안 난 엔진·스크립트 오류 (tools/gallery.gd 와 같음)
class ErrorLog extends Logger:
	var lines: Array = []
	var lock := Mutex.new()

	func _log_error(function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool, error_type: int, _backtraces: Array) -> void:
		if error_type == ERROR_TYPE_WARNING:
			return
		lock.lock()
		lines.append("%s (%s:%d %s)" % [rationale if rationale != "" else code, file, line, function])
		lock.unlock()

	func _log_message(_message: String, _error: bool) -> void:
		pass


var out_dir := ""
var only := "" # 파일 이름에 이 글자가 든 장면만 (비면 전부)
var jobs: Array = []
var job_i := -1
var wait := 0
var saved: Array = []
var failed: Array = []
var counts: Array = []
var done := false
var errors := ErrorLog.new()
var store: Node
var view: Node
var input: Node
var world: Node3D
var aim: Node3D # world.hand_aim
var alert: Control # ui/bomb_alert.gd (판에서는 ui/hud_extra.gd 가 만들어 넣음)
var bolt_script: GDScript # 끝날 때 끼워 둔 시계를 빼려고 쥐고 있음
var bolt_ms := 0.0
var cam := Camera3D.new()
var grid_ver := 5000
var last_floor := ""
var last_view := ""
var is_low := false
var base_size := Vector2i.ZERO
var t0 := 0
var clock_steps := 0 # 몸 동작 가상 시계 걸음 (그린 프레임 수)


func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	for i in a.size():
		if a[i] == "--out" and i + 1 < a.size():
			out_dir = a[i + 1]
		elif a[i] == "--only" and i + 1 < a.size():
			only = a[i + 1]
	for job in JOBS:
		if only == "" or str(job[0]).contains(only):
			jobs.append(job)
	if DisplayServer.get_name() == "headless":
		print("효과 사진: 화면을 그릴 수 없는 환경 (--headless) 입니다 — xvfb-run -a godot --rendering-driver opengl3 … 로 돌리세요")
		_end(2)
		return
	if out_dir == "" or DirAccess.make_dir_recursive_absolute(out_dir) != OK:
		print("효과 사진: --out <폴더> 가 필요합니다 (만들 수 없는 폴더 '%s')" % out_dir)
		_end(1)
		return
	OS.add_logger(errors)
	t0 = Time.get_ticks_msec()
	ExtMotion.clock = func(): return K.clock_s(clock_steps) # 사람 몸 (외부 모델 천·클립) 은 벽시계 대신 이 시계 (tools/gallery.gd 와 같음)


# 첫 프레임에 (자동 로드 View 가 설정 파일을 읽은 뒤): 설정 고정 → 판·카메라·화면 신호
func _setup() -> void:
	store = root.get_node("Store")
	view = root.get_node("View")
	input = root.get_node("PlayerInput")
	base_size = root.size
	for k in K.SETTINGS:
		view.settings[k] = K.SETTINGS[k]
	_gfx(false)
	world = load("res://world/world.tscn").instantiate()
	root.add_child(world)
	aim = world.hand_aim
	aim.hold_spin = SPIN
	bolt_script = world.bolt_fx.get_script()
	bolt_script.clock = func() -> float: return bolt_ms
	alert = load("res://ui/bomb_alert.gd").new()
	root.add_child(alert)
	cam.near = WC.CAM_CLIP[0]
	cam.far = WC.CAM_CLIP[1]
	cam.fov = C.FOV_DEFAULT
	root.add_child(cam)


# 화질: 높음 · 그래픽 낮춤 (설정 파일에는 안 씀). 판이 떠 있으면 world/gfx.gd 가 다시 적용하게 알림
func _gfx(low: bool) -> void:
	is_low = low
	view.settings["lowGfx"] = low
	view.settings["gfx"] = K.gfx_choice(low)
	view.settings["outline"] = not low # 그래픽 낮춤 장면은 가장 약한 모습으로 (웹 기본값이 외곽선 끔)
	if world != null:
		view.changed.emit("gfx")


func _end(code: int) -> void:
	done = true
	ExtMotion.clock = Callable() # 끝나면 가상 시계를 뺌
	if bolt_script != null: # 정적 변수에 이 도구의 함수가 남은 채 엔진이 내려가지 않게
		bolt_script.clock = Callable()
	quit(code)


func _process(_dt: float) -> bool:
	if done:
		return true
	if world == null:
		_setup()
	clock_steps += 1
	if job_i >= 0:
		var job_now: Array = jobs[job_i]
		alert.refresh(store.state, store.me(), ALERT_NOW, true, str(view.mode), false)
		wait -= 1
		if wait > 0:
			return false
		_save(job_now)
	job_i += 1
	if job_i >= jobs.size():
		_report()
		return true
	var job: Array = jobs[job_i]
	wait = K.WARM_FRAMES
	if bool(job[5]) != is_low:
		_gfx(bool(job[5]))
		wait = K.FIRST_WARM_FRAMES
	var want: Vector2i = job[6] if job[6] != null else base_size
	if root.size != want:
		root.size = want
		wait = maxi(wait, SIZE_FRAMES)
	if str(job[1]) != last_floor or str(job[4]) != last_view:
		last_floor = str(job[1])
		last_view = str(job[4])
		wait = K.FIRST_WARM_FRAMES * 3 # 테마·사람이 바뀜: 사람 몸 (외부 모델) 이 올라올 때까지 넉넉히
	_fill(str(job[2]), str(job[3]), str(job[4]))
	return false


func _save(job: Array) -> void:
	var file := str(job[0])
	var img := root.get_texture().get_image()
	var path := out_dir.path_join(file)
	if img == null or img.is_empty() or img.save_png(path) != OK:
		failed.append(file)
		return
	saved.append("%s (%d×%d)" % [path, img.get_width(), img.get_height()])
	var got := [aim.box_mm.visible_instance_count if aim.box_mmi.visible else 0, aim.edge_mm.visible_instance_count if aim.edge_mmi.visible else 0, aim.ring.visible,
		(aim.bomb_mm.visible_instance_count / 2) if aim.bomb_mmi.visible else 0]
	var span := _ring_span() if aim.ring.visible else 0.0
	counts.append("%s 상자·판 %d · 모서리 막대 %d · 조준 고리 %s · 폭탄 고리 %d · 조준 고리 화면 높이 비 %.2f · 화면 신호 %s · draws %d · prims %d" % [file, got[0], got[1], "있음" if got[2] else "없음", got[3], span,
		"'%s %s'" % [alert.text.text, alert.sec.text] if alert.plate.visible else "없음",
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME), RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)])
	if got != job[7]:
		failed.append("%s (그린 수 %s, 기대 %s)" % [file, got, job[7]])
	if span > RING_CAP:
		failed.append("%s (조준 고리가 화면 높이 %.2f — 상한 %.2f)" % [file, span, RING_CAP])
	if (str(job[3]) == "alert") != alert.plate.visible:
		failed.append("%s (화면 신호 %s)" % [file, alert.plate.visible])
	if alert.plate.visible: # 판이 화면 안인가
		var r := Rect2(alert.plate.position, alert.plate.size)
		if not Rect2(Vector2.ZERO, alert.get_viewport_rect().size).encloses(r):
			failed.append("%s (판이 화면 밖 %s)" % [file, r])


# 조준 고리가 화면을 얼마나 덮는지: 고리 둘레 점들 (카메라 앞의 것만) 을 화면에 비춘 세로 범위 (화면 안으로 자름) ÷ 화면 높이
func _ring_span() -> float:
	var c := root.get_camera_3d()
	if c == null:
		return 0.0
	var vh := float(root.get_visible_rect().size.y)
	var r: float = aim.ring.scale.x
	var lo := INF
	var hi := -INF
	for i in RING_SEG:
		var a := TAU * i / RING_SEG
		var p: Vector3 = aim.ring.global_position + Vector3(cos(a) * r, 0, sin(a) * r)
		if c.is_position_behind(p):
			hi = vh # 카메라 뒤로 넘어가는 고리는 화면 아래 끝까지 이어짐
			continue
		var y := clampf(c.unproject_position(p).y, 0.0, vh)
		lo = minf(lo, y)
		hi = maxf(hi, y)
	return maxf(0.0, hi - lo) / vh


func _report() -> void:
	for s in saved:
		print("효과 사진 저장 %s" % s)
	for s in counts:
		print("효과 사진 %s" % s)
	for f in failed:
		print("효과 사진 실패 %s" % f)
	for e in errors.lines:
		print("효과 사진 오류 %s" % e)
	var ok := failed.is_empty() and errors.lines.is_empty() and saved.size() == jobs.size()
	print("효과 사진: %d장 저장, 실패 %d, 오류 %d줄, %.1f초" % [saved.size(), failed.size(), errors.lines.size(), (Time.get_ticks_msec() - t0) / 1000.0])
	_end(0 if ok else 1)


# ---------- 가짜 판 ----------
static func field_n() -> int:
	return LP.field_size_for(K.PLAYERS)


static func mid_x() -> int:
	return field_n() / 2


# 사람 하나 (스냅샷 players[] 꼴)
static func _man(id: int, slot: int, color: int, chr: String, x: float, y: float, yaw: float) -> Dictionary:
	return {"id": id, "slot": slot, "away": false, "color": color, "name": "P%d" % id, "nick": "", "spectator": false, "team": null, "isBot": id != ME_ID,
		"x": x, "y": y, "z": 0.0, "yaw": yaw, "pitch": 0.0, "alive": true, "stunned": false, "hasControl": false, "ammo": 0, "dashCd": 0, "airDashes": 0,
		"dummy": false, "ghostCd": null, "pushCd": 0, "jumpLeft": 0, "danger": null, "ghostLeft": 0, "speedLeft": 0, "emote": -1, "emoteLeft": 0,
		"held": null, "bombs": 0, "bricks": 0, "brickSide": false, "aim": null, "damage": 0.0, "wins": 0, "controlling": false, "cause": null, "master": false, "zombie": false,
		"char": chr, "skillCd": 0, "ult": 0, "ultMax": 100, "iframeLeft": 0, "combo": 0, "marks": [], "respawnIn": null}


# 장면을 판 상태에 넣음 (빈 바닥: 지형 없음 → 칸 높이 0) + 카메라
func _fill(map_id: String, scene: String, v: String) -> void:
	var n := field_n()
	var mx := mid_x()
	var grid := PackedByteArray()
	grid.resize(n * n * int(C.GRID_H))
	var players := []
	var bombs := []
	var me_cell := Vector2i(mx, int(ME_AT[1]))
	var ax := me_cell.x
	var ay := me_cell.y + AIM_AHEAD
	alert.clear()
	world.bolt_fx.clear()
	bolt_ms = 0.0
	if v == "eye":
		# 놓인 폭탄 (왼쪽) + 견줄 번개 예고 (오른쪽) + 크기 견줄 사람. 나는 없음 (판 카메라 대신 이 도구의 카메라)
		var bx := mx + int(RING_BOMB[0])
		var by := n / 2 + int(RING_BOMB[1])
		bombs.append({"id": 1, "x": bx, "y": by, "z": 0, "left": RING_LEFT})
		players.append(_man(FOE_ID, 1, 5, "ninja", bx + 0.5 + float(RING_MAN[0]), by + 0.5 + float(RING_MAN[1]), -PI / 2.0))
		world.bolt_fx.on_event({"type": "boltWarn", "id": 1, "x": n / 2.0 + float(BOLT_AT[0]), "y": n / 2.0 + float(BOLT_AT[1]), "z": 0.0, "r": BOLT_R, "ms": BOLT_MS})
		bolt_ms = BOLT_MS * BOLT_U
	else:
		var me := _man(ME_ID, 0, ME_COLOR, "tank", mx + float(ME_AT[0]), float(ME_AT[1]), YAW)
		players.append(me)
		match scene:
			"brick", "brick-bad", "low":
				me["held"] = "brick"
				me["bricks"] = 2
				me["aim"] = {"kind": "brick", "cells": [[ax, ay, 0], [ax, ay + 1, 0]], "z": 0, "spawnZ": int(C.BRICK_DROP_HEIGHT), "ok": scene != "brick-bad"}
				if scene == "low":
					bombs.append({"id": 1, "x": me_cell.x + int(LOW_BOMB[0]), "y": me_cell.y + int(LOW_BOMB[1]), "z": 0, "left": float(LOW_BOMB[2])})
			"bomb":
				var cells := [[ax, ay, 0]] # 서버 BombPlan 과 같은 차례: 폭탄 자리 먼저, 그 뒤 둘레 칸
				var R := int(C.BOMB_RADIUS)
				for dx in range(-R, R + 1):
					for dy in range(-R, R + 1):
						if dx != 0 or dy != 0:
							cells.append([ax + dx, ay + dy, 0])
				me["held"] = "bomb"
				me["bombs"] = 1
				me["aim"] = {"kind": "bomb", "cells": cells, "ok": true}
			"knock":
				me["held"] = "knockback"
				me["ammo"] = 1
			"alert":
				var bx := me_cell.x + int(ALERT_BOMB[0])
				var by := me_cell.y + int(ALERT_BOMB[1])
				bombs.append({"id": 1, "x": bx, "y": by, "z": 0, "left": float(ALERT_BOMB[2])})
				alert.on_event({"type": "bombPlace", "who": FOE_ID, "x": bx, "y": by, "z": 0})
	grid_ver += 1
	store.my_id = null if v == "eye" else ME_ID
	store.grid = grid
	store.grid_version = grid_ver
	store.state = {
		"phase": "playing", "mode": "survival", "time": 0.0, "gridVersion": grid_ver, "teamMode": false,
		"field": {"w": n, "d": n, "h": int(C.GRID_H)}, "map": {"id": map_id, "choice": map_id},
		"players": players, "pieces": [], "items": [], "projectiles": [], "bombs": bombs, "events": [],
		"lava": {"active": false, "z": C.LAVA_START_Z}, "round": {"n": 1, "winnerId": null},
	}
	var by_id := {}
	for p in players:
		by_id[int(p.id)] = p
	store._players_by_id = by_id
	# 판 빛의 하늘 어둡게는 프레임 dt 로 서서히 켜짐 — 여기서 끝까지 돌려 둠 (tools/event_sheet.gd 와 같음)
	var lf = world.light_fx
	if lf != null and lf.has_method("frame"):
		for i in ceili(1.0 / (C.GAME_LIGHT_SKY_SPEED * 0.1)) + 1:
			lf.frame(true, [], 0.1)
	# 카메라
	view.settings["third"] = v == "third"
	if v == "eye":
		var fwd := Co.dir(YAW, -deg_to_rad(float(EYE_VIEW[1])))
		cam.global_transform = Transform3D(Basis.looking_at(fwd, Vector3.UP), Co.gxyz(n / 2.0, n / 2.0, float(EYE_VIEW[2])) - fwd * float(EYE_VIEW[0]))
		cam.make_current()
	else:
		input.set_yaw_pitch(YAW, 0.0) # 판 카메라가 이 방향으로 (1인칭 = 내 눈 · 3인칭 = 내 뒤)
		world.rig.cam.make_current()
