@tool
class_name ActorDefinition
extends ContentDefinition

@export var field_model_3d: PackedScene
@export_range(1, 9999) var base_max_hp: int = 100
@export_range(0, 9999) var base_max_mp: int = 20
@export_range(0, 9999) var base_attack: int = 12
@export_range(0, 999) var basic_attack_resource_gain: int = 2
@export var initial_realm: CultivationRealmDefinition
@export_range(1, 99) var initial_realm_layer: int = 1
@export_range(0, 999999) var initial_cultivation_points: int = 0
@export var initial_foundation: DaoFoundationDefinition
@export var equipment_slots: Array[StringName] = [&"weapon"]
@export var initial_equipment: Array[EquipmentDefinition] = []
@export var initial_skills: Array[SkillDefinition] = []
