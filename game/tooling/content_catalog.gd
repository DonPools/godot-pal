@tool
class_name ContentCatalog
extends RefCounted

const TYPES := [
	"actor", "item", "equipment", "skill", "status", "enemy", "shop", "encounter",
	"map", "dialogue", "story",
]

var items: Array[Dictionary] = []
var diagnostics: Array[Dictionary] = []
var database: ContentDatabase
var _by_key: Dictionary[String, Dictionary] = {}


func build(database: ContentDatabase) -> void:
	items.clear()
	diagnostics.clear()
	_by_key.clear()
	self.database = database
	if database == null:
		diagnostics.append(_diagnostic("catalog_database_missing", "ContentDatabase is missing", ""))
		return
	for message: String in database.build_index():
		diagnostics.append(_diagnostic("catalog_database_invalid", message, database.resource_path))
	_add_definitions("actor", database.actors)
	for definition: ItemDefinition in database.items:
		_add_resource("equipment" if definition is EquipmentDefinition else "item", definition)
	_add_definitions("skill", database.skills)
	_add_definitions("status", database.statuses)
	_add_definitions("enemy", database.enemies)
	_add_definitions("shop", database.shops)
	_add_definitions("encounter", database.encounters)
	_add_definitions("map", database.maps)
	var scanned := ContentSourceScanner.new().scan_story_resources()
	diagnostics.append_array(scanned.get("diagnostics", []))
	var seen_dialogues: Dictionary[String, bool] = {}
	for story: StoryModule in scanned.get("stories", []):
		_add_resource("story", story)
		if story.dialogue != null:
			var key := story.dialogue.resource_path
			if not seen_dialogues.has(key):
				seen_dialogues[key] = true
				_add_resource("dialogue", story.dialogue)
	for dialogue: DialogueDefinition in scanned.get("dialogues", []):
		if not seen_dialogues.has(dialogue.resource_path):
			seen_dialogues[dialogue.resource_path] = true
			_add_resource("dialogue", dialogue)
	items.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return "%s:%s" % [left["type"], left["id"]] < "%s:%s" % [right["type"], right["id"]]
	)


func list(content_type: String = "all") -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for record: Dictionary in items:
		if content_type == "all" or record.get("type") == content_type:
			var public_record := record.duplicate(true)
			public_record.erase("resource")
			result.append(public_record)
	return result


func find(content_type: String, content_id: StringName) -> Dictionary:
	var result: Dictionary = _by_key.get(_key(content_type, content_id), {}).duplicate(true)
	result.erase("resource")
	return result


func resource(content_type: String, content_id: StringName) -> Resource:
	var record: Dictionary = _by_key.get(_key(content_type, content_id), {})
	return record.get("resource") as Resource


func refs_to(content_id: StringName, database: ContentDatabase) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for record: Dictionary in items:
		var resource_value := record.get("resource") as Resource
		_collect_resource_refs(resource_value, content_id, record.get("path", ""), "", result, {})
	if database != null:
		for definition: MapDefinition in database.maps:
			if definition == null or definition.scene == null:
				continue
			var instance := definition.scene.instantiate()
			_collect_node_refs(instance, instance, definition.scene.resource_path, content_id, result)
			instance.free()
	var unique: Dictionary[String, Dictionary] = {}
	for reference: Dictionary in result:
		var key := "%s:%s:%s" % [
			reference.get("file", ""),
			reference.get("field", ""),
			reference.get("content_id", ""),
		]
		unique[key] = reference
	result.clear()
	result.assign(unique.values())
	result.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return "%s:%s" % [left.get("file"), left.get("field")] < "%s:%s" % [right.get("file"), right.get("field")]
	)
	return result


func export_document() -> Dictionary:
	var records: Array[Dictionary] = []
	for record: Dictionary in items:
		var exported := record.duplicate(true)
		exported.erase("resource")
		records.append(exported)
	return {
		"catalog_version": 1,
		"content_count": records.size(),
		"content": records,
	}


func _add_definitions(content_type: String, definitions: Array) -> void:
	for definition: Resource in definitions:
		_add_resource(content_type, definition)


func _add_resource(content_type: String, resource_value: Resource) -> void:
	if resource_value == null:
		return
	var content_id := StringName(resource_value.get("id"))
	var key := _key(content_type, content_id)
	if content_id.is_empty():
		diagnostics.append(_diagnostic("catalog_id_missing", "%s resource has an empty id" % content_type, resource_value.resource_path))
		return
	if _by_key.has(key):
		diagnostics.append(_diagnostic("catalog_id_duplicate", "duplicate %s id: %s" % [content_type, content_id], resource_value.resource_path))
		return
	var record := _details(content_type, resource_value)
	record["resource"] = resource_value
	items.append(record)
	_by_key[key] = record


