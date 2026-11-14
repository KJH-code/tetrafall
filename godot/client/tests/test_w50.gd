# W50 안정성 회귀 테스트: 스케줄러가 주인이 사라진 작업을 버림 · 종료 때 정적 상태 정리
extends RefCounted

const PSched := preload("res://world/prewarm_sched.gd")

var errors: Array = []


func check(cond: bool, msg: String) -> void:
	if not cond:
		errors.append(msg)


class Owner:
	extends Node
	var runs := 0

	func piece() -> bool:
		runs += 1
		return false


# 방을 나가 노드가 free 됐는데 작업이 남으면 step 마다 "previously freed instance" 오류가 영영 (로그 폭주)
func test_sched_drops_task_of_freed_owner() -> void:
	var s := PSched.Sched.new()
	var o := Owner.new()
	s.add("a", 0, Callable(o, "piece"), 1.0)
	s.add("b", 1, func(): return true, 1.0)
	o.free()
	for i in 5:
		s.step(1000.0 + i * 20.0, 16.0)
	check(not s.has("a"), "주인이 사라진 작업은 버려야 함")
	check(s.pending() == 0, "남은 작업 %d" % s.pending())


func test_sched_finished_capped() -> void:
	var s := PSched.Sched.new()
	for i in 200:
		s.add("t%d" % i, 0, func(): return true, 0.1)
		s.step(1000.0 + i * 20.0, 16.0)
	check(s.finished.size() <= PSched.Sched.FINISHED_MAX, "끝난 기록 상한 %d" % s.finished.size())
	check(s.pending() == 0, "다 끝남")


func test_outline_owner_pruned() -> void:
	var Body := preload("res://chars/body.gd")
	Body._ol_owner.clear()
	for i in 1500: # 이미 없어진 재질 id (몸을 지우고 난 뒤)
		var o := Object.new()
		Body._ol_owner[o.get_instance_id()] = 1
		o.free()
	var live := Material.new()
	Body._ol_owner[live.get_instance_id()] = 1
	var n := Body.prune_ol_owner()
	check(n == 1500 and Body._ol_owner.size() == 1, "사라진 재질 기록을 버림 %d 남음 %d" % [n, Body._ol_owner.size()])
	Body._ol_owner.clear()
