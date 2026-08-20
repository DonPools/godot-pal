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
		if not map_scene.entry_trigger_id.is_empty():
			_validate_story_trigger(
				definition,
				"entry_trigger_id",
				map_scene.entry_trigger_id,
				stories,
				errors
			)
		_validate_story_sources(definition, map_scene, database, stories, portals, errors)
		map_scene.free()
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
		"Camera3D": Camera3D,
	}
	for path: String in requirements:
		var node := map_scene.get_node_or_null(NodePath(path))
		if node == null or not is_instance_of(node, requirements[path]):
			errors.append("map %s is missing 3D node %s" % [definition.id, path])
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
			if interactable.event != null or interactable.trigger_id != &"default":
				errors.append(
					"map %s 3D portal %s has incompatible event or trigger"
					% [definition.id, path]
				)
			portals.append(_portal_record(
				definition.id,
				path,
				interactable.portal_target_map_id,
				interactable.portal_target_spawn_id
			))
		elif interactable.event != null:
			_validate_embedded_event(
				definition,
				path,
				interactable,
				database,
				stories,
				errors
			)
			if interactable.event is ScenePortalEvent:
				var portal := interactable.event as ScenePortalEvent
				portals.append(_portal_record(
					definition.id,
					path,
					portal.target_map.id if portal.target_map != null else &"",
					portal.target_spawn_id
				))
		else:
			_validate_story_trigger(
				definition,
				"3D interactable %s trigger_id" % path,
				interactable.trigger_id,
				stories,
				errors
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
		if source.event == null or source.trigger_id not in source.event.get_trigger_ids():
			errors.append(
				"map %s encounter source %s references an invalid event trigger"
				% [definition.id, child.name]
			)
		elif source.event is StoryModule and not _story_is_registered(source.event, stories):
			errors.append(
				"map %s encounter source %s references an unscanned StoryModule"
				% [definition.id, child.name]
			)


func _validate_embedded_event(
	definition: MapDefinition,
	interactable_path: NodePath,
	interactable: StoryInteractable3D,
	database: ContentDatabase,
	stories: Array[StoryModule],
	errors: PackedStringArray
) -> void:
	var event := interactable.event
	if interactable.trigger_id.is_empty() or interactable.trigger_id not in event.get_trigger_ids():
		errors.append(
			"map %s interactable %s references unknown embedded event trigger: %s"
			% [definition.id, interactable_path, interactable.trigger_id]
		)
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
		if battle_event.defeat_map != null and not database.has_map(battle_event.defeat_map.id):
			errors.append(
				"map %s battle event %s references an unregistered defeat map"
				% [definition.id, interactable_path]
			)
		elif (
			battle_event.defeat_map != null
			and not _map_contains_spawn(battle_event.defeat_map, battle_event.defeat_spawn_id)
		):
			errors.append(
				"map %s battle event %s references an unknown defeat spawn"
				% [definition.id, interactable_path]
			)
	elif event is ScenePortalEvent:
		var portal_event := event as ScenePortalEvent
		if portal_event.target_map == null or not database.has_map(portal_event.target_map.id):
			errors.append(
				"map %s portal event %s references an unregistered map"
				% [definition.id, interactable_path]
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


func _validate_story_trigger(
	definition: MapDefinition,
	field: String,
	trigger_id: StringName,
	stories: Array[StoryModule],
	errors: PackedStringArray
) -> void:
	if trigger_id.is_empty():
		errors.append("map %s %s is empty" % [definition.id, field])
		return
	if definition.story_module != null:
		if not _story_is_registered(definition.story_module, stories):
			return
		if trigger_id not in definition.story_module.get_trigger_ids():
			errors.append(
				"map %s %s references trigger %s outside default story %s"
				% [definition.id, field, trigger_id, definition.story_module.id]
			)
		return
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
