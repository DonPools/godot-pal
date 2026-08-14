class_name StoryDirector
extends Node

var _game_run_provider: Callable
var _travel_callback: Callable
var _dialogue_layer: DialogueLayer
var _scene_stack: GameSceneStack
var _shop_scene: PackedScene
var _battle_scene: PackedScene
var _content_database: ContentDatabase
var _busy: bool = false


func configure(
	game_run_provider: Callable,
	travel_callback: Callable,
	dialogue_layer: DialogueLayer,
	scene_stack: GameSceneStack,
	shop_scene: PackedScene,
	battle_scene: PackedScene,
	content_database: ContentDatabase
) -> void:
	_game_run_provider = game_run_provider
	_travel_callback = travel_callback
	_dialogue_layer = dialogue_layer
	_scene_stack = scene_stack
	_shop_scene = shop_scene
	_battle_scene = battle_scene
	_content_database = content_database


func is_busy() -> bool:
	return _busy


func run_binding(
	binding: StoryBinding,
	origin: StoryOrigin,
	map_scene: MapGameScene
) -> void:
	if _busy:
		return
	if binding == null or binding.event == null:
		push_error("StoryDirector received an empty StoryBinding")
		return
	if binding.trigger_id not in binding.event.get_trigger_ids():
		push_error("Story event does not declare trigger %s" % binding.trigger_id)
		return
	var story := StoryContext.new()
	story.initialize(
		_game_run_provider.call(),
		_dialogue_layer,
		map_scene,
		origin,
		_scene_stack,
		_shop_scene,
		_battle_scene,
		_content_database
	)
	if not binding.event.can_run(binding.trigger_id, story):
		story.invalidate()
		return
	_busy = true
	map_scene.set_player_control_enabled(false)
	await binding.event.run(binding.trigger_id, story)
	var destination := story.pending_map()
	var spawn_id := story.pending_spawn_id()
	story.invalidate()
	_busy = false
	if destination != null:
		_travel_callback.call(destination, spawn_id)
	elif is_instance_valid(map_scene):
		map_scene.set_player_control_enabled(true)
