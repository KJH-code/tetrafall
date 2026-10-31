# 클라: 서버에 입력만 보내고 받은 스냅샷을 그림 (예측 없음, JS 판과 같은 철학).
# 게임 좌표 (x, y 바닥, z 위) → 고도 Vector3(x, z, y). 헤드리스면 그리기는 건너뛰고 받은 것만 셈 (자동 확인용)
extends Node

const C := preload("res://sim/config.gd")
const Pieces := preload("res://sim/pieces.gd")

const COLORS := [Color("ff5a5a"), Color("4aa8ff"), Color("ffd23f"), Color("5ad17a"), Color("c77dff"), Color("ff9f43"), Color("48dbfb"), Color("f368e0")]
const SHAPE_COLORS := {"I": Color("4dd0e1"), "O": Color("ffd54f"), "T": Color("ba68c8"), "S": Color("81c784"), "Z": Color("e57373"), "J": Color("64b5f6"), "L": Color("ffb74d")}

var args := {}
var ws := WebSocketPeer.new()
var my_id := -1
var state := {}
var grid := PackedByteArray()
var gW := 10
var gD := 10
var gH := 16
var headless := false
var bot := false
var quit_after := 0
var rounds_seen := 0
var snapshots := 0
var first_state_ms := -1
var start_ms := 0
var last_input_at := 0
var bot_think_at := 0
var bot_input := {"fwd": 0.0, "strafe": 0.0, "jump": false, "yaw": 0.0}
var my_yaw := 0.0
var last_phase := ""

# 그리기
var cam: Camera3D
var grid_mm: MultiMeshInstance3D
var piece_pool: Array = [] # 떨어지는 블록 칸 MeshInstance3D (모자라면 늘림)
var shadow_pool: Array = []
var piece_box: BoxMesh
var shadow_box: BoxMesh
var shape_mats := {}
var shadow_mat: StandardMaterial3D
var lava_mesh: MeshInstance3D
var floor_mesh: MeshInstance3D
var player_nodes := {} # id -> Node3D
var hud: Label
var built_gv := -1
var font: FontFile


# 웹엔 시스템 글꼴이 없어 한글이 네모로 나옴 → 레포 글꼴 (한글 + 라틴 부분집합)
func load_font() -> FontFile:
	var f: FontFile = load("res://assets/fonts/black-han-sans-korean.woff2")
	f.fallbacks = [load("res://assets/fonts/black-han-sans-latin.woff2")]
	return f


func _ready() -> void:
	start_ms = Time.get_ticks_msec()
	headless = DisplayServer.get_name() == "headless"
	bot = args.has("bot")
	quit_after = int(args.get("quit-after-rounds", 0))
	var url := str(args.get("url", "ws://127.0.0.1:%d" % C.PORT))
	var err := ws.connect_to_url(url)
	print("[클라] %s 접속 (%s)%s" % [url, "봇" if bot else "사람", " 헤드리스" if headless else ""])
	if err != OK:
		push_error("접속 실패 %d" % err)
	if not headless:
		build_scene()


func _process(_delta: float) -> void:
	ws.poll()
	var st := ws.get_ready_state()
	if st == WebSocketPeer.STATE_OPEN:
		if my_id < 0 and not has_meta("hello_sent"):
			set_meta("hello_sent", true)
			send({"type": "hello", "room": str(args.get("room", "A")), "name": str(args.get("name", ""))})
		while ws.get_available_packet_count() > 0:
			var m = JSON.parse_string(ws.get_packet().get_string_from_utf8())
			if typeof(m) == TYPE_DICTIONARY:
				on_message(m)
		send_input()
	elif st == WebSocketPeer.STATE_CLOSED:
		if headless:
			print("[클라 %d] 연결 끊김 (%d)" % [my_id, ws.get_close_code()])
			finish()
		elif hud:
			hud.text = "서버 연결 끊김 (%s)" % str(args.get("url", ""))
	if not headless:
		draw_state()
		# --shot 경로 --shot-after 초: 화면을 PNG 로 저장하고 끝 (데스크톱 확인용)
		if args.has("shot") and Time.get_ticks_msec() - start_ms > float(args.get("shot-after", 8)) * 1000.0:
			get_viewport().get_texture().get_image().save_png(str(args.shot))
			print("[클라] 화면 저장 %s" % args.shot)
			get_tree().quit(0)


