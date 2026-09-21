## Base class for headless tests. Failures are collected, never asserted, so that one
## failing check does not abort the whole run.
class_name TestCase
extends RefCounted

var suite_name := ""
## The running SceneTree (for tests that need nodes inside a tree).
var tree: SceneTree
var _current := ""
var _errors: Array[String] = []


func setup() -> void:
	pass


func teardown() -> void:
	pass


func begin(test_name: String) -> void:
	_current = test_name
	_errors.clear()


func end() -> bool:
	if _errors.is_empty():
		print("PASS %s::%s" % [suite_name, _current])
		return true
	print("FAIL %s::%s" % [suite_name, _current])
	for e in _errors:
		print("    " + e)
	return false


func check(cond: bool, msg: String) -> void:
	if not cond:
		_errors.append(msg)


func check_eq(actual: Variant, expected: Variant, msg: String = "") -> void:
	if actual != expected:
		_errors.append("%s expected %s, got %s" % [msg, str(expected), str(actual)])


func check_near(actual: float, expected: float, tol: float, msg: String = "") -> void:
	if absf(actual - expected) > tol:
		_errors.append("%s expected %s ± %s, got %s" % [msg, expected, tol, actual])
