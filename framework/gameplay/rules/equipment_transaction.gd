class_name EquipmentTransaction
extends RefCounted


static func equip(
	game_run: GameRun,
	actor_state: ActorState,
	equipment: EquipmentDefinition,
	database: ContentDatabase
) -> EquipmentResult:
	var result := EquipmentResult.new()
	if game_run == null or actor_state == null:
		result.outcome = EquipmentResult.Outcome.INVALID_ACTOR
		return result
	if equipment == null or equipment.slot.is_empty() or database == null:
		return result
	result.slot = equipment.slot
	result.equipped_item_id = equipment.id
	var previous_id: StringName = actor_state.equipment.get(equipment.slot, &"")
	if previous_id == equipment.id:
		result.outcome = EquipmentResult.Outcome.ALREADY_EQUIPPED
		return result
	if game_run.inventory.quantity(equipment.id) <= 0:
		result.outcome = EquipmentResult.Outcome.ITEM_UNAVAILABLE
		return result
	var trial := InventoryState.new()
	if not trial.restore(game_run.inventory.to_dictionary()):
		result.outcome = EquipmentResult.Outcome.INVENTORY_REJECTED
		return result
	if not trial.remove_item(equipment, 1).succeeded():
		result.outcome = EquipmentResult.Outcome.ITEM_UNAVAILABLE
		return result
	if not previous_id.is_empty():
		var previous := database.item(previous_id) as EquipmentDefinition
		if previous == null or not trial.add_item(
			previous,
			1,
			RewardPolicy.Value.ALL_OR_NOTHING
		).succeeded():
			result.outcome = EquipmentResult.Outcome.INVENTORY_REJECTED
			return result
		result.returned_item_id = previous_id
	game_run.inventory.restore(trial.to_dictionary())
	actor_state.equipment[equipment.slot] = equipment.id
	var actor_definition := database.actor(actor_state.definition_id)
	actor_state.hp = mini(
		actor_state.hp,
		CultivationRules.max_hp(actor_definition, actor_state, database)
	)
	actor_state.mp = mini(
		actor_state.mp,
		CultivationRules.max_mp(actor_definition, actor_state, database)
	)
	result.outcome = EquipmentResult.Outcome.EQUIPPED
	return result