func on_message(m: Dictionary) -> void:
	match str(m.type):
		"welcome":
			my_id = int(m.id)
			print("[클라] 내 id %d, 방 %s" % [my_id, m.room])
		"grid":
			gW = int(m.W)
			gD = int(m.D)
			gH = int(m.H)
			grid = Marshalls.base64_to_raw(m.data)
			built_gv = -1
		"state":
			state = m
			snapshots += 1
			if first_state_ms < 0:
				first_state_ms = Time.get_ticks_msec() - start_ms
				print("[클라] 첫 스냅샷 (엔진 시작 뒤 %dms)" % first_state_ms)
			var ph := str(m.phase)
			if ph == "over" and last_phase == "playing":
				rounds_seen += 1
				var me := find_me()
				print("[클라 %d] 판 %d 끝: 승자 id %d (나 %s), 스냅샷 %d개" % [my_id, int(m.round), int(m.winner), "생존" if not me.is_empty() and me[7] else "죽음", snapshots])
				if quit_after > 0 and rounds_seen >= quit_after:
					finish()
			last_phase = ph


func finish() -> void:
	print("[클라 %d] 끝: 판 %d번 봄, 스냅샷 %d개, 첫 스냅샷 %dms" % [my_id, rounds_seen, snapshots, first_state_ms])
	get_tree().quit(0 if rounds_seen >= maxi(1, quit_after) else 2)


func send(m: Dictionary) -> void:
	ws.send_text(JSON.stringify(m))


func find_me() -> Array:
	for p in state.get("players", []):
		if int(p[0]) == my_id:
			return p
	return []


# ---------- 입력 ----------
func send_input() -> void:
	var now := Time.get_ticks_msec()
	if now - last_input_at < 1000 / C.TICK_RATE:
		return
	last_input_at = now
	if bot:
		bot_update(now)
		send({"type": "input", "fwd": bot_input.fwd, "strafe": 0, "jump": bot_input.jump, "yaw": bot_input.yaw})
		return
	if headless:
		return
	# 화면 기준 WASD (카메라는 필드 남쪽에서 북쪽을 봄): 누른 방향을 바라보고 앞으로
	var v := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_W): v.y += 1
	if Input.is_physical_key_pressed(KEY_S): v.y -= 1
	if Input.is_physical_key_pressed(KEY_D): v.x += 1
	if Input.is_physical_key_pressed(KEY_A): v.x -= 1
	var fwd := 0.0
	if v != Vector2.ZERO:
		my_yaw = atan2(-v.y, v.x) # 화면 위(W) = 게임 -y
		fwd = 1.0
	send({"type": "input", "fwd": fwd, "strafe": 0, "jump": Input.is_physical_key_pressed(KEY_SPACE), "yaw": my_yaw})


func _unhandled_input(e: InputEvent) -> void:
	if bot:
		return
	if e is InputEventKey and e.pressed and not e.echo:
		match e.physical_keycode:
			KEY_SPACE: send({"type": "action", "name": "jump"})
			KEY_SHIFT: send({"type": "action", "name": "dash"})
			KEY_J: send({"type": "action", "name": "push"})
			KEY_F: send({"type": "action", "name": "skill"})
			KEY_R: send({"type": "action", "name": "ult"})
	elif e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		send({"type": "action", "name": "push"})


# 자동 확인용 봇: 가장 가까운 상대 쪽으로 걸어가 밀치고, 가끔 점프·대시. 블록 그림자 밑이면 비킴
func bot_update(now: int) -> void:
	if now < bot_think_at or state.is_empty():
		return
	bot_think_at = now + int(C.BOT_THINK_MS)
	var me := find_me()
	if me.is_empty() or not me[7] or str(state.phase) != "playing":
		bot_input = {"fwd": 0.0, "jump": false, "yaw": bot_input.yaw}
		return
	var mx: float = me[3]
	var my: float = me[4]
	var best: Array = []
	var bd := INF
	for p in state.players:
		if int(p[0]) == my_id or not p[7]:
			continue
		var d := Vector2(p[3] - mx, p[4] - my).length()
		if d < bd:
			bd = d
			best = p
	var yaw: float = bot_input.yaw
	var fwd := 0.0
	if not best.is_empty():
		yaw = atan2(best[4] - my, best[3] - mx)
		fwd = 1.0 if bd > 1.0 else 0.0
		if bd < 1.6:
			send({"type": "action", "name": "push"})
		elif bd < 4.0 and randf() < 0.1:
			send({"type": "action", "name": "skill"})
		if me.size() > 12 and int(me[12]) >= 100:
			send({"type": "action", "name": "ult"})
	# 떨어지는 블록 밑이면 가운데 쪽으로 비킴
	for pc in state.pieces:
		for c in pc.c:
			if int(c[0]) == floori(mx) and int(c[1]) == floori(my):
				yaw = atan2(state.D / 2.0 - my, state.W / 2.0 - mx) + 0.8
				fwd = 1.0
	var jump := randf() < 0.05
	if randf() < 0.03:
		send({"type": "action", "name": "dash"})
	bot_input = {"fwd": fwd, "jump": jump, "yaw": yaw}