func _details(content_type: String, resource_value: Resource) -> Dictionary:
	var result := {
		"type": content_type,
		"id": String(resource_value.get("id")),
		"path": resource_value.resource_path,
		"display_name": String(resource_value.get("display_name")) if resource_value is ContentDefinition else "",
		"properties": _editable_properties(resource_value),
	}
	match content_type:
		"actor":
			var actor := resource_value as ActorDefinition
			result.merge({"max_hp": actor.base_max_hp, "max_mp": actor.base_max_mp, "initial_level": actor.initial_level})
		"item", "equipment":
			var item := resource_value as ItemDefinition
			result.merge({"price": item.price, "max_stack": item.max_stack, "effect_count": item.effects.size()})
		"skill":
			var skill := resource_value as SkillDefinition
			result.merge({"mp_cost": skill.mp_cost, "effect_count": skill.effects.size()})
		"status":
			var status := resource_value as StatusDefinition
			result.merge({"duration_rounds": status.duration_rounds, "periodic_damage": status.periodic_damage})
		"enemy":
			var enemy := resource_value as EnemyDefinition
			result.merge({"max_hp": enemy.max_hp, "attack": enemy.attack, "money_reward": enemy.money_reward})
		"shop":
			result["entry_count"] = (resource_value as ShopDefinition).entries.size()
		"encounter":
			result["enemy_count"] = (resource_value as BattleEncounter).enemies.size()
		"map":
			var map := resource_value as MapDefinition
			result.merge({"scene": map.scene.resource_path if map.scene != null else "", "default_spawn_id": String(map.default_spawn_id)})
		"dialogue":
			result["block_count"] = (resource_value as DialogueDefinition).blocks.size()
		"story":
			var story := resource_value as StoryModule
			result.merge({"initial_stage": String(story.initial_stage), "valid_stages": _names(story.valid_stages), "trigger_ids": _names(story.get_trigger_ids())})
	return result


func _editable_properties(resource_value: Resource) -> Dictionary:
	var result: Dictionary = {}
	for property: Dictionary in resource_value.get_property_list():
		var usage := int(property.get("usage", 0))
		var field := String(property.get("name", ""))
		if (
			(usage & PROPERTY_USAGE_STORAGE) == 0
			or (usage & PROPERTY_USAGE_EDITOR) == 0
			or field in [
				"id", "script", "resource_local_to_scene", "resource_name", "resource_path",
			]
		):
			continue
		var encoded := _json_value(resource_value.get(field))
		if encoded.get("supported", false):
			result[field] = encoded.get("value")
	return result


func _json_value(value: Variant) -> Dictionary:
	if value == null:
		return {"supported": false}
	if value is bool or value is int or value is float or value is String:
		return {"supported": true, "value": value}
	if value is StringName:
		return {"supported": true, "value": String(value)}
	if value is Array:
		var values: Array = []
		for element: Variant in value:
			var encoded := _json_value(element)
			if not encoded.get("supported", false):
				return {"supported": false}
			values.append(encoded.get("value"))
		return {"supported": true, "value": values}
	return {"supported": false}


func _collect_node_refs(
	root: Node,
	node: Node,
	file: String,
	target_id: StringName,
	result: Array[Dictionary]
) -> void:
	for property: Dictionary in node.get_property_list():
		if (int(property.get("usage", 0)) & PROPERTY_USAGE_EDITOR) == 0:
			continue
		var field := StringName(property.get("name", ""))
		_collect_value_refs(node.get(field), target_id, file, "%s:%s" % [root.get_path_to(node), field], result, {})
	for child: Node in node.get_children():
		_collect_node_refs(root, child, file, target_id, result)


func _collect_resource_refs(
	resource_value: Resource,
	target_id: StringName,
	file: String,
	field_prefix: String,
	result: Array[Dictionary],
	visited: Dictionary[int, bool]
) -> void:
	if resource_value == null or visited.has(resource_value.get_instance_id()):
		return
	visited[resource_value.get_instance_id()] = true
	for property: Dictionary in resource_value.get_property_list():
		if (int(property.get("usage", 0)) & PROPERTY_USAGE_STORAGE) == 0:
			continue
		var field := String(property.get("name", ""))
		if field in ["resource_path", "resource_name", "script", "id"]:
			continue
		var qualified := field if field_prefix.is_empty() else "%s.%s" % [field_prefix, field]
		_collect_value_refs(resource_value.get(field), target_id, file, qualified, result, visited)


func _collect_value_refs(
	value: Variant,
	target_id: StringName,
	file: String,
	field: String,
	result: Array[Dictionary],
	visited: Dictionary[int, bool]
) -> void:
	if value is Resource:
		var referenced := value as Resource
		if referenced.get("id") != null and StringName(referenced.get("id")) == target_id:
			result.append({"file": file, "field": field, "content_id": String(target_id)})
		_collect_resource_refs(referenced, target_id, file, field, result, visited)
	elif value is Array:
		for index: int in range(value.size()):
			_collect_value_refs(value[index], target_id, file, "%s[%d]" % [field, index], result, visited)
	elif value is Dictionary:
		for key: Variant in value:
			_collect_value_refs(value[key], target_id, file, "%s.%s" % [field, key], result, visited)
	elif value is StringName and value == target_id:
		result.append({"file": file, "field": field, "content_id": String(target_id)})


func _key(content_type: String, content_id: StringName) -> String:
	return "%s:%s" % [content_type, content_id]


func _names(values: Array[StringName]) -> Array[String]:
	var result: Array[String] = []
	for value: StringName in values:
		result.append(String(value))
	return result


func _diagnostic(code: String, message: String, file: String) -> Dictionary:
	return {"code": code, "message": message, "file": file, "field": ""}
