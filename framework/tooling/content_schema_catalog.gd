class_name ContentSchemaCatalog
extends RefCounted


static func schema_for(content_type: String) -> Dictionary:
	match content_type:
		"realm":
			return _definition_schema("realm", "CultivationRealmDefinition", [
				_field("max_layer", "int", false, 1),
				_field("layer_cultivation_costs", "PackedInt32Array", false, []),
				_field("breakthrough_cultivation_required", "int", false, 0),
				_field("next_realm", "CultivationRealmDefinition", false, null),
				_field("base_max_hp_bonus", "int", false, 0),
				_field("base_max_mp_bonus", "int", false, 0),
				_field("base_attack_bonus", "int", false, 0),
				_field("max_hp_bonus_per_layer", "int", false, 0),
				_field("max_mp_bonus_per_layer", "int", false, 0),
				_field("attack_bonus_per_layer", "int", false, 0),
			])
		"foundation":
			var schema := _definition_schema("foundation", "DaoFoundationDefinition", [
				_field("required_realm", "CultivationRealmDefinition", true, null),
				_field("granted_skills", "Array[SkillDefinition]", false, []),
				_field("battle_modifier", "BattleBuildModifier", false, null),
				_field("aura_color", "Color", false, "8ccccfff"),
				_field("max_hp_bonus", "int", false, 0),
				_field("max_mp_bonus", "int", false, 0),
				_field("attack_bonus", "int", false, 0),
			])
			schema["create_required_options"] = ["path", "realm"]
			return schema
		"actor":
			var schema := _definition_schema("actor", "ActorDefinition", [
				_field("base_max_hp", "int", false, 100),
				_field("base_max_mp", "int", false, 20),
				_field("base_attack", "int", false, 12),
				_field("initial_realm", "CultivationRealmDefinition", true, null),
				_field("initial_realm_layer", "int", false, 1),
				_field("initial_cultivation_points", "int", false, 0),
				_field("initial_foundation", "DaoFoundationDefinition", false, null),
				_field("equipment_slots", "Array[StringName]", false, ["weapon"]),
			])
			schema["create_required_options"] = ["path", "realm"]
			return schema
		"npc":
			var schema := _definition_schema("npc", "NpcDefinition", [
				_field("field_model_3d", "PackedScene", true, null),
			])
			schema["create_required_options"] = ["path", "scene"]
			return schema
		"item":
			var schema := _definition_schema("item", "ItemDefinition", [
				_field("icon", "Texture2D", true, null),
				_field("category", "ItemDefinition.Category", false, "consumable"),
				_field("price", "int", false, 0),
				_field("max_stack", "int", false, 9),
				_field("can_discard", "bool", false, true),
				_field("can_sell", "bool", false, true),
				_field("usable_in_field", "bool", false, false),
				_field("usable_in_battle", "bool", false, false),
				_field("effects", "Array[GameEffect]", false, []),
			])
			schema["create_required_options"] = ["path", "icon"]
			return schema
		"equipment":
			var schema := _definition_schema("equipment", "EquipmentDefinition", [
				_field("icon", "Texture2D", true, null),
				_field("slot", "StringName", true, "weapon"),
				_field("price", "int", false, 0),
				_field("can_discard", "bool", false, true),
				_field("can_sell", "bool", false, true),
			])
			schema["create_required_options"] = ["path", "icon"]
			return schema
		"skill":
			var schema := _definition_schema("skill", "SkillDefinition", [
				_field("icon", "Texture2D", true, null),
				_field("mp_cost", "int", false, 0),
				_field("usable_in_field", "bool", false, false),
				_field("usable_in_battle", "bool", false, false),
				_field("target_rule", "SkillDefinition.TargetRule", false, "direction"),
				_field("cooldown_seconds", "float", false, 0.0),
				_field("cast_seconds", "float", false, 0.0),
				_field("active_seconds", "float", false, 0.1),
				_field("recovery_seconds", "float", false, 0.2),
				_field("max_range", "float", false, 1.5),
				_field("radius", "float", false, 0.0),
				_field("effects", "Array[GameEffect]", false, []),
				_field("presentation_scene", "PackedScene", false, null),
				_field("sound", "AudioStream", false, null),
			])
			schema["create_required_options"] = ["path", "icon"]
			return schema
		"status":
			return _definition_schema("status", "StatusDefinition", [
				_field("duration_seconds", "float", false, 1.0),
				_field("tick_interval_seconds", "float", false, 1.0),
				_field("periodic_damage", "int", false, 0),
			])
		"enemy":
			var schema := _definition_schema("enemy", "EnemyDefinition", [
				_field("max_hp", "int", false, 30),
				_field("attack", "int", false, 8),
				_field("cultivation_reward", "int", false, 0),
				_field("character_scene", "PackedScene", true, null),
				_field("move_speed", "float", false, 3.0),
				_field("aggro_range", "float", false, 8.0),
				_field("attack_range", "float", false, 1.5),
				_field("attack_windup_seconds", "float", false, 0.35),
				_field("attack_active_seconds", "float", false, 0.1),
				_field("attack_recovery_seconds", "float", false, 0.45),
				_field("combat_style", "EnemyDefinition.CombatStyle", false, "melee"),
				_field("is_boss", "bool", false, false),
				_field("projectile_speed", "float", false, 8.0),
				_field("charge_damage", "int", false, 0),
				_field("charge_windup_seconds", "float", false, 0.8),
				_field("charge_active_seconds", "float", false, 0.5),
				_field("charge_recovery_seconds", "float", false, 0.6),
				_field("charge_speed", "float", false, 10.0),
				_field("charge_cooldown_seconds", "float", false, 4.0),
				_field("charge_stagger_seconds", "float", false, 1.6),
				_field("charge_staggers_on_pillar", "bool", false, false),
				_field("money_reward", "int", false, 0),
				_field("drop_item", "ItemDefinition", false, null),
				_field("drop_quantity", "int", false, 0),
				_field("strategy", "EnemyStrategy", true, null),
			])
			schema["create_required_options"] = ["path", "scene"]
			return schema
		"shop":
			var schema := _definition_schema("shop", "ShopDefinition", [
				_field("entries", "Array[ShopEntry]", true, []),
			])
			schema["create_required_options"] = ["path", "item"]
			return schema
		"encounter":
			var schema := _definition_schema("encounter", "BattleEncounter", [
				_field("enemies", "Array[EncounterEnemy]", true, []),
				_field("allows_escape", "bool", false, true),
				_field("encounter_radius", "float", false, 10.0),
				_field("leash_radius", "float", false, 14.0),
				_field("reward_policy", "RewardPolicy.Value", false, "all_or_nothing"),
				_field("battle_music", "AudioStream", false, null),
			])
			schema["create_required_options"] = ["path", "enemy"]
			return schema
		"map":
			return {
				"type": "map",
				"resource_class": "MapDefinition",
				"id_prefix": "map.",
				"create_required_options": ["path", "scene"],
				"fields": [
					_field("id", "StringName", true, ""),
					_field("display_name", "String", true, ""),
					_field("description", "String", false, ""),
					_field("tags", "Array[StringName]", false, []),
					_field("scene", "PackedScene", true, null),
					_field("default_spawn_id", "StringName", true, "default"),
					_field("music", "AudioStream", false, null),
					_field("story_module", "StoryModule", false, null),
				],
			}
		"dialogue":
			return {
				"type": "dialogue",
				"resource_class": "DialogueDefinition",
				"id_prefix": "dialogue.",
				"create_required_options": ["path"],
				"fields": [
					_field("id", "StringName", true, ""),
					_field("blocks", "Array[DialogueBlock]", true, []),
				],
			}
		"story":
			return {
				"type": "story",
				"resource_class": "StoryModule",
				"id_prefix": "story.",
				"create_required_options": ["path"],
				"fields": [
					_field("id", "StringName", true, ""),
					_field("initial_stage", "StringName", true, "not_started"),
					_field("valid_stages", "Array[StringName]", true, ["not_started"]),
					_field("dialogue", "DialogueDefinition", false, null),
				],
			}
	return {}


static func _definition_schema(
	content_type: String,
	resource_class: String,
	additional_fields: Array[Dictionary]
) -> Dictionary:
	var fields: Array[Dictionary] = [
		_field("id", "StringName", true, ""),
		_field("display_name", "String", true, ""),
		_field("description", "String", false, ""),
		_field("tags", "Array[StringName]", false, []),
	]
	fields.append_array(additional_fields)
	return {
		"type": content_type,
		"resource_class": resource_class,
		"id_prefix": "item." if content_type == "equipment" else content_type + ".",
		"create_required_options": ["path"],
		"fields": fields,
	}


static func _field(
	name: String,
	type: String,
	required: bool,
	default_value: Variant
) -> Dictionary:
	return {
		"name": name,
		"type": type,
		"required": required,
		"default": default_value,
	}
