class_name MapSceneValidator
extends RefCounted


func validate(database: ContentDatabase, stories: Array[StoryModule]) -> PackedStringArray:
	var errors := PackedStringArray()
	if database == null:
		errors.append("map scene validation requires a ContentDatabase")
		return errors
	var spawn_ids_by_map: Dictionary[StringName, Dictionary] = {}
	var portals: Array[Dictionary] = []
	for definition: MapDefinition in database.maps:
		if definition == null or definition.scene == null or definition.id.is_empty():
			continue
		var instance := definition.scene.instantiate()
		if not instance is MapGameScene:
			errors.append(
				"map %s scene root must inherit MapGameScene: %s"
				% [definition.id, definition.scene.resource_path]
			)
			instance.free()
			continue
		var map_scene := instance as MapGameScene
		_validate_tile_layer(definition, map_scene, &"GroundLayer", true, errors)
		_validate_tile_layer(definition, map_scene, &"DetailLayer", false, errors)
		var spawn_ids := _collect_spawn_ids(definition, map_scene, errors)
		spawn_ids_by_map[definition.id] = spawn_ids
		if not spawn_ids.has(definition.default_spawn_id):
			errors.append(
				"map %s default_spawn_id does not exist: %s"
				% [definition.id, definition.default_spawn_id]
			)
		if not map_scene.entry_trigger_id.is_empty():
			_validate_story_trigger(
				definition,
				"entry_trigger_id",
				map_scene.entry_trigger_id,
				stories,
				errors
			)
		_validate_interactables(definition, map_scene, database, stories, portals, errors)
		map_scene.free()
	_validate_portals(database, spawn_ids_by_map, portals, errors)
	return errors


func _validate_tile_layer(
	definition: MapDefinition,
	map_scene: MapGameScene,
	layer_name: StringName,
	cells_required: bool,
	errors: PackedStringArray
) -> void:
	var layer := map_scene.get_node_or_null(NodePath(String(layer_name))) as TileMapLayer
	if layer == null:
		errors.append("map %s is missing %s" % [definition.id, layer_name])
		return
	var used_cells := layer.get_used_cells()
	if used_cells.is_empty():
		if cells_required:
			errors.append("map %s %s has no painted cells" % [definition.id, layer_name])
		return
	if layer.tile_set == null:
		errors.append("map %s %s has no TileSet" % [definition.id, layer_name])
		return
	for cell: Vector2i in used_cells:
		var source_id := layer.get_cell_source_id(cell)
		var atlas_coords := layer.get_cell_atlas_coords(cell)
		if not layer.tile_set.has_source(source_id):
			errors.append(
				"map %s %s cell %s uses missing TileSet source %d"
				% [definition.id, layer_name, cell, source_id]
			)
			continue
		var atlas_source := layer.tile_set.get_source(source_id) as TileSetAtlasSource
		if atlas_source == null or atlas_source.texture == null:
			errors.append(
				"map %s %s TileSet source %d has no atlas texture"
				% [definition.id, layer_name, source_id]
			)
		elif not atlas_source.has_tile(atlas_coords):
			errors.append(
				"map %s %s cell %s uses missing atlas tile %s"
				% [definition.id, layer_name, cell, atlas_coords]
			)


func _collect_spawn_ids(
	definition: MapDefinition,
	map_scene: MapGameScene,
	errors: PackedStringArray
) -> Dictionary:
	var result: Dictionary[StringName, bool] = {}
	var spawn_points := map_scene.get_node_or_null(^"SpawnPoints")
	if spawn_points == null:
		errors.append("map %s is missing SpawnPoints" % definition.id)
		return result
	for child: Node in spawn_points.get_children():
		if not child is Marker2D:
			errors.append(
				"map %s SpawnPoints child must be Marker2D: %s" % [definition.id, child.name]
			)
			continue
		var spawn_id := StringName(child.name)
		if spawn_id.is_empty() or result.has(spawn_id):
			errors.append("map %s has empty or repeated spawn ID: %s" % [definition.id, spawn_id])
		result[spawn_id] = true
	return result


