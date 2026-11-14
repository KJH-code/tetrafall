# W33 동작 contact sheet: 캐릭터 몸 (--ext 외부 모델) 을 상태마다 한 칸씩, 3/4 뷰·옆 뷰로 나란히 한 장에 저장 (코드 구동 + 클립 층 진짜 길).
# 상태 = body._anim_state 와 같은 모양의 사전 (공격은 act {move, phase, u}), 발 접지·클립 섞임은 몸이 매 프레임 하는 그대로 (ext.sync).
# W49: 끝에 --preset new|old|min 을 더하면 그 모션 프리셋으로 (--w43off 는 W43 넷만).
# xvfb-run -a -s "-screen 0 1900x1000x24" godot --path godot/client --resolution 1900x1000 -s res://tools/pose_sheet.gd -- <out.png> <캐릭터> <묶음 loco|atk|skill|react|all> [yaw 도: 30 = 3/4 앞, 90 = 옆, 기본 30] [칸 폭 px, 기본 200] [--code = 외부 몸 끄기(코드 몸)] [--noclip = 클립 층 끄기 (전: 코드 구동만)] [--only 이름,이름 = 그 상태만]
extends SceneTree

const C := preload("res://core/config.gd")

# 캐릭터별 평타·스킬 공격 이름 (config BASIC_ATTACKS 와 moves 표)
const SKILLS := {
	"tank": ["tankCharge", "tankSlam"],
	"ninja": ["ninjaDash", "표창", "공중 표창", "ninjaWallKick"],
	"hunter": ["hunterLeap", "hunterAim"],
	"hook": ["hookThrow", "hookDragged", "hookZip", "hookSlam"],
}


func _base(t := 1.0) -> Dictionary:
	return {"air": false, "walking": false, "hs": 0.0, "walk": 0.0, "vz": 0.0, "t": t, "stunned": false, "dancing": false, "emote": -1, "emoteT": 0.0, "victory": -1.0, "punch": 0.0,
		"holding": false, "hit": null, "act": null, "accF": 0.0, "accS": 0.0, "tumble": 0.0, "recover": 0.0, "land": 0.0, "flip": -1.0, "rag": false, "sniffAt": null, "idle": 0.0,
		"airDash": 0.0, "mvF": 0.0, "mvS": 0.0, "vw": Vector2.ZERO, "bump": null, "whirl": -1.0, "dizzy": 0.0, "glide": false, "amp": false, "form": "", "loaded": false, "ammo": 3.0}


