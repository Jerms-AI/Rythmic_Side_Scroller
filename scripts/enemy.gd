extends CharacterBody2D

enum State { APPROACH, ATTACK, PUNCH, HIT, DEAD }

const SPEED := 80.0
const GRAVITY := 800.0
const ATTACK_RANGE := 360.0
const ATTACK_COOLDOWN := 1.2
const HIT_DURATION := 0.2
const PUNCH_DURATION := 0.3

var hp := 1
var state: State = State.APPROACH
var _state_timer := 0.0
var _attack_timer := 0.0
var _beat_count := 0
var _combo_stage := 0  # 0=none  1=onbeat(wait offbeat)  2=blocked(wait offbeat)  3=blocked+offbeat(wait onbeat)  4=triple done(wait onbeat for quad)
var _combo_timer := 0.0
const COMBO_WINDOW := 0.6
var _charge := 0.0
const CHARGE_RATE := 0.8

@onready var sprite: AnimatedSprite2D = $Sprite
@onready var player: CharacterBody2D = get_node("/root/Main/Player")
@onready var rhythm_engine: Node = get_node("/root/Main/RhythmEngine")


func _ready() -> void:
	sprite.play("idle")
	rhythm_engine.beat_hit.connect(_on_beat)


func _face_player() -> void:
	sprite.flip_h = global_position.x < player.global_position.x


func _physics_process(delta: float) -> void:
	if state == State.DEAD:
		return

	if not is_on_floor():
		velocity.y += GRAVITY * delta

	_state_timer -= delta
	_attack_timer -= delta
	if _combo_timer > 0.0:
		_combo_timer -= delta
		if _combo_timer <= 0.0:
			_combo_stage = 0

	_face_player()

	match state:
		State.APPROACH:
			var dist := global_position.distance_to(player.global_position)
			if dist > ATTACK_RANGE:
				var dir := (player.global_position - global_position).normalized()
				velocity.x = dir.x * SPEED
				if sprite.animation != "walk":
					sprite.play("walk")
			else:
				velocity.x = 0.0
				state = State.ATTACK
				sprite.play("idle")

		State.ATTACK:
			velocity.x = 0.0
			_charge = minf(_charge + delta * CHARGE_RATE, 1.0)
			var base_scale := Vector2(0.36, 0.36)
			sprite.scale = base_scale * (1.0 + _charge * 0.2)
			if sprite.animation != "idle":
				sprite.play("idle")
			var dist := global_position.distance_to(player.global_position)
			if dist > ATTACK_RANGE:
				_reset_charge()
				state = State.APPROACH

		State.PUNCH:
			velocity.x = 0.0
			if _state_timer <= 0.0:
				_attack_timer = ATTACK_COOLDOWN
				state = State.ATTACK
				sprite.play("idle")

		State.HIT:
			velocity.x = 0.0
			if _state_timer <= 0.0:
				state = State.APPROACH

	move_and_slide()


func _on_beat() -> void:
	_beat_count += 1
	if _beat_count % 2 != 0:
		return
	if state == State.ATTACK:
		var dist := global_position.distance_to(player.global_position)
		if dist <= ATTACK_RANGE:
			_enter_punch()


func _reset_charge() -> void:
	_charge = 0.0
	sprite.scale = Vector2(0.36, 0.36)


func _enter_punch() -> void:
	_reset_charge()
	sprite.play("punch")
	state = State.PUNCH
	_state_timer = PUNCH_DURATION
	var dist := global_position.distance_to(player.global_position)
	if dist <= ATTACK_RANGE:
		if player.is_blocking():
			player.blocked_hit()
			_combo_stage = 2
			_combo_timer = COMBO_WINDOW
		elif player.is_ducking():
			pass
		else:
			player.take_hit()
			_combo_stage = 0


func hit_onbeat() -> void:
	if state == State.DEAD or state == State.HIT:
		return
	if _combo_stage == 4:
		whiff()
	elif _combo_stage == 3:
		_combo_stage = 4
		_combo_timer = COMBO_WINDOW
		sprite.modulate = Color(0.6, 0.1, 0.85, 1)
		await get_tree().create_timer(0.1).timeout
		if state != State.DEAD and state != State.HIT:
			sprite.modulate = Color.WHITE
	elif _combo_stage == 0:
		_combo_stage = 1
		_combo_timer = COMBO_WINDOW
		sprite.modulate = Color(1, 0.15, 0.15, 1)
		await get_tree().create_timer(0.12).timeout
		if state != State.DEAD and state != State.HIT:
			sprite.modulate = Color.WHITE
	else:
		whiff()


func hit_offbeat() -> void:
	if state == State.DEAD or state == State.HIT:
		return
	if _combo_stage == 1:
		_combo_stage = 0
		_combo_timer = 0.0
		sprite.modulate = Color(0.6, 0.1, 0.85, 1)
		await get_tree().create_timer(0.1).timeout
		if state != State.DEAD:
			sprite.modulate = Color.WHITE
	elif _combo_stage == 2:
		_combo_stage = 3
		_combo_timer = COMBO_WINDOW
		sprite.modulate = Color(1, 0.5, 0.0, 1)
		await get_tree().create_timer(0.1).timeout
		if state != State.DEAD and state != State.HIT:
			sprite.modulate = Color.WHITE
	else:
		whiff()


func hit_uppercut() -> void:
	if state == State.DEAD or state == State.HIT:
		return
	if _combo_stage == 4:
		_combo_stage = 0
		_combo_timer = 0.0
		hp = 0
		_die_uppercut()
	else:
		whiff()


func take_damage(amount: int) -> void:
	if state == State.DEAD or state == State.HIT:
		return
	hp -= amount
	if hp <= 0:
		_die()
	else:
		_reset_charge()
		state = State.HIT
		_state_timer = HIT_DURATION
		await get_tree().create_timer(HIT_DURATION).timeout
		if state != State.DEAD:
			sprite.modulate = Color.WHITE


func whiff() -> void:
	if state == State.DEAD:
		return
	sprite.modulate = Color(1, 1, 1, 1)
	await get_tree().create_timer(0.08).timeout
	if state != State.DEAD:
		sprite.modulate = Color.WHITE


func _die() -> void:
	state = State.DEAD
	velocity = Vector2.ZERO
	sprite.modulate = Color(1, 0.15, 0.15, 1)
	await get_tree().create_timer(0.1).timeout
	sprite.modulate = Color.WHITE
	var tween := create_tween().set_parallel(true)
	tween.tween_property(sprite, "modulate:a", 0.0, 0.3)
	tween.tween_property(sprite, "scale", Vector2(0.58, 0.11), 0.3).set_ease(Tween.EASE_OUT)
	await tween.finished
	queue_free()


func _die_uppercut() -> void:
	state = State.DEAD
	velocity = Vector2.ZERO
	sprite.modulate = Color(0.9, 0.9, 1.0, 1)
	var tween := create_tween().set_parallel(true)
	tween.tween_property(self, "position:y", position.y - 800.0, 2.2).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tween.tween_property(self, "position:x", position.x + randf_range(-80.0, 80.0), 2.2).set_ease(Tween.EASE_OUT)
	tween.tween_property(sprite, "modulate:a", 0.0, 1.8).set_delay(0.4)
	tween.tween_property(sprite, "scale", Vector2(0.22, 0.50), 2.0).set_ease(Tween.EASE_OUT)
	await tween.finished
	queue_free()
