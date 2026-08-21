class_name StoryTraceContext
extends StoryContext

var stage: StringName
var flags: Dictionary[StringName, Variant] = {}
var source_completed: bool = false
var battle_outcome: BattleResult.Outcome = BattleResult.Outcome.VICTORY
var trace: Array[Dictionary] = []
var pending_map_id: StringName
var recorded_spawn_id: StringName
var dialogue_choices: Dictionary[StringName, StringName] = {}
var inventory_quantities: Dictionary[StringName, int] = {}
var chance_result: bool = false
var breakthrough_succeeds: bool = true


func show_dialogue(dialogue: DialogueDefinition, block_id: StringName = &"default") -> DialogueResult:
	trace.append({"operation": "show_dialogue", "dialogue_id": String(dialogue.id), "block_id": String(block_id)})
	var result := DialogueResult.new()
	result.selected_option_id = dialogue_choices.get(block_id, &"")
	return result


func get_stage(module: StoryModule) -> StringName:
	return stage if not stage.is_empty() else module.initial_stage


func set_stage(_module: StoryModule, stage_id: StringName) -> void:
	stage = stage_id
	trace.append({"operation": "set_stage", "stage_id": String(stage_id)})


func is_flag_set(flag_id: StringName) -> bool:
	return bool(flags.get(flag_id, false))


func set_flag(flag_id: StringName, value: Variant = true) -> void:
	flags[flag_id] = value
	trace.append({"operation": "set_flag", "flag_id": String(flag_id), "value": value})


func clear_flag(flag_id: StringName) -> void:
	flags.erase(flag_id)
	trace.append({"operation": "clear_flag", "flag_id": String(flag_id)})


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
	trace.append({"operation": "give_item", "item_id": String(item.id), "quantity": quantity})
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
	trace.append({
		"operation": "deliver_items",
		"item_id": String(item.id),
		"quantity": quantity,
		"money_reward": money_reward,
	})
	return result


func roll_percent(chance: int) -> bool:
	trace.append({"operation": "roll_percent", "chance": chance, "result": chance_result})
	return chance_result


func is_ready_for_breakthrough() -> bool:
	return breakthrough_succeeds


func breakthrough(
	foundation: DaoFoundationDefinition,
	catalyst: ItemDefinition
) -> CultivationResult:
	var result := CultivationResult.new()
	result.outcome = (
		CultivationResult.Outcome.SUCCEEDED
		if breakthrough_succeeds
		else CultivationResult.Outcome.INSUFFICIENT_CULTIVATION
	)
	trace.append({
		"operation": "breakthrough",
		"foundation_id": String(foundation.id) if foundation != null else "",
		"catalyst_item_id": String(catalyst.id) if catalyst != null else "",
		"succeeded": result.succeeded(),
	})
	return result


func play_sound(stream: AudioStream) -> void:
	trace.append({
		"operation": "play_sound",
		"resource_path": stream.resource_path if stream != null else "",
	})


func is_source_entity_completed() -> bool:
	return source_completed


func complete_source_entity() -> void:
	source_completed = true
	trace.append({"operation": "complete_source_entity"})


func start_battle(encounter: BattleEncounter) -> BattleResult:
	trace.append({"operation": "start_battle", "encounter_id": String(encounter.id)})
	var result := BattleResult.new()
	result.outcome = battle_outcome
	return result


func restore_party() -> void:
	trace.append({"operation": "restore_party"})


func travel_to(destination: MapDestination) -> void:
	pending_map_id = destination.map_id if destination != null else &""
	recorded_spawn_id = destination.spawn_id if destination != null else &""
	trace.append({
		"operation": "travel_to",
		"map_id": String(pending_map_id),
		"spawn_id": String(recorded_spawn_id),
	})
