class_name ItemSkillDefinitionFactory
extends RefCounted

const CONTENT_TYPES := ["item", "equipment", "skill", "status"]


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
		"item": definition = ItemDefinition.new()
		"equipment": definition = EquipmentDefinition.new()
		"skill": definition = SkillDefinition.new()
		"status": definition = StatusDefinition.new()
		_:
			result.reject(
				"content_type_unsupported",
				"item/skill factory does not support %s" % content_type,
				"",
				"type",
				content_id
			)
			return result
	_configure_common_fields(definition, content_id, options)
	if definition is ItemDefinition:
		if not _configure_item(
			definition as ItemDefinition,
			options,
			content_id,
			result
		):
			return result
		if definition is EquipmentDefinition:
			(definition as EquipmentDefinition).slot = StringName(
				options.get("slot", "weapon")
			)
	elif definition is SkillDefinition:
		if not _configure_skill(
			definition as SkillDefinition,
			options,
			content_id,
			result
		):
			return result
	elif definition is StatusDefinition:
		var status := definition as StatusDefinition
		status.duration_seconds = float(options.get("duration_seconds", "1"))
		status.tick_interval_seconds = float(options.get("tick_interval_seconds", "1"))
		status.periodic_damage = int(options.get("periodic_damage", "0"))
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


static func _configure_item(
	item: ItemDefinition,
	options: Dictionary,
	content_id: StringName,
	result: ContentCreationResult
) -> bool:
	item.price = int(options.get("price", "0"))
	var is_equipment := item is EquipmentDefinition
	if not is_equipment:
		item.max_stack = int(options.get("max_stack", "9"))
		var category := ContentOptionParser.item_category(
			String(options.get("category", "consumable"))
		)
		if category < 0 or category == ItemDefinition.Category.EQUIPMENT:
			result.reject(
				"item_category_invalid",
				"item category must be consumable, key_item, or material; use create equipment for equipment",
				String(options.get("path", "")),
				"category",
				content_id
			)
			return false
		item.category = category as ItemDefinition.Category
	elif (
		options.has("category")
		or options.has("usable_in_field")
		or options.has("usable_in_battle")
		or options.has("effect")
		or options.has("effect_amount")
	):
		result.reject(
			"equipment_usage_unsupported",
			"equipment create does not accept category, usable, or effect options",
			String(options.get("path", "")),
			"arguments",
			content_id
		)
		return false
	var default_can_discard := (
		"false" if item.category == ItemDefinition.Category.KEY_ITEM else "true"
	)
	var can_discard: Variant = ContentOptionParser.boolean(
		String(options.get("can_discard", default_can_discard))
	)
	var can_sell: Variant = ContentOptionParser.boolean(
		String(options.get("can_sell", "true"))
	)
	if can_discard == null or can_sell == null:
		result.reject(
			"item_permission_invalid",
			"can_discard and can_sell must be true or false",
			String(options.get("path", "")),
			"can_discard" if can_discard == null else "can_sell",
			content_id
		)
		return false
	item.can_discard = bool(can_discard)
	item.can_sell = bool(can_sell)
	if item.category == ItemDefinition.Category.KEY_ITEM and item.can_discard:
		result.reject(
			"key_item_discard_unsupported",
			"key items cannot be discardable",
			String(options.get("path", "")),
			"can_discard",
			content_id
		)
		return false
	var icon_path := String(options.get("icon", ""))
	item.icon = load(icon_path) as Texture2D
	if item.icon == null:
		result.reject(
			"item_icon_invalid",
			"item create requires --icon with a Texture2D path",
			icon_path,
			"icon",
			content_id
		)
		return false
	if is_equipment:
		return true
	var usable_in_field: Variant = ContentOptionParser.boolean(
		String(options.get("usable_in_field", "false"))
	)
	var usable_in_battle: Variant = ContentOptionParser.boolean(
		String(options.get("usable_in_battle", "false"))
	)
	if usable_in_field == null or usable_in_battle == null:
		result.reject(
			"item_usage_invalid",
			"usable_in_field and usable_in_battle must be true or false",
			String(options.get("path", "")),
			"usable_in_field" if usable_in_field == null else "usable_in_battle",
			content_id
		)
		return false
	item.usable_in_field = bool(usable_in_field)
	item.usable_in_battle = bool(usable_in_battle)
	if (
		item.category != ItemDefinition.Category.CONSUMABLE
		and (item.usable_in_field or item.usable_in_battle)
	):
		result.reject(
			"item_usage_category_invalid",
			"only consumable items can be field-usable or battle-usable",
			String(options.get("path", "")),
			"category",
			content_id
		)
		return false
	var effect_name := String(options.get("effect", "")).strip_edges().to_lower()
	if effect_name.is_empty() and options.has("effect_amount"):
		result.reject(
			"item_effect_missing",
			"effect_amount requires --effect heal|restore_mp",
			String(options.get("path", "")),
			"effect",
			content_id
		)
		return false
	if effect_name not in ["", "heal", "restore_mp"]:
		result.reject(
			"item_effect_unsupported",
			"item effect must be heal or restore_mp",
			String(options.get("path", "")),
			"effect",
			content_id
		)
		return false
	if (item.usable_in_field or item.usable_in_battle) and effect_name.is_empty():
		result.reject(
			"item_effect_required",
			"usable items require --effect heal|restore_mp and --effect-amount",
			String(options.get("path", "")),
			"effect",
			content_id
		)
		return false
	if not effect_name.is_empty():
		if not item.usable_in_field and not item.usable_in_battle:
			result.reject(
				"item_effect_scope_missing",
				"item effects require at least one usable scope",
				String(options.get("path", "")),
				"usable_in_field",
				content_id
			)
			return false
		var effect_amount_text := String(options.get("effect_amount", ""))
		if not effect_amount_text.is_valid_int() or int(effect_amount_text) <= 0:
			result.reject(
				"item_effect_amount_invalid",
				"effect_amount must be a positive integer",
				String(options.get("path", "")),
				"effect_amount",
				content_id
			)
			return false
		var effect: GameEffect
		if effect_name == "heal":
			var heal := HealEffect.new()
			heal.amount = int(effect_amount_text)
			effect = heal
		else:
			var restore_mp := RestoreMpEffect.new()
			restore_mp.amount = int(effect_amount_text)
			effect = restore_mp
		effect.id = StringName("effect.%s" % content_id)
		item.effects.append(effect)
	return true


