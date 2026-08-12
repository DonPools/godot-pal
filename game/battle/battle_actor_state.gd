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


func is_alive() -> bool:
	return hp > 0


func take_damage(amount: int) -> int:
	var applied := maxi(amount / 2, 1) if defending else maxi(amount, 0)
	var previous := hp
	hp = maxi(hp - applied, 0)
	return previous - hp
