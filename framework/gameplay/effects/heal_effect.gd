@tool
class_name HealEffect
extends GameEffect

@export_range(1, 9999) var amount: int = 1


func apply(context: EffectContext) -> EffectResult:
	var result := EffectResult.new()
	result.effect_id = id
	result.requested_amount = amount
	if context == null:
		return result
	if context.battle_target != null:
		result.changed_amount = context.battle_target.heal(amount)
	elif context.target != null and context.target_definition != null:
		result.changed_amount = context.target.heal(
			amount,
			context.target_max_hp
			if context.target_max_hp >= 0
			else context.target_definition.base_max_hp
		)
	return result
