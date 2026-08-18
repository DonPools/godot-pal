class_name BattleActionRequestResult
extends RefCounted

enum Rejection {
	NONE,
	SESSION_FINISHED,
	ACTOR_NOT_FOUND,
	ACTOR_DEAD,
	ACTOR_BUSY,
	ACTION_INVALID,
	TARGET_INVALID,
	COOLDOWN,
	INSUFFICIENT_RESOURCE,
	ITEM_UNAVAILABLE,
}

var action_instance_id: int = 0
var action_id: StringName
var rejection: Rejection = Rejection.NONE


func accepted() -> bool:
	return rejection == Rejection.NONE and action_instance_id > 0
