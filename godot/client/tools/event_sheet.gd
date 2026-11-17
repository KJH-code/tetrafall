# 돌발 이벤트 견본 (c9-u3): 서버·봇 없이 이벤트 세계 연출 (fx/event_fx.gd) 을 정해진 판·시각·카메라로 찍음 (찍을 때마다 같은 사진 → 모양을 바꾸기 전·뒤 비교용)
#   xvfb-run -a godot --path godot/client --resolution 1280x720 --rendering-driver opengl3 -s res://tools/event_sheet.gd -- --out <폴더> [--only wind,ice] [--low]
# 나오는 파일 (20장): ev-<종류>-<바닥>-<시점>.png
#   종류 KINDS 5: wind 돌풍 (meadow 는 +x 쪽, volcano 는 +y 쪽 — 두 장에서 줄의 긴 축이 90도 다름) · ice 빙판 · lowgrav 저중력 · rain 블록 폭우 · supply 보급
#   바닥 FLOORS 2: meadow (밝은 초원) · volcano (어두운 화산) / 시점 2: eye (가장자리 칸 눈높이) · over (비스듬히 위에서 필드 전체)
#   --low 면 그래픽 낮춤으로 5장만: ev-<종류>-meadow-over-low.png (줄·티끌 수가 줄고 반짝 줄이 꺼짐, 빙판 판·빛 기둥은 그대로)
# 판 그리기 (world/world.tscn) 를 효과 견본 (tools/fx_sheet.gd) 처럼 띄우고 가짜 판 상태를 넣음: 지형 단 둘 · 사람 하나 (발밑 고리) · 떨어지는 블록 하나 (그림자 칸·착지 테) · 보급이면 아이템 셋.
# 이벤트 연출은 판의 효과 노드 (world.fx_root 아래 fx.gd) 의 event_fx 를 그대로 씀 — 판 효과 노드의 프레임 처리를 끄고 event_fx.update 를 손으로 STEP 초씩 돌려 시각을 맞춤 (줄·티끌·판 자리는 번호 해시라 늘 같음).
# 엔진 시간은 안 멈춤 (멈추면 사람 몸 자세가 dt 0 으로 깨짐) — 사람 몸의 숨쉬기 자세만 찍을 때마다 조금 다를 수 있음.
# 끝나면 저장한 파일 목록 (출력 줄 머리는 '효과 사진' — 본문 글꼴 글자 검사가 스크립트 따옴표 글을 다 훑어서 글꼴에 있는 글자만 씀), 종료 코드 0 (못 만든 사진·스크립트 오류가 있으면 1, 그릴 수 없는 환경 (--headless) 이면 2)
extends SceneTree

const K := preload("res://tools/gallery_config.gd")
const C := preload("res://core/config.gd")
const Co := preload("res://core/coords.gd")
const WC := preload("res://world/world_config.gd")
const LP := preload("res://world/lobby_preview.gd")
const Cells := preload("res://world/cells.gd")
const ExtMotion := preload("res://chars/ext_motion.gd")

const KINDS := ["wind", "ice", "lowgrav", "rain", "supply"]
const FLOORS := [["meadow", "flat", [1.0, 0.0]], ["volcano", "bowl", [0.0, 1.0]]] # [테마 이름 (파일 이름에), 그 테마 맵 id, 돌풍 방향 (게임 x, y)]
const VIEWS := ["eye", "over"]
const TOTAL_MS := {"wind": 5000.0, "ice": 6000.0, "lowgrav": 6000.0, "rain": 6000.0, "supply": 0.0} # 서버 이벤트 길이 (ConfigEvents.cs EVENT_*_MS)
const SHOT_AT := {"wind": 2.0, "ice": 2.0, "lowgrav": 2.0, "rain": 2.0, "supply": 0.3} # 이벤트 시작 뒤 찍는 시각 (초)
const STEP := 1.0 / 30.0 # 연출을 손으로 돌리는 한 걸음 (초)
const HOLD_FRAMES := 3 # 시점만 바뀐 장면에서 찍기 전 그릴 프레임
const EYE_LOOK_Z := 1.0 # 눈높이 시점이 보는 높이 (필드 가운데 위)
# 가짜 판 (필드 가운데 기준 칸 오프셋): 지형 단 [dx0, dx1, dy0, dy1, 높이] · 사람 [dx, dy] · 떨어지는 블록 칸 [dx, dy] 와 높이 · 아이템 [dx, dy]
const STEPS := [[-6, -3, -1, 1, 1], [-5, -4, 0, 1, 2], [3, 5, 0, 2, 1]]
const MAN := [-1.5, -4.0]
const PIECE := {"cells": [[1, -2], [2, -2], [3, -2], [2, -1]], "z": 5, "shape": "T", "eta": 2400.0}
const ITEMS := [[-3, -5], [3, -6], [-5, 1]]


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
var only: Array = KINDS
var low := false
var jobs: Array = [] # [파일 이름, 바닥 [테마, 맵, 돌풍 방향], 종류, 시점]
var job_i := -1
var wait := 0
var saved: Array = []
var failed: Array = []
var counts: Array = [] # 장마다 그린 인스턴스 수 (출력 줄)
var done := false
var errors := ErrorLog.new()
var store: Node
var view: Node
var world: Node3D
var efx: Node3D # 판 효과 노드의 event_fx
var cam := Camera3D.new()
var grid_ver := 3000
var last_floor := ""
var t0 := 0
var clock_steps := 0 # 몸 동작 가상 시계 걸음 (그린 프레임 수)


