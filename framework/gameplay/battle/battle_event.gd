class_name BattleEvent
extends RefCounted

enum Kind {
	MESSAGE,
	ACTION_STARTED,
	ACTION_ACTIVE,
	ACTION_FINISHED,
	ACTION_REJECTED,
	DODGE_STARTED,
	DODGED,
	COOLDOWN_STARTED,
	PROJECTILE_REQUESTED,
	DAMAGE,
	HEAL,
	MP_RESTORED,
	STATUS_APPLIED,
	STATUS_TICK,
	DEATH,
	OUTCOME,
}

var kind: Kind = Kind.MESSAGE
var actor_id: StringName
var target_id: StringName
var action_id: StringName
var action_instance_id: int = 0
var amount: int = 0
var duration_seconds: float = 0.0
var rejection: BattleActionRequestResult.Rejection = BattleActionRequestResult.Rejection.NONE
var message: String


static func message_event(text: String) -> BattleEvent:
	var event := BattleEvent.new()
	event.message = text
	return event


static func action_event(
	event_kind: Kind,
	actor: StringName,
	action: BattleActionState
) -> BattleEvent:
	var event := BattleEvent.new()
	event.kind = event_kind
	event.actor_id = actor
	event.action_id = action.action_id
	event.action_instance_id = action.instance_id
	return event


static func damage_event(
	actor: StringName,
	target: StringName,
	action: BattleActionState,
	damage: int
) -> BattleEvent:
	var event := action_event(Kind.DAMAGE, actor, action)
	event.target_id = target
	event.amount = damage
	return event


static func rejection_event(
	actor: StringName,
	action: StringName,
	reason: BattleActionRequestResult.Rejection
) -> BattleEvent:
	var event := BattleEvent.new()
	event.kind = Kind.ACTION_REJECTED
	event.actor_id = actor
	event.action_id = action
	event.rejection = reason
	return event


static func outcome_event(value: BattleResult.Outcome) -> BattleEvent:
	var event := BattleEvent.new()
	event.kind = Kind.OUTCOME
	event.amount = int(value)
	return event


static func duration_event(
	event_kind: Kind,
	actor: StringName,
	action: BattleActionState,
	duration: float
) -> BattleEvent:
	var event := action_event(event_kind, actor, action)
	event.duration_seconds = duration
	return event
