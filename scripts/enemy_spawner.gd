extends Node2D

@export var enemy_scene: PackedScene
@export var spawn_interval: float = 3.0
@export var spawn_x_offset: float = 200.0
@export var max_spawns: int = 3

var _timer := 0.0
var _spawn_count := 0


func _process(delta: float) -> void:
	if _spawn_count >= max_spawns:
		return
	_timer -= delta
	if _timer <= 0.0:
		_timer = spawn_interval
		_spawn()


func _spawn() -> void:
	if enemy_scene == null:
		return
	var e := enemy_scene.instantiate()
	var viewport_size := get_viewport().get_visible_rect().size
	e.global_position = Vector2(viewport_size.x + spawn_x_offset, 500)
	get_parent().add_child(e)
	_spawn_count += 1
