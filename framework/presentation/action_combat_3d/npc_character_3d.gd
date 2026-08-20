class_name NpcCharacter3D
extends CharacterBody3D

@export var definition: NpcDefinition
@export var initial_direction := Vector3.LEFT


func _ready() -> void:
	configure(definition)


func configure(value: NpcDefinition) -> void:
	definition = value
	if definition == null or definition.field_model_3d == null:
		push_error("NpcCharacter3D requires a NpcDefinition with field_model_3d")
		return
	var previous_model := get_node_or_null(^"Model") as Node3D
	if previous_model != null:
		remove_child(previous_model)
		previous_model.free()
	var model := definition.field_model_3d.instantiate() as Node3D
	if model == null:
		push_error("NpcDefinition field_model_3d root must be Node3D")
		return
	model.name = &"Model"
	add_child(model)
	move_child(model, 0)
	ModelPresentation3D.apply_outline(model, 0.018)
	if not initial_direction.is_zero_approx():
		model.look_at(model.global_position + initial_direction, Vector3.UP)
	var animation_player := _find_animation_player(model)
	if animation_player != null:
		for animation_name: StringName in animation_player.get_animation_list():
			if String(animation_name).get_file() == "idle":
				animation_player.play(animation_name)
				break


func _find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node as AnimationPlayer
	for child: Node in node.get_children():
		var found := _find_animation_player(child)
		if found != null:
			return found
	return null
