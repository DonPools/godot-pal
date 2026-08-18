@tool
class_name RestoreMpEffect
extends GameEffect

@export_range(1, 9999) var amount: int = 1


func apply(context: EffectContext) -> EffectResult:
	var result := EffectResult.new()
	result.effect_id = id
	result.requested_amount = amount
	if context == null:
		return result
	if context.battle_target != null:
		result.changed_amount = context.battle_target.restore_mp(amount)
	elif context.target != null and context.target_definition != null:
		result.changed_amount = context.target.restore_mp(
			amount,
			context.target_definition.base_max_mp
		)
	return result
