# 몸 자세 벤치 (헤드리스, 장면 트리 밖): 8캐릭터 몸을 make_body 로 만들어 30프레임 데운 뒤 300프레임 pose 를 5번 → 5번의 중앙값
#   godot --headless --path godot/client -s res://tools/bench_bodies.gd
# 찍는 줄 (프레임당, 8명 합):
#   몸 묶음 뼈 X ms (8명)        — Prof '몸 코드 묶음 뼈' (body.gd _sync_bones — 병합 전 이름 '몸 묶음 뼈' 도 읽음)
#   외부 몸 sync Z ms (8명)      — Prof '몸 외부 몸 sync' (external.gd Ext.sync — 외부 모델 캐릭터: 탱크·닌자·사냥꾼·갈고리. 그 넷은 코드 묶음 뼈가 0)
#   pose 합 Y ms (8명)           — pose 8번 부른 벽시계 시간 (Prof 켠 채)
#   묶음 사슬 [..] · 뼈 [..]     — 캐릭터마다 매 프레임 곱하는 부모 사슬 수 · 맞추는 뼈 수
# bone_groups 가 없는 예전 몸 (사이클 5 u3 전) 도 그대로 돎: 그땐 bone_dyn 을 씀 (뼈마다 사슬 하나 → 사슬 = 뼈)
# 다른 일이 돌면 값이 흔들림 → 같이 `uptime` 을 보고 load 가 낮을 때 잼. 고치기 전과 비교는 그 커밋을 git worktree 로 따로 꺼내 그 복사본 경로로 --path
extends SceneTree

const CHARS := ["tank", "ninja", "hunter", "bard", "berserker", "cannon", "builder", "hook"]
const WARM := 30
const FRAMES := 300
const RUNS := 5
const BONE_LABEL := "몸 묶음 뼈"
const BONE_KEYS := ["몸 코드 묶음 뼈", "몸 묶음 뼈"] # body.gd pose 의 Prof 구간 이름 (최신 · 병합 전)
const EXT_KEY := "몸 외부 몸 sync"


func _initialize() -> void:
	var Chars = load("res://chars/chars.gd")
	var Prof = load("res://core/prof.gd")
	var bodies := []
	for c in CHARS:
		bodies.append(Chars.make_body(c, Color(0.8, 0.3, 0.3)))
	for i in WARM:
		for k in bodies.size():
			bodies[k].pose({"id": k + 1, "alive": true, "x": 3.0, "y": 3.0, "z": 1.0, "yaw": 0.5, "damage": 10}, i * 16.0)
	var bone_ms := []
	var ext_ms := []
	var pose_ms := []
	Prof.on = true
	for r in RUNS:
		Prof.reset()
		var t0 := Time.get_ticks_usec()
		for i in FRAMES:
			for k in bodies.size():
				bodies[k].pose({"id": k + 1, "alive": true, "x": 3.0 + 0.05 * i, "y": 3.0, "z": 1.0, "yaw": 0.5, "damage": 10}, 1000.0 + i * 16.0)
		pose_ms.append((Time.get_ticks_usec() - t0) / 1000.0 / FRAMES)
		var us := 0.0
		for key in BONE_KEYS:
			us += float(Prof.sums.get(key, [0, 0])[0])
		bone_ms.append(us / 1000.0 / FRAMES)
		ext_ms.append(float(Prof.sums.get(EXT_KEY, [0, 0])[0]) / 1000.0 / FRAMES)
	Prof.on = false
	var chains := []
	var bones := []
	for b in bodies:
		var groups = b.get("bone_groups")
		if groups != null:
			chains.append(groups.size())
			var n := 0
			for g in groups:
				n += g.bones.size()
			bones.append(n)
		else:
			var dyn = b.get("bone_dyn")
			chains.append(dyn.size())
			bones.append(dyn.size())
	print("%s %.3f ms (8명)" % [BONE_LABEL, _median(bone_ms)])
	print("외부 몸 sync %.3f ms (8명)" % _median(ext_ms))
	print("pose 합 %.3f ms (8명)" % _median(pose_ms))
	print("묶음 사슬 %s · 뼈 %s" % [str(chains), str(bones)])
	for b in bodies:
		b.free()
	quit()


static func _median(a: Array) -> float:
	var s := a.duplicate()
	s.sort()
	return float(s[floori(s.size() / 2.0)])
