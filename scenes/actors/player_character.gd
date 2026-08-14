class_name PlayerCharacter
extends CharacterBody2D

signal interact_requested

@export var move_speed: float = 72.0

@onready var visual: AnimatedSprite2D = $Visual

var control_enabled: bool = true
var direction: StringName = &"south"


func configure(definition: ActorDefinition) -> void:
	if definition == null or definition.field_sprite == null:
		push_error("PlayerCharacter requires an ActorDefinition with field_sprite")
		return
	visual.sprite_frames = DirectionalSpriteFrames.from_3x4_sheet(definition.field_sprite)
	visual.position = DirectionalSpriteFrames.visual_offset(definition.field_sprite)
	visual.play(direction)


func set_control_enabled(enabled: bool) -> void:
	control_enabled = enabled
	if not enabled:
		velocity = Vector2.ZERO


func set_direction(value: StringName) -> void:
	if value not in [&"south", &"west", &"north", &"east"]:
		return
	direction = value
	visual.play(direction)
	visual.pause()


func _physics_process(_delta: float) -> void:
	if not control_enabled:
		velocity = Vector2.ZERO
		return
	var input := Input.get_vector(&"move_west", &"move_east", &"move_north", &"move_south")
	if input.is_zero_approx():
		velocity = Vector2.ZERO
		visual.pause()
		visual.frame = 0
		return
	var isometric := Vector2(input.x - input.y, (input.x + input.y) * 0.5).normalized()
	velocity = isometric * move_speed
	_update_direction(input)
	visual.play(direction)
	move_and_slide()


func _unhandled_input(event: InputEvent) -> void:
	if control_enabled and event.is_action_pressed(&"interact"):
		interact_requested.emit()
		get_viewport().set_input_as_handled()


func _update_direction(input: Vector2) -> void:
	if absf(input.x) >= absf(input.y):
		direction = &"east" if input.x > 0.0 else &"west"
	else:
		direction = &"south" if input.y > 0.0 else &"north"
