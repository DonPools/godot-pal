@tool
class_name SkillDefinition
extends ContentDefinition

@export_range(0, 999) var mp_cost: int = 0
@export var usable_in_field: bool = false
@export var usable_in_battle: bool = true
@export var effects: Array[GameEffect] = []
