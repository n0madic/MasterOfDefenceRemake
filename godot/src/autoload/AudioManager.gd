## Sound playback: `SimGame.sound(name, position)` -> assets/audio/<name>.wav.
## Music: music<L>.ogg looped on the camera (`_fstartbackgroundmusic`), menu.ogg in menus.
extends Node

const AUDIO_DIR := "res://assets/audio"
const MAX_PLAYERS := 16
const LOOPED := ["tlen", "water"]

var sound_volume := 0.5
var music_volume := 0.5
var _players: Array[AudioStreamPlayer] = []
var _music: AudioStreamPlayer
var _shutting_down := false
var _loops: Dictionary = {}
var _cache: Dictionary = {}


func _ready() -> void:
	for i in MAX_PLAYERS:
		var p := AudioStreamPlayer.new()
		p.bus = "Master"
		add_child(p)
		_players.append(p)
	_music = AudioStreamPlayer.new()
	add_child(_music)


func bind(game: SimGame) -> void:
	if not game.sound.is_connected(_on_sound):
		game.sound.connect(_on_sound)


func _stream(name: String) -> AudioStream:
	if _cache.has(name):
		return _cache[name]
	var s: AudioStream = null
	for ext in ["wav", "ogg"]:
		var path := "%s/%s.%s" % [AUDIO_DIR, name, ext]
		if ResourceLoader.exists(path):
			s = load(path)
			break
	_cache[name] = s
	return s


func play(name: String) -> void:
	var s := _stream(name)
	if s == null or _shutting_down:
		return
	for p in _players:
		if not p.playing:
			p.stream = s
			p.volume_db = linear_to_db(sound_volume)
			p.play()
			return


func _on_sound(name: String, _position: Vector3) -> void:
	play(name)


func play_loop(name: String) -> void:
	if _loops.has(name) or _shutting_down:
		return
	var s := _stream(name)
	if s == null:
		return
	var p := AudioStreamPlayer.new()
	p.stream = s
	p.volume_db = linear_to_db(sound_volume)
	add_child(p)
	p.finished.connect(p.play)
	p.play()
	_loops[name] = p


## Playbacks still running at exit are released by the audio thread after the ObjectDB
## leak check and get reported as leaks: `Main.quit()` stops everything and waits a frame,
## and nothing may start in between (the in-game menu keeps ticking its hover sound).
func stop_all() -> void:
	_shutting_down = true
	for p in _players:
		p.stop()
	for p in _loops.values():
		p.stop()
	_music.stop()


func stop_loops() -> void:
	for p in _loops.values():
		p.queue_free()
	_loops.clear()


func play_music(path: String) -> void:
	if not ResourceLoader.exists(path) or _shutting_down:
		return
	var s: AudioStream = load(path)
	if s is AudioStreamOggVorbis:
		(s as AudioStreamOggVorbis).loop = true
	_music.stream = s
	_music.volume_db = linear_to_db(music_volume)
	_music.play()


func stop_music() -> void:
	_music.stop()


func set_volumes(sound: float, music: float) -> void:
	sound_volume = sound
	music_volume = music
	_music.volume_db = linear_to_db(maxf(music, 0.001))
	for p in _loops.values():
		p.volume_db = linear_to_db(maxf(sound, 0.001))
