@tool
class_name ContentDefinitionValidator
extends RefCounted


static func validate_realm(
	definition: CultivationRealmDefinition,
	errors: PackedStringArray
) -> void:
	if (
		definition.max_layer < 1
		or definition.layer_cultivation_costs.size() != definition.max_layer - 1
		or definition.breakthrough_cultivation_required < 0
		or definition.base_max_hp_bonus < 0
		or definition.base_max_mp_bonus < 0
		or definition.base_attack_bonus < 0
		or definition.max_hp_bonus_per_layer < 0
		or definition.max_mp_bonus_per_layer < 0
		or definition.attack_bonus_per_layer < 0
	):
		errors.append("Realm %s has invalid cultivation or stat values" % definition.id)
	for cost: int in definition.layer_cultivation_costs:
		if cost <= 0:
			errors.append("Realm %s has a non-positive layer cultivation cost" % definition.id)
			break


static func validate_foundation(
	definition: DaoFoundationDefinition,
	errors: PackedStringArray
) -> void:
	if (
		definition.max_hp_bonus < 0
		or definition.max_mp_bonus < 0
		or definition.attack_bonus < 0
	):
		errors.append("Foundation %s has invalid stat bonuses" % definition.id)


static func validate_actor(
	definition: ActorDefinition,
	errors: PackedStringArray
) -> void:
	if (
		definition.base_max_hp < 1
		or definition.base_max_mp < 0
		or definition.base_attack < 0
		or definition.basic_attack_resource_gain < 0
		or definition.initial_realm_layer < 1
		or definition.initial_cultivation_points < 0
	):
		errors.append("Actor %s has invalid base stats or initial cultivation" % definition.id)
	var equipment_slots: Dictionary[StringName, bool] = {}
	for slot: StringName in definition.equipment_slots:
		if slot.is_empty() or equipment_slots.has(slot):
			errors.append("Actor %s has an empty or repeated equipment slot" % definition.id)
		else:
			equipment_slots[slot] = true
	if &"initial_party" in definition.tags and definition.field_model_3d == null:
		errors.append("Actor %s has no 3D field model" % definition.id)
	elif definition.field_model_3d != null:
		_validate_node_3d_scene(
			definition.field_model_3d,
			"Actor %s 3D field model root is not Node3D" % definition.id,
			errors
		)


static func validate_npc(
	definition: NpcDefinition,
	errors: PackedStringArray
) -> void:
	if definition.field_model_3d == null:
		errors.append("NPC %s has no 3D field model" % definition.id)
	else:
		_validate_node_3d_scene(
			definition.field_model_3d,
			"NPC %s 3D field model root is not Node3D" % definition.id,
			errors
		)


static func validate_item(
	definition: ItemDefinition,
	errors: PackedStringArray
) -> void:
	if (
		definition.price < 0
		or definition.max_stack < 1
		or int(definition.category) not in ItemDefinition.Category.values()
	):
		errors.append("Item %s has invalid price or max_stack" % definition.id)
	if definition.icon == null and not definition.resource_path.is_empty():
		errors.append("Item %s has no icon" % definition.id)
	if definition.category == ItemDefinition.Category.KEY_ITEM and definition.can_discard:
		errors.append("Key item %s cannot be discardable" % definition.id)
	if (
		definition.category != ItemDefinition.Category.CONSUMABLE
		and (definition.usable_in_field or definition.usable_in_battle)
	):
		errors.append("Non-consumable item %s cannot be usable" % definition.id)
	if (
		(definition.usable_in_field or definition.usable_in_battle)
		and definition.effects.is_empty()
	):
		errors.append("Item %s is usable but has no GameEffect" % definition.id)
	if definition is EquipmentDefinition and (definition as EquipmentDefinition).slot.is_empty():
		errors.append("Equipment %s has an empty slot" % definition.id)


