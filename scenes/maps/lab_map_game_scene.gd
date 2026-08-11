class_name LabMapGameScene
extends GameScene

@export var map_id: StringName
@export var map_title: String
@export var tile_source_id: int = 10
@export var entry_trigger_id: StringName

@onready var ground_layer: TileMapLayer = $GroundLayer
@onready var detail_layer: TileMapLayer = $DetailLayer
@onready var y_sort_root: Node2D = $YSortRoot
@onready var player: PlayerCharacter = $YSortRoot/PlayerCharacter
@onready var spawn_points: Node2D = $SpawnPoints
@onready var map_name_label: Label = $HudLayer/MapName
@onready var objective_label: Label = $HudLayer/Objective

var definition: MapDefinition
var story_module: StoryModule


func enter(context: GameSceneContext, arguments: Variant) -> void:
	super.enter(context, arguments)
	var data: Dictionary = arguments if arguments is Dictionary else {}
	definition = data.get("definition")
	story_module = data.get("story")
	_build_tile_layers()
	_configure_characters()
	_configure_interactables()
	_place_player(StringName(data.get("spawn_id", definition.default_spawn_id)))
	context.audio_service.play_music(definition.music_source_id)
	map_name_label.text = map_title
	_refresh_objective()
	player.interact_requested.connect(_on_player_interact)
	call_deferred("_run_entry_binding")


func exit_scene() -> void:
	capture_location()
	super.exit_scene()


func set_player_control_enabled(enabled: bool) -> void:
	player.set_control_enabled(enabled)


func complete_entity(entity_id: StringName) -> void:
	for interactable: Interactable in _map_interactables():
		if interactable.persistent_id == entity_id:
			interactable.apply_completed()


func capture_location() -> void:
	if scene_context == null or player == null:
		return
	var location := scene_context.game_run.location
	location.map_id = map_id
	location.spawn_id = &""
	location.position = player.position
	location.direction = player.direction
	location.has_exact_position = true


func _build_tile_layers() -> void:
	var atlas: Dictionary = scene_context.asset_library.tile_atlas(tile_source_id)
	var texture: Texture2D = atlas.get("texture")
	var cell_size: Vector2i = atlas.get("cell_size", Vector2i(32, 16))
	var columns: int = atlas.get("columns", 1)
	var frame_count: int = atlas.get("frame_count", 0)
	var tile_set := TileSet.new()
	tile_set.tile_shape = TileSet.TILE_SHAPE_ISOMETRIC
	tile_set.tile_layout = TileSet.TILE_LAYOUT_DIAMOND_DOWN
	tile_set.tile_size = Vector2i(32, 16)
	var source := TileSetAtlasSource.new()
	source.texture = texture
	source.texture_region_size = cell_size
	for frame_index: int in range(frame_count):
		var atlas_coords := Vector2i(frame_index % columns, frame_index / columns)
		source.create_tile(atlas_coords)
		var tile_data := source.get_tile_data(atlas_coords, 0)
		tile_data.texture_origin = Vector2i(0, 8 - cell_size.y / 2)
	tile_set.add_source(source, 0)
	ground_layer.tile_set = tile_set
	detail_layer.tile_set = tile_set
	var ground_frames := _ground_frames()
	for y: int in range(10):
		for x: int in range(15):
			var frame: int = ground_frames[(x * 3 + y * 5) % ground_frames.size()]
			_set_tile(ground_layer, Vector2i(x, y), frame, columns, frame_count)
	for tile: Dictionary in _detail_tiles():
		_set_tile(
			detail_layer,
			Vector2i(int(tile["x"]), int(tile["y"])),
			int(tile["frame"]),
			columns,
			frame_count
		)


func _ground_frames() -> Array[int]:
	if tile_source_id == 10:
		return [1, 2]
	return [48, 49]


func _detail_tiles() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var wall_frames: Array[int] = []
	if tile_source_id == 10:
		wall_frames.assign([6, 7, 22, 23])
	else:
		wall_frames.assign([2, 3, 18, 19])
	for x: int in range(15):
		result.append({"x": x, "y": 0, "frame": wall_frames[x % wall_frames.size()]})
	for y: int in range(1, 9):
		result.append({"x": 0, "y": y, "frame": wall_frames[y % wall_frames.size()]})
	return result


func _set_tile(
	layer: TileMapLayer,
	coords: Vector2i,
	frame_index: int,
	columns: int,
	frame_count: int
) -> void:
	var safe_index := clampi(frame_index, 0, maxi(frame_count - 1, 0))
	layer.set_cell(
		coords,
		0,
		Vector2i(safe_index % columns, safe_index / columns),
		0
	)


func _configure_characters() -> void:
	player.configure(scene_context.asset_library, 2)
	for child: Node in y_sort_root.get_children():
		if child is NpcCharacter:
			child.configure(scene_context.asset_library)
		elif child is WorldProp:
			child.configure(scene_context.asset_library)


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
	if marker == null:
		marker = spawn_points.get_child(0) as Node2D
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
		98 if not interactable.portal_target_map_id.is_empty() else 78
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
		objective_label.text = "方向键移动 · Enter/Space 互动 · F5/F9 存取"
		return
	var stage := scene_context.game_run.story.get_stage(
		story_module.id,
		story_module.initial_stage
	)
	match stage:
		&"not_started", &"met_innkeeper":
			objective_label.text = "先和掌柜谈谈"
		&"looking_for_owner":
			objective_label.text = "去雨院寻找蓑衣客"
		&"owner_found":
			objective_label.text = "拿起井边的旧伞"
		&"umbrella_found":
			objective_label.text = "把旧伞交给掌柜"
		&"completed":
			objective_label.text = "故事完成 · 可继续探索或 F9 读档"
		_:
			objective_label.text = "方向键移动 · Enter/Space 互动"
