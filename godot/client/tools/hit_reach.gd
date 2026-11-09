# W34 서버 판정 vs 보이는 타격 위치 측정: 평타마다 타격 단계 (strike u = 0.5·1.0) 자세를 몸이 게임에서 하는 그대로 (_figure_anim → Ext.sync) 만들고,
# 모델 (스킨 적용한 정점) 이 몸 중심 (플레이어 x·y) 에서 앞쪽으로 얼마나 나갔는지 — 가장 먼 정점 (무기 끝·주먹·발끝) 과 손 뼈 — 를 m 로 재서 서버 판정과 비교.
# 서버 평타 판정 (server/game-combat.js basicHit): 먼저 step 만큼 앞으로 나간 뒤, 중심 거리 <= range (기본 PUSH_RANGE 1.8) 이고 부채꼴 (반각 PUSH_HALF_ANGLE_DEG) 안인 상대를 침.
# 상대 몸 반폭 PLAYER_HALF = 0.3 이라, 중심 거리 d 일 때 상대 몸 앞면은 d - 0.3 → 서버가 치는 가장 먼 앞면 = step + range - 0.3 (중심에서). 보이는 끝이 그보다 짧으면 '닿기 전에 맞음', 길면 '뚫고 지나갔는데 안 맞음'.
# godot --headless 불가 (스킨·뼈 자세는 헤드리스에서도 되지만 xvfb 없이도 됨):
#   godot --headless --path godot/client -s res://tools/hit_reach.gd -- [캐릭터 ,로 이음 기본 tank,ninja,hunter,hook] [--csv 파일]
extends SceneTree

const C := preload("res://core/config.gd")


func _initialize() -> void:
	_run.call_deferred()


func _base() -> Dictionary:
	return {"air": false, "walking": false, "hs": 0.0, "walk": 0.0, "vz": 0.0, "t": 1.0, "stunned": false, "dancing": false, "emote": -1, "emoteT": 0.0, "victory": -1.0, "punch": 0.0,
		"holding": false, "hit": null, "act": null, "accF": 0.0, "accS": 0.0, "tumble": 0.0, "recover": 0.0, "land": 0.0, "flip": -1.0, "rag": false, "sniffAt": null, "idle": 0.0,
		"airDash": 0.0, "bump": null, "whirl": -1.0, "dizzy": 0.0, "glide": false, "amp": false, "form": "", "loaded": false, "ammo": 3.0}


# 스킨 적용 정점의 몸 기준 앞 (+x) 최대 거리 (m), 몸 중심 = frame 원점. 돌려줌 {tip, tip_z, hand, hand_z}
func _reach(b) -> Dictionary:
	var X = b.ext
	var sk: Skeleton3D = X.sk
	var space: Node3D = X.space
	var inv := space.global_transform.affine_inverse()
	var sc: float = space.global_transform.basis.get_scale().x
	var skg := sk.global_transform
	var tip := -1e9
	var tip_z := 0.0
	var gcache := {}
	for pt in X.parts:
		var mi: MeshInstance3D = pt.mi
		if mi == null or mi.skin == null or mi.mesh == null or not mi.visible:
			continue
		var arr: Array = mi.mesh.surface_get_arrays(0)
		var pos: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var bi: PackedInt32Array = arr[Mesh.ARRAY_BONES]
		var bw: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
		if bi.is_empty():
			continue
		var skin: Skin = mi.skin
		var bones := PackedInt32Array()
		var binds: Array = []
		for k in skin.get_bind_count():
			var bn := skin.get_bind_bone(k)
			if bn < 0:
				bn = sk.find_bone(skin.get_bind_name(k))
			bones.append(bn)
			binds.append(skin.get_bind_pose(k))
			if not gcache.has(bn):
				gcache[bn] = X._gt(bn)
		for i in pos.size():
			var p := Vector3.ZERO
			var wsum := 0.0
			for k in 4:
				var w: float = bw[i * 4 + k]
				if w <= 0.0:
					continue
				var bk: int = bi[i * 4 + k]
				p += (gcache[bones[bk]] * (binds[bk] as Transform3D) * pos[i]) * w
				wsum += w
			if wsum <= 0.0:
				continue
			var loc: Vector3 = inv * (skg * (p / wsum))
			var f: float = loc.x * sc
			if f > tip:
				tip = f
				tip_z = loc.z * sc
	var hand := -1e9
	var hand_z := 0.0
	for hn in ["mixamorig_RightHand", "mixamorig_LeftHand", "mixamorig_RightFoot", "mixamorig_LeftFoot", "mixamorig_RightHandMiddle4", "mixamorig_LeftHandMiddle4", "mixamorig_RightToeBase", "mixamorig_LeftToeBase"]:
		var bi2 := sk.find_bone(hn)
		if bi2 < 0:
			continue
		var gb: Transform3D = X._gt(bi2)
		var loc2: Vector3 = inv * (skg * gb.origin)
		if loc2.x * sc > hand:
			hand = loc2.x * sc
			hand_z = loc2.z * sc
	return {"tip": tip, "tip_z": tip_z, "hand": hand, "hand_z": hand_z}


