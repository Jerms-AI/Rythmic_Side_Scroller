extends Control

# Frequency bands to display — edit these to zoom into a range
@export var freq_min: float = 20.0
@export var freq_max: float = 500.0
@export var bar_count: int = 40
@export var visible_debug: bool = true

var _analyzer: AudioEffectSpectrumAnalyzerInstance
var _bar_heights: Array = []
var _peak_heights: Array = []
const PEAK_DECAY := 0.015
const BAR_SMOOTH := 0.3

# Tracks the highlighted range from rhythm engine
var highlight_low: float = 50.0
var highlight_high: float = 200.0


func _ready() -> void:
	visible = visible_debug
	_bar_heights.resize(bar_count)
	_bar_heights.fill(0.0)
	_peak_heights.resize(bar_count)
	_peak_heights.fill(0.0)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func setup(analyzer: AudioEffectSpectrumAnalyzerInstance) -> void:
	_analyzer = analyzer


func _process(_delta: float) -> void:
	if not visible or _analyzer == null:
		return
	for i in bar_count:
		var t_low := float(i) / bar_count
		var t_high := float(i + 1) / bar_count
		var f_low := _lerp_freq(t_low)
		var f_high := _lerp_freq(t_high)
		var mag: Vector2 = _analyzer.get_magnitude_for_frequency_range(f_low, f_high)
		var energy := (mag.x + mag.y) * 0.5
		# Smooth bar up fast, down slow
		if energy > _bar_heights[i]:
			_bar_heights[i] = energy
		else:
			_bar_heights[i] = lerp(_bar_heights[i], energy, BAR_SMOOTH)
		if _bar_heights[i] > _peak_heights[i]:
			_peak_heights[i] = _bar_heights[i]
		else:
			_peak_heights[i] = max(0.0, _peak_heights[i] - PEAK_DECAY)
	queue_redraw()


func _draw() -> void:
	if _analyzer == null:
		return

	var w := size.x
	var h := size.y * 0.35
	var y_base := size.y - 10.0
	var bar_w := (w / bar_count) - 1.0

	# Background
	draw_rect(Rect2(0, y_base - h - 5, w, h + 15), Color(0, 0, 0, 0.6))

	# Label
	draw_string(ThemeDB.fallback_font, Vector2(6, y_base - h - 8),
		"%.0f Hz — %.0f Hz   |   highlight: %.0f–%.0f Hz (drag in inspector)" % [freq_min, freq_max, highlight_low, highlight_high],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1,1,1,0.7))

	for i in bar_count:
		var t_low := float(i) / bar_count
		var t_high := float(i + 1) / bar_count
		var f_low := _lerp_freq(t_low)
		var f_high := _lerp_freq(t_high)

		var bar_h := clampf(_bar_heights[i] * 800.0, 0.0, h)
		var x := i * (bar_w + 1)

		# Highlight the currently sampled kick range
		var in_range := f_high >= highlight_low and f_low <= highlight_high
		var col := Color(1.0, 0.55, 0.1, 0.9) if in_range else Color(0.3, 0.7, 1.0, 0.8)

		draw_rect(Rect2(x, y_base - bar_h, bar_w, bar_h), col)

		# Peak tick
		var peak_h := clampf(_peak_heights[i] * 800.0, 0.0, h)
		draw_rect(Rect2(x, y_base - peak_h - 2, bar_w, 2), Color(1, 1, 1, 0.6))

	# Frequency labels every ~100Hz
	var step := 100.0
	var f: float = ceil(freq_min / step) * step
	while f <= freq_max:
		var t := log(f / freq_min) / log(freq_max / freq_min)
		var x := t * w
		draw_rect(Rect2(x, y_base - h - 2, 1, h + 2), Color(1, 1, 1, 0.2))
		draw_string(ThemeDB.fallback_font, Vector2(x + 2, y_base - 1),
			"%.0f" % f, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(1, 1, 1, 0.5))
		f += step


func _lerp_freq(t: float) -> float:
	return freq_min * pow(freq_max / freq_min, t)
