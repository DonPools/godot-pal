class_name ContentOptionParser
extends RefCounted


static func target_rule(value: String) -> int:
	var normalized := value.strip_edges().to_lower().replace("-", "_")
	var names := {
		"self": SkillDefinition.TargetRule.SELF,
		"single_enemy": SkillDefinition.TargetRule.SINGLE_ENEMY,
		"direction": SkillDefinition.TargetRule.DIRECTION,
		"point": SkillDefinition.TargetRule.POINT,
		"area": SkillDefinition.TargetRule.AREA,
	}
	return int(names.get(normalized, -1))


static func item_category(value: String) -> int:
	match value.strip_edges().to_lower().replace("-", "_"):
		"consumable":
			return ItemDefinition.Category.CONSUMABLE
		"equipment":
			return ItemDefinition.Category.EQUIPMENT
		"key_item":
			return ItemDefinition.Category.KEY_ITEM
		"material":
			return ItemDefinition.Category.MATERIAL
	return -1


static func combat_style(value: String) -> int:
	match value.strip_edges().to_lower():
		"melee":
			return EnemyDefinition.CombatStyle.MELEE
		"ranged":
			return EnemyDefinition.CombatStyle.RANGED
		"charger":
			return EnemyDefinition.CombatStyle.CHARGER
	return -1


static func reward_policy(value: String) -> int:
	match value.strip_edges().to_lower().replace("-", "_"):
		"all_or_nothing":
			return RewardPolicy.Value.ALL_OR_NOTHING
		"allow_partial":
			return RewardPolicy.Value.ALLOW_PARTIAL
	return -1


static func boolean(value: String) -> Variant:
	match value.strip_edges().to_lower():
		"true":
			return true
		"false":
			return false
	return null
