@tool
class_name ActorDefinition
extends ContentDefinition

@export var field_sprite: Texture2D
@export_range(1, 9999) var base_max_hp: int = 100
@export_range(0, 9999) var base_max_mp: int = 20
@export_range(1, 99) var initial_level: int = 1
@export var initial_equipment: Array[EquipmentDefinition] = []
@export var initial_skills: Array[SkillDefinition] = []
