class_name MapGameScene
extends GameScene

@export var entry_trigger_id: StringName
@export var interaction_sound: AudioStream
@export var portal_sound: AudioStream

@onready var ground_layer: TileMapLayer = $GroundLayer
@onready var detail_layer: TileMapLayer = $DetailLayer
@onready var y_sort_root: Node2D = $YSortRoot
@onready var player: PlayerCharacter = $YSortRoot/PlayerCharacter
@onready var spawn_points: Node2D = $SpawnPoints
@onready var map_name_label: Label = $HudLayer/MapName
@onready var objective_label: Label = $HudLayer/Objective

var map_id: StringName:
	get:
		return definition.id if definition != null else &""

var definition: MapDefinition
var story_module: StoryModule


func enter(context: GameSceneContext, arguments: Variant) -> void:
	super.enter(context, arguments)
	var data: Dictionary = arguments if arguments is Dictionary else {}
	definition = data.get("definition") as MapDefinition
	story_module = data.get("story") as StoryModule
	if definition == null:
		push_error("MapGameScene.enter requires a MapDefinition")
		return
	_configure_characters()
	_configure_interactables()
	_place_player(StringName(data.get("spawn_id", definition.default_spawn_id)))
	context.audio_service.play_music(definition.music)
	map_name_label.text = definition.display_name
	_refresh_objective()
	player.interact_requested.connect(_on_player_interact)
	call_deferred("_run_entry_binding")


func exit_scene() -> void:
	capture_location()
	super.exit_scene()


func pause_scene() -> void:
	capture_location()
	super.pause_scene()


func set_player_control_enabled(enabled: bool) -> void:
	player.set_control_enabled(enabled)


func complete_entity(entity_id: StringName) -> void:
	for interactable: Interactable in _map_interactables():
		if interactable.persistent_id == entity_id:
			interactable.apply_completed()


func capture_location() -> void:
	if scene_context == null or player == null or definition == null:
		return
	var location := scene_context.game_run.location
	location.map_id = definition.id
	location.spawn_id = &""
	location.position = player.position
	location.direction = player.direction
	location.has_exact_position = true


func _configure_characters() -> void:
	var leader := scene_context.game_run.party.leader()
	var leader_definition := (
		scene_context.content_database.actor(leader.definition_id)
		if leader != null
		else null
	)
	player.configure(leader_definition)
	for child: Node in y_sort_root.get_children():
		if child is NpcCharacter:
			child.configure()
		elif child is WorldProp:
			child.configure()


func _configure_interactables() -> void:
	for interactable: Interactable in _map_interactables():
		if not interactable.portal_target_map_id.is_empty():
			var destination := scene_context.content_database.map(
				interactable.portal_target_map_id
			)
			var portal := ScenePortalEvent.new()
			portal.target_map = destination
			portal.target_spawn_id = interactable.portal_target_spawn_id
			interactable.configure_story(portal)
		else:
			interactable.configure_story(story_module)
		if (
			not interactable.persistent_id.is_empty()
			and scene_context.game_run.world.is_completed(map_id, interactable.persistent_id)
		):
			interactable.apply_completed()


func _place_player(spawn_id: StringName) -> void:
	var location := scene_context.game_run.location
	if location.map_id == map_id and location.has_exact_position:
		player.position = location.position
		player.set_direction(location.direction)
		return
	var marker := spawn_points.get_node_or_null(NodePath(String(spawn_id))) as Node2D
	if marker == null and spawn_points.get_child_count() > 0:
		marker = spawn_points.get_child(0) as Node2D
	if marker == null:
		push_error("Map %s has no spawn point for %s" % [map_id, spawn_id])
		return
	player.position = marker.position
	player.set_direction(&"south")
	location.map_id = map_id
	location.spawn_id = spawn_id
	location.has_exact_position = false


func _run_entry_binding() -> void:
	await get_tree().process_frame
	if entry_trigger_id.is_empty() or story_module == null:
		return
	var binding := StoryBinding.new()
	binding.event = story_module
	binding.trigger_id = entry_trigger_id
	await scene_context.story_director.run_binding(
		binding,
		StoryOrigin.create(map_id),
		self
	)
	_refresh_objective()


func _on_player_interact() -> void:
	var interactable := _nearest_interactable()
	if interactable == null:
		return
	scene_context.audio_service.play_sound(
		portal_sound
		if not interactable.portal_target_map_id.is_empty()
		else interaction_sound
	)
	await scene_context.story_director.run_binding(
		interactable.binding,
		interactable.story_origin(map_id),
		self
	)
	if is_instance_valid(self):
		_refresh_objective()


func _nearest_interactable() -> Interactable:
	var nearest: Interactable
	var nearest_distance := 42.0
	for interactable: Interactable in _map_interactables():
		if not interactable.is_available():
			continue
		var distance := player.global_position.distance_to(interactable.global_position)
		if distance < nearest_distance:
			nearest = interactable
			nearest_distance = distance
	return nearest


func _map_interactables() -> Array[Interactable]:
	var result: Array[Interactable] = []
	for candidate: Node in get_tree().get_nodes_in_group(&"story_interactables"):
		if candidate is Interactable and is_ancestor_of(candidate):
			result.append(candidate)
	return result


func _refresh_objective() -> void:
	if story_module == null:
		objective_label.text = "方向键/摇杆移动 · Enter/A 互动 · M/Start 菜单"
		return
	var stage := scene_context.game_run.story.get_stage(
		story_module.id,
		story_module.initial_stage
	)
	var objective := story_module.get_objective_text(stage, map_id)
	objective_label.text = (
		objective if not objective.is_empty() else "方向键移动 · Enter/Space 互动"
	)
