class_name GameEffect
extends Resource

@export var id: StringName


func apply(_context: EffectContext) -> EffectResult:
	push_error("GameEffect.apply() must be implemented")
	return EffectResult.new()
