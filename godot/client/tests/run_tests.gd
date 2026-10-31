# 헤드리스 테스트 러너 (GUT 없이): godot --headless --path godot/client -s res://tests/run_tests.gd
# FILES 의 test_*.gd 에서 test_ 로 시작하는 함수를 전부 돌림. 실패 = check 실패 (errors) · 그 테스트 동안 난 엔진·스크립트 오류
# (없는 함수·null 접근·타입 오류 — GDScript 는 예외가 없어 그냥 넘어가므로 Logger 로 잡음) · 파일을 못 읽음 · test_ 함수가 하나도 없음.
# 하나라도 실패하면 종료 코드 1. 묶음마다 test_<묶음>.gd 를 만들고 FILES 에 한 줄 더함 (godot/PLAN.md 7절)
extends SceneTree

const FILES := ["res://tests/test_core.gd", "res://tests/test_ui.gd", "res://tests/test_audio.gd", "res://tests/test_world.gd", "res://tests/test_shaders.gd", "res://tests/test_fx.gd", "res://tests/test_chars.gd", "res://tests/test_bblocks.gd", "res://tests/test_perf.gd", "res://tests/test_tutorial_ui.gd"]


# 테스트 동안 난 오류를 모음 (경고는 뺌). 다른 스레드에서도 불릴 수 있어 잠금
class ErrorLog extends Logger:
	var lines: Array = []
	var lock := Mutex.new()

	func _log_error(function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool, error_type: int, _backtraces: Array) -> void:
		if error_type == ERROR_TYPE_WARNING:
			return
		lock.lock()
		lines.append("%s (%s:%d %s)" % [rationale if rationale != "" else code, file, line, function])
		lock.unlock()

	func _log_message(_message: String, _error: bool) -> void:
		pass

	func take() -> Array:
		lock.lock()
		var out := lines
		lines = []
		lock.unlock()
		return out


func _initialize() -> void:
	var log := ErrorLog.new()
	OS.add_logger(log)
	var passed := 0
	var failed := 0
	for path in FILES:
		log.take()
		var script = load(path) if ResourceLoader.exists(path) else null
		var load_errs := log.take()
		if script == null or not script.can_instantiate() or not load_errs.is_empty():
			failed += 1
			print("  FAIL %s (못 읽음)" % path)
			for e in load_errs:
				print("       %s" % e)
			continue
		var names := []
		for m in script.get_script_method_list():
			if str(m.name).begins_with("test_"):
				names.append(str(m.name))
		if names.is_empty():
			failed += 1
			print("  FAIL %s (test_ 함수 없음)" % path)
			continue
		for name in names:
			var t = script.new()
			t.call(name)
			var errs: Array = (t.get("errors") if t.get("errors") is Array else ["errors 배열이 없음 (테스트 파일 모양)"]).duplicate()
			for e in log.take():
				errs.append("오류: " + e)
			if errs.is_empty():
				passed += 1
				print("  ok   %s" % name)
			else:
				failed += 1
				print("  FAIL %s" % name)
				for e in errs:
					print("       %s" % e)
	OS.remove_logger(log)
	print("%d 통과, %d 실패" % [passed, failed])
	quit(1 if failed else 0)
