class_name InventoryState
extends RefCounted

var max_distinct_items: int = 12
var _order: Array[StringName] = []
var _quantities: Dictionary[StringName, int] = {}
var _capacity_flags: Dictionary[StringName, bool] = {}


func quantity(item_id: StringName) -> int:
	return _quantities.get(item_id, 0)


func item_ids() -> Array[StringName]:
	return _order.duplicate()


func occupied_capacity() -> int:
	var result := 0
	for item_id: StringName in _order:
		if _capacity_flags.get(item_id, true):
			result += 1
	return result


func remaining_capacity() -> int:
	return maxi(max_distinct_items - occupied_capacity(), 0)


func add_item(
	item: ItemDefinition,
	requested_quantity: int = 1,
	policy: RewardPolicy.Value = RewardPolicy.Value.ALL_OR_NOTHING
) -> RewardResult:
	var result := _result_for(item, requested_quantity)
	if item == null or requested_quantity <= 0:
		result.failure_reason = RewardResult.FailureReason.INVALID_QUANTITY
		result.rejected_quantity = maxi(requested_quantity, 0)
		return result
	var current := quantity(item.id)
	var capacity := maxi(item.max_stack - current, 0)
	if current == 0 and _uses_capacity(item) and occupied_capacity() >= max_distinct_items:
		capacity = 0
	var accepted := mini(requested_quantity, capacity)
	if policy == RewardPolicy.Value.ALL_OR_NOTHING and accepted < requested_quantity:
		accepted = 0
	if accepted <= 0:
		result.rejected_quantity = requested_quantity
		result.failure_reason = RewardResult.FailureReason.INVENTORY_FULL
		return result
	if current == 0:
		_order.append(item.id)
		_capacity_flags[item.id] = _uses_capacity(item)
	_quantities[item.id] = current + accepted
	result.changed_quantity = accepted
	result.rejected_quantity = requested_quantity - accepted
	if result.rejected_quantity > 0:
		result.failure_reason = RewardResult.FailureReason.INVENTORY_FULL
	return result


func remove_item(item: ItemDefinition, requested_quantity: int = 1) -> RewardResult:
	var result := _result_for(item, requested_quantity)
	if item == null or requested_quantity <= 0:
		result.failure_reason = RewardResult.FailureReason.INVALID_QUANTITY
		result.rejected_quantity = maxi(requested_quantity, 0)
		return result
	var current := quantity(item.id)
	if current < requested_quantity:
		result.rejected_quantity = requested_quantity
		result.failure_reason = RewardResult.FailureReason.INSUFFICIENT_QUANTITY
		return result
	var remaining := current - requested_quantity
	if remaining == 0:
		_quantities.erase(item.id)
		_order.erase(item.id)
		_capacity_flags.erase(item.id)
	else:
		_quantities[item.id] = remaining
	result.changed_quantity = requested_quantity
	return result


func to_dictionary() -> Dictionary:
	var entries: Array[Dictionary] = []
	for item_id: StringName in _order:
		entries.append({"item_id": String(item_id), "quantity": quantity(item_id)})
	return {"max_distinct_items": max_distinct_items, "entries": entries}


func restore(data: Dictionary, database: ContentDatabase = null) -> bool:
	var raw_entries: Variant = data.get("entries")
	if not raw_entries is Array:
		return false
	var restored_order: Array[StringName] = []
	var restored_quantities: Dictionary[StringName, int] = {}
	var restored_capacity_flags: Dictionary[StringName, bool] = {}
	for raw_entry: Variant in raw_entries:
		if not raw_entry is Dictionary:
			return false
		var raw_id: Variant = raw_entry.get("item_id")
		var amount := int(raw_entry.get("quantity", 0))
		if not raw_id is String or String(raw_id).is_empty() or amount <= 0:
			return false
		var item_id := StringName(raw_id)
		if restored_quantities.has(item_id):
			return false
		restored_order.append(item_id)
		restored_quantities[item_id] = amount
		var definition := database.item(item_id) if database != null else null
		restored_capacity_flags[item_id] = (
			definition == null or _uses_capacity(definition)
		)
	var restored_maximum := int(data.get("max_distinct_items", 12))
	if restored_maximum < 1:
		return false
	var restored_occupied := 0
	for item_id: StringName in restored_order:
		if restored_capacity_flags.get(item_id, true):
			restored_occupied += 1
	if restored_occupied > restored_maximum:
		return false
	max_distinct_items = restored_maximum
	_order = restored_order
	_quantities = restored_quantities
	_capacity_flags = restored_capacity_flags
	return true


func _result_for(item: ItemDefinition, requested_quantity: int) -> RewardResult:
	var result := RewardResult.new()
	result.item_id = item.id if item != null else &""
	result.requested_quantity = requested_quantity
	return result


func _uses_capacity(item: ItemDefinition) -> bool:
	return item != null and item.category != ItemDefinition.Category.KEY_ITEM