# ---------- 그리기 ----------
func gpos(x: float, y: float, z: float) -> Vector3:
	return Vector3(x, z, y)


func build_scene() -> void:
	font = load_font()
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color("1d2440")
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color("8090c0")
	e.ambient_light_energy = 0.6
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -35, 0)
	sun.light_energy = 1.1
	sun.shadow_enabled = true
	add_child(sun)
	cam = Camera3D.new()
	cam.fov = 50
	add_child(cam)
	grid_mm = make_mm(Vector3.ONE * 0.96)
	piece_box = BoxMesh.new()
	piece_box.size = Vector3.ONE * 0.96
	shadow_box = BoxMesh.new()
	shadow_box.size = Vector3(0.9, 0.05, 0.9)
	for sname in SHAPE_COLORS:
		var m := StandardMaterial3D.new()
		m.albedo_color = SHAPE_COLORS[sname]
		shape_mats[sname] = m
	shadow_mat = StandardMaterial3D.new()
	shadow_mat.albedo_color = Color(0.75, 0.2, 0.2)
	shadow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	floor_mesh = MeshInstance3D.new()
	floor_mesh.mesh = BoxMesh.new()
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color("5f7a4a")
	floor_mesh.material_override = fm
	add_child(floor_mesh)
	lava_mesh = MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(60, 60)
	lava_mesh.mesh = pm
	var lm := StandardMaterial3D.new()
	lm.albedo_color = Color(1, 0.35, 0.1, 0.85)
	lm.emission_enabled = true
	lm.emission = Color(1, 0.3, 0.05)
	lm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	lava_mesh.material_override = lm
	lava_mesh.visible = false
	add_child(lava_mesh)
	var layer := CanvasLayer.new()
	add_child(layer)
	hud = Label.new()
	hud.position = Vector2(16, 12)
	hud.add_theme_font_override("font", font)
	hud.add_theme_font_size_override("font_size", 20)
	hud.add_theme_color_override("font_outline_color", Color.BLACK)
	hud.add_theme_constant_override("outline_size", 6)
	hud.text = "접속 중…"
	layer.add_child(hud)


# 쌓인 격자 칸: MultiMesh 하나 (착지·층 지우기 때만 다시 만듦). 떨어지는 블록·그림자는 칸 수가 적어 MeshInstance3D 묶음.
# (2026-10-30 확인: 헤드리스 크로미움 SwiftShader WebGL 에선 고도 웹 화면이 띠·큰 다각형으로 깨져 보임.
#  같은 빌드를 Mesa(ANGLE→GL) 로 띄우면 멀쩡 → 브라우저 소프트웨어 렌더러 문제, 스샷은 WEB_GL=mesa 로)
func make_mm(size: Vector3) -> MultiMeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	var inst := MultiMeshInstance3D.new()
	inst.multimesh = mm
	inst.material_override = mat
	add_child(inst)
	return inst


func pool_mesh(mesh: Mesh) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.mesh = mesh
	add_child(m)
	return m


func cell_color(v: int) -> Color:
	if v == Pieces.CELL_TERRAIN:
		return Color("8d9a6a")
	var i := v - Pieces.CELL_SHAPE_BASE
	if i >= 0 and i < Pieces.SHAPE_NAMES.size():
		return SHAPE_COLORS[Pieces.SHAPE_NAMES[i]]
	return Color.GRAY