static func validate_skill(
	definition: SkillDefinition,
	errors: PackedStringArray
) -> void:
	if definition.icon == null and not definition.resource_path.is_empty():
		errors.append("Skill %s has no icon" % definition.id)
	if definition.usable_in_field:
		errors.append("Skill %s cannot currently be used in the field" % definition.id)
	if (
		definition.usable_in_battle
		and not SkillDefinition.is_battle_target_rule_supported(definition.target_rule)
	):
		errors.append("Skill %s uses an unsupported battle target rule" % definition.id)
	if definition.usable_in_battle and definition.effects.is_empty():
		errors.append("Skill %s is usable in battle but has no GameEffect" % definition.id)
	var invalid_target_values := (
		definition.target_rule == SkillDefinition.TargetRule.AREA
		and definition.radius <= 0.0
	) or (
		definition.target_rule in [
			SkillDefinition.TargetRule.SINGLE_ENEMY,
			SkillDefinition.TargetRule.DIRECTION,
			SkillDefinition.TargetRule.POINT,
		]
		and definition.max_range <= 0.0
	)
	if (
		definition.mp_cost < 0
		or definition.cooldown_seconds < 0.0
		or definition.cast_seconds < 0.0
		or definition.active_seconds <= 0.0
		or definition.recovery_seconds < 0.0
		or definition.max_range < 0.0
		or definition.radius < 0.0
		or int(definition.target_rule) not in SkillDefinition.TargetRule.values()
		or invalid_target_values
	):
		errors.append("Skill %s has invalid realtime combat values" % definition.id)


static func validate_status(
	definition: StatusDefinition,
	errors: PackedStringArray
) -> void:
	if (
		definition.duration_seconds <= 0.0
		or definition.tick_interval_seconds <= 0.0
		or definition.periodic_damage < 0
		or (
			definition.periodic_damage > 0
			and definition.tick_interval_seconds > definition.duration_seconds
		)
	):
		errors.append("Status %s has invalid duration or periodic damage" % definition.id)


static func validate_enemy(
	definition: EnemyDefinition,
	errors: PackedStringArray
) -> void:
	if (
		definition.max_hp < 1
		or definition.attack < 0
		or definition.cultivation_reward < 0
		or definition.money_reward < 0
		or definition.drop_quantity < 0
		or definition.move_speed <= 0.0
		or definition.aggro_range <= 0.0
		or definition.attack_range <= 0.0
		or definition.attack_windup_seconds < 0.0
		or definition.attack_active_seconds <= 0.0
		or definition.attack_recovery_seconds < 0.0
		or int(definition.combat_style) not in EnemyDefinition.CombatStyle.values()
		or definition.projectile_speed <= 0.0
		or (
			definition.combat_style == EnemyDefinition.CombatStyle.CHARGER
			and (
				definition.charge_damage <= 0
				or definition.charge_windup_seconds < 0.0
				or definition.charge_active_seconds <= 0.0
				or definition.charge_recovery_seconds < 0.0
				or definition.charge_speed <= 0.0
				or definition.charge_cooldown_seconds < 0.0
				or definition.charge_stagger_seconds <= 0.0
			)
		)
		or (
			definition.charge_staggers_on_pillar
			and definition.combat_style != EnemyDefinition.CombatStyle.CHARGER
		)
	):
		errors.append("Enemy %s has invalid combat values" % definition.id)


static func validate_encounter(
	definition: BattleEncounter,
	errors: PackedStringArray
) -> void:
	if (
		definition.encounter_radius <= 0.0
		or definition.leash_radius < definition.encounter_radius
		or int(definition.reward_policy) not in RewardPolicy.Value.values()
	):
		errors.append("Encounter %s has invalid realtime boundaries" % definition.id)


static func _validate_node_3d_scene(
	scene: PackedScene,
	error_message: String,
	errors: PackedStringArray
) -> void:
	var instance := scene.instantiate()
	if not instance is Node3D:
		errors.append(error_message)
	instance.free()
