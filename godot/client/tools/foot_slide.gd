# W33 발 미끄러짐 측정: 걷기·달리기 클립 한 바퀴 동안 '땅에 닿은 발' (둘 중 낮은 발) 이 몸 기준으로 뒤로 가는 거리 (m) 를, 코드 걸음 위상이 그 한 바퀴 동안 몸이 가는 거리와 비교.
# 위상 속도 = hs × ANIM_WALK_FREQ × gait.freq (rad/s) → 한 바퀴 거리 = 2π / (ANIM_WALK_FREQ × freq). 비 = 발이 뒤로 간 거리 / 몸이 간 거리 — 1 이면 안 미끄러짐, <1 이면 발이 땅에서 미끄러져 앞서감 (스케이트), >1 이면 뒤로 끌림.
# godot --headless --path godot/client -s res://tools/foot_slide.gd -- [캐릭터 ,로 이음 기본 ninja,tank,hunter,hook]
extends SceneTree

const C := preload("res://core/config.gd")
const Pose := preload("res://chars/figure_pose.gd")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var a := OS.get_cmdline_user_args()
	var chars: PackedStringArray = (a[0] if a.size() > 0 else "ninja,tank,hunter,hook").split(",")
	var Body = load("res://chars/body.gd")
	var Chars = load("res://chars/chars.gd")
	Body.use_ext = true
	var vp := SubViewport.new()
	root.add_child(vp)
	for ch in chars:
		var b = Chars.make_body(ch, Color.RED)
		vp.add_child(b)
		await process_frame
		var X = b.ext
		var sk: Skeleton3D = X.sk
		var sc: float = (sk.global_transform.basis.get_scale() * X.get_parent().global_transform.basis.get_scale()).x
		var freq: float = float(Pose.gait_of(ch).freq)
		var need: float = TAU / (C.ANIM_WALK_FREQ * freq)
		for nm in ["walk", "run"]:
			if not X.clipset.has(nm):
				continue
			var n := 60
			var fR := sk.find_bone("mixamorig_RightFoot")
			var fL := sk.find_bone("mixamorig_LeftFoot")
			var prev := Vector2.ZERO
			var travel := 0.0
			var had := false
			var prev_stance := -1
			for i in n + 1:
				var t: float = float(X.clipset[nm].len) * float(i) / n
				X.preview_clip(nm, t)
				X.fade_t = 1.0 # 클립 바뀐 직후 크로스페이드 (실제 시간 0.1초) 를 건너뜀
				X.preview_clip(nm, t)
				var pr := _pos(sk, fR)
				var pl := _pos(sk, fL)
				var stance: int = 0 if pr.y <= pl.y else 1
				var cur: Vector3 = pr if stance == 0 else pl
				if had and stance == prev_stance:
					travel += -(cur.x - prev.x) # 몸 앞 +x → 땅에 닿은 발이 뒤로 가는 만큼
				prev = Vector2(cur.x, cur.y)
				prev_stance = stance
				had = true
			travel *= sc
			print("TFS %s %s 한 바퀴: 닿은 발 뒤로 %.2f m, 코드 걸음 위상이 가는 거리 %.2f m, 비 %.2f" % [ch, nm, travel, need, travel / need])
		b.queue_free()
	quit()


static func _pos(sk: Skeleton3D, bi: int) -> Vector3:
	var t := Transform3D.IDENTITY
	var b := bi
	while b >= 0:
		t = sk.get_bone_pose(b) * t
		b = sk.get_bone_parent(b)
	return t.origin