static func _configure_skill(
	skill: SkillDefinition,
	options: Dictionary,
	content_id: StringName,
	result: ContentCreationResult
) -> bool:
	var icon_path := String(options.get("icon", ""))
	skill.icon = load(icon_path) as Texture2D
	if skill.icon == null:
		result.reject(
			"skill_icon_invalid",
			"skill create requires --icon with a Texture2D path",
			icon_path,
			"icon",
			content_id
		)
		return false
	skill.mp_cost = int(options.get("mp_cost", "0"))
	var usable_in_field: Variant = ContentOptionParser.boolean(
		String(options.get("usable_in_field", "false"))
	)
	var usable_in_battle: Variant = ContentOptionParser.boolean(
		String(options.get("usable_in_battle", "false"))
	)
	if usable_in_field == null or usable_in_battle == null:
		result.reject(
			"skill_usage_invalid",
			"usable_in_field and usable_in_battle must be true or false",
			String(options.get("path", "")),
			"usable_in_field" if usable_in_field == null else "usable_in_battle",
			content_id
		)
		return false
	skill.usable_in_field = bool(usable_in_field)
	skill.usable_in_battle = bool(usable_in_battle)
	if skill.usable_in_field:
		result.reject(
			"skill_field_usage_unsupported",
			"skills cannot currently be created as field-usable",
			String(options.get("path", "")),
			"usable_in_field",
			content_id
		)
		return false
	var target_rule := ContentOptionParser.target_rule(
		String(options.get("target_rule", "direction"))
	)
	if target_rule < 0:
		result.reject(
			"skill_target_rule_invalid",
			"target_rule must be self, single_enemy, direction, point, or area",
			String(options.get("path", "")),
			"target_rule",
			content_id
		)
		return false
	skill.target_rule = target_rule as SkillDefinition.TargetRule
	if (
		skill.usable_in_battle
		and not SkillDefinition.is_battle_target_rule_supported(skill.target_rule)
	):
		result.reject(
			"skill_target_rule_unsupported",
			"battle skills currently support only direction or area target_rule",
			String(options.get("path", "")),
			"target_rule",
			content_id
		)
		return false
	var effect_name := String(options.get("effect", "")).strip_edges().to_lower()
	if effect_name.is_empty() and options.has("effect_amount"):
		result.reject(
			"skill_effect_missing",
			"effect_amount requires --effect damage",
			String(options.get("path", "")),
			"effect",
			content_id
		)
		return false
	if not effect_name.is_empty() and effect_name != "damage":
		result.reject(
			"skill_effect_unsupported",
			"skill effect must be damage",
			String(options.get("path", "")),
			"effect",
			content_id
		)
		return false
	if skill.usable_in_battle and effect_name.is_empty():
		result.reject(
			"skill_effect_required",
			"battle-usable skills require --effect damage and --effect-amount",
			String(options.get("path", "")),
			"effect",
			content_id
		)
		return false
	if not effect_name.is_empty():
		if not skill.usable_in_battle:
			result.reject(
				"skill_effect_scope_missing",
				"skill effects require --usable-in-battle true",
				String(options.get("path", "")),
				"usable_in_battle",
				content_id
			)
			return false
		var effect_amount_text := String(options.get("effect_amount", ""))
		if not effect_amount_text.is_valid_int() or int(effect_amount_text) <= 0:
			result.reject(
				"skill_effect_amount_invalid",
				"effect_amount must be a positive integer",
				String(options.get("path", "")),
				"effect_amount",
				content_id
			)
			return false
		var damage := DamageEffect.new()
		damage.id = StringName("effect.%s" % content_id)
		damage.amount = int(effect_amount_text)
		skill.effects.append(damage)
	skill.cooldown_seconds = float(options.get("cooldown_seconds", "0"))
	skill.cast_seconds = float(options.get("cast_seconds", "0"))
	skill.active_seconds = float(options.get("active_seconds", "0.1"))
	skill.recovery_seconds = float(options.get("recovery_seconds", "0.2"))
	skill.max_range = float(options.get("max_range", "1.5"))
	skill.radius = float(options.get("radius", "0"))
	var presentation_path := String(options.get("presentation_scene", ""))
	if not presentation_path.is_empty():
		skill.presentation_scene = load(presentation_path) as PackedScene
		if skill.presentation_scene == null:
			result.reject(
				"skill_presentation_scene_invalid",
				"presentation_scene must reference a PackedScene",
				presentation_path,
				"presentation_scene",
				content_id
			)
			return false
	var sound_path := String(options.get("sound", ""))
	if not sound_path.is_empty():
		skill.sound = load(sound_path) as AudioStream
		if skill.sound == null:
			result.reject(
				"skill_sound_invalid",
				"sound must reference an AudioStream",
				sound_path,
				"sound",
				content_id
			)
			return false
	return true