func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	for i in a.size():
		if a[i] == "--out" and i + 1 < a.size():
			out_dir = a[i + 1]
		elif a[i] == "--only" and i + 1 < a.size():
			only = Array(a[i + 1].split(",", false))
		elif a[i] == "--low":
			low = true
	if DisplayServer.get_name() == "headless":
		print("효과 사진: 화면을 그릴 수 없는 환경 (--headless) 입니다 — xvfb-run -a godot --rendering-driver opengl3 … 로 돌리세요")
		_end(2)
		return
	for k in only:
		if not KINDS.has(k):
			print("효과 사진: --only 는 %s 중에서 (받은 것 '%s')" % [",".join(KINDS), k])
			_end(1)
			return
	if out_dir == "" or DirAccess.make_dir_recursive_absolute(out_dir) != OK:
		print("효과 사진: --out <폴더> 가 필요합니다 (만들 수 없는 폴더 '%s')" % out_dir)
		_end(1)
		return
	OS.add_logger(errors)
	t0 = Time.get_ticks_msec()
	ExtMotion.clock = func(): return K.clock_s(clock_steps) # 사람 몸 (외부 모델 천·클립) 은 벽시계 대신 이 시계 — 프레임마다 한 걸음 (tools/gallery.gd 와 같음)


# 첫 프레임에 (자동 로드 View 의 _ready 가 user://settings.json 을 읽은 뒤): 설정 고정 → 판·카메라
func _setup() -> void:
	store = root.get_node("Store")
	view = root.get_node("View")
	for k in K.SETTINGS:
		view.settings[k] = K.SETTINGS[k]
	view.settings["third"] = true # 사람 몸이 보이게 (1인칭이면 내 몸을 끔 — 여기선 내가 없지만 같은 설정으로)
	view.settings["lowGfx"] = low
	view.settings["gfx"] = K.gfx_choice(low)
	world = load("res://world/world.tscn").instantiate()
	root.add_child(world)
	var wfx: Node = world.fx_root.get_child(0)
	wfx.set_process(false) # 판 효과 노드가 판 카메라·dt 0 으로 event_fx 를 돌리지 않게 — 이 도구가 손으로 돌림
	efx = wfx.event_fx
	cam.near = WC.CAM_CLIP[0]
	cam.far = WC.CAM_CLIP[1]
	root.add_child(cam)
	cam.make_current()
	for fl in FLOORS:
		for kind in KINDS:
			if not only.has(kind):
				continue
			if low:
				if str(fl[0]) == "meadow":
					jobs.append(["ev-%s-%s-over-low.png" % [kind, fl[0]], fl, kind, "over"])
				continue
			for v in VIEWS:
				jobs.append(["ev-%s-%s-%s.png" % [kind, fl[0], v], fl, kind, v])


func _end(code: int) -> void:
	done = true
	ExtMotion.clock = Callable() # 끝나면 가상 시계를 뺌
	quit(code)