func _run() -> void:
	var a := OS.get_cmdline_user_args()
	var chars: PackedStringArray = (a[0] if a.size() > 0 and not a[0].begins_with("--") else "tank,ninja,hunter,hook").split(",")
	var csv := ""
	if a.has("--csv"):
		csv = a[a.find("--csv") + 1]
	var Body = load("res://chars/body.gd")
	var Chars = load("res://chars/chars.gd")
	Body.use_ext = not a.has("--code")
	var vp := SubViewport.new()
	root.add_child(vp)
	var lines := ["캐릭터,동작,공중,step,range,서버 최대 앞면(m),보이는 끝(m),끝 높이(m),손·발 뼈(m),차(끝-서버)"]
	for ch in chars:
		var b = Chars.make_body(ch, Color.RED)
		vp.add_child(b)
		await process_frame
		var sets: Dictionary = C.BASIC_ATTACKS[ch]
		var defs := []
		for d in sets.chain:
			defs.append([d, false])
			if d.has("loaded"):
				defs.append([d.loaded, false])
		for d in sets.air:
			defs.append([d, true])
		# 서 있을 때 (기준)
		for k in 10:
			var st0 := _base()
			b._figure_anim(st0, 0.05)
			b._apply(0.05)
			b._sync_bones()
			if b.ext != null:
				b.ext.sync(st0)
		var r0 := _reach(b) if b.ext != null else {"tip": 0.0, "tip_z": 0.0, "hand": 0.0, "hand_z": 0.0}
		print("HIT %s 서 있을 때 끝 %.2f m 손 %.2f m" % [ch, r0.tip, r0.hand])
		for pair in defs:
			var d: Dictionary = pair[0]
			var air: bool = pair[1]
			if d.get("shell", false) or d.get("note", false) or d.get("glide", false) or d.get("dive", false):
				continue
			var best := {"tip": -1e9, "hand": -1e9, "tip_z": 0.0}
			for u in [0.5, 1.0]:
				for k in 14:
					var st := _base()
					st.air = air
					st.act = {"id": 1, "move": d.name, "phase": "strike", "u": u, "air": air}
					st.loaded = str(d.name) == "탕"
					b._figure_anim(st, 0.05)
					b._apply(0.05)
					b._sync_bones()
					if b.ext != null:
						b.ext.sync(st)
				var r := _reach(b) if b.ext != null else {"tip": 0.0, "tip_z": 0.0, "hand": 0.0, "hand_z": 0.0}
				if r.tip > best.tip:
					best = r
			var step: float = float(d.get("step", 0.0))
			var rng: float = float(d.get("range", C.PUSH_RANGE))
			var server: float = step + rng - C.PLAYER_HALF
			var line := "%s,%s,%s,%.1f,%.1f,%.2f,%.2f,%.2f,%.2f,%+.2f" % [ch, d.name, "공중" if air else "지상", step, rng, server, best.tip, best.tip_z, best.hand, best.tip - server]
			lines.append(line)
			print("HIT ", line)
		b.queue_free()
		await process_frame
	if csv != "":
		var f := FileAccess.open(csv, FileAccess.WRITE)
		f.store_string("\n".join(lines) + "\n")
		f.close()
	quit()
