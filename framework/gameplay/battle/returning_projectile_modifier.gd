@tool
class_name ReturningProjectileModifier
extends BattleBuildModifier

@export var skill: SkillDefinition


func apply_to(snapshot: BattleBuildSnapshot) -> void:
	if snapshot != null and skill != null:
		snapshot.returning_projectile_skill_id = skill.id


func referenced_skills() -> Array[SkillDefinition]:
	return [skill] if skill != null else []


func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if skill == null or skill.target_rule != SkillDefinition.TargetRule.DIRECTION:
		errors.append("returning projectile modifier requires a directional skill")
	return errors