func _validate_interactables(
	definition: MapDefinition,
	map_scene: MapGameScene,
	database: ContentDatabase,
	stories: Array[StoryModule],
	portals: Array[Dictionary],
	errors: PackedStringArray
) -> void:
	var interactables: Array[Interactable] = []
	_collect_interactables(map_scene, interactables)
	var persistent_ids: Dictionary[StringName, bool] = {}
	for interactable: Interactable in interactables:
		var interactable_path := map_scene.get_path_to(interactable)
		var field := "interactable %s trigger_id" % interactable_path
		if not interactable.persistent_id.is_empty():
			if persistent_ids.has(interactable.persistent_id):
				errors.append(
					"map %s has repeated persistent ID: %s"
					% [definition.id, interactable.persistent_id]
				)
			persistent_ids[interactable.persistent_id] = true
		if not interactable.portal_target_map_id.is_empty():
			if interactable.event != null:
				errors.append(
					"map %s portal %s cannot also configure a StoryEvent"
					% [definition.id, interactable_path]
				)
			if interactable.trigger_id != &"default":
				errors.append(
					"map %s portal %s must use trigger_id default"
					% [definition.id, interactable_path]
				)
			portals.append({
				"source_map_id": definition.id,
				"node_path": interactable_path,
				"target_map_id": interactable.portal_target_map_id,
				"target_spawn_id": interactable.portal_target_spawn_id,
			})
		elif interactable.event != null:
			_validate_embedded_event(definition, interactable_path, interactable, database, errors)
		else:
			_validate_story_trigger(
				definition,
				field,
				interactable.trigger_id,
				stories,
				errors
			)


func _validate_embedded_event(
	definition: MapDefinition,
	interactable_path: NodePath,
	interactable: Interactable,
	database: ContentDatabase,
	errors: PackedStringArray
) -> void:
	var event := interactable.event
	if interactable.trigger_id.is_empty() or interactable.trigger_id not in event.get_trigger_ids():
		errors.append(
			"map %s interactable %s references unknown embedded event trigger: %s"
			% [definition.id, interactable_path, interactable.trigger_id]
		)
	if event is ShopEvent:
		var shop_event := event as ShopEvent
		if shop_event.shop == null or not database.has_shop(shop_event.shop.id):
			errors.append("map %s shop event %s references an unregistered shop" % [definition.id, interactable_path])
	elif event is TreasureChestEvent:
		var chest := event as TreasureChestEvent
		_validate_item_source(definition, interactable_path, interactable, chest.item, database, errors)
		if chest.quantity < 1:
			errors.append("map %s chest %s has invalid quantity" % [definition.id, interactable_path])
	elif event is ItemPickupEvent:
		var pickup := event as ItemPickupEvent
		_validate_item_source(definition, interactable_path, interactable, pickup.item, database, errors)
		if pickup.quantity < 1:
			errors.append("map %s pickup %s has invalid quantity" % [definition.id, interactable_path])
		if pickup.reward_policy == RewardPolicy.Value.ALLOW_PARTIAL:
			errors.append(
				"map %s pickup %s cannot use ALLOW_PARTIAL without remaining quantity state"
				% [definition.id, interactable_path]
			)


func _validate_item_source(
	definition: MapDefinition,
	interactable_path: NodePath,
	interactable: Interactable,
	item: ItemDefinition,
	database: ContentDatabase,
	errors: PackedStringArray
) -> void:
	if item == null or not database.has_item(item.id):
		errors.append("map %s item event %s references an unregistered item" % [definition.id, interactable_path])
	if interactable.persistent_id.is_empty():
		errors.append("map %s item event %s requires persistent_id" % [definition.id, interactable_path])


func _collect_interactables(node: Node, result: Array[Interactable]) -> void:
	for child: Node in node.get_children():
		if child is Interactable:
			result.append(child)
		_collect_interactables(child, result)


func _validate_story_trigger(
	definition: MapDefinition,
	field: String,
	trigger_id: StringName,
	stories: Array[StoryModule],
	errors: PackedStringArray
) -> void:
	if trigger_id.is_empty():
		errors.append("map %s %s is empty" % [definition.id, field])
	else:
		var matching_stories: Array[StoryModule] = []
		for story: StoryModule in stories:
			if story != null and trigger_id in story.get_trigger_ids():
				matching_stories.append(story)
		if matching_stories.is_empty():
			errors.append(
				"map %s %s references unknown story trigger: %s"
				% [definition.id, field, trigger_id]
			)
		elif matching_stories.size() > 1:
			errors.append(
				"map %s %s has ambiguous story trigger %s across %d modules"
				% [definition.id, field, trigger_id, matching_stories.size()]
			)


func _validate_portals(
	database: ContentDatabase,
	spawn_ids_by_map: Dictionary[StringName, Dictionary],
	portals: Array[Dictionary],
	errors: PackedStringArray
) -> void:
	for portal: Dictionary in portals:
		var source_map_id := StringName(portal["source_map_id"])
		var target_map_id := StringName(portal["target_map_id"])
		var target_spawn_id := StringName(portal["target_spawn_id"])
		var node_path: NodePath = portal["node_path"]
		if not database.has_map(target_map_id):
			errors.append(
				"map %s portal %s references unknown target map: %s"
				% [source_map_id, node_path, target_map_id]
			)
			continue
		var target_spawns: Dictionary = spawn_ids_by_map.get(target_map_id, {})
		if target_spawn_id.is_empty() or not target_spawns.has(target_spawn_id):
			errors.append(
				"map %s portal %s references unknown spawn %s in map %s"
				% [source_map_id, node_path, target_spawn_id, target_map_id]
			)
