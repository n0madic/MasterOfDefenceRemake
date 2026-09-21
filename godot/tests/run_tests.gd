## Headless test runner:
##   godot --headless --path godot --import
##   godot --headless --path godot -s res://tests/run_tests.gd
##
## Discovers res://tests/test_*.gd, instantiates each script and calls every method whose
## name starts with `test_`. Test scripts extend `TestCase` and report via `check()`.
extends SceneTree

const TESTS_DIR := "res://tests"
## Measured: the UI suite still leaks after 0.3 s, is clean from 0.5 s on.
const AUDIO_DRAIN_SECONDS := 1.0


var _started := false


## The tests run from the first `_process`: in `_initialize` the root is not yet inside
## the tree, so nodes added there get no `_enter_tree` / `_ready`. `_run` spans a few
## frames (the audio drain at the end), so later frames just wait for it.
func _process(_delta: float) -> bool:
	if not _started:
		_started = true
		_run()
	return false


func _run() -> void:
	var filter := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--filter="):
			filter = arg.substr("--filter=".length())
	var failures := 0
	var total := 0
	var files := _discover()
	files.sort()
	for file in files:
		if filter != "" and not file.contains(filter):
			continue
		var script: GDScript = load(TESTS_DIR + "/" + file)
		if script == null or not script.can_instantiate():
			push_error("cannot load " + file)
			failures += 1
			continue
		var case: TestCase = script.new()
		case.suite_name = file
		case.tree = self
		for m in script.get_script_method_list():
			var name: String = m["name"]
			if not name.begins_with("test_"):
				continue
			total += 1
			case.begin(name)
			case.setup()
			case.call(name)
			case.teardown()
			if not case.end():
				failures += 1
	print("\n%d tests, %d failed" % [total, failures])
	# Sounds started by the screens under test are still playing: the mixer releases
	# their playbacks only after the ObjectDB leak check and reports them as leaks, so
	# drain them the way `Main.quit()` does before leaving. Headless frames take no time,
	# so wait for the mix thread by the clock (a fade-out and a deletion pass of the
	# dummy driver) and then give `AudioServer.update()` a frame to free them. (The
	# autoload is not an identifier here: the script is compiled before it is registered.)
	root.get_node("AudioManager").stop_all()
	await create_timer(AUDIO_DRAIN_SECONDS).timeout
	await process_frame
	quit(1 if failures > 0 else 0)


func _discover() -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open(TESTS_DIR)
	if dir == null:
		push_error("cannot open " + TESTS_DIR)
		return out
	dir.list_dir_begin()
	var f := dir.get_next()
	while f != "":
		if f.begins_with("test_") and f.ends_with(".gd"):
			out.append(f)
		f = dir.get_next()
	dir.list_dir_end()
	return out
