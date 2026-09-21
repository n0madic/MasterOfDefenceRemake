## Test base with a loaded GameData instance and helpers to drive SimGame headless.
class_name SimTestCase
extends TestCase

const GameDataScript := preload("res://src/autoload/GameData.gd")

var data: GameDataScript
var game: SimGame
var messages: Array = []
var sounds: Array = []


func setup() -> void:
	data = GameDataScript.new()
	data.load_all()
	game = SimGame.new(data, 12345)
	messages.clear()
	sounds.clear()
	game.message.connect(func(t, k, ms): messages.append({"text": t, "kind": k, "ms": ms}))
	game.sound.connect(func(n, _p): sounds.append(n))


func teardown() -> void:
	game = null
	data.free()


func run_ticks(n: int) -> void:
	for i in n:
		game.tick()


## Tick until `pred` is true; returns the number of ticks or -1 on timeout.
func run_until(pred: Callable, max_ticks: int) -> int:
	for i in range(1, max_ticks + 1):
		game.tick()
		if pred.call():
			return i
	return -1


## A monster standing still at `pos` (speed 0, no path progress).
func dummy_enemy(pos: Vector3, air: bool = false, life: float = 100000.0, armor: int = 0) -> SimEnemy:
	var e := game.create_enemy(false, 7 if air else 1)
	e.speed = 0.0
	e.path.body = pos
	e.path.time = 1.0  # away from the fade-in
	e.max_life = life
	e.life = life
	e.armor = armor
	return e
