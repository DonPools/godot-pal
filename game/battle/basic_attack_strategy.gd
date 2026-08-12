class_name BasicAttackStrategy
extends EnemyStrategy

@export_range(0.1, 2.0, 0.05) var attack_multiplier: float = 1.0


func choose_damage(enemy: BattleActorState, _target: BattleActorState) -> int:
	return maxi(roundi(enemy.attack * attack_multiplier), 1)
