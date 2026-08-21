@tool
class_name ContentReferenceValidator
extends RefCounted


static func validate(database: ContentDatabase) -> PackedStringArray:
	var errors := PackedStringArray()
	for definition: CultivationRealmDefinition in database.realms:
		if definition == null:
			continue
		if definition.next_realm != null:
			if not database.has_realm(definition.next_realm.id):
				errors.append("Realm %s references an unregistered next realm" % definition.id)
			elif definition.next_realm == definition:
				errors.append("Realm %s cannot advance to itself" % definition.id)
			if definition.breakthrough_cultivation_required <= 0:
				errors.append("Realm %s requires positive breakthrough cultivation" % definition.id)
	for definition: DaoFoundationDefinition in database.foundations:
		if definition == null:
			continue
		if definition.required_realm == null or not database.has_realm(definition.required_realm.id):
			errors.append("Foundation %s references an unregistered required realm" % definition.id)
		for skill: SkillDefinition in definition.granted_skills:
			if skill == null or not database.has_skill(skill.id):
				errors.append("Foundation %s references an unregistered granted skill" % definition.id)
		_validate_build_modifier(
			database,
			definition.battle_modifier,
			"Foundation %s" % definition.id,
			errors
		)
	if database.starting_party.is_empty():
		errors.append("ContentDatabase starting_party is empty")
	var starting_ids: Dictionary[StringName, bool] = {}
	for definition: ActorDefinition in database.starting_party:
		if definition == null or not database.has_actor(definition.id):
			errors.append("ContentDatabase starting_party references an unregistered actor")
		elif starting_ids.has(definition.id):
			errors.append("ContentDatabase starting_party repeats actor %s" % definition.id)
		else:
			starting_ids[definition.id] = true
	for definition: ActorDefinition in database.actors:
		if definition == null:
			continue
		if definition.initial_realm == null or not database.has_realm(definition.initial_realm.id):
			errors.append("Actor %s references an unregistered initial realm" % definition.id)
		elif definition.initial_realm_layer > definition.initial_realm.max_layer:
			errors.append("Actor %s initial realm layer exceeds its realm" % definition.id)
		elif (
			definition.initial_realm_layer < definition.initial_realm.max_layer
			and definition.initial_cultivation_points >= definition.initial_realm.cultivation_cost_for_layer(definition.initial_realm_layer)
		):
			errors.append("Actor %s initial cultivation should already advance a layer" % definition.id)
		elif (
			definition.initial_realm_layer == definition.initial_realm.max_layer
			and definition.initial_realm.breakthrough_cultivation_required > 0
			and definition.initial_cultivation_points > definition.initial_realm.breakthrough_cultivation_required
		):
			errors.append("Actor %s initial cultivation exceeds breakthrough requirement" % definition.id)
		if definition.initial_foundation != null:
			if not database.has_foundation(definition.initial_foundation.id):
				errors.append("Actor %s references an unregistered initial foundation" % definition.id)
			elif definition.initial_foundation.required_realm != definition.initial_realm:
				errors.append("Actor %s initial foundation does not match its realm" % definition.id)
		var initial_slots: Dictionary[StringName, bool] = {}
		for equipment: EquipmentDefinition in definition.initial_equipment:
			if equipment == null or not database.has_item(equipment.id):
				errors.append("Actor %s references unregistered initial equipment" % definition.id)
			elif equipment.slot not in definition.equipment_slots:
				errors.append("Actor %s initial equipment uses an unsupported slot" % definition.id)
			elif initial_slots.has(equipment.slot):
				errors.append("Actor %s repeats an initial equipment slot" % definition.id)
			else:
				initial_slots[equipment.slot] = true
		var initial_skills: Dictionary[StringName, bool] = {}
		for skill_definition: SkillDefinition in definition.initial_skills:
			if skill_definition == null or not database.has_skill(skill_definition.id):
				errors.append("Actor %s references unregistered initial skill" % definition.id)
			elif initial_skills.has(skill_definition.id):
				errors.append("Actor %s repeats initial skill %s" % [definition.id, skill_definition.id])
			else:
				initial_skills[skill_definition.id] = true
	for definition: ItemDefinition in database.items:
		if definition == null:
			continue
		for effect: GameEffect in definition.effects:
			if effect == null or effect.id.is_empty():
				errors.append("Item %s contains an invalid GameEffect" % definition.id)
			elif not effect is HealEffect and not effect is RestoreMpEffect:
				errors.append("Item %s contains an unsupported GameEffect" % definition.id)
		if definition is EquipmentDefinition:
			_validate_build_modifier(
				database,
				(definition as EquipmentDefinition).battle_modifier,
				"Equipment %s" % definition.id,
				errors
			)
	for definition: SkillDefinition in database.skills:
		if definition == null:
			continue
		if (
			definition.presentation_scene != null
			and not _is_node_3d_scene(definition.presentation_scene)
		):
			errors.append("Skill %s presentation_scene root is not Node3D" % definition.id)
		for effect: GameEffect in definition.effects:
			if effect == null or effect.id.is_empty():
				errors.append("Skill %s contains an invalid GameEffect" % definition.id)
			elif not effect is DamageEffect:
				errors.append("Skill %s contains an unsupported GameEffect" % definition.id)
	for definition: EnemyDefinition in database.enemies:
		if definition != null:
			if definition.character_scene == null:
				errors.append("Enemy %s has no CharacterBody3D scene" % definition.id)
			elif not _is_character_body_3d_scene(definition.character_scene):
				errors.append("Enemy %s character_scene root is not CharacterBody3D" % definition.id)
			if definition.strategy == null:
				errors.append("Enemy %s has no EnemyStrategy" % definition.id)
			if definition.drop_item != null and not database.has_item(definition.drop_item.id):
				errors.append("Enemy %s references an unregistered drop item" % definition.id)
			if definition.strategy is ChillStrikeStrategy:
				var chill_strategy := definition.strategy as ChillStrikeStrategy
				if chill_strategy.status == null or not database.has_status(chill_strategy.status.id):
					errors.append("Enemy %s references an unregistered status" % definition.id)
	for definition: BattleEncounter in database.encounters:
		if definition == null:
			continue
		if definition.enemies.is_empty():
			errors.append("Encounter %s has no enemies" % definition.id)
		var instance_ids: Dictionary[StringName, bool] = {}
		for entry: EncounterEnemy in definition.enemies:
			if entry == null or entry.enemy == null or not database.has_enemy(entry.enemy.id):
				errors.append("Encounter %s contains an invalid enemy" % definition.id)
			elif entry.instance_id.is_empty() or instance_ids.has(entry.instance_id):
				errors.append("Encounter %s has an empty or repeated enemy instance ID" % definition.id)
			else:
				instance_ids[entry.instance_id] = true
				if (
					not entry.spawn_offset.is_finite()
					or entry.spawn_offset.length() > definition.encounter_radius
				):
					errors.append(
						"Encounter %s enemy %s has invalid spawn configuration"
						% [definition.id, entry.instance_id]
					)
	for definition: ShopDefinition in database.shops:
		if definition == null:
			continue
		var shop_items: Dictionary[StringName, bool] = {}
		for entry: ShopEntry in definition.entries:
			if entry == null or entry.item == null or not database.has_item(entry.item.id):
				errors.append("Shop %s contains an invalid item entry" % definition.id)
			elif shop_items.has(entry.item.id):
				errors.append("Shop %s repeats item %s" % [definition.id, entry.item.id])
			else:
				shop_items[entry.item.id] = true
				if entry.buy_price() < 0:
					errors.append("Shop %s item %s has an invalid price" % [definition.id, entry.item.id])


	return errors


static func _is_character_body_3d_scene(scene: PackedScene) -> bool:
	if scene == null:
		return false
	var instance := scene.instantiate()
	var valid := instance is CharacterBody3D
	instance.free()
	return valid


static func _validate_build_modifier(
	database: ContentDatabase,
	modifier: BattleBuildModifier,
	owner: String,
	errors: PackedStringArray
) -> void:
	if modifier == null:
		return
	for message: String in modifier.validate():
		errors.append("%s has invalid battle modifier: %s" % [owner, message])
	for skill: SkillDefinition in modifier.referenced_skills():
		if skill == null or not database.has_skill(skill.id):
			errors.append("%s battle modifier references an unregistered skill" % owner)


static func _is_node_3d_scene(scene: PackedScene) -> bool:
	if scene == null:
		return false
	var instance := scene.instantiate()
	var valid := instance is Node3D
	instance.free()
	return valid
