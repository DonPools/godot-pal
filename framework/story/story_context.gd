class_name StoryContext
extends RefCounted

var source_entity_id: StringName:
	get:
		return _origin.source_entity_id if _origin != null else &""
var source_actor_id: StringName:
	get:
		return _origin.source_actor_id if _origin != null else &""

var _game_run: GameRun
var _dialogue_layer: DialogueLayer
var _map_scene: MapGameScene
var _origin: StoryOrigin
var _scene_stack: GameSceneStack
var _shop_scene: PackedScene
var _content_database: ContentDatabase
var _active: bool = false
var _pending_map: MapDefinition
var _pending_spawn_id: StringName
var _last_battle_result: BattleResult
var _defeat_handled: bool = true


func initialize(
	game_run: GameRun,
	dialogue_layer: DialogueLayer,
	map_scene: MapGameScene,
	origin: StoryOrigin,
	scene_stack: GameSceneStack = null,
	shop_scene: PackedScene = null,
	content_database: ContentDatabase = null
) -> void:
	_game_run = game_run
	_dialogue_layer = dialogue_layer
	_map_scene = map_scene
	_origin = origin
	_scene_stack = scene_stack
	_shop_scene = shop_scene
	_content_database = content_database
	_active = true


func show_dialogue(
	dialogue: DialogueDefinition,
	block_id: StringName = &"default"
) -> DialogueResult:
	if not _require_active("show_dialogue"):
		return DialogueResult.new()
	return await _dialogue_layer.show_dialogue(dialogue, block_id)


func open_shop(shop: ShopDefinition) -> ShopResult:
	if not _require_active("open_shop"):
		return ShopResult.new()
	if shop == null or _scene_stack == null or _shop_scene == null:
		push_error("StoryContext.open_shop requires a shop and configured ShopGameScene")
		return ShopResult.new()
	var result: Variant = await _scene_stack.push(_shop_scene, shop)
	return result as ShopResult if result is ShopResult else ShopResult.new()


func start_battle(encounter: BattleEncounter) -> BattleResult:
	if not _require_active("start_battle"):
		return BattleResult.new()
	if encounter == null or _map_scene == null:
		push_error("StoryContext.start_battle requires an encounter and active MapGameScene")
		return BattleResult.new()
	_last_battle_result = await _map_scene.start_battle(encounter)
	_defeat_handled = _last_battle_result.outcome != BattleResult.Outcome.DEFEAT
	return _last_battle_result


func restore_party() -> void:
	if not _require_active("restore_party") or _content_database == null:
		return
	for actor_state: ActorState in _game_run.party.members:
		var definition := _content_database.actor(actor_state.definition_id)
		if definition != null:
			actor_state.hp = CultivationRules.max_hp(definition, actor_state, _content_database)
			actor_state.mp = CultivationRules.max_mp(definition, actor_state, _content_database)
	_defeat_handled = true


func give_item(
	item: ItemDefinition,
	quantity: int = 1,
	policy: RewardPolicy.Value = RewardPolicy.Value.ALL_OR_NOTHING
) -> RewardResult:
	if not _require_active("give_item"):
		return RewardResult.new()
	return _game_run.inventory.add_item(item, quantity, policy)


func item_quantity(item: ItemDefinition) -> int:
	if not _require_active("item_quantity") or item == null:
		return 0
	return _game_run.inventory.quantity(item.id)


func deliver_items(
	item: ItemDefinition,
	quantity: int,
	money_reward: int
) -> DeliveryResult:
	if not _require_active("deliver_items"):
		return DeliveryResult.new()
	return ItemDeliveryTransaction.exchange(_game_run, item, quantity, money_reward)


func is_ready_for_breakthrough() -> bool:
	return (
		_require_active("is_ready_for_breakthrough")
		and CultivationRules.is_ready_for_breakthrough(
			_game_run.party.leader(),
			_content_database
		)
	)


func breakthrough(
	foundation: DaoFoundationDefinition,
	catalyst: ItemDefinition
) -> CultivationResult:
	if not _require_active("breakthrough"):
		return CultivationResult.new()
	var result := CultivationTransaction.breakthrough(
		_game_run,
		foundation,
		catalyst,
		_content_database
	)
	if result.succeeded() and _map_scene != null:
		_map_scene.refresh_player_state()
	return result


func play_sound(stream: AudioStream) -> void:
	if _require_active("play_sound") and _map_scene != null:
		_map_scene.play_story_sound(stream)


func roll_percent(chance: int) -> bool:
	if not _require_active("roll_percent"):
		return false
	return _game_run.randomness.roll_percent(chance)


func get_stage(module: StoryModule) -> StringName:
	if not _require_active("get_stage"):
		return &""
	return _game_run.story.get_stage(module.id, module.initial_stage)


func set_stage(module: StoryModule, stage_id: StringName) -> void:
	if not _require_active("set_stage"):
		return
	if not module.has_stage(stage_id):
		push_error("Story %s rejected unknown stage %s" % [module.id, stage_id])
		return
	_game_run.story.set_stage(module.id, stage_id)


func is_flag_set(flag_id: StringName) -> bool:
	return _require_active("is_flag_set") and _game_run.flags.is_set(flag_id)


func get_flag(flag_id: StringName, default_value: Variant = null) -> Variant:
	if not _require_active("get_flag"):
		return default_value
	return _game_run.flags.get_value(flag_id, default_value)


func set_flag(flag_id: StringName, value: Variant = true) -> void:
	if _require_active("set_flag"):
		_game_run.flags.set_value(flag_id, value)


func clear_flag(flag_id: StringName) -> void:
	if _require_active("clear_flag"):
		_game_run.flags.clear(flag_id)


func is_source_entity_completed() -> bool:
	if not _require_active("is_source_entity_completed") or source_entity_id.is_empty():
		return false
	return _game_run.world.is_completed(_origin.map_id, source_entity_id)


func complete_source_entity() -> void:
	if not _require_active("complete_source_entity"):
		return
	if source_entity_id.is_empty():
		push_error("complete_source_entity requires a persistent StoryOrigin")
		return
	_game_run.world.complete(_origin.map_id, source_entity_id)
	if _map_scene != null:
		_map_scene.complete_entity(source_entity_id)


func wait_seconds(seconds: float) -> void:
	if not _require_active("wait_seconds"):
		return
	await _map_scene.get_tree().create_timer(maxf(seconds, 0.0)).timeout


func travel_to(destination: MapDestination) -> void:
	if not _require_active("travel_to"):
		return
	if destination == null or destination.map_id.is_empty() or _content_database == null:
		push_error("travel_to requires a MapDestination and ContentDatabase")
		return
	var map := _content_database.map(destination.map_id)
	if map == null:
		push_error("travel_to references unknown map %s" % destination.map_id)
		return
	_pending_map = map
	_pending_spawn_id = (
		destination.spawn_id
		if not destination.spawn_id.is_empty()
		else map.default_spawn_id
	)
	if _last_battle_result != null and _last_battle_result.outcome == BattleResult.Outcome.DEFEAT:
		_defeat_handled = true
	_active = false


func pending_map() -> MapDefinition:
	return _pending_map


func pending_spawn_id() -> StringName:
	return _pending_spawn_id


func has_unhandled_defeat() -> bool:
	return (
		_last_battle_result != null
		and _last_battle_result.outcome == BattleResult.Outcome.DEFEAT
		and not _defeat_handled
	)


func invalidate() -> void:
	_active = false
	_map_scene = null


func _require_active(operation: String) -> bool:
	if _active:
		return true
	push_error("StoryContext.%s called after the context became invalid" % operation)
	return false
