# W40 천·망토 움직임 확인 (정지 프레임 줄): 몸 하나를 월드에서 움직이며 (서 있기 → 달리기 → 멈춤 / 서 있다 맞아 날아감 / 점프) 천 시뮬을 진짜 길 (ext.sync + cloth.step, 고정 1/60 초) 로 돌리고
# 정해 둔 시각마다 옆·뒤 화면을 한 장에 이어 붙임. 카메라는 몸을 따라다니므로 천이 몸 뒤로 날리는 정도가 보임. 소프트웨어 렌더라 움직임 속도는 못 보고 프레임만.
# xvfb-run -a -s "-screen 0 1900x1000x24" godot --path godot/client --resolution 1900x1000 -s res://tools/cloth_shot.gd -- <out.png> <캐릭터> <run|hit|jump|turn> [카메라 방위 도: 0 = 옆, 90 = 뒤] [--noclip] [--nocloth]
extends SceneTree

const C := preload("res://core/config.gd")

const FRAMES := {
	"run": [0.4, 1.0, 1.6, 2.2, 2.4, 2.7, 3.2, 3.8],
	"hit": [0.4, 0.8, 0.9, 1.0, 1.15, 1.4, 1.8, 2.6],
	"jump": [0.4, 0.7, 0.9, 1.1, 1.3, 1.5, 1.8, 2.4],
	"turn": [0.4, 1.0, 1.4, 1.6, 1.8, 2.0, 2.4, 3.0],
}


func _base() -> Dictionary:
	return {"air": false, "walking": false, "hs": 0.0, "walk": 0.0, "vz": 0.0, "t": 1.0, "stunned": false, "dancing": false, "emote": -1, "emoteT": 0.0, "victory": -1.0, "punch": 0.0,
		"holding": false, "hit": null, "act": null, "accF": 0.0, "accS": 0.0, "tumble": 0.0, "recover": 0.0, "land": 0.0, "flip": -1.0, "rag": false, "sniffAt": null, "idle": 0.0,
		"airDash": 0.0, "bump": null, "whirl": -1.0, "dizzy": 0.0, "glide": false, "amp": false, "form": "", "loaded": false, "ammo": 3.0}


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var a := OS.get_cmdline_user_args()
	var out: String = a[0]
	var ch: String = a[1]
	var scen: String = a[2] if a.size() > 2 else "run"
	var yaw: float = float(a[3]) if a.size() > 3 and not str(a[3]).begins_with("--") else 0.0
	var Body = load("res://chars/body.gd")
	var Chars = load("res://chars/chars.gd")
	Body.use_ext = true
	var cw := 230
	var chh := 330
	var frames: Array = FRAMES[scen]
	var vp := SubViewport.new()
	vp.own_world_3d = true
	vp.size = Vector2i(cw, chh)
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
	var holder := Node3D.new()
	vp.add_child(holder)
	var b = Chars.make_body(ch, Color.html("e05050"))
	holder.add_child(b)
	if a.has("--noclip") and b.ext != null:
		b.ext.clipset = {}
	if a.has("--nocloth") and b.ext != null:
		b.ext.cloths.clear()
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 2.3
	vp.add_child(cam)
	cam.current = true
	var X = b.ext
	var dt := 1.0 / 60.0
	var tt := 0.0
	var px := 0.0
	var py := 0.0
	var vy := 0.0
	var walkph := 0.0
	var air := false
	var sheet := Image.create(cw * frames.size(), chh, false, Image.FORMAT_RGBA8)
	var fi := 0
	var total: float = frames[frames.size() - 1]
	var hs := 0.0
	var walking := false
	var hitage := -1.0
	while tt <= total + 0.001:
		walking = false
		hs = 0.0
		air = false
		var st := _base()
		match scen:
			"run":
				if tt > 0.5 and tt < 2.2:
					hs = C.MOVE_SPEED
					walking = true
				px += hs * dt
			"hit":
				if tt >= 0.8 and tt < 1.1:
					px -= 7.0 * dt * (1.0 - (tt - 0.8) / 0.3)
					hitage = tt - 0.8
				elif tt >= 1.1:
					hitage = tt - 0.8
				if hitage >= 0.0:
					st.hit = {"id": 7, "age": hitage, "stop": 0.0, "dx": -1.0, "dy": 0.0, "pow": 1.6}
			"jump":
				if tt >= 0.6 and not air and py <= 0.0 and vy == 0.0 and tt < 0.62:
					vy = 7.0
				if tt >= 0.6:
					vy -= 20.0 * dt
					py = maxf(0.0, py + vy * dt)
					if py <= 0.0:
						vy = 0.0
				air = py > 0.0
				st.air = air
				st.vz = vy
				if tt > 0.5:
					hs = C.MOVE_SPEED * 0.6
					walking = not air
					px += hs * dt
			"turn":
				if tt > 0.5 and tt < 1.6:
					hs = C.MOVE_SPEED
					walking = true
					px += hs * dt
				if tt >= 1.4:
					holder.rotation.y = lerpf(0.0, PI * 0.9, clampf((tt - 1.4) / 0.25, 0.0, 1.0))
					px += (0.0 if tt > 1.65 else hs * dt * 0.3) * cos(holder.rotation.y)
		walkph += hs * dt * 1.4
		st.walking = walking
		st.hs = hs
		st.walk = walkph
		st.t = 1.0 + tt
		holder.position = Vector3(px, py, 0)
		b.hs = hs
		b.walk = walkph
		b.vz = float(st.vz)
		b.t = float(st.t)
		b.set_meta("air", st.air)
		b.set_meta("walking", walking)
		b._figure_anim(st, dt)
		b._apply(dt)
		b._sync_bones()
		if X != null:
			X.cloth_t = Time.get_ticks_msec() * 0.001 - dt
			X.sync(st)
		if fi < frames.size() and tt >= float(frames[fi]) - 0.0001:
			cam.look_at_from_position(Vector3(px - 20.0 * sin(deg_to_rad(yaw)), py + 0.9, 20.0 * cos(deg_to_rad(yaw))), Vector3(px, py + 0.9, 0), Vector3.UP)
			await process_frame
			await process_frame
			var im := vp.get_texture().get_image()
			sheet.blit_rect(im, Rect2i(0, 0, cw, chh), Vector2i(fi * cw, 0))
			fi += 1
		tt += dt
	sheet.save_png(out)
	print("TF 저장 ", out, " ", scen, " 프레임 ", frames)
	quit()
