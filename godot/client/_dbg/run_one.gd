extends SceneTree
func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var script = load("res://tests/%s.gd" % args[0])
	for m in script.get_script_method_list():
		var nm := str(m.name)
		if nm.begins_with("test_") and (args.size() < 2 or nm in args.slice(1)):
			var t = script.new()
			var t0 := Time.get_ticks_msec()
			t.call(nm)
			print(("  ok   " if t.errors.is_empty() else "  FAIL ") + nm, " ", Time.get_ticks_msec() - t0, "ms")
			for e in t.errors:
				print("       ", e)
	quit()
