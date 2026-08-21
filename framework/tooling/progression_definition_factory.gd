class_name ProgressionDefinitionFactory
extends RefCounted

const CONTENT_TYPES := ["realm", "foundation", "actor"]


static func supports(content_type: String) -> bool:
	return content_type in CONTENT_TYPES


static func create(
	content_type: String,
	content_id: StringName,
	options: Dictionary
) -> ContentCreationResult:
	var result := ContentCreationResult.new()
	var definition: ContentDefinition
	match content_type:
		"realm": definition = CultivationRealmDefinition.new()
		"foundation": definition = DaoFoundationDefinition.new()
		"actor": definition = ActorDefinition.new()
		_:
			result.reject(
				"content_type_unsupported",
				"progression factory does not support %s" % content_type,
				"",
				"type",
				content_id
			)
			return result
	_configure_common_fields(definition, content_id, options)
	if definition is CultivationRealmDefinition:
		if not _configure_realm(
			definition as CultivationRealmDefinition,
			options,
			content_id,
			result
		):
			return result
	elif definition is DaoFoundationDefinition:
		if not _configure_foundation(
			definition as DaoFoundationDefinition,
			options,
			content_id,
			result
		):
			return result
	elif definition is ActorDefinition:
		if not _configure_actor(
			definition as ActorDefinition,
			options,
			content_id,
			result
		):
			return result
	result.resource = definition
	return result


static func _configure_common_fields(
	definition: ContentDefinition,
	content_id: StringName,
	options: Dictionary
) -> void:
	definition.id = content_id
	definition.display_name = String(options.get(
		"display_name",
		String(content_id).get_slice(".", String(content_id).get_slice_count(".") - 1)
	))
	definition.description = String(options.get("description", "TODO"))


static func _configure_realm(
	realm: CultivationRealmDefinition,
	options: Dictionary,
	content_id: StringName,
	result: ContentCreationResult
) -> bool:
	realm.max_layer = int(options.get("max_layer", "1"))
	var costs := PackedInt32Array()
	var raw_costs := String(options.get("layer_costs", ""))
	if not raw_costs.is_empty():
		for raw_cost: String in raw_costs.split(",", false):
			if (
				not raw_cost.strip_edges().is_valid_int()
				or int(raw_cost.strip_edges()) <= 0
			):
				result.reject(
					"realm_layer_costs_invalid",
					"layer_costs must be comma-separated positive integers",
					String(options.get("path", "")),
					"layer_cultivation_costs",
					content_id
				)
				return false
			costs.append(int(raw_cost.strip_edges()))
	if realm.max_layer < 1 or costs.size() != realm.max_layer - 1:
		result.reject(
			"realm_layer_cost_count_invalid",
			"layer_costs must contain exactly max_layer - 1 positive integers",
			String(options.get("path", "")),
			"layer_cultivation_costs",
			content_id
		)
		return false
	realm.layer_cultivation_costs = costs
	realm.breakthrough_cultivation_required = int(
		options.get("breakthrough_cultivation", "0")
	)
	realm.base_max_hp_bonus = int(options.get("base_hp_bonus", "0"))
	realm.base_max_mp_bonus = int(options.get("base_mp_bonus", "0"))
	realm.base_attack_bonus = int(options.get("base_attack_bonus", "0"))
	realm.max_hp_bonus_per_layer = int(options.get("hp_bonus_per_layer", "0"))
	realm.max_mp_bonus_per_layer = int(options.get("mp_bonus_per_layer", "0"))
	realm.attack_bonus_per_layer = int(options.get("attack_bonus_per_layer", "0"))
	var next_realm_path := String(options.get("next_realm", ""))
	if not next_realm_path.is_empty():
		realm.next_realm = load(next_realm_path) as CultivationRealmDefinition
		if realm.next_realm == null:
			result.reject(
				"realm_next_realm_invalid",
				"next_realm must reference a CultivationRealmDefinition",
				next_realm_path,
				"next_realm",
				content_id
			)
			return false
	return true


static func _configure_foundation(
	foundation: DaoFoundationDefinition,
	options: Dictionary,
	content_id: StringName,
	result: ContentCreationResult
) -> bool:
	var realm_path := String(options.get("realm", ""))
	foundation.required_realm = (
		load(realm_path) as CultivationRealmDefinition
		if not realm_path.is_empty()
		else null
	)
	if foundation.required_realm == null:
		result.reject(
			"foundation_realm_invalid",
			"foundation create requires --realm with a CultivationRealmDefinition path",
			realm_path,
			"required_realm",
			content_id
		)
		return false
	foundation.max_hp_bonus = int(options.get(
		"max_hp_bonus",
		options.get("base_hp_bonus", "0")
	))
	foundation.max_mp_bonus = int(options.get(
		"max_mp_bonus",
		options.get("base_mp_bonus", "0")
	))
	foundation.attack_bonus = int(options.get(
		"attack_bonus",
		options.get("base_attack_bonus", "0")
	))
	return true


static func _configure_actor(
	actor: ActorDefinition,
	options: Dictionary,
	content_id: StringName,
	result: ContentCreationResult
) -> bool:
	actor.base_max_hp = int(options.get("max_hp", "100"))
	actor.base_max_mp = int(options.get("max_mp", "20"))
	actor.base_attack = int(options.get("attack", "12"))
	var realm_path := String(options.get("realm", ""))
	actor.initial_realm = (
		load(realm_path) as CultivationRealmDefinition
		if not realm_path.is_empty()
		else null
	)
	if actor.initial_realm == null:
		result.reject(
			"actor_realm_invalid",
			"actor create requires --realm with a CultivationRealmDefinition path",
			realm_path,
			"initial_realm",
			content_id
		)
		return false
	actor.initial_realm_layer = int(options.get("realm_layer", "1"))
	actor.initial_cultivation_points = int(options.get("cultivation_points", "0"))
	actor.equipment_slots.clear()
	for raw_slot: String in String(
		options.get("equipment_slots", "weapon")
	).split(",", false):
		actor.equipment_slots.append(StringName(raw_slot.strip_edges()))
	if (
		actor.initial_realm_layer < 1
		or actor.initial_realm_layer > actor.initial_realm.max_layer
		or actor.initial_cultivation_points < 0
	):
		result.reject(
			"actor_cultivation_invalid",
			"realm_layer and cultivation_points are outside the initial realm",
			String(options.get("path", "")),
			"initial_realm_layer",
			content_id
		)
		return false
	var foundation_path := String(options.get("foundation", ""))
	if not foundation_path.is_empty():
		actor.initial_foundation = load(foundation_path) as DaoFoundationDefinition
		if actor.initial_foundation == null:
			result.reject(
				"actor_foundation_invalid",
				"foundation must reference a DaoFoundationDefinition",
				foundation_path,
				"initial_foundation",
				content_id
			)
			return false
	return true
