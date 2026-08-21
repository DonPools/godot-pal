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
		if (
			definition.story_module != null
			and not _story_is_registered(definition.story_module, stories)
		):
			errors.append(
				"map %s references an unscanned default StoryModule: %s"
				% [definition.id, definition.story_module.id]
			)
		var instance := definition.scene.instantiate()
		if not instance is MapGameScene3D:
			errors.append(
				"map %s scene root must inherit MapGameScene3D: %s"
				% [definition.id, definition.scene.resource_path]
			)
			instance.free()
			continue
		var map_scene := instance as MapGameScene3D
		_validate_map(definition, map_scene, errors)
		var spawn_ids := _collect_spawn_ids(definition, map_scene, errors)
		spawn_ids_by_map[definition.id] = spawn_ids
		if not spawn_ids.has(definition.default_spawn_id):
			errors.append(
				"map %s default_spawn_id does not exist: %s"
				% [definition.id, definition.default_spawn_id]
			)
		for index: int in range(map_scene.entry_bindings.size()):
			_validate_story_binding(
				definition,
				"entry_bindings[%d]" % index,
				map_scene.entry_bindings[index],
				stories,
				errors
			)
		_validate_story_sources(definition, map_scene, database, stories, portals, errors)
		map_scene.free()
	_validate_story_destinations(database, stories, errors)
	_validate_portals(database, spawn_ids_by_map, portals, errors)
	return errors


func _collect_spawn_ids(
	definition: MapDefinition,
	map_scene: MapGameScene3D,
	errors: PackedStringArray
) -> Dictionary:
	var result: Dictionary[StringName, bool] = {}
	var spawn_points := map_scene.get_node_or_null(^"WorldRoot/SpawnPoints")
	if spawn_points == null:
		errors.append("map %s is missing WorldRoot/SpawnPoints" % definition.id)
		return result
	for child: Node in spawn_points.get_children():
		if not child is Marker3D:
			errors.append(
				"map %s SpawnPoints child must be Marker3D: %s"
				% [definition.id, child.name]
			)
			continue
		var spawn_id := StringName(child.name)
		if spawn_id.is_empty() or result.has(spawn_id):
			errors.append("map %s has empty or repeated spawn ID: %s" % [definition.id, spawn_id])
		result[spawn_id] = true
	return result


func _validate_map(
	definition: MapDefinition,
	map_scene: MapGameScene3D,
	errors: PackedStringArray
) -> void:
	var requirements := {
		"WorldRoot": Node3D,
		"WorldRoot/Terrain": Node3D,
		"WorldRoot/PlayerCharacter3D": CharacterBody3D,
		"WorldRoot/EncounterSources": Node3D,
		"WorldRoot/Enemies": Node3D,
		"WorldRoot/NavigationRegion3D": NavigationRegion3D,
		"Camera3D": MapCameraRig3D,
		"PointerController": MapPointerController3D,
	}
	for path: String in requirements:
		var node := map_scene.get_node_or_null(NodePath(path))
		if node == null or not is_instance_of(node, requirements[path]):
			errors.append("map %s is missing 3D node %s" % [definition.id, path])
	var pointer_controller := map_scene.get_node_or_null(
		^"PointerController"
	) as MapPointerController3D
	if pointer_controller != null and (
		pointer_controller.move_cursor == null
		or pointer_controller.attack_cursor == null
		or pointer_controller.interact_cursor == null
		or pointer_controller.forbidden_cursor == null
	):
		errors.append("map %s PointerController has incomplete cursor assets" % definition.id)
	var navigation := map_scene.get_node_or_null(
		^"WorldRoot/NavigationRegion3D"
	) as NavigationRegion3D
	if navigation != null and navigation.navigation_mesh == null:
		errors.append("map %s NavigationRegion3D has no NavigationMesh" % definition.id)
	var terrain := map_scene.get_node_or_null(^"WorldRoot/Terrain") as Node3D
	if terrain != null and terrain.get_child_count() == 0:
		errors.append("map %s 3D Terrain has no modules" % definition.id)