func _process(_dt: float) -> bool:
	if done:
		return true
	if world == null:
		_setup()
	clock_steps += 1
	if job_i >= 0:
		wait -= 1
		if wait > 0:
			_tick(0.0) # 판 카메라가 바뀌어도 줄이 이 카메라를 보게 (시각은 그대로)
			return false
		_save(str(jobs[job_i][0]))
	job_i += 1
	if job_i >= jobs.size():
		_report()
		return true
	var job: Array = jobs[job_i]
	cam.make_current() # 판 카메라 (cam_rig) 는 자기 _ready 에서 current 가 됨 → 장면마다 다시 가져옴
	var floor_id := str(job[1][0])
	wait = HOLD_FRAMES
	if floor_id != last_floor:
		_stage(str(job[1][1]))
		wait = K.FIRST_WARM_FRAMES * 3 # 사람 몸 (외부 모델) 이 올라올 때까지 넉넉히
		last_floor = floor_id
	elif job_i == 0 or str(jobs[job_i - 1][2]) != str(job[2]):
		wait = K.WARM_FRAMES
	_aim(str(job[3]))
	_run(str(job[2]), job[1][2])
	return false


func _save(file: String) -> void:
	var img := root.get_texture().get_image()
	var path := out_dir.path_join(file)
	if img == null or img.is_empty() or img.save_png(path) != OK:
		failed.append(file)
		return
	saved.append("%s (%d×%d)" % [path, img.get_width(), img.get_height()])
	var n := []
	for id in efx.layers:
		var node: MultiMeshInstance3D = efx.layers[id]
		if node.visible:
			n.append("%s %d" % [id, node.multimesh.visible_instance_count])
	counts.append("%s 그림 %s" % [file, ", ".join(n) if not n.is_empty() else "없음"])


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
	print("효과 사진: %d장 저장, 실패 %d, 오류 %d줄, %.1f초%s" % [saved.size(), failed.size(), errors.lines.size(), (Time.get_ticks_msec() - t0) / 1000.0, " (그래픽 낮춤)" if low else ""])
	_end(0 if ok else 1)


# ---------- 가짜 판 ----------
static func field_n() -> int:
	return LP.field_size_for(K.PLAYERS)


static func mid_cell() -> Vector2i:
	return Vector2i(field_n() / 2, field_n() / 2)


# 판 중 (playing) 스냅샷 모양으로: 지형 단 둘 + 사람 하나 + 떨어지는 블록 하나 (아이템은 보급 장면에서만 _run 이 넣음)
func _stage(map_id: String) -> void:
	var n := field_n()
	var h := int(C.GRID_H)
	var m := mid_cell()
	var grid := PackedByteArray()
	grid.resize(n * n * h)
	for s in STEPS:
		for x in range(m.x + int(s[0]), m.x + int(s[1]) + 1):
			for y in range(m.y + int(s[2]), m.y + int(s[3]) + 1):
				for z in int(s[4]):
					grid[(z * n + y) * n + x] = Cells.TERRAIN
	var cells := []
	var shadow := []
	for c in PIECE.cells:
		cells.append([m.x + int(c[0]), m.y + int(c[1]), int(PIECE.z)])
		shadow.append([m.x + int(c[0]), m.y + int(c[1])])
	var piece := {"id": 1, "shape": str(PIECE.shape), "cells": cells, "phase": "falling", "controller": null, "thrown": false, "ghostBy": null, "sky": false,
		"landZ": 0, "fits": true, "shadow": shadow, "shadowVisible": true, "eta": float(PIECE.eta), "timeLeft": 0}
	var man := {"id": 1, "slot": 0, "away": false, "color": 0, "name": "P1", "nick": "", "spectator": false, "team": null, "isBot": true,
		"x": m.x + float(MAN[0]), "y": m.y + float(MAN[1]), "z": 0.0, "yaw": -PI / 2.0, "pitch": 0.0, "alive": true, "stunned": false, "hasControl": false,
		"dummy": false, "emote": -1, "emoteLeft": 0, "held": null, "damage": 0.0, "wins": 0, "controlling": false, "cause": null, "master": false, "zombie": false,
		"char": "ninja", "skillCd": 0, "ult": 0, "ultMax": 100, "iframeLeft": 0, "combo": 0, "marks": [], "respawnIn": null}
	grid_ver += 1
	store.my_id = null
	store.grid = grid
	store.grid_version = grid_ver
	store.state = {
		"phase": "playing", "mode": "survival", "time": 0.0, "gridVersion": grid_ver,
		"field": {"w": n, "d": n, "h": h}, "map": {"id": map_id, "choice": map_id},
		"players": [man], "pieces": [piece], "items": [], "events": [],
		"lava": {"active": false, "z": C.LAVA_START_Z}, "round": {"n": 1, "winnerId": null},
	}
	store._players_by_id = {1: man}
	# 판 빛의 하늘 어둡게는 프레임 dt 로 서서히 켜짐 — 시간 배율 0 이라 여기서 끝까지 돌려 둠
	var lf = world.light_fx
	if lf != null and lf.has_method("frame"):
		for i in ceili(1.0 / (C.GAME_LIGHT_SKY_SPEED * 0.1)) + 1:
			lf.frame(true, [], 0.1)


