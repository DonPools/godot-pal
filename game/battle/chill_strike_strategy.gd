@tool
class_name ChillStrikeStrategy
extends EnemyStrategy

@export_range(0.1, 2.0, 0.05) var attack_multiplier: float = 1.0
@export var status: StatusDefinition


func choose_damage(enemy: BattleActorState, _target: BattleActorState) -> int:
	return maxi(roundi(enemy.attack * attack_multiplier), 1)


func choose_action(enemy: BattleActorState, target: BattleActorState) -> EnemyAction:
	return EnemyAction.attack(choose_damage(enemy, target), status)
