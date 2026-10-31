# 헤드리스 테스트 러너 (GUT 없이): godot --headless --path godot/prototype -s res://tests/run_tests.gd
# test_*.gd 의 test_ 로 시작하는 함수를 전부 돌림. 하나라도 실패하면 종료 코드 1
extends SceneTree

const FILES := ["res://tests/test_core.gd", "res://tests/test_chars.gd"]


func _init() -> void:
	var passed := 0
	var failed := 0
	for path in FILES:
		var script: GDScript = load(path)
		for m in script.get_script_method_list():
			var name: String = m.name
			if not name.begins_with("test_"):
				continue
			var t = script.new()
			t.call(name)
			if t.errors.is_empty():
				passed += 1
				print("  ok   %s" % name)
			else:
				failed += 1
				print("  FAIL %s" % name)
				for e in t.errors:
					print("       %s" % e)
	print("%d 통과, %d 실패" % [passed, failed])
	quit(1 if failed else 0)