# 카메라: eye = −y 쪽 변 가운데 칸에 선 눈높이에서 필드 가운데를 봄 · over = 갤러리 맵 사진처럼 비스듬히 위에서 필드 전체
func _aim(v: String) -> void:
	var n := float(field_n())
	if v == "eye":
		cam.fov = C.FOV_DEFAULT
		cam.look_at_from_position(Co.gxyz(n / 2.0, 0.5, C.EYE_HEIGHT), Co.gxyz(n / 2.0, n / 2.0, EYE_LOOK_Z), Vector3.UP)
		return
	var V: Dictionary = K.MAP_OVER
	var fwd := Co.dir(deg_to_rad(float(V.yaw)), -deg_to_rad(float(V.pitch)))
	var basis := Basis.looking_at(fwd, Vector3.UP)
	var tv := tan(deg_to_rad(float(V.fov)) / 2.0) * float(V.margin)
	var th := tv * float(root.size.x) / maxf(1.0, float(root.size.y))
	var at := Co.gxyz(n / 2.0, n / 2.0, 0.0)
	var dist := 1.0
	while dist < 4000.0: # 필드 네 모서리가 화면 안에 드는 거리까지 물러남
		var inv := Transform3D(basis, at - fwd * dist).affine_inverse()
		var inside := true
		for p in [Co.gxyz(0, 0, 0), Co.gxyz(n, 0, 0), Co.gxyz(0, n, 0), Co.gxyz(n, n, 0)]:
			var q: Vector3 = inv * p
			if -q.z <= 0.01 or absf(q.x) > -q.z * th or absf(q.y) > -q.z * tv:
				inside = false
		if inside:
			break
		dist += 0.25
	cam.fov = float(V.fov)
	cam.global_transform = Transform3D(basis, at - fwd * dist)


# ---------- 이벤트 ----------
var ev_kind := ""
var ev_dir: Array = [1.0, 0.0]
var ev_t := 0.0 # 이벤트 시작 뒤 흐른 시간 (초)


# 앞 장면의 연출을 지우고 (이벤트 없음 한 걸음) 시계를 0 으로 → 이 종류를 SHOT_AT 초까지 돌림
func _run(kind: String, dir: Array) -> void:
	var st: Dictionary = store.state
	st.erase("roundEvent")
	st["items"] = []
	efx.update(0.0, cam, st, low)
	efx.clock = 0.0
	ev_kind = kind
	ev_dir = dir
	ev_t = 0.0
	var e := {"type": "roundEvent", "kind": kind, "ms": float(TOTAL_MS[kind])}
	if kind == "supply":
		var m := mid_cell()
		var items := []
		for it in ITEMS:
			var x := m.x + int(it[0])
			var y := m.y + int(it[1])
			items.append({"type": "bomb", "x": x, "y": y, "z": world.column_top(x, y)})
		st["items"] = items
	elif kind == "wind":
		e["dir"] = {"x": float(dir[0]), "y": float(dir[1])}
	efx.on_round_event(e)
	while ev_t + STEP * 0.5 < float(SHOT_AT[kind]):
		_tick(STEP)


func _tick(dt: float) -> void:
	ev_t += dt
	var st: Dictionary = store.state
	if ev_kind != "supply":
		st["roundEvent"] = {"kind": ev_kind, "left": float(TOTAL_MS[ev_kind]) - ev_t * 1000.0, "dir": {"x": float(ev_dir[0]), "y": float(ev_dir[1])} if ev_kind == "wind" else null}
	efx.update(dt, cam, st, low)