func draw_state() -> void:
	if state.is_empty():
		return
	var W := int(state.W)
	var D := int(state.D)
	# 카메라: 필드 남쪽 위에서 비스듬히
	cam.position = Vector3(W / 2.0, W * 0.9 + 6.0, D + W * 0.7)
	cam.look_at(Vector3(W / 2.0, 3.0, D / 2.0))
	floor_mesh.mesh.size = Vector3(W, 0.5, D)
	floor_mesh.position = Vector3(W / 2.0, -0.25, D / 2.0)
	if built_gv != int(state.gv) and grid.size() == gW * gD * gH:
		built_gv = int(state.gv)
		var cells := []
		for i in grid.size():
			if grid[i] != 0:
				cells.append(i)
		var mm := grid_mm.multimesh
		mm.instance_count = cells.size()
		for k in cells.size():
			var i: int = cells[k]
			var x := i % gW
			var y := (i / gW) % gD
			var z := i / (gW * gD)
			mm.set_instance_transform(k, Transform3D(Basis(), gpos(x + 0.5, y + 0.5, z + 0.5)))
			mm.set_instance_color(k, cell_color(grid[i]))
	# 떨어지는 블록 + 착지 그림자
	var pcs: Array = state.pieces
	var k := 0
	for pc in pcs:
		for c in pc.c:
			if k >= piece_pool.size():
				piece_pool.append(pool_mesh(piece_box))
				shadow_pool.append(pool_mesh(shadow_box))
			var a: MeshInstance3D = piece_pool[k]
			a.visible = true
			a.position = gpos(c[0] + 0.5, c[1] + 0.5, c[2] + 0.5)
			a.material_override = shape_mats.get(pc.s, shadow_mat)
			var b: MeshInstance3D = shadow_pool[k]
			b.visible = true
			b.position = gpos(c[0] + 0.5, c[1] + 0.5, float(pc.l) + 0.03)
			b.material_override = shadow_mat
			k += 1
	for i in range(k, piece_pool.size()):
		piece_pool[i].visible = false
		shadow_pool[i].visible = false
	var lz := float(state.lava)
	lava_mesh.visible = lz > -50
	lava_mesh.position = Vector3(W / 2.0, lz, D / 2.0)
	# 플레이어: 몸 상자 + 코(바라보는 쪽) + 이름·%
	var seen := {}
	var lines := []
	for p in state.players:
		var id := int(p[0])
		seen[id] = true
		var node: Node3D = player_nodes.get(id)
		if node == null:
			node = make_player(int(p[1]))
			player_nodes[id] = node
		node.visible = p[7]
		node.position = gpos(p[3], p[4], p[5])
		node.rotation = Vector3(0, -float(p[6]), 0)
		var lab: Label3D = node.get_node("Label")
		lab.text = "%s%s\n%d%%" % [p[2], " (나)" if id == my_id else "", int(p[8])]
		lab.modulate = Color(1, 0.6, 0.6) if p[9] else Color.WHITE
		lines.append("%s %d%% %s 승 %d%s" % [p[2], int(p[8]), "" if p[7] else "(탈락)", int(p[10]), (" R %d" % int(p[12])) if p.size() > 12 else ""])
	for id in player_nodes.keys():
		if not seen.has(id):
			player_nodes[id].queue_free()
			player_nodes.erase(id)
	var ph := str(state.phase)
	var top := "판 %d | %s | %dx%d | 블록 %d | FPS %d" % [int(state.round), {"lobby": "대기 (2명부터 시작)", "playing": "진행 중", "over": "끝"}.get(ph, ph), W, D, pcs.size(), Engine.get_frames_per_second()]
	if ph == "over":
		var wn := "무승부"
		for p in state.players:
			if int(p[0]) == int(state.winner):
				wn = str(p[2])
		top += " | 승자 " + wn
	hud.text = top + "\n" + "\n".join(lines) + "\nWASD 이동 | Space 점프(2단) | Shift 대시 | 클릭/J 평타 | F 순간 베기 | R 강화"


func make_player(slot: int) -> Node3D:
	var root := Node3D.new()
	var body := MeshInstance3D.new()
	var cm := CapsuleMesh.new()
	cm.radius = C.PLAYER_HALF
	cm.height = C.PLAYER_HEIGHT
	body.mesh = cm
	body.position.y = C.PLAYER_HEIGHT / 2.0
	var mat := StandardMaterial3D.new()
	mat.albedo_color = COLORS[slot % COLORS.size()]
	body.material_override = mat
	root.add_child(body)
	var nose := MeshInstance3D.new()
	var nm := BoxMesh.new()
	nm.size = Vector3(0.3, 0.15, 0.15)
	nose.mesh = nm
	nose.position = Vector3(0.35, C.PLAYER_HEIGHT * 0.75, 0)
	nose.material_override = mat
	root.add_child(nose)
	var lab := Label3D.new()
	lab.name = "Label"
	lab.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lab.position.y = C.PLAYER_HEIGHT + 0.5
	lab.font = font
	lab.font_size = 48
	lab.outline_size = 12
	lab.pixel_size = 0.006
	lab.no_depth_test = true
	root.add_child(lab)
	add_child(root)
	return root
