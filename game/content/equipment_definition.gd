class_name EquipmentDefinition
extends ItemDefinition

@export var slot: StringName = &"weapon"
@export var max_hp_bonus: int = 0
@export var max_mp_bonus: int = 0


func _init() -> void:
	category = Category.EQUIPMENT
	max_stack = 1
	usable_in_field = false
	usable_in_battle = false
