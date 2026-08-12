class_name BattleActorState
extends RefCounted

var id: StringName
var display_name: String
var hp: int
var max_hp: int
var mp: int
var max_mp: int
var attack: int
var defending: bool = false
var statuses: Dictionary[StringName, int] = {}


func is_alive() -> bool:
	return hp > 0


func take_damage(amount: int) -> int:
	var applied := maxi(amount / 2, 1) if defending else maxi(amount, 0)
	var previous := hp
	hp = maxi(hp - applied, 0)
	return previous - hp


func apply_status(definition: StatusDefinition) -> bool:
	if definition == null or definition.id.is_empty():
		return false
	var previous := int(statuses.get(definition.id, 0))
	statuses[definition.id] = maxi(previous, definition.duration_rounds)
	return previous == 0


func tick_status(definition: StatusDefinition) -> int:
	if definition == null or not statuses.has(definition.id):
		return 0
	var damage := take_damage(definition.periodic_damage)
	var remaining := int(statuses[definition.id]) - 1
	if remaining <= 0:
		statuses.erase(definition.id)
	else:
		statuses[definition.id] = remaining
	return damage
