extends CharacterBody2D

enum State { IDLE, WALK, PUNCH, BLOCK, DUCK, UPPERCUT }

const SPEED := 200.0
const GRAVITY := 800.0
const PUNCH_DURATION := 0.25

var state: State = State.IDLE
var _state_timer := 0.0
var _facing := 1
var _fist: ColorRect
var _shield: ColorRect

@onready var sprite: AnimatedSprite2D = $Sprite
@onready var hitbox: Area2D = $Hitbox
@onready var rhythm_engine: Node = get_node("/root/Main/RhythmEngine")


func _ready() -> void:
	_fist = ColorRect.new()
	_fist.size = Vector2(96, 96)
	_fist.color = Color(0.7, 0.85, 1.0, 1)
	_fist.visible = false
	add_child(_fist)

	_shield = ColorRect.new()
	_shield.size = Vector2(84, 84)
	_shield.color = Color(0.95, 0.85, 0.2, 1)
	_shield.visible = false
	add_child(_shield)

	sprite.play("idle")


func is_blocking() -> bool:
	return state == State.BLOCK and rhythm_engine.is_on_beat()

func is_ducking() -> bool:
	return state == State.DUCK


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y += GRAVITY * delta

	_state_timer -= delta

	match state:
		State.IDLE, State.WALK:
			_handle_move_input()
			if Input.is_action_just_pressed("punch"):
				_enter_state(State.PUNCH)
			elif Input.is_action_pressed("block"):
				_enter_state(State.BLOCK)
			elif Input.is_action_pressed("duck"):
				_enter_state(State.DUCK)

		State.DUCK:
			var dir := Input.get_axis("move_left", "move_right")
			if dir != 0.0:
				_facing = int(sign(dir))
				velocity.x = dir * SPEED
			else:
				velocity.x = move_toward(velocity.x, 0, SPEED)
			if Input.is_action_just_pressed("punch") and rhythm_engine.is_on_beat():
				_enter_state(State.UPPERCUT)
			elif not Input.is_action_pressed("duck"):
				_enter_state(State.IDLE)

		State.UPPERCUT:
			if _state_timer <= 0.0:
				_enter_state(State.IDLE)

		State.PUNCH:
			if _state_timer <= 0.0:
				_enter_state(State.IDLE)

		State.BLOCK:
			velocity.x = move_toward(velocity.x, 0, SPEED)
			if not Input.is_action_pressed("block"):
				_enter_state(State.IDLE)

	sprite.flip_h = _facing == -1
	move_and_slide()


func _handle_move_input() -> void:
	var dir := Input.get_axis("move_left", "move_right")
	if dir != 0.0:
		_facing = int(sign(dir))
		velocity.x = dir * SPEED
		if state != State.WALK:
			state = State.WALK
			sprite.play("walk")
	else:
		velocity.x = move_toward(velocity.x, 0, SPEED)
		if state != State.IDLE:
			state = State.IDLE
			sprite.play("idle")


func _enter_state(new_state: State) -> void:
	state = new_state
	match new_state:
		State.PUNCH:
			_state_timer = PUNCH_DURATION
			hitbox.set_deferred("monitoring", true)
			_fist.position = Vector2(168 * _facing, -228)
			_fist.visible = true
			_shield.visible = false
			sprite.play("punch")
		State.BLOCK:
			hitbox.set_deferred("monitoring", false)
			_fist.visible = false
			_shield.position = Vector2(132 * _facing, -270)
			_shield.visible = true
			sprite.play("block")
		State.DUCK:
			hitbox.set_deferred("monitoring", false)
			_fist.visible = false
			_shield.visible = false
			sprite.play("crouch")
		State.UPPERCUT:
			_state_timer = PUNCH_DURATION
			hitbox.set_deferred("monitoring", true)
			_fist.position = Vector2(84 * _facing, -480)
			_fist.visible = true
			_shield.visible = false
			sprite.play("uppercut")
		State.IDLE, State.WALK:
			hitbox.set_deferred("monitoring", false)
			_fist.visible = false
			_shield.visible = false
			sprite.play("idle")


func take_hit() -> void:
	sprite.modulate = Color(1, 0.15, 0.15, 1)
	await get_tree().create_timer(0.1).timeout
	sprite.modulate = Color.WHITE


func blocked_hit() -> void:
	sprite.modulate = Color(1, 1, 0.1, 1)
	await get_tree().create_timer(0.1).timeout
	sprite.modulate = Color.WHITE


func _on_hitbox_body_entered(body: Node) -> void:
	if state == State.UPPERCUT:
		if body.has_method("hit_uppercut"):
			body.hit_uppercut()
		return
	if rhythm_engine.is_on_beat():
		if body.has_method("hit_onbeat"):
			body.hit_onbeat()
	elif rhythm_engine.is_on_offbeat():
		if body.has_method("hit_offbeat"):
			body.hit_offbeat()
	else:
		if body.has_method("whiff"):
			body.whiff()
