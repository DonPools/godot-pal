class_name FakeStoryContext
extends StoryContext

var stage: StringName = &"not_started"
var shown_blocks: Array[StringName] = []
var flags: Dictionary[StringName, Variant] = {}
var source_completed: bool = false
var next_battle_result := BattleResult.new()
var party_restored: bool = false
var recorded_pending_map: MapDefinition
var recorded_pending_spawn_id: StringName
var dialogue_choices: Dictionary[StringName, StringName] = {}
var inventory_quantities: Dictionary[StringName, int] = {}
var delivered_items: Array[Dictionary] = []
var chance_results: Array[bool] = []


func show_dialogue(
	_dialogue: DialogueDefinition,
	block_id: StringName = &"default"
) -> DialogueResult:
	shown_blocks.append(block_id)
	var result := DialogueResult.new()
	result.selected_option_id = dialogue_choices.get(block_id, &"")
	return result


func get_stage(_module: StoryModule) -> StringName:
	return stage


func set_stage(module: StoryModule, stage_id: StringName) -> void:
	if module.has_stage(stage_id):
		stage = stage_id


func is_flag_set(flag_id: StringName) -> bool:
	return bool(flags.get(flag_id, false))


func set_flag(flag_id: StringName, value: Variant = true) -> void:
	flags[flag_id] = value


func clear_flag(flag_id: StringName) -> void:
	flags.erase(flag_id)


func give_item(
	item: ItemDefinition,
	quantity: int = 1,
	_policy: RewardPolicy.Value = RewardPolicy.Value.ALL_OR_NOTHING
) -> RewardResult:
	var result := RewardResult.new()
	if item == null or quantity <= 0:
		return result
	inventory_quantities[item.id] = inventory_quantities.get(item.id, 0) + quantity
	result.item_id = item.id
	result.requested_quantity = quantity
	result.changed_quantity = quantity
	return result


func item_quantity(item: ItemDefinition) -> int:
	return inventory_quantities.get(item.id, 0) if item != null else 0


func deliver_items(
	item: ItemDefinition,
	quantity: int,
	money_reward: int
) -> DeliveryResult:
	var result := DeliveryResult.new()
	if item == null or inventory_quantities.get(item.id, 0) < quantity:
		result.outcome = DeliveryResult.Outcome.INSUFFICIENT_ITEMS
		return result
	inventory_quantities[item.id] -= quantity
	result.outcome = DeliveryResult.Outcome.COMPLETED
	result.item_id = item.id
	result.quantity = quantity
	result.money_delta = money_reward
	delivered_items.append({
		"item_id": item.id,
		"quantity": quantity,
		"money_reward": money_reward,
	})
	return result


func roll_percent(_chance: int) -> bool:
	return chance_results.pop_front() if not chance_results.is_empty() else false


func complete_source_entity() -> void:
	source_completed = true


func is_source_entity_completed() -> bool:
	return source_completed


func start_battle(_encounter: BattleEncounter) -> BattleResult:
	return next_battle_result


func restore_party() -> void:
	party_restored = true


func travel_to(map: MapDefinition, spawn_id: StringName = &"") -> void:
	recorded_pending_map = map
	recorded_pending_spawn_id = spawn_id