func _validate_story_sources(
	definition: MapDefinition,
	map_scene: MapGameScene3D,
	database: ContentDatabase,
	stories: Array[StoryModule],
	portals: Array[Dictionary],
	errors: PackedStringArray
) -> void:
	var persistent_ids: Dictionary[StringName, bool] = {}
	var interactables: Array[StoryInteractable3D] = []
	_collect_interactables(map_scene, interactables)
	for interactable: StoryInteractable3D in interactables:
		var path := map_scene.get_path_to(interactable)
		_validate_persistent_id(definition, interactable.persistent_id, persistent_ids, errors)
		if (
			not interactable.actor_definition_id.is_empty()
			and not database.has_actor(interactable.actor_definition_id)
			and not database.has_npc(interactable.actor_definition_id)
		):
			errors.append(
				"map %s 3D interactable %s references an unknown actor or NPC definition"
				% [definition.id, path]
			)
		if not interactable.portal_target_map_id.is_empty():
			if interactable.binding != null:
				errors.append(
					"map %s 3D portal %s has an incompatible StoryBinding"
					% [definition.id, path]
				)
			portals.append(_portal_record(
				definition.id,
				path,
				interactable.portal_target_map_id,
				interactable.portal_target_spawn_id
			))
		elif interactable.binding != null:
			_validate_story_binding(
				definition,
				"3D interactable %s binding" % path,
				interactable.binding,
				stories,
				errors
			)
			_validate_embedded_event(
				definition,
				path,
				interactable,
				database,
				stories,
				errors
			)
			if (
				interactable.binding.event != null
				and interactable.binding.event is ScenePortalEvent
			):
				var portal := interactable.binding.event as ScenePortalEvent
				if portal.destination != null:
					portals.append(_portal_record(
						definition.id,
						path,
						portal.destination.map_id,
						_resolved_destination_spawn(database, portal.destination)
					))
		else:
			errors.append(
				"map %s 3D interactable %s has no StoryBinding"
				% [definition.id, path]
			)
	var source_root := map_scene.get_node_or_null(^"WorldRoot/EncounterSources")
	if source_root == null:
		return
	for child: Node in source_root.get_children():
		if not child is EncounterSource3D:
			errors.append(
				"map %s EncounterSources child must be EncounterSource3D: %s"
				% [definition.id, child.name]
			)
			continue
		var source := child as EncounterSource3D
		_validate_persistent_id(definition, source.persistent_id, persistent_ids, errors, true)
		if source.encounter == null or not database.has_encounter(source.encounter.id):
			errors.append(
				"map %s encounter source %s references an unregistered encounter"
				% [definition.id, child.name]
			)
		if source.binding == null or source.binding.event == null:
			errors.append(
				"map %s encounter source %s has no StoryBinding"
				% [definition.id, child.name]
			)
		else:
			_validate_story_binding(
				definition,
				"encounter source %s binding" % child.name,
				source.binding,
				stories,
				errors
			)


func _validate_embedded_event(
	definition: MapDefinition,
	interactable_path: NodePath,
	interactable: StoryInteractable3D,
	database: ContentDatabase,
	stories: Array[StoryModule],
	errors: PackedStringArray
) -> void:
	var event := interactable.binding.event
	if event == null:
		return
	if event is StoryModule and not _story_is_registered(event, stories):
		errors.append(
			"map %s interactable %s references an unscanned StoryModule"
			% [definition.id, interactable_path]
		)
	elif event is ShopEvent:
		var shop_event := event as ShopEvent
		if shop_event.shop == null or not database.has_shop(shop_event.shop.id):
			errors.append(
				"map %s shop event %s references an unregistered shop"
				% [definition.id, interactable_path]
			)
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
	elif event is DialogueEvent:
		var dialogue_event := event as DialogueEvent
		if (
			dialogue_event.dialogue == null
			or dialogue_event.dialogue.block(dialogue_event.block_id) == null
		):
			errors.append(
				"map %s dialogue event %s references an unknown dialogue block"
				% [definition.id, interactable_path]
			)
	elif event is BattleTriggerEvent:
		var battle_event := event as BattleTriggerEvent
		if battle_event.encounter == null or not database.has_encounter(battle_event.encounter.id):
			errors.append(
				"map %s battle event %s references an unregistered encounter"
				% [definition.id, interactable_path]
			)
		if interactable.persistent_id.is_empty():
			errors.append(
				"map %s battle event %s requires persistent_id"
				% [definition.id, interactable_path]
			)
		if battle_event.defeat_destination != null:
			_validate_destination(
				"map %s battle event %s defeat_destination"
				% [definition.id, interactable_path],
				battle_event.defeat_destination,
				database,
				errors
			)
	elif event is ScenePortalEvent:
		var portal_event := event as ScenePortalEvent
		_validate_destination(
			"map %s portal event %s destination" % [definition.id, interactable_path],
			portal_event.destination,
			database,
			errors
		)


func _validate_item_source(
	definition: MapDefinition,
	interactable_path: NodePath,
	interactable: StoryInteractable3D,
	item: ItemDefinition,
	database: ContentDatabase,
	errors: PackedStringArray
) -> void:
	if item == null or not database.has_item(item.id):
		errors.append(
			"map %s item event %s references an unregistered item"
			% [definition.id, interactable_path]
		)
	if interactable.persistent_id.is_empty():
		errors.append("map %s item event %s requires persistent_id" % [definition.id, interactable_path])


