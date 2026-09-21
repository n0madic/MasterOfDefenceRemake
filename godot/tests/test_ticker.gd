extends TestCase

const TickerScript := preload("res://src/autoload/Ticker.gd")


func test_period_from_slider() -> void:
	var t: Node = TickerScript.new()
	check_eq(t.period_ms(), 16, "slider 20 -> 16 ms")
	check_near(t.ticks_per_second(), 62.5, 1e-9, "62.5 ticks/s")
	t.slider = 100
	check_eq(t.fps(), 140, "M -> fps 140")
	check_eq(t.period_ms(), 7, "1000 \\ 140 = 7")
	t.slider = 80
	check_eq(t.period_ms(), 8, "fps 120 -> 8 ms")
	t.slider = 0
	check_eq(t.period_ms(), 25, "fps 40 -> 25 ms")
	t.free()


func test_accumulator_carries_remainder() -> void:
	check_eq(TickerScript.ticks_for(15.9, 16), 0, "not yet")
	check_eq(TickerScript.ticks_for(33.0, 16), 2, "two ticks")
	var acc := 0.0
	var ticks := 0
	for frame in 100:
		acc += 16.6667  # 60 Hz render
		var n := TickerScript.ticks_for(acc, 16)
		acc -= float(n * 16)
		ticks += n
	check(ticks == 104, "100 frames at 60 Hz = 1666.67 ms -> 104 ticks, got %d" % ticks)


## The simulation ticks `ticked` once per period; the visual side gets one `frame_ticked`
## per frame carrying how many ticks ran (none when no period elapsed).
func test_frame_ticked_once_per_frame_with_tick_count() -> void:
	var t: Node = TickerScript.new()
	t.paused = false
	var ticks := [0]
	var frames: Array[int] = []
	t.ticked.connect(func(): ticks[0] += 1)
	t.frame_ticked.connect(func(n: int): frames.append(n))
	t._process(0.05)  # 50 ms at 16 ms per tick
	check_eq(ticks[0], 3, "three ticks in 50 ms")
	check_eq(frames, [3], "one frame_ticked carrying 3")
	t._process(0.001)
	check_eq(ticks[0], 3, "1 ms adds no tick")
	check_eq(frames, [3], "no frame_ticked without a tick")
	t.free()
