@tool
class_name DamageEffect
extends GameEffect

@export_range(1, 9999) var amount: int = 1


func apply(context: EffectContext) -> EffectResult:
	var result := EffectResult.new()
	result.effect_id = id
	result.requested_amount = amount
	if context == null:
		return result
	if context.battle_target != null:
		result.changed_amount = context.battle_target.take_damage(amount)
	elif context.target != null:
		result.changed_amount = context.target.take_damage(amount)
	return result
