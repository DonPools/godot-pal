class_name MapGenerationPropPlacement
extends RefCounted

var id: StringName
var rule: MapGenerationPropRule
var cell: Vector2i
var yaw_quarter_turns: int = 0


func to_dictionary() -> Dictionary:
	return {
		"id": String(id),
		"rule_id": String(rule.id) if rule != null else "",
		"x": cell.x,
		"y": cell.y,
		"yaw_quarter_turns": yaw_quarter_turns,
	}
