class_name PointerTarget3D
extends Area3D

const POINTER_COLLISION_LAYER := 5

@export var pointer_enabled: bool = true


func _ready() -> void:
	set_pointer_enabled(pointer_enabled)


func set_pointer_enabled(enabled: bool) -> void:
	pointer_enabled = enabled
	set_collision_layer_value(POINTER_COLLISION_LAYER, enabled)
	input_ray_pickable = enabled
