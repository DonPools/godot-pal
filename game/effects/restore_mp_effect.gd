@tool
class_name RestoreMpEffect
extends GameEffect

@export_range(1, 9999) var amount: int = 1


func apply(context: EffectContext) -> EffectResult:
	var result := EffectResult.new()
	result.effect_id = id
	result.requested_amount = amount
	if context == null or context.target == null or context.target_definition == null:
		return result
	result.changed_amount = context.target.restore_mp(amount, context.target_definition.base_max_mp)
	return result
