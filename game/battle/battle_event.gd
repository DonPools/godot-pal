class_name BattleEvent
extends RefCounted

enum Kind {
	MESSAGE,
	DAMAGE,
	HEAL,
	OUTCOME,
}

var kind: Kind = Kind.MESSAGE
var actor_id: StringName
var amount: int = 0
var message: String


static func message_event(text: String) -> BattleEvent:
	var event := BattleEvent.new()
	event.message = text
	return event
