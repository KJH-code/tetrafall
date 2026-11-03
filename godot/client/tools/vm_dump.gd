# 1인칭 팔 (chars/viewmodel.gd) 숫자 뽑기 (W11, tools/vm_dump.mjs 와 같은 장면): godot --headless --path godot/client -s res://tools/vm_dump.gd -- [캐릭터] [out.json]
# 결과 (W11, 2026-11-03): seq 157프레임·동작마다 96프레임 모두 JS 와 방패·어깨·팔꿈치 차 0.000. 판 중 (--vm-log, --no-glb 예전 조립 포함 476프레임) 도
#   같은 동작·단계의 가장 가까운 u 와 방패 자리·회전 차 최대 0.13 (프레임 간격 탓) — 3·4타 방패는 허리에 붙은 채 허리 회전 × VM_BODY_FOLLOW 만 따라감 (JS 도 같음).
#   보이기도 같음 (1·2타 숨김, 3·4타 보임). 이 환경 (llvmpipe, Compatibility) 에서는 증상 재현 못 함.
extends SceneTree

const C := preload("res://core/config.gd")


static func _r(x: float) -> float:
	return roundf(x * 1e4) / 1e4


static func _rel(o: Node3D, root: Node3D) -> Transform3D:
	var m := Transform3D.IDENTITY
	var n: Node3D = o
	while n != null and n != root:
		m = n.transform * m
		n = n.get_parent() as Node3D
	return m


static func _dec(m: Transform3D) -> Dictionary:
	var s := m.basis.get_scale()
	var q := m.basis.orthonormalized().get_rotation_quaternion()
	if q.w < 0:
		q = -q
	return {"p": [_r(m.origin.x), _r(m.origin.y), _r(m.origin.z)], "q": [_r(q.x), _r(q.y), _r(q.z), _r(q.w)], "s": [_r(s.x), _r(s.y), _r(s.z)]}


static func _v(v: Vector3) -> Array:
	return [_r(v.x), _r(v.y), _r(v.z)]


func _initialize() -> void:
	var Chars = load("res://chars/chars.gd") # 실행 때 읽음 (preload 면 autoload 이름 View 를 못 찾음)
	var VM = load("res://chars/viewmodel.gd")
	var a := OS.get_cmdline_user_args()
	var ch: String = a[0] if a.size() > 0 else "tank"
	var path: String = a[1] if a.size() > 1 else "user://vm.json"
	var sets: Dictionary = C.BASIC_ATTACKS[ch]
	var moves := []
	for x in sets.chain:
		moves.append(x.name)
	for x in sets.air:
		moves.append(x.name)
	var base := {"air": false, "walking": false, "hs": 0.0, "walk": 0.0, "vz": 0.0, "t": 0.0, "stunned": false, "dancing": false, "emote": -1, "emoteT": 0.0, "victory": -1.0, "punch": 0.0, "holding": false, "hit": null, "act": null, "accF": 0.0, "accS": 0.0, "tumble": 0.0, "recover": 0.0, "land": 0.0, "flip": -1.0, "rag": false, "sniffAt": null, "idle": 0.0, "airDash": 0.0, "bump": null, "whirl": -1.0, "dizzy": 0.0, "glide": false, "amp": false, "form": "", "loaded": false, "ammo": 3.0}
	var out := []
	var dt := 1.0 / 60.0
	# seq: 한 몸으로 1타 → 끝 타를 이어서 (실제 준비·타격·회복 시간, 60fps — vm_dump.mjs 와 같은 프레임 수). 아니면 동작마다 새 몸
	var seq := a.size() > 2 and a[2] == "seq"
	var all: Array = sets.chain + sets.air
	var b = null
	var vm = null
	var t := 1.0
	for mi in moves.size():
		var move: String = moves[mi]
		if not seq or mi == 0:
			b = Chars.make_body(ch, Color.WHITE)
			vm = VM.new()
			vm._ready()
			vm._sync(b)
			t = 1.0
		var fr: Array = [["wind", 8], ["strike", 6], ["rec", 10]]
		if seq:
			fr = [["wind", ceili(all[mi].windup / 1000.0 / dt)], ["strike", ceili(C.FIGURE_STRIKE_S / dt)], ["rec", ceili(all[mi].rec / 1000.0 / dt)]]
		for ph in fr:
			for i in ph[1]:
				t += dt
				var act := {"id": mi + 1, "move": move, "phase": ph[0], "u": (i + 1.0) / ph[1], "air": mi >= sets.chain.size()}
				var st: Dictionary = base.duplicate(true)
				st.t = t
				st.act = act
				st.air = seq and act.air
				b._figure_anim(st, dt)
				b._apply(dt)
				b.t = 0.0 # 숨쉬기 끔 (비교용)
				vm._follow(dt)
				var row := {"move": move, "phase": ph[0], "u": _r(act.u)}
				var sh = vm.twin._n(vm.twin.refs.shields.get("front")) if vm.twin.refs.get("shields") is Dictionary else null
				if sh != null:
					row.shieldVis = sh.visible
					row.shieldLocal = {"p": _v(sh.position), "r": _v(sh.rotation), "s": _v(sh.scale), "order": sh.rotation_order}
					row.shield = _dec(_rel(sh, vm.anchor))
				row.waist = _dec(_rel(vm.twin.waist, vm.anchor))
				row.shoulders = [_dec(_rel(vm.twin.shoulders[0], vm.anchor)), _dec(_rel(vm.twin.shoulders[1], vm.anchor))]
				row.elbows = [_dec(_rel(vm.twin.elbows[0], vm.anchor)), _dec(_rel(vm.twin.elbows[1], vm.anchor))]
				row.srcWaist = _v(b.waist.rotation)
				row.srcSh = [_v(b.shoulders[0].rotation), _v(b.shoulders[1].rotation)]
				row.srcEl = [_v(b.elbows[0].rotation), _v(b.elbows[1].rotation)]
				var aq: Quaternion = vm.anchor.basis.orthonormalized().get_rotation_quaternion()
				row.anchor = {"p": _v(vm.anchor.position), "q": [_r(aq.x), _r(aq.y), _r(aq.z), _r(aq.w)], "s": _r(vm.anchor.scale.x)}
				out.append(row)
		if not seq or mi == moves.size() - 1:
			vm.twin.free()
			b.free()
			vm.free()
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(out))
	f.close()
	print("vm_dump ", out.size(), " → ", path)
	quit()
