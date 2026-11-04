# 이펙트 확인용 (W18, 테스트 밖 도구): 재연 (core/replay.gd) 중 정한 가상 시각에 가짜 이벤트를 넣고 연속 프레임을 찍음 → 같은 판·같은 순간의 전/후 스크린샷.
#   xvfb-run -a <godot> --path godot/client --rendering-driver opengl3 --resolution 1280x720 --fixed-fps 30 -- \
#     --replay game8.rec --replay-render --replay-fps 30 --replay-secs 3 --fx-probe crit --fx-shots /tmp/crit [--fx-at 0.5] [--fx-frames 1,3,5,8] [--set third=true]
# 장면 (--fx-probe): 타격 crit·heavy·medium·light·hurt (나를 때림) · 폭발 boom·bigshell·shell·bigbomb·muzzle · 땅 quake·slam·rush·spin · KO smash·crush ·
#   캐릭터 armorBreak·blink·mark·metal·amp·hookslam · 여럿 all (한 번에 다 — 비용 확인)
# 대상: 맞는 사람 = 카메라 앞 2~14칸에서 화면 가운데에 가장 가까운 사람, 자리 효과 = 카메라 앞 5칸 바닥. 찍고 나면 끝냄
extends Node

var replay = null # core/replay.gd (t_start)
var scenario := ""
var prefix := ""
var at_s := 0.5
var frames: Array = [1, 3, 5, 8]
var fired := -1 # 넣은 프레임 번호
var n := 0


func _ready() -> void:
	var a: Dictionary = replay.args
	scenario = str(a.get("fx-probe", "crit"))
	prefix = str(a.get("fx-shots", "/tmp/fx"))
	at_s = float(a.get("fx-at", 0.5))
	if a.has("fx-frames"):
		frames = Array(str(a["fx-frames"]).split(",")).map(func(x): return int(x))
	process_priority = 1000


func _process(_d: float) -> void:
	if replay == null or Net.virt < replay.t_start + at_s * 1000.0:
		return
	n += 1
	if fired < 0:
		fired = n
		for e in events(scenario):
			Store.game_event.emit(e)
		print("[효과 확인] %s 넣음 (가상 %.2f초)" % [scenario, (Net.virt - replay.t_start) / 1000.0])
	var k := n - fired
	if frames.has(k):
		_shot(k)
	if k > int(frames.max()) + 1:
		var fx = get_tree().get_first_node_in_group("fx")
		if fx != null:
			print("[효과 확인] 끝 효과 %s" % [fx.effects.stats()])
		get_tree().quit(0)


func _shot(k: int) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := "%s_%02d.png" % [prefix, k]
	img.save_png(path)
	var fx = get_tree().get_first_node_in_group("fx")
	print("[효과 확인] %s · 그리기 %d · 물체 %d · 효과 %s" % [path, Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME), fx.effects.stats() if fx != null and fx.effects.has_method("stats") else "-"])


func _world():
	for nd in get_tree().root.find_children("*", "Node3D", true, false):
		if nd.has_method("column_top") and nd.has_method("solid_at"):
			return nd
	return null


# 카메라 앞 dist 칸 바닥 (게임 좌표)
func _front(dist := 5.0) -> Vector3:
	var cam := get_viewport().get_camera_3d()
	var Co := preload("res://core/coords.gd")
	var p := Co.game(cam.global_position)
	var f := Co.game(-cam.global_basis.z)
	var v := Vector2(f.x, f.y).normalized() * dist
	var x := p.x + v.x
	var y := p.y + v.y
	var w = _world()
	var z := float(w.column_top(floori(x), floori(y))) if w != null else 0.0
	return Vector3(x, y, maxf(0.0, z))


func _target() -> Dictionary:
	var cam := get_viewport().get_camera_3d()
	var Co := preload("res://core/coords.gd")
	var best := {}
	var best_a := 9.0
	for p in Store.state.get("players", []):
		if not p.alive or (Store.my_id != null and int(p.id) == Store.my_id):
			continue
		var gp := Co.gxyz(p.x, p.y, p.z + 1.0)
		var d := gp - cam.global_position
		if d.length() < 2.0 or d.length() > 14.0:
			continue
		var ang := d.normalized().angle_to(-cam.global_basis.z)
		if ang < best_a:
			best_a = ang
			best = p
	if best.is_empty():
		var f := _front(4.0)
		var ps: Array = Store.state.get("players", [])
		for p in ps:
			if Store.my_id == null or int(p.id) != Store.my_id:
				return p
		return {"id": -99, "x": f.x, "y": f.y, "z": f.z}
	return best


