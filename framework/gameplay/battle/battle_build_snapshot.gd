class_name BattleBuildSnapshot
extends RefCounted

var returning_projectile_skill_id: StringName
var area_refund_skill_id: StringName
var area_refund_target_count: int = 0
var area_refund_amount: int = 0
var basic_chain_length: int = 0
var basic_chain_wave_damage: int = 0
var skill_hit_resource_refund: int = 0
var skill_hit_cooldown_reduction: float = 0.0


static func create(
	state: ActorState,
	database: ContentDatabase
) -> BattleBuildSnapshot:
	var snapshot := BattleBuildSnapshot.new()
	if state == null or database == null:
		return snapshot
	var foundation := database.foundation(state.foundation_id)
	if foundation != null and foundation.battle_modifier != null:
		foundation.battle_modifier.apply_to(snapshot)
	for item_id: StringName in state.equipment.values():
		var equipment := database.item(item_id) as EquipmentDefinition
		if equipment != null and equipment.battle_modifier != null:
			equipment.battle_modifier.apply_to(snapshot)
	return snapshot
