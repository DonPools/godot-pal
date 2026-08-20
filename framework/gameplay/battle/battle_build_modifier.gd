@tool
class_name BattleBuildModifier
extends Resource


func apply_to(_snapshot: BattleBuildSnapshot) -> void:
	pass


func referenced_skills() -> Array[SkillDefinition]:
	return []


func validate() -> PackedStringArray:
	return PackedStringArray()