func events(name: String) -> Array:
	var me = Store.my_id
	var t := _target()
	var f := _front()
	var tp := Vector3(float(t.x), float(t.y), float(t.z))
	var c := [floori(f.x), floori(f.y), floori(f.z)]
	match name:
		"crit":
			return [{"type": "hit", "by": me, "target": t.id, "ok": true, "crit": true, "kind": "push", "n": 2}]
		"heavy":
			return [{"type": "hit", "by": me, "target": t.id, "ok": true, "finish": true, "kind": "push", "n": 3}]
		"medium":
			return [{"type": "hit", "by": me, "target": t.id, "ok": true, "kind": "push", "n": 1}]
		"light":
			return [{"type": "hit", "by": me, "target": t.id, "ok": true, "kind": "projectile"}]
		"hurt":
			return [{"type": "hit", "by": t.id, "target": me, "ok": true, "crit": true, "kind": "push", "n": 2}]
		"boom":
			return [{"type": "boom", "x": f.x, "y": f.y, "z": f.z + 0.5}]
		"bigshell":
			return [{"type": "bigShellBlast", "x": f.x, "y": f.y, "z": f.z + 0.6, "r": 2.2, "who": me}]
		"shell":
			return [{"type": "shellEnd", "x": f.x, "y": f.y, "z": f.z + 0.6, "what": "player"}]
		"muzzle":
			return [{"type": "shellFire", "x": tp.x, "y": tp.y, "z": tp.z + 1.2, "dir": {"x": 1, "y": 0}, "who": t.id, "big": true}, {"type": "bang", "x": tp.x, "y": tp.y, "z": tp.z, "yaw": 0.0, "who": t.id}]
		"bigbomb":
			return [{"type": "bigBomb", "who": me, "cells": [[c[0], c[1], c[2]], [c[0] + 1, c[1], c[2]], [c[0], c[1], c[2] + 1]]}]
		"quake":
			var cells := []
			for dx in range(-1, 2):
				cells.append([c[0] + dx, c[1], c[2]])
				cells.append([c[0] + dx, c[1] + 1, c[2]])
			return [{"type": "quakeRise", "cells": cells, "ms": 1000, "id": 777, "who": me}]
		"slam":
			return [{"type": "slam", "who": me, "x": f.x, "y": f.y, "z": f.z, "r": 2.0}]
		"rush":
			return [{"type": "rushLand", "who": me, "x": f.x, "y": f.y, "z": f.z, "r": 1.5}]
		"spin":
			return [{"type": "spinEnd", "who": t.id, "x": tp.x, "y": tp.y, "z": tp.z, "r": 2.0, "rage": 1.5}]
		"smash":
			return [{"type": "death", "who": t.id, "cause": "fall", "x": tp.x, "y": tp.y, "z": tp.z - 1.0, "out": {"x": 1, "y": 0}}]
		"crush":
			return [{"type": "death", "who": t.id, "cause": "crush", "x": tp.x, "y": tp.y, "z": tp.z}]
		"armorBreak":
			return [{"type": "armorBreak", "who": t.id}, {"type": "hit", "by": me, "target": t.id, "ok": true, "kind": "push", "n": 3, "finish": true}]
		"blink":
			return [{"type": "blink", "who": t.id, "from": {"x": tp.x - 3.0, "y": tp.y, "z": tp.z}, "to": {"x": tp.x, "y": tp.y, "z": tp.z}}]
		"mark":
			return [{"type": "mark", "target": t.id, "n": 5, "by": me}]
		"metal":
			return [{"type": "form", "who": t.id, "form": "metal", "x": tp.x, "y": tp.y, "z": tp.z, "r": 1.8}]
		"amp":
			return [{"type": "ampEnd", "who": t.id, "x": tp.x, "y": tp.y, "z": tp.z, "yaw": 0.0}]
		"hookslam":
			return [{"type": "blockSlam", "who": t.id, "x": f.x, "y": f.y, "z": f.z, "r": 1.8, "cells": [c]}]
		"all":
			var out := []
			for k in ["crit", "heavy", "boom", "bigshell", "quake", "slam", "smash", "crush", "spin", "metal", "amp", "mark", "bigbomb"]:
				out.append_array(events(k))
			return out
	return []
