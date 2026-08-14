class_name EnemyAction
extends RefCounted

var damage: int = 0
var applied_status: StatusDefinition


static func attack(amount: int, status: StatusDefinition = null) -> EnemyAction:
	var action := EnemyAction.new()
	action.damage = maxi(amount, 0)
	action.applied_status = status
	return action
