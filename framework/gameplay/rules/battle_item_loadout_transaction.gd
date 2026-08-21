class_name BattleItemLoadoutTransaction
extends RefCounted


static func assign(
	game_run: GameRun,
	actor_state: ActorState,
	item: ItemDefinition,
	database: ContentDatabase
) -> BattleItemLoadoutResult:
	var result := BattleItemLoadoutResult.new()
	result.item_id = item.id if item != null else &""
	if game_run == null or actor_state == null:
		result.outcome = BattleItemLoadoutResult.Outcome.INVALID_ACTOR
		return result
	if (
		item == null
		or database == null
		or database.item(item.id) != item
	):
		return result
	if not item.can_be_used_in_battle():
		result.outcome = BattleItemLoadoutResult.Outcome.ITEM_NOT_USABLE_IN_BATTLE
		return result
	if game_run.inventory.quantity(item.id) <= 0:
		result.outcome = BattleItemLoadoutResult.Outcome.ITEM_UNAVAILABLE
		return result
	result.previous_item_id = actor_state.battle_item_id
	if actor_state.battle_item_id == item.id:
		result.outcome = BattleItemLoadoutResult.Outcome.UNCHANGED
		return result
	actor_state.battle_item_id = item.id
	result.outcome = BattleItemLoadoutResult.Outcome.ASSIGNED
	return result


static func clear(actor_state: ActorState) -> BattleItemLoadoutResult:
	var result := BattleItemLoadoutResult.new()
	if actor_state == null:
		result.outcome = BattleItemLoadoutResult.Outcome.INVALID_ACTOR
		return result
	result.previous_item_id = actor_state.battle_item_id
	result.item_id = actor_state.battle_item_id
	if actor_state.battle_item_id.is_empty():
		result.outcome = BattleItemLoadoutResult.Outcome.UNCHANGED
		return result
	actor_state.battle_item_id = &""
	result.outcome = BattleItemLoadoutResult.Outcome.CLEARED
	return result