func _validate_persistent_id(
	definition: MapDefinition,
	persistent_id: StringName,
	known_ids: Dictionary[StringName, bool],
	errors: PackedStringArray,
	required: bool = false
) -> void:
	if persistent_id.is_empty():
		if required:
			errors.append("map %s encounter source requires persistent_id" % definition.id)
		return
	if known_ids.has(persistent_id):
		errors.append("map %s has repeated persistent ID: %s" % [definition.id, persistent_id])
	known_ids[persistent_id] = true


func _map_contains_spawn(definition: MapDefinition, spawn_id: StringName) -> bool:
	if definition == null or definition.scene == null or spawn_id.is_empty():
		return false
	var instance := definition.scene.instantiate()
	var spawn_points := instance.get_node_or_null(^"WorldRoot/SpawnPoints")
	var found := (
		instance is MapGameScene3D
		and spawn_points != null
		and spawn_points.get_node_or_null(NodePath(String(spawn_id))) is Marker3D
	)
	instance.free()
	return found


func _validate_story_destinations(
	database: ContentDatabase,
	stories: Array[StoryModule],
	errors: PackedStringArray
) -> void:
	for story: StoryModule in stories:
		if story == null:
			continue
		for property: Dictionary in story.get_property_list():
			if (int(property.get("usage", 0)) & PROPERTY_USAGE_EDITOR) == 0:
				continue
			var property_name := StringName(property.get("name", ""))
			var value: Variant = story.get(property_name)
			if value is MapDestination:
				_validate_destination(
					"story %s %s" % [story.id, property_name],
					value as MapDestination,
					database,
					errors
				)
			elif value is Array:
				for index: int in range(value.size()):
					if value[index] is MapDestination:
						_validate_destination(
							"story %s %s[%d]" % [story.id, property_name, index],
							value[index] as MapDestination,
							database,
							errors
						)


func _validate_destination(
	owner: String,
	destination: MapDestination,
	database: ContentDatabase,
	errors: PackedStringArray
) -> void:
	if destination == null or destination.map_id.is_empty():
		errors.append("%s has no destination map ID" % owner)
		return
	var map := database.map(destination.map_id)
	if map == null:
		errors.append("%s references unknown map %s" % [owner, destination.map_id])
		return
	var spawn_id := (
		destination.spawn_id
		if not destination.spawn_id.is_empty()
		else map.default_spawn_id
	)
	if not _map_contains_spawn(map, spawn_id):
		errors.append("%s references unknown spawn %s" % [owner, spawn_id])


func _resolved_destination_spawn(
	database: ContentDatabase,
	destination: MapDestination
) -> StringName:
	if destination == null:
		return &""
	if not destination.spawn_id.is_empty():
		return destination.spawn_id
	var map := database.map(destination.map_id)
	return map.default_spawn_id if map != null else &""


func _collect_interactables(node: Node, result: Array[StoryInteractable3D]) -> void:
	for child: Node in node.get_children():
		if child is StoryInteractable3D:
			result.append(child as StoryInteractable3D)
		_collect_interactables(child, result)


func _story_is_registered(event: StoryEvent, stories: Array[StoryModule]) -> bool:
	if not event is StoryModule:
		return false
	var module := event as StoryModule
	for story: StoryModule in stories:
		if story != null and story.id == module.id:
			return true
	return false


func _validate_story_binding(
	definition: MapDefinition,
	field: String,
	binding: StoryBinding,
	stories: Array[StoryModule],
	errors: PackedStringArray
) -> void:
	if binding == null or binding.event == null:
		errors.append("map %s %s has no event" % [definition.id, field])
		return
	if binding.trigger_id.is_empty() or binding.trigger_id not in binding.event.get_trigger_ids():
		errors.append(
			"map %s %s references unknown trigger %s"
			% [definition.id, field, binding.trigger_id]
		)
	if binding.event is StoryModule and not _story_is_registered(binding.event, stories):
		errors.append(
			"map %s %s references an unscanned StoryModule"
			% [definition.id, field]
		)


func _portal_record(
	source_map_id: StringName,
	node_path: NodePath,
	target_map_id: StringName,
	target_spawn_id: StringName
) -> Dictionary:
	return {
		"source_map_id": source_map_id,
		"node_path": node_path,
		"target_map_id": target_map_id,
		"target_spawn_id": target_spawn_id,
	}


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
