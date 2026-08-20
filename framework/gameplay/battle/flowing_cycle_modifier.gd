@tool
class_name FlowingCycleModifier
extends BattleBuildModifier

@export_range(0, 99) var resource_refund_per_skill_hit: int = 1
@export_range(0.0, 10.0, 0.01) var cooldown_reduction_per_skill_hit: float = 0.15


func apply_to(snapshot: BattleBuildSnapshot) -> void:
	if snapshot == null:
		return
	snapshot.skill_hit_resource_refund = resource_refund_per_skill_hit
	snapshot.skill_hit_cooldown_reduction = cooldown_reduction_per_skill_hit


func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if resource_refund_per_skill_hit <= 0 and cooldown_reduction_per_skill_hit <= 0.0:
		errors.append("flowing cycle modifier must change resource or cooldown")
	return errors
