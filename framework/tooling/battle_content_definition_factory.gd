class_name BattleContentDefinitionFactory
extends RefCounted

const CONTENT_TYPES := ["enemy", "shop", "encounter"]


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
		"enemy": definition = EnemyDefinition.new()
		"shop": definition = ShopDefinition.new()
		"encounter": definition = BattleEncounter.new()
		_:
			result.reject(
				"content_type_unsupported",
				"battle content factory does not support %s" % content_type,
				"",
				"type",
				content_id
			)
			return result
	_configure_common_fields(definition, content_id, options)
	if definition is EnemyDefinition:
		if not _configure_enemy(
			definition as EnemyDefinition,
			options,
			content_id,
			result
		):
			return result
	elif definition is ShopDefinition:
		if not _configure_shop(
			definition as ShopDefinition,
			options,
			content_id,
			result
		):
			return result
	elif definition is BattleEncounter:
		if not _configure_encounter(
			definition as BattleEncounter,
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


static func _configure_enemy(
	enemy: EnemyDefinition,
	options: Dictionary,
	content_id: StringName,
	result: ContentCreationResult
) -> bool:
	enemy.max_hp = int(options.get("max_hp", "30"))
	enemy.attack = int(options.get("attack", "8"))
	enemy.move_speed = float(options.get("move_speed", "3"))
	enemy.aggro_range = float(options.get("aggro_range", "8"))
	enemy.attack_range = float(options.get("attack_range", "1.5"))
	enemy.attack_windup_seconds = float(options.get("attack_windup_seconds", "0.35"))
	enemy.attack_active_seconds = float(options.get("attack_active_seconds", "0.1"))
	enemy.attack_recovery_seconds = float(options.get("attack_recovery_seconds", "0.45"))
	var combat_style := ContentOptionParser.combat_style(
		String(options.get("combat_style", "melee"))
	)
	var is_boss: Variant = ContentOptionParser.boolean(
		String(options.get("is_boss", "false"))
	)
	var pillar_stagger: Variant = ContentOptionParser.boolean(
		String(options.get("charge_staggers_on_pillar", "false"))
	)
	if combat_style < 0 or is_boss == null or pillar_stagger == null:
		result.reject(
			"enemy_combat_role_invalid",
			"combat_style must be melee, ranged, or charger and role flags must be boolean",
			String(options.get("path", "")),
			"combat_style",
			content_id
		)
		return false
	enemy.combat_style = combat_style as EnemyDefinition.CombatStyle
	enemy.is_boss = bool(is_boss)
	enemy.projectile_speed = float(options.get("projectile_speed", "8"))
	enemy.charge_damage = int(options.get("charge_damage", "0"))
	enemy.charge_windup_seconds = float(options.get("charge_windup_seconds", "0.8"))
	enemy.charge_active_seconds = float(options.get("charge_active_seconds", "0.5"))
	enemy.charge_recovery_seconds = float(options.get("charge_recovery_seconds", "0.6"))
	enemy.charge_speed = float(options.get("charge_speed", "10"))
	enemy.charge_cooldown_seconds = float(options.get("charge_cooldown_seconds", "4"))
	enemy.charge_stagger_seconds = float(options.get("charge_stagger_seconds", "1.6"))
	enemy.charge_staggers_on_pillar = bool(pillar_stagger)
	if (
		enemy.combat_style == EnemyDefinition.CombatStyle.CHARGER
		and enemy.charge_damage <= 0
	):
		result.reject(
			"enemy_charge_damage_required",
			"charger combat_style requires a positive charge_damage",
			String(options.get("path", "")),
			"charge_damage",
			content_id
		)
		return false
	if (
		enemy.charge_staggers_on_pillar
		and enemy.combat_style != EnemyDefinition.CombatStyle.CHARGER
	):
		result.reject(
			"enemy_pillar_stagger_style_invalid",
			"charge_staggers_on_pillar requires charger combat_style",
			String(options.get("path", "")),
			"charge_staggers_on_pillar",
			content_id
		)
		return false
	enemy.cultivation_reward = int(options.get("cultivation_reward", "0"))
	enemy.money_reward = int(options.get("money_reward", "0"))
	enemy.drop_quantity = int(options.get("drop_quantity", "0"))
	var drop_path := String(options.get("drop_item", ""))
	if not drop_path.is_empty():
		enemy.drop_item = load(drop_path) as ItemDefinition
		if enemy.drop_item == null:
			result.reject(
				"enemy_drop_item_invalid",
				"drop_item must reference an ItemDefinition",
				drop_path,
				"drop_item",
				content_id
			)
			return false
	var scene_path := String(options.get("scene", ""))
	enemy.character_scene = load(scene_path) as PackedScene
	if enemy.character_scene == null:
		result.reject(
			"enemy_scene_load_failed",
			"enemy create requires --scene with a CharacterBody3D PackedScene",
			scene_path,
			"character_scene",
			content_id
		)
		return false
	var enemy_instance := enemy.character_scene.instantiate()
	if not enemy_instance is CharacterBody3D:
		result.reject(
			"enemy_scene_type_invalid",
			"enemy character_scene root must inherit CharacterBody3D",
			scene_path,
			"character_scene",
			content_id
		)
		enemy_instance.free()
		return false
	enemy_instance.free()
	enemy.strategy = BasicAttackStrategy.new()
	return true


static func _configure_shop(
	shop: ShopDefinition,
	options: Dictionary,
	content_id: StringName,
	result: ContentCreationResult
) -> bool:
	var item_path := String(options.get("item", ""))
	var shop_item := load(item_path) as ItemDefinition
	if shop_item == null:
		result.reject(
			"shop_item_load_failed",
			"shop create requires --item with an ItemDefinition path",
			item_path,
			"entries",
			content_id
		)
		return false
	var entry := ShopEntry.new()
	entry.item = shop_item
	shop.entries.assign([entry])
	return true


static func _configure_encounter(
	encounter: BattleEncounter,
	options: Dictionary,
	content_id: StringName,
	result: ContentCreationResult
) -> bool:
	var enemy_path := String(options.get("enemy", ""))
	var enemy_definition := load(enemy_path) as EnemyDefinition
	if enemy_definition == null:
		result.reject(
			"encounter_enemy_load_failed",
			"encounter create requires --enemy with an EnemyDefinition path",
			enemy_path,
			"enemies",
			content_id
		)
		return false
	var encounter_enemy := EncounterEnemy.new()
	encounter_enemy.enemy = enemy_definition
	encounter_enemy.instance_id = StringName(options.get("instance_id", "enemy"))
	encounter_enemy.spawn_offset = Vector3(
		float(options.get("spawn_x", "0")),
		float(options.get("spawn_y", "0")),
		float(options.get("spawn_z", "0"))
	)
	encounter.enemies.assign([encounter_enemy])
	var allows_escape: Variant = ContentOptionParser.boolean(
		String(options.get("allows_escape", "true"))
	)
	if allows_escape == null:
		result.reject(
			"encounter_allows_escape_invalid",
			"allows_escape must be true or false",
			String(options.get("path", "")),
			"allows_escape",
			content_id
		)
		return false
	encounter.allows_escape = bool(allows_escape)
	encounter.encounter_radius = float(options.get("encounter_radius", "10"))
	encounter.leash_radius = float(options.get("leash_radius", "14"))
	var reward_policy := ContentOptionParser.reward_policy(
		String(options.get("reward_policy", "all_or_nothing"))
	)
	if reward_policy < 0:
		result.reject(
			"encounter_reward_policy_invalid",
			"reward_policy must be all_or_nothing or allow_partial",
			String(options.get("path", "")),
			"reward_policy",
			content_id
		)
		return false
	encounter.reward_policy = reward_policy as RewardPolicy.Value
	var music_path := String(options.get("battle_music", ""))
	if not music_path.is_empty():
		encounter.battle_music = load(music_path) as AudioStream
		if encounter.battle_music == null:
			result.reject(
				"encounter_battle_music_invalid",
				"battle_music must reference an AudioStream",
				music_path,
				"battle_music",
				content_id
			)
			return false
	return true
