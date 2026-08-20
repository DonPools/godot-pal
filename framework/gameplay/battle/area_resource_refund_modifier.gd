@tool
class_name AreaResourceRefundModifier
extends BattleBuildModifier

@export var skill: SkillDefinition
@export_range(1, 99) var required_target_count: int = 3
@export_range(1, 999) var resource_refund: int = 3


func apply_to(snapshot: BattleBuildSnapshot) -> void:
	if snapshot == null or skill == null:
		return
	snapshot.area_refund_skill_id = skill.id
	snapshot.area_refund_target_count = required_target_count
	snapshot.area_refund_amount = resource_refund


func referenced_skills() -> Array[SkillDefinition]:
	return [skill] if skill != null else []


func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if skill == null or skill.target_rule != SkillDefinition.TargetRule.AREA:
		errors.append("area resource refund modifier requires an area skill")
	if required_target_count < 1 or resource_refund < 1:
		errors.append("area resource refund modifier requires positive values")
	return errors
