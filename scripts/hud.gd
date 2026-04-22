extends CanvasLayer

@onready var beat_indicator: ColorRect = $BeatIndicator
@onready var offbeat_indicator: ColorRect = $OffbeatIndicator

var _beat_flash := 0.0
var _offbeat_flash := 0.0
const FLASH_DURATION := 0.1


func _ready() -> void:
	var rhythm_engine := get_node("/root/Main/RhythmEngine")
	rhythm_engine.beat_hit.connect(_on_beat)
	rhythm_engine.offbeat_hit.connect(_on_offbeat)


func _process(delta: float) -> void:
	_beat_flash -= delta
	_offbeat_flash -= delta
	beat_indicator.color = Color(1, 0.6, 0, 1) if _beat_flash > 0.0 else Color(0.3, 0.3, 0.3, 1)
	offbeat_indicator.color = Color(0.9, 0.9, 0.1, 1) if _offbeat_flash > 0.0 else Color(0.3, 0.3, 0.3, 1)


func _on_beat() -> void:
	_beat_flash = FLASH_DURATION


func _on_offbeat() -> void:
	_offbeat_flash = FLASH_DURATION
