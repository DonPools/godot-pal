@tool
class_name SkillDefinition
extends ContentDefinition

enum TargetRule {
	SELF,
	SINGLE_ENEMY,
	DIRECTION,
	POINT,
	AREA,
}

const SUPPORTED_BATTLE_TARGET_RULES: Array[TargetRule] = [
	TargetRule.DIRECTION,
	TargetRule.AREA,
]

@export var icon: Texture2D
@export_range(0, 999) var mp_cost: int = 0
@export var usable_in_field: bool = false
@export var usable_in_battle: bool = false
@export var target_rule: TargetRule = TargetRule.DIRECTION
@export_range(0.0, 60.0, 0.01) var cooldown_seconds: float = 0.0
@export_range(0.0, 10.0, 0.01) var cast_seconds: float = 0.0
@export_range(0.01, 10.0, 0.01) var active_seconds: float = 0.1
@export_range(0.0, 10.0, 0.01) var recovery_seconds: float = 0.2
@export_range(0.0, 100.0, 0.1) var max_range: float = 1.5
@export_range(0.0, 50.0, 0.1) var radius: float = 0.0
@export var effects: Array[GameEffect] = []
@export var presentation_scene: PackedScene
@export var sound: AudioStream


static func is_battle_target_rule_supported(value: TargetRule) -> bool:
	return value in SUPPORTED_BATTLE_TARGET_RULES


## Derives runtime usability from the declaration and implemented battle paths.
func can_be_used_in_battle() -> bool:
	return (
		usable_in_battle
		and is_battle_target_rule_supported(target_rule)
		and not effects.is_empty()
	)
