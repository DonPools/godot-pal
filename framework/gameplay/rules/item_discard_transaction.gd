class_name ItemDiscardTransaction
extends RefCounted


static func discard(
	game_run: GameRun,
	item: ItemDefinition,
	quantity: int = 1
) -> ItemDiscardResult:
	var result := ItemDiscardResult.new()
	result.item_id = item.id if item != null else &""
	result.quantity = quantity
	if game_run == null or item == null:
		return result
	if quantity <= 0:
		result.outcome = ItemDiscardResult.Outcome.INVALID_QUANTITY
		return result
	if not item.can_discard:
		result.outcome = ItemDiscardResult.Outcome.NOT_DISCARDABLE
		return result
	if game_run.inventory.quantity(item.id) < quantity:
		result.outcome = ItemDiscardResult.Outcome.INSUFFICIENT_QUANTITY
		return result
	var removal := game_run.inventory.remove_item(item, quantity)
	if not removal.succeeded():
		result.outcome = ItemDiscardResult.Outcome.INSUFFICIENT_QUANTITY
		return result
	result.outcome = ItemDiscardResult.Outcome.DISCARDED
	return result
