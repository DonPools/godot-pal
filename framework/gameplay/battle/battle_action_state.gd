class_name BattleActionState
extends RefCounted

enum Phase {
	WINDUP,
	ACTIVE,
	RECOVERY,
}

var instance_id: int
var intent: BattleActionIntent
var action_id: StringName
var phase: Phase = Phase.WINDUP
var remaining_seconds: float = 0.0
var windup_seconds: float = 0.0
var active_seconds: float = 0.1
var recovery_seconds: float = 0.0
var base_damage: int = 0
var applied_status: StatusDefinition
var hit_targets: Dictionary[StringName, bool] = {}


func has_hit(target_id: StringName) -> bool:
	return hit_targets.has(target_id)


func record_hit(target_id: StringName) -> void:
	hit_targets[target_id] = true
