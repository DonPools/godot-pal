class_name ShopTransaction
extends RefCounted


static func buy(game_run: GameRun, entry: ShopEntry, quantity: int = 1) -> ShopResult:
	var result := ShopResult.new()
	if game_run == null or entry == null or entry.item == null or quantity <= 0:
		return result
	result.item_id = entry.item.id
	result.quantity = quantity
	var total_price := entry.buy_price() * quantity
	if not game_run.economy.can_afford(total_price):
		result.outcome = ShopResult.Outcome.INSUFFICIENT_FUNDS
		return result
	var reward := game_run.inventory.add_item(
		entry.item,
		quantity,
		RewardPolicy.Value.ALL_OR_NOTHING
	)
	if not reward.succeeded():
		result.outcome = ShopResult.Outcome.INVENTORY_FULL
		return result
	if not game_run.economy.try_spend(total_price):
		game_run.inventory.remove_item(entry.item, quantity)
		result.outcome = ShopResult.Outcome.INSUFFICIENT_FUNDS
		return result
	result.outcome = ShopResult.Outcome.PURCHASED
	result.money_delta = -total_price
	return result
