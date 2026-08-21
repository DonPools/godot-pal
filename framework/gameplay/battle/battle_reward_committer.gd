class_name BattleRewardCommitter
extends RefCounted


static func commit_victory(
	result: BattleResult,
	encounter: BattleEncounter,
	defeated_enemy_ids: Array[StringName],
	game_run: GameRun,
	database: ContentDatabase
) -> void:
	if result == null or encounter == null or game_run == null or database == null:
		return
	var item_order: Array[StringName] = []
	var item_definitions: Dictionary[StringName, ItemDefinition] = {}
	var requested_items: Dictionary[StringName, int] = {}
	for entry: EncounterEnemy in encounter.enemies:
		if entry == null or entry.enemy == null or entry.instance_id not in defeated_enemy_ids:
			continue
		result.cultivation_reward += entry.enemy.cultivation_reward
		result.money_reward += entry.enemy.money_reward
		if entry.enemy.drop_item != null and entry.enemy.drop_quantity > 0:
			var item_id := entry.enemy.drop_item.id
			if not requested_items.has(item_id):
				item_order.append(item_id)
				item_definitions[item_id] = entry.enemy.drop_item
			requested_items[item_id] = (
				int(requested_items.get(item_id, 0)) + entry.enemy.drop_quantity
			)
	var leader := game_run.party.leader()
	if leader != null and result.cultivation_reward > 0:
		CultivationRules.gain_cultivation(leader, result.cultivation_reward, database)
	if result.money_reward > 0:
		game_run.economy.add_money(result.money_reward)
	_commit_item_rewards(
		result,
		encounter,
		item_order,
		item_definitions,
		requested_items,
		game_run,
		database
	)
	if not result.dropped_items.is_empty():
		result.dropped_item_id = result.dropped_items.keys()[0]
		result.dropped_quantity = result.dropped_items[result.dropped_item_id]


static func _commit_item_rewards(
	result: BattleResult,
	encounter: BattleEncounter,
	item_order: Array[StringName],
	item_definitions: Dictionary[StringName, ItemDefinition],
	requested_items: Dictionary[StringName, int],
	game_run: GameRun,
	database: ContentDatabase
) -> void:
	if item_order.is_empty():
		return
	var trial := InventoryState.new()
	if not trial.restore(game_run.inventory.to_dictionary(), database):
		return
	for item_id: StringName in item_order:
		var requested := int(requested_items[item_id])
		var reward := trial.add_item(
			item_definitions[item_id],
			requested,
			encounter.reward_policy
		)
		if reward.changed_quantity > 0:
			result.dropped_items[item_id] = reward.changed_quantity
		if reward.rejected_quantity > 0:
			result.rejected_dropped_items[item_id] = reward.rejected_quantity
		if (
			encounter.reward_policy == RewardPolicy.Value.ALL_OR_NOTHING
			and not reward.succeeded()
		):
			result.dropped_items.clear()
			result.rejected_dropped_items.clear()
			for rejected_id: StringName in item_order:
				result.rejected_dropped_items[rejected_id] = int(requested_items[rejected_id])
			return
	game_run.inventory.restore(trial.to_dictionary(), database)
