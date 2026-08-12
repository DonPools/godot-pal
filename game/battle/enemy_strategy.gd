@tool
class_name EnemyStrategy
extends Resource


func choose_damage(_enemy: BattleActorState, _target: BattleActorState) -> int:
	push_error("EnemyStrategy.choose_damage() must be implemented")
	return 0


func choose_action(enemy: BattleActorState, target: BattleActorState) -> EnemyAction:
	return EnemyAction.attack(choose_damage(enemy, target))
