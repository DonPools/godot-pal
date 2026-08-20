@tool
class_name CultivationRealmDefinition
extends ContentDefinition

@export_range(1, 99) var max_layer: int = 1
@export var layer_cultivation_costs: PackedInt32Array = PackedInt32Array()
@export_range(0, 999999) var breakthrough_cultivation_required: int = 0
@export var next_realm: CultivationRealmDefinition
@export var base_max_hp_bonus: int = 0
@export var base_max_mp_bonus: int = 0
@export var base_attack_bonus: int = 0
@export var max_hp_bonus_per_layer: int = 0
@export var max_mp_bonus_per_layer: int = 0
@export var attack_bonus_per_layer: int = 0


func cultivation_cost_for_layer(layer: int) -> int:
	if layer < 1 or layer >= max_layer:
		return -1
	return layer_cultivation_costs[layer - 1]


func max_hp_bonus(layer: int) -> int:
	return base_max_hp_bonus + maxi(layer - 1, 0) * max_hp_bonus_per_layer


func max_mp_bonus(layer: int) -> int:
	return base_max_mp_bonus + maxi(layer - 1, 0) * max_mp_bonus_per_layer


func attack_bonus(layer: int) -> int:
	return base_attack_bonus + maxi(layer - 1, 0) * attack_bonus_per_layer
