class_name ItemDeliveryTransaction
extends RefCounted


static func exchange(
	game_run: GameRun,
	item: ItemDefinition,
	quantity: int,
	money_reward: int
) -> DeliveryResult:
	var result := DeliveryResult.new()
	if game_run == null or item == null or quantity <= 0 or money_reward < 0:
		return result
	result.item_id = item.id
	result.quantity = quantity
	if game_run.inventory.quantity(item.id) < quantity:
		result.outcome = DeliveryResult.Outcome.INSUFFICIENT_ITEMS
		return result
	var removal := game_run.inventory.remove_item(item, quantity)
	if not removal.succeeded():
		result.outcome = DeliveryResult.Outcome.INSUFFICIENT_ITEMS
		return result
	game_run.economy.add_money(money_reward)
	result.outcome = DeliveryResult.Outcome.COMPLETED
	result.money_delta = money_reward
	return result