func _states(ch: String, group: String) -> Array:
	var out := []   # [이름, st 덮어쓰기]
	var ms: float = C.MOVE_SPEED
	if group == "loco" or group == "all":
		out.append(["idle", {"t": 0.3}])
		out.append(["idle2", {"t": 1.5}])
		for i in 4:
			out.append(["walk%d" % i, {"walking": true, "hs": ms * 0.6, "walk": i * 1.571}])
		for i in 4:
			out.append(["run%d" % i, {"walking": true, "hs": ms, "walk": i * 1.571}])
		out.append(["jump_up", {"air": true, "hs": ms, "vz": 7.0, "t": 0.1}])
		out.append(["fall", {"air": true, "hs": ms * 0.5, "vz": -9.0, "t": 0.8}])
		out.append(["land", {"land": 0.8}])
		out.append(["airdash", {"air": true, "airDash": 1.0, "hs": ms}])
	if group == "getup": # W43 일어나기: 진행 u = 0.05 … 0.95 (recover 는 코드 웅크림이 줄어드는 값, 래그돌 없음 = 모터 가중치 1)
		for u in [0.05, 0.15, 0.3, 0.45, 0.6, 0.75, 0.9, 1.0]:
			out.append(["getup_%d" % int(u * 100), {"recover": maxf(0.0, 1.0 - u / 0.64), "getup_u": u}])
	if group == "dir": # W43 방향 이동: 몸은 앞을 봄, 이동 방향 (몸 기준 앞 mvF·왼쪽 mvS) 만 다름. 걷기 (0.6) · 달리기 (1.0) × 앞·뒤·왼·오른 + 대각선
		for sp in [["walk", 0.6, 1.2], ["run", 1.0, 1.2]]:
			for d in [["fwd", 1.0, 0.0], ["back", -1.0, 0.0], ["left", 0.0, 1.0], ["right", 0.0, -1.0]]:
				var v: float = ms * float(sp[1])
				out.append(["%s_%s" % [sp[0], d[0]], {"walking": true, "hs": v, "walk": float(sp[2]), "mvF": v * float(d[1]), "mvS": v * float(d[2]), "vw": Vector2(v * float(d[1]), v * float(d[2]))}])
		for d in [["fwdL", 0.7071, 0.7071], ["backL", -0.7071, 0.7071], ["backR", -0.7071, -0.7071], ["fwdR", 0.7071, -0.7071]]:
			for sp in [["walk", 0.6, 3.2], ["run", 1.0, 3.2]]:
				var v2: float = ms * float(sp[1])
				out.append(["%s_%s" % [sp[0], d[0]], {"walking": true, "hs": v2, "walk": float(sp[2]), "mvF": v2 * float(d[1]), "mvS": v2 * float(d[2]), "vw": Vector2(v2 * float(d[1]), v2 * float(d[2]))}])
	var sets: Dictionary = C.BASIC_ATTACKS[ch]
	var atk := []
	for a in sets.chain:
		atk.append([a.name, false])
		if a.has("loaded"):
			atk.append([a.loaded.name, false])
	for a in sets.air:
		atk.append([a.name, true])
	if group == "atk" or group == "all":
		for a in atk:
			for ph in [["wind", 1.0], ["strike", 0.5], ["rec", 0.4]]:
				out.append(["%s/%s" % [a[0], ph[0]], {"air": a[1], "act": {"id": 1, "move": a[0], "phase": ph[0], "u": ph[1], "air": a[1]}, "loaded": str(a[0]) == "탕"}])
	if group == "skill" or group == "all":
		for mv in SKILLS[ch]:
			var m: Dictionary = load("res://chars/moves.gd").MOVES.get(mv, {})
			var phs := []
			if m.has("W"):
				phs.append(["wind", 1.0])
			phs.append(["strike", 0.5])
			phs.append(["rec", 0.4])
			for ph in phs:
				out.append(["%s/%s" % [mv, ph[0]], {"air": bool(m.get("float", false)), "act": {"id": 2, "move": mv, "phase": ph[0], "u": ph[1], "air": bool(m.get("float", false))}}])
	if group == "react" or group == "all":
		out.append(["hit", {"hit": {"id": 7, "age": 0.05, "stop": 0.0, "dx": -1.0, "dy": 0.0, "pow": 1.5}}])
		out.append(["stunned", {"stunned": true, "t": 0.6}])
		out.append(["tumble", {"stunned": true, "tumble": 1.0, "t": 0.9}])
		out.append(["recover", {"recover": 0.6}])
		out.append(["flip", {"air": true, "flip": 0.5}])
		out.append(["taunt", {"emote": int(C.EMOTE_CHAR), "emoteT": 0.8}])
		out.append(["victory", {"victory": 1.2}])
		out.append(["broken", {"act": {"id": 3, "move": atk[0][0], "phase": "broken", "u": 0.1, "air": false}}])
	return out


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var a := OS.get_cmdline_user_args()
	var pi := a.find("--preset") # W49: 새·옛·최소 모션 프리셋 (chars_config.gd EXT_MOTION_PRESETS) 으로 그리기 — 같은 상태를 프리셋만 바꿔 나란히 비교
	if pi >= 0 and pi + 1 < a.size():
		load("res://chars/chars_config.gd").set_flags(load("res://chars/chars_config.gd").preset_flags(a[pi + 1]))
	var out: String = a[0]
	var ch: String = a[1]
	var group: String = a[2] if a.size() > 2 else "loco"
	var yaw: float = float(a[3]) if a.size() > 3 else 30.0
	var cw: int = int(a[4]) if a.size() > 4 else 200
	var Body = load("res://chars/body.gd")
	var Chars = load("res://chars/chars.gd")
	Body.use_ext = not a.has("--code")
	var states := _states(ch, group)
	if a.has("--only"):
		var want: PackedStringArray = str(a[a.find("--only") + 1]).split(",")
		var keep := []
		for s in states:
			if want.has(str(s[0])):
				keep.append(s)
		states = keep
	var cols := mini(8, states.size())
	var rows := ceili(float(states.size()) / cols)
	var cell := 1.55
	var rowh := 2.15
	var vp := SubViewport.new()
	vp.own_world_3d = true
	var chh := int(cw * 1.3)
	vp.size = Vector2i(cols * cw, rows * chh)
	vp.msaa_3d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.30, 0.34, 0.46)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.25, 0.25, 0.3)
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	we.environment = env
	vp.add_child(we)
	var light := DirectionalLight3D.new()
	vp.add_child(light)
	light.look_at_from_position(Vector3(3, 4, 5), Vector3.ZERO, Vector3.UP)
	var bodies := []
	for i in states.size():
		var r := i / cols
		var c := i % cols
		var b = Chars.make_body(ch, Color.html("e05050"))
		var t := Node3D.new()
		t.position = Vector3(c * cell, -r * rowh, 0)
		t.rotation.y = deg_to_rad(yaw - 90.0)
		vp.add_child(t)
		t.add_child(b)
		if a.has("--w43off") and b.ext != null:
			b.ext.move_off = true
		if a.has("--noclip") and b.ext != null:
			b.ext.clipset = {}
		bodies.append(b)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = rows * rowh
	vp.add_child(cam)
	cam.current = true
	var cx := (cols - 1) * cell * 0.5
	var cy := -(rows - 1) * rowh * 0.5 + 0.9
	cam.look_at_from_position(Vector3(cx, cy, 20), Vector3(cx, cy, 0), Vector3.UP)
	# 칸 이름표
	var lay := CanvasLayer.new()
	root.add_child(lay)
	var dt := 0.05
	for k in 14:
		for i in states.size():
			var st := _base(1.0 + k * dt)
			var ov: Dictionary = states[i][1]
			for key in ov:
				st[key] = ov[key]
			if ov.has("t"):
				st.t = float(ov.t)
			var b = bodies[i]
			if ov.has("getup_u") and b.ext != null:
				b.ext.getup_mark = float(ov.getup_u)
			b.hs = float(st.hs)
			b.walk = float(st.walk)
			b.vz = float(st.vz)
			b.t = float(st.t)
			b.air_dash_t = float(st.airDash) * C.FIGURE_AIR_DASH.s # W34: 공중 대시 몸 기울임도 (rig 틸트) 게임 그대로
			b.set_meta("air", st.air)
			b.set_meta("walking", st.walking)
			b._figure_anim(st, dt)
			b._apply(dt)
			b._sync_bones()
			if b.ext != null:
				b.ext.sync(st)
				if OS.get_environment("SHEET_DBG") != "" and k == 13:
					print("TFD loop ", b.ext.sk.get_bone_pose_rotation(b.ext.sk.find_bone("mixamorig_RightArm")), b.ext.clip_info)
		await process_frame
	if OS.get_environment("SHEET_DBG") != "":
		for b in bodies:
			print("TFD ", b.ext.clip_info if b.ext else "-", " RArm ", b.ext.sk.get_bone_pose_rotation(b.ext.sk.find_bone("mixamorig_RightArm")), " sk ", b.ext.sk.get_path(), " mods ", b.ext.sk.get_child_count())
	var img := vp.get_texture().get_image()
	# 이름표 (작은 글자)
	img.save_png(out)
	var names := []
	for s in states:
		names.append(s[0])
	print("TF 저장 ", out, " 칸 ", cols, "x", rows, " : ", ", ".join(names))
	quit()
