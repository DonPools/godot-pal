class_name EffectResult
extends RefCounted

var effect_id: StringName
var requested_amount: int = 0
var changed_amount: int = 0


func succeeded() -> bool:
	return changed_amount > 0
