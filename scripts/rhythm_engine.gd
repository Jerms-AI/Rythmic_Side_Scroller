extends Node

signal beat_hit
signal offbeat_hit

# When a beat map JSON is loaded, it takes over. BPM math is the fallback.
@export var beat_map_path: String = "res://assets/beat_maps/fast_shadow.json"
@export var bpm: float = 109.0
@export var beat_window_ms: float = 80.0
@export var beat_offset_ms: float = 0.0
@export var metronome_enabled: bool = false
@export var calibration_key: Key = KEY_T

var _beat_interval_ms: float
var _last_beat_number: int = -1

var _tap_times: Array = []

var _click: AudioStreamPlayer
var _music: AudioStreamPlayer

# Beat map mode: sorted array of beat timestamps in ms
var _beat_map: Array = []
var _next_beat_idx: int = 0
var _next_offbeat_idx: int = 0  # tracks midpoint firing


func _ready() -> void:
	_beat_interval_ms = (60.0 / bpm) * 1000.0

	_click = AudioStreamPlayer.new()
	_click.stream = load("res://assets/audio/beat_click.wav")
	_click.volume_db = -6.0
	add_child(_click)

	_music = AudioStreamPlayer.new()
	_music.stream = load("res://assets/audio/music/Fast Shadow.ogg")
	_music.volume_db = 0.0
	add_child(_music)
	_music.play()

	_try_load_beat_map()


func _try_load_beat_map() -> void:
	if beat_map_path == "":
		return
	if not ResourceLoader.exists(beat_map_path):
		# File doesn't exist yet — fall back to BPM clock silently
		return
	var file := FileAccess.open(beat_map_path, FileAccess.READ)
	if file == null:
		push_warning("RhythmEngine: could not open %s" % beat_map_path)
		return
	var data: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if data == null or not data.has("beats"):
		push_warning("RhythmEngine: beat map missing 'beats' key")
		return
	_beat_map = data["beats"]
	if data.has("bpm"):
		bpm = float(data["bpm"])
		_beat_interval_ms = (60.0 / bpm) * 1000.0
	print("RhythmEngine: loaded beat map — %d beats, %.1f BPM" % [_beat_map.size(), bpm])


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == calibration_key:
			_register_tap()


func _register_tap() -> void:
	var now_ms := _audio_pos_ms()
	_tap_times.append(now_ms)
	if _tap_times.size() > 8:
		_tap_times.pop_front()
	if _tap_times.size() >= 4:
		_calculate_offset()


func _calculate_offset() -> void:
	var intervals: Array = []
	for i in range(1, _tap_times.size()):
		intervals.append(_tap_times[i] - _tap_times[i - 1])
	var avg_interval := 0.0
	for iv in intervals:
		avg_interval += iv
	avg_interval /= intervals.size()

	if avg_interval > 200.0 and avg_interval < 2000.0:
		bpm = 60000.0 / avg_interval
		_beat_interval_ms = (60.0 / bpm) * 1000.0

	var phases: Array = []
	for t in _tap_times:
		phases.append(fmod(t, _beat_interval_ms))
	var avg_phase := 0.0
	for p in phases:
		avg_phase += p
	avg_phase /= phases.size()

	beat_offset_ms = -avg_phase
	print("Calibrated — BPM: %.1f  offset: %.1fms" % [bpm, beat_offset_ms])


# Latency-compensated audio position in milliseconds.
# Uses AudioServer mix/output latency so the clock matches what you hear.
func _audio_pos_ms() -> float:
	var pos := _music.get_playback_position()
	pos += AudioServer.get_time_since_last_mix()
	pos -= AudioServer.get_output_latency()
	return maxf(pos, 0.0) * 1000.0 - beat_offset_ms


func _process(_delta: float) -> void:
	var pos_ms := _audio_pos_ms()

	if _beat_map.size() > 0:
		while _next_beat_idx < _beat_map.size() and pos_ms >= float(_beat_map[_next_beat_idx]):
			emit_signal("beat_hit")
			if metronome_enabled:
				_click.play()
			_next_beat_idx += 1

		# Fire offbeat_hit at midpoint between each pair of beats
		while _next_offbeat_idx + 1 < _beat_map.size():
			var mid := (float(_beat_map[_next_offbeat_idx]) + float(_beat_map[_next_offbeat_idx + 1])) * 0.5
			if pos_ms >= mid:
				emit_signal("offbeat_hit")
				_next_offbeat_idx += 1
			else:
				break
	else:
		var beat_num := int(pos_ms / _beat_interval_ms)
		if beat_num > _last_beat_number:
			_last_beat_number = beat_num
			emit_signal("beat_hit")
			if metronome_enabled:
				_click.play()
		var offbeat_num := int((pos_ms + _beat_interval_ms * 0.5) / _beat_interval_ms)
		if offbeat_num > _last_beat_number:
			emit_signal("offbeat_hit")


func is_on_beat() -> bool:
	var pos_ms := _audio_pos_ms()

	if _beat_map.size() > 0:
		var nearest_dist := INF
		for idx in [_next_beat_idx - 1, _next_beat_idx]:
			if idx >= 0 and idx < _beat_map.size():
				var dist := absf(pos_ms - float(_beat_map[idx]))
				if dist < nearest_dist:
					nearest_dist = dist
		return nearest_dist <= beat_window_ms
	else:
		var beat_pos := fmod(pos_ms, _beat_interval_ms)
		var dist := minf(beat_pos, _beat_interval_ms - beat_pos)
		return dist <= beat_window_ms


# True within beat_window_ms of the midpoint between two beats.
func is_on_offbeat() -> bool:
	var pos_ms := _audio_pos_ms()

	if _beat_map.size() > 0:
		# Midpoint between the last beat and the next beat
		var prev_idx := _next_beat_idx - 1
		var next_idx := _next_beat_idx
		if prev_idx >= 0 and next_idx < _beat_map.size():
			var mid := (float(_beat_map[prev_idx]) + float(_beat_map[next_idx])) * 0.5
			return absf(pos_ms - mid) <= beat_window_ms
		return false
	else:
		var beat_pos := fmod(pos_ms, _beat_interval_ms)
		var dist_from_mid := absf(beat_pos - _beat_interval_ms * 0.5)
		return dist_from_mid <= beat_window_ms
