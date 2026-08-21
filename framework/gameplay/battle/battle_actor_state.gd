class_name BattleActorState
extends RefCounted

var id: StringName
var definition_id: StringName
var display_name: String
var hp: int
var max_hp: int
var mp: int
var max_mp: int
var attack: int
var basic_attack_resource_gain: int = 0
var basic_chain_hits: int = 0
var build := BattleBuildSnapshot.new()
var allowed_skill_ids: Array[StringName] = []
var battle_item_id: StringName
var move_speed: float = 4.5
var attack_windup_seconds: float = 0.12
var attack_active_seconds: float = 0.1
var attack_recovery_seconds: float = 0.2
var attack_status: StatusDefinition
var charge_damage: int = 0
var charge_windup_seconds: float = 0.8
var charge_active_seconds: float = 0.5
var charge_recovery_seconds: float = 0.6
var charge_speed: float = 10.0
var charge_cooldown_seconds: float = 4.0
var charge_stagger_seconds: float = 1.6
var charge_staggers_on_pillar: bool = false
var stagger_remaining_seconds: float = 0.0
var current_action: BattleActionState
var cooldowns: Dictionary[StringName, float] = {}
var statuses: Dictionary[StringName, BattleStatusState] = {}


func is_alive() -> bool:
	return hp > 0


func can_act() -> bool:
	return is_alive() and current_action == null and stagger_remaining_seconds <= 0.0


func take_damage(amount: int) -> int:
	var previous := hp
	hp = maxi(hp - maxi(amount, 0), 0)
	return previous - hp


func heal(amount: int) -> int:
	var previous := hp
	hp = mini(hp + maxi(amount, 0), max_hp)
	return hp - previous


func restore_mp(amount: int) -> int:
	var previous := mp
	mp = mini(mp + maxi(amount, 0), max_mp)
	return mp - previous


func cooldown_remaining(action_id: StringName) -> float:
	return float(cooldowns.get(action_id, 0.0))


func start_cooldown(action_id: StringName, seconds: float) -> void:
	if not action_id.is_empty() and seconds > 0.0:
		cooldowns[action_id] = seconds


func advance_cooldowns(delta: float) -> void:
	for action_id: StringName in cooldowns.keys():
		var remaining := maxf(float(cooldowns[action_id]) - delta, 0.0)
		if remaining <= 0.0:
			cooldowns.erase(action_id)
		else:
			cooldowns[action_id] = remaining


func reduce_cooldowns(seconds: float) -> void:
	if seconds <= 0.0:
		return
	for action_id: StringName in cooldowns.keys():
		var remaining := maxf(float(cooldowns[action_id]) - seconds, 0.0)
		if remaining <= 0.0:
			cooldowns.erase(action_id)
		else:
			cooldowns[action_id] = remaining


func apply_status(definition: StatusDefinition) -> bool:
	if definition == null or definition.id.is_empty():
		return false
	var existing := statuses.get(definition.id) as BattleStatusState
	if existing != null:
		existing.remaining_seconds = maxf(
			existing.remaining_seconds,
			definition.duration_seconds
		)
		return false
	statuses[definition.id] = BattleStatusState.from_definition(definition)
	return true
